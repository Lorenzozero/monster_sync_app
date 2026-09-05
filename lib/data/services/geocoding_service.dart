import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// RICERCA DESTINAZIONE E CALCOLO PERCORSO
///
/// Tutto su servizi aperti e senza chiave API:
///   - **Nominatim** (OpenStreetMap) per cercare un posto per nome
///
/// Il calcolo del percorso è passato a Valhalla, vedi `route_planner.dart`:
/// OSRM pubblico non sa dare alternative.
///
/// Serve la rete. Sono i server pubblici di cortesia dei due
/// progetti: vanno usati con parsimonia (una richiesta per volta, User-Agent
/// vero) e non sono adatti a un'app distribuita a migliaia di persone. Per
/// quello si passa a un'istanza propria o a un servizio a pagamento.
///
/// Senza rete la navigazione interna traccia comunque la linea retta verso la
/// destinazione: meglio di niente, ma non e' un percorso stradale.
/// ─────────────────────────────────────────────────────────────────────────────

class Place {
  final String name;
  final String detail;
  final LatLng coord;
  const Place(this.name, this.detail, this.coord);
}

/// Una manovra lungo il percorso, gia' tradotta in italiano.
class RouteStep {
  final String instruction; // "Gira a destra"
  final String streetName;  // "Via del Muraglione"
  final double distanceM;   // lunghezza di questo tratto
  final String maneuver;    // tipo grezzo OSRM, per scegliere l'icona
  final String modifier;    // left / right / straight / ...
  final LatLng at;          // dove avviene la manovra
  const RouteStep({
    required this.instruction,
    required this.streetName,
    required this.distanceM,
    required this.maneuver,
    required this.modifier,
    required this.at,
  });
}

class RouteResult {
  final List<LatLng> points;
  final List<RouteStep> steps;
  final double distanceM;
  final double durationS;
  final bool straightLineFallback;
  const RouteResult({
    required this.points,
    required this.steps,
    required this.distanceM,
    required this.durationS,
    this.straightLineFallback = false,
  });

  String get distanceLabel => distanceM >= 1000
      ? '${(distanceM / 1000).toStringAsFixed(1)} km'
      : '${distanceM.round()} m';

  /// Orario di arrivo stimato, formato HH:MM.
  String get etaLabel {
    final eta = DateTime.now().add(Duration(seconds: durationS.round()));
    return '${eta.hour.toString().padLeft(2, '0')}:'
        '${eta.minute.toString().padLeft(2, '0')}';
  }
}

class GeocodingService {
  GeocodingService._();
  static final GeocodingService instance = GeocodingService._();

  static const _ua = 'MonsterSync/1.0 (progetto personale, github.com/Lorenzozero)';

  Future<String?> _get(Uri uri) async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8);
      final req = await client.getUrl(uri);
      // Nominatim rifiuta le richieste senza uno User-Agent identificabile.
      req.headers.set(HttpHeaders.userAgentHeader, _ua);
      final res = await req.close().timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        client.close();
        return null;
      }
      final body = await res.transform(utf8.decoder).join();
      client.close();
      return body;
    } catch (e) {
      debugPrint('GeocodingService: $uri fallita ($e)');
      return null;
    }
  }

  /// Cerca un luogo per nome. [near] serve solo a ordinare i risultati per
  /// vicinanza: cercando "distributore" da Firenze non ha senso proporre Bolzano.
  Future<List<Place>> search(String query, {LatLng? near}) async {
    if (query.trim().length < 3) return const [];
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': query,
      'format': 'json',
      'limit': '8',
      'addressdetails': '0',
      'accept-language': 'it',
    });
    final body = await _get(uri);
    if (body == null) return const [];
    try {
      final list = jsonDecode(body) as List;
      final places = <Place>[];
      for (final e in list) {
        final lat = double.tryParse('${e['lat']}');
        final lon = double.tryParse('${e['lon']}');
        if (lat == null || lon == null) continue;
        final full = '${e['display_name']}';
        final parts = full.split(',');
        places.add(Place(
          parts.first.trim(),
          parts.length > 1 ? parts.sublist(1).join(',').trim() : '',
          LatLng(lat, lon),
        ));
      }
      if (near != null) {
        const d = Distance();
        places.sort((a, b) =>
            d(near, a.coord).compareTo(d(near, b.coord)));
      }
      return places;
    } catch (e) {
      debugPrint('GeocodingService: risposta non interpretabile ($e)');
      return const [];
    }
  }

  /// Rotta da [a] verso [b], in gradi da nord.
  ///
  /// Finche' la centralina non manda la bussola, la direzione in cui punta la
  /// moto si ricava cosi': da dove eri a dove sei adesso.
  static double bearing(LatLng a, LatLng b) {
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  /// La linea retta verso la destinazione: non è un percorso stradale, e lo
  /// dichiara. È quello che resta quando il calcolo del percorso non risponde,
  /// e in moto meglio una direzione che niente.
  RouteResult straightLine(LatLng from, LatLng to) {
    const d = Distance();
    final meters = d(from, to).toDouble();
    return RouteResult(
      points: [from, to],
      steps: [
        RouteStep(
          instruction: 'Direzione destinazione',
          streetName: '',
          distanceM: meters,
          maneuver: '0',
          modifier: '',
          at: from,
        ),
      ],
      distanceM: meters,
      // stima grossolana a 45 km/h di media, giusto per avere un ETA
      durationS: meters / (45 / 3.6),
      straightLineFallback: true,
    );
  }
}
