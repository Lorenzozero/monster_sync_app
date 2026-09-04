import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// PREZZO DELLA BENZINA — dati aperti ufficiali, nessuna chiave API
///
/// Fonte: **Osservaprezzi Carburanti del MIMIT** (Ministero delle Imprese e del
/// Made in Italy). Ogni mattina il ministero pubblica il prezzo comunicato dal
/// gestore di *ogni* impianto d'Italia:
///
///   https://www.mimit.gov.it/images/exportCSV/prezzo_alle_8.csv
///
/// È un CSV separato da `|`, con due righe di intestazione:
///
///   Estrazione del 2026-09-02
///   idImpianto|descCarburante|prezzo|isSelf|dtComu
///   3464|Benzina|2.159|1|01/09/2026 19:30:13
///
/// ## Perché la mediana e non la media
/// Nel file convivono benzine normali a 1,8 € e "speciali" da pista a 3,5 €:
/// poche righe fuori scala spostano la media, non la mediana. La mediana di
/// ~20.000 impianti self è il prezzo che davvero incontri al distributore.
///
/// ## Perché solo il primo tratto del file
/// Il file intero pesa ~3,8 MB (93.000 righe). Scaricarlo tutto da cellulare,
/// in moto, per ricavarne un numero solo è uno spreco. Con una richiesta HTTP
/// Range si prendono i primi 1,4 MB — misurato il 2026-09-04: **7.589 impianti
/// self, mediana 2,029 €/l, identica alla mediana del file intero**. Il
/// campione è abbondante e l'ordine del file (per codice impianto) non è
/// geografico, quindi non introduce distorsioni.
///
/// Il valore resta in cache 12 ore: il file si aggiorna una volta al giorno,
/// riscaricarlo più spesso non cambierebbe nulla.
/// ─────────────────────────────────────────────────────────────────────────────

class FuelPrice {
  /// €/litro, benzina self.
  final double euroPerLitre;

  /// Quanti impianti hanno concorso alla mediana.
  final int samples;

  /// Data dichiarata dal ministero nella prima riga del CSV.
  final String extraction;

  /// Quando l'abbiamo letto noi.
  final DateTime fetchedAt;

  /// true quando la rete non ha risposto e nemmeno la cache esisteva: il
  /// prezzo è il valore di ripiego, non un dato del ministero. Va detto
  /// all'utente invece di spacciarlo per reale.
  final bool isFallback;

  const FuelPrice({
    required this.euroPerLitre,
    required this.samples,
    required this.extraction,
    required this.fetchedAt,
    this.isFallback = false,
  });

  String get label => '${euroPerLitre.toStringAsFixed(3)} €/l';

  String get sourceLabel => isFallback
      ? 'prezzo di riferimento (nessun dato scaricato)'
      : 'MIMIT · $extraction · $samples impianti';
}

class FuelPriceService {
  FuelPriceService._();
  static final FuelPriceService instance = FuelPriceService._();

  static const _csvUrl =
      'https://www.mimit.gov.it/images/exportCSV/prezzo_alle_8.csv';

  /// Quanto leggere del file. Vedi il commento in testa: con questo taglio la
  /// mediana coincide con quella del file completo.
  static const int _rangeBytes = 1400000;

  static const _kPrice = 'fuel_price_value';
  static const _kSamples = 'fuel_price_samples';
  static const _kExtraction = 'fuel_price_extraction';
  static const _kFetched = 'fuel_price_fetched_at';

  static const Duration _maxAge = Duration(hours: 12);

  /// Prezzo di ripiego se non c'è né rete né cache. Volutamente vicino alla
  /// mediana osservata, ma marcato come tale.
  static const double _fallbackPrice = 1.95;

  FuelPrice? _memory;

  /// Prezzo corrente. Usa la cache se è fresca, altrimenti riscarica.
  /// Non lancia mai: al peggio torna il valore di ripiego.
  Future<FuelPrice> current({bool forceRefresh = false}) async {
    if (!forceRefresh && _memory != null && _isFresh(_memory!.fetchedAt)) {
      return _memory!;
    }

    final prefs = await SharedPreferences.getInstance();

    if (!forceRefresh) {
      final cached = _readCache(prefs);
      if (cached != null && _isFresh(cached.fetchedAt)) {
        _memory = cached;
        return cached;
      }
    }

    final fresh = await _download();
    if (fresh != null) {
      _memory = fresh;
      await prefs.setDouble(_kPrice, fresh.euroPerLitre);
      await prefs.setInt(_kSamples, fresh.samples);
      await prefs.setString(_kExtraction, fresh.extraction);
      await prefs.setString(_kFetched, fresh.fetchedAt.toIso8601String());
      return fresh;
    }

    // Rete assente: meglio un prezzo vecchio di ieri che nessun prezzo.
    final stale = _readCache(prefs);
    if (stale != null) {
      _memory = stale;
      return stale;
    }

    return FuelPrice(
      euroPerLitre: _fallbackPrice,
      samples: 0,
      extraction: '—',
      fetchedAt: DateTime.now(),
      isFallback: true,
    );
  }

  static bool _isFresh(DateTime t) =>
      DateTime.now().difference(t) < _maxAge;

  FuelPrice? _readCache(SharedPreferences prefs) {
    final p = prefs.getDouble(_kPrice);
    final f = prefs.getString(_kFetched);
    if (p == null || f == null) return null;
    final when = DateTime.tryParse(f);
    if (when == null) return null;
    return FuelPrice(
      euroPerLitre: p,
      samples: prefs.getInt(_kSamples) ?? 0,
      extraction: prefs.getString(_kExtraction) ?? '—',
      fetchedAt: when,
    );
  }

  Future<FuelPrice?> _download() async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10);
      final req = await client.getUrl(Uri.parse(_csvUrl));
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-$_rangeBytes');
      req.headers.set(HttpHeaders.userAgentHeader,
          'MonsterSync/1.0 (progetto personale)');
      final res = await req.close().timeout(const Duration(seconds: 30));

      // 206 = Range accettato, 200 = il server lo ignora e manda tutto.
      if (res.statusCode != 206 && res.statusCode != 200) {
        client.close();
        debugPrint('FuelPriceService: HTTP ${res.statusCode}');
        return null;
      }

      final body = await res.transform(utf8.decoder).join();
      client.close();
      return _parse(body);
    } catch (e) {
      debugPrint('FuelPriceService: scaricamento fallito ($e)');
      return null;
    }
  }

  /// Estrae la mediana dei prezzi della benzina self.
  @visibleForTesting
  static FuelPrice? parse(String csv) => _parse(csv);

  static FuelPrice? _parse(String csv) {
    final lines = csv.split('\n');
    if (lines.length < 3) return null;

    // Prima riga: "Estrazione del 2026-09-02"
    final extraction =
        lines.first.replaceFirst('Estrazione del', '').trim();

    final prices = <double>[];
    // L'ultima riga di un download troncato a metà è incompleta: si scarta.
    for (var i = 2; i < lines.length - 1; i++) {
      final f = lines[i].split('|');
      if (f.length < 4) continue;
      if (f[1] != 'Benzina') continue; // niente diesel, GPL, speciali da pista
      if (f[3].trim() != '1') continue; // solo self, il prezzo che paghi
      final p = double.tryParse(f[2].trim().replaceAll(',', '.'));
      // Fuori da questa forbice è un errore di comunicazione del gestore.
      if (p == null || p < 1.0 || p > 3.5) continue;
      prices.add(p);
    }

    if (prices.length < 100) return null;
    prices.sort();
    final n = prices.length;
    final median = n.isOdd
        ? prices[n ~/ 2]
        : (prices[n ~/ 2 - 1] + prices[n ~/ 2]) / 2;

    return FuelPrice(
      euroPerLitre: median,
      samples: n,
      extraction: extraction.isEmpty ? '—' : extraction,
      fetchedAt: DateTime.now(),
    );
  }
}

/// Costo di un giro: litri bruciati e euro spesi.
class RideCost {
  final double km;
  final double lPer100;
  final double litres;
  final double euro;
  final FuelPrice price;

  const RideCost({
    required this.km,
    required this.lPer100,
    required this.litres,
    required this.euro,
    required this.price,
  });

  factory RideCost.compute({
    required double km,
    required double lPer100,
    required FuelPrice price,
  }) {
    final litres = km * lPer100 / 100.0;
    return RideCost(
      km: km,
      lPer100: lPer100,
      litres: litres,
      euro: litres * price.euroPerLitre,
      price: price,
    );
  }

  String get litresLabel => '${litres.toStringAsFixed(2)} l';
  String get euroLabel => '${euro.toStringAsFixed(2)} €';
  String get consumptionLabel => '${lPer100.toStringAsFixed(1)} l/100km';

  /// Il modo in cui i consumi si leggono davvero al bar: km con un litro.
  String get kmPerLitreLabel =>
      lPer100 <= 0 ? '--' : '${(100 / lPer100).toStringAsFixed(1)} km/l';
}
