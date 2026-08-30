import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// METEO E CONDIZIONE DELLA STRADA
///
/// Non serve a scrivere i gradi sul cruscotto: serve a sapere se l'asfalto è
/// probabilmente bagnato, e a ridurre di conseguenza la velocità di riferimento
/// delle pace notes. È la differenza fra un widget decorativo e un assistente.
///
/// Sorgente: Open-Meteo — gratuita, senza API key, e soprattutto restituisce
/// anche le ORE PRECEDENTI di precipitazione, che è l'unico modo per capire se
/// ha piovuto mentre eri in strada o poco prima che partissi.
/// ─────────────────────────────────────────────────────────────────────────────

enum RoadCondition {
  dry,        // asciutto
  drying,     // ha piovuto qualche ora fa: probabilmente ancora umido a tratti
  damp,       // pioggia recente: bagnato
  wet,        // sta piovendo
}

class WeatherInfo {
  final double temperatureC;
  final double precipitationNowMm;
  final double precipitationLast6hMm;
  final RoadCondition road;
  final DateTime fetchedAt;
  final bool fromCache;

  const WeatherInfo({
    required this.temperatureC,
    required this.precipitationNowMm,
    required this.precipitationLast6hMm,
    required this.road,
    required this.fetchedAt,
    this.fromCache = false,
  });

  /// Fattore di aderenza applicato alla velocità di riferimento delle curve.
  /// Sono valori prudenziali, non misure: servono a spostare la soglia nella
  /// direzione giusta, non a certificare quanto tiene la gomma.
  double get gripFactor {
    switch (road) {
      case RoadCondition.dry:
        return 1.00;
      case RoadCondition.drying:
        return 0.88;
      case RoadCondition.damp:
        return 0.75;
      case RoadCondition.wet:
        return 0.65;
    }
  }

  String get roadLabel {
    switch (road) {
      case RoadCondition.dry:
        return 'ASFALTO ASCIUTTO';
      case RoadCondition.drying:
        return 'HA PIOVUTO, FONDO UMIDO';
      case RoadCondition.damp:
        return 'ASFALTO BAGNATO';
      case RoadCondition.wet:
        return 'STA PIOVENDO';
    }
  }

  /// Avviso da leggere a voce, o null se non c'è niente da dire.
  String? get advisory {
    switch (road) {
      case RoadCondition.dry:
        return null;
      case RoadCondition.drying:
        return 'Ha piovuto nelle ultime ore: attenzione all\'ombra e sotto gli alberi, '
            'dove l\'asfalto resta umido più a lungo.';
      case RoadCondition.damp:
        return 'Asfalto bagnato: velocità di riferimento ridotte del venticinque per cento.';
      case RoadCondition.wet:
        return 'Sta piovendo: velocità di riferimento ridotte di un terzo. '
            'Attenzione alle strisce e ai tombini.';
    }
  }

  Map<String, dynamic> toJson() => {
        't': temperatureC,
        'pn': precipitationNowMm,
        'p6': precipitationLast6hMm,
        'r': road.index,
        'at': fetchedAt.toIso8601String(),
      };

  static WeatherInfo fromJson(Map<String, dynamic> j) => WeatherInfo(
        temperatureC: (j['t'] as num).toDouble(),
        precipitationNowMm: (j['pn'] as num).toDouble(),
        precipitationLast6hMm: (j['p6'] as num).toDouble(),
        road: RoadCondition.values[j['r'] as int],
        fetchedAt: DateTime.parse(j['at'] as String),
        fromCache: true,
      );
}

class WeatherService {
  WeatherService._();
  static final WeatherService instance = WeatherService._();

  static const String _prefsKey = 'weather_last';
  static const Duration _maxAge = Duration(minutes: 20);

  WeatherInfo? _memory;

  /// Ritorna il meteo per la posizione data. Se la rete manca o è lenta,
  /// ricade sull'ultimo risultato salvato: in moto capita spesso di non avere
  /// campo, e un dato di venti minuti fa è comunque meglio di niente.
  Future<WeatherInfo?> forPosition(double lat, double lon,
      {bool forceRefresh = false}) async {
    final now = DateTime.now();
    if (!forceRefresh &&
        _memory != null &&
        now.difference(_memory!.fetchedAt) < _maxAge) {
      return _memory;
    }

    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=${lat.toStringAsFixed(4)}&longitude=${lon.toStringAsFixed(4)}'
        '&current=temperature_2m,precipitation'
        '&hourly=precipitation&past_hours=6&forecast_hours=1'
        '&timezone=auto',
      );

      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 6);
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.userAgentHeader, 'MonsterSync/1.0');
      final res = await req.close().timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) {
        client.close();
        return await _loadCache();
      }
      final body = await res.transform(utf8.decoder).join();
      client.close();

      final j = jsonDecode(body) as Map<String, dynamic>;
      final current = j['current'] as Map<String, dynamic>;
      final hourly = j['hourly'] as Map<String, dynamic>;

      final temp = (current['temperature_2m'] as num?)?.toDouble() ?? 0.0;
      final pNow = (current['precipitation'] as num?)?.toDouble() ?? 0.0;

      final list = (hourly['precipitation'] as List?) ?? const [];
      double p6 = 0.0;
      for (final v in list) {
        if (v is num) p6 += v.toDouble();
      }

      final info = WeatherInfo(
        temperatureC: temp,
        precipitationNowMm: pNow,
        precipitationLast6hMm: p6,
        road: _classify(pNow, p6, temp),
        fetchedAt: now,
      );
      _memory = info;
      await _saveCache(info);
      return info;
    } catch (e) {
      debugPrint('WeatherService: rete non disponibile ($e), uso la cache');
      return _loadCache();
    }
  }

  /// Le soglie sono prudenziali per scelta: se c'è un dubbio, si assume
  /// meno aderenza, non di più.
  static RoadCondition _classify(double now, double last6h, double tempC) {
    if (now > 0.05) return RoadCondition.wet;
    if (last6h > 2.0) return RoadCondition.damp;
    if (last6h > 0.2) {
      // Sotto i 10 °C l'asfalto asciuga molto più lentamente.
      return tempC < 10 ? RoadCondition.damp : RoadCondition.drying;
    }
    return RoadCondition.dry;
  }

  Future<void> _saveCache(WeatherInfo i) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_prefsKey, jsonEncode(i.toJson()));
    } catch (_) {}
  }

  Future<WeatherInfo?> _loadCache() async {
    if (_memory != null) return _memory;
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString(_prefsKey);
      if (s == null) return null;
      return WeatherInfo.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
