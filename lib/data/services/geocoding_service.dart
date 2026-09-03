import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// RICERCA DESTINAZIONE E CALCOLO PERCORSO
///
/// Tutto su servizi aperti e senza chiave API:
///   - **Nominatim** (OpenStreetMap) per cercare un posto per nome
///   - **OSRM** per calcolare il percorso stradale e le indicazioni di svolta
///
/// Servono entrambi la rete. Sono i server pubblici di cortesia dei due
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

  /// Percorso stradale da [from] a [to]. Se OSRM non risponde ritorna la linea
  /// retta, segnalandolo con [straightLineFallback].
  Future<RouteResult> route(LatLng from, LatLng to) async {
    final uri = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
      '?overview=full&geometries=geojson&steps=true',
    );
    final body = await _get(uri);
    if (body != null) {
      try {
        final j = jsonDecode(body) as Map<String, dynamic>;
        final routes = j['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final r = routes.first as Map<String, dynamic>;
          final coords =
              (r['geometry']?['coordinates'] as List?) ?? const [];
          final pts = <LatLng>[];
          for (final c in coords) {
            if (c is List && c.length >= 2) {
              pts.add(LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()));
            }
          }
          final steps = <RouteStep>[];
          for (final leg in (r['legs'] as List? ?? const [])) {
            for (final s in (leg['steps'] as List? ?? const [])) {
              final man = s['maneuver'] as Map<String, dynamic>? ?? const {};
              final loc = man['location'] as List? ?? const [];
              steps.add(RouteStep(
                instruction: _italian(
                    '${man['type'] ?? ''}', '${man['modifier'] ?? ''}'),
                streetName: '${s['name'] ?? ''}'.trim(),
                distanceM: ((s['distance'] as num?) ?? 0).toDouble(),
                maneuver: '${man['type'] ?? ''}',
                modifier: '${man['modifier'] ?? ''}',
                at: loc.length >= 2
                    ? LatLng((loc[1] as num).toDouble(), (loc[0] as num).toDouble())
                    : to,
              ));
            }
          }
          if (pts.length >= 2) {
            return RouteResult(
              points: pts,
              steps: steps,
              distanceM: ((r['distance'] as num?) ?? 0).toDouble(),
              durationS: ((r['duration'] as num?) ?? 0).toDouble(),
            );
          }
        }
      } catch (e) {
        debugPrint('GeocodingService: rotta non interpretabile ($e)');
      }
    }

    // Nessuna rotta: linea retta, dichiarata come tale.
    const d = Distance();
    final meters = d(from, to).toDouble();
    return RouteResult(
      points: [from, to],
      steps: [
        RouteStep(
          instruction: 'Direzione destinazione',
          streetName: '',
          distanceM: meters,
          maneuver: 'depart',
          modifier: 'straight',
          at: from,
        ),
      ],
      distanceM: meters,
      // stima grossolana a 45 km/h di media, giusto per avere un ETA
      durationS: meters / (45 / 3.6),
      straightLineFallback: true,
    );
  }

  /// Traduce la manovra OSRM in una frase leggibile a colpo d'occhio.
  static String _italian(String type, String modifier) {
    String dir() {
      switch (modifier) {
        case 'left':
          return 'a sinistra';
        case 'right':
          return 'a destra';
        case 'slight left':
          return 'leggermente a sinistra';
        case 'slight right':
          return 'leggermente a destra';
        case 'sharp left':
          return 'stretta a sinistra';
        case 'sharp right':
          return 'stretta a destra';
        case 'uturn':
          return 'inversione a U';
        default:
          return 'dritto';
      }
    }

    switch (type) {
      case 'depart':
        return 'Parti';
      case 'arrive':
        return 'Sei arrivato';
      case 'turn':
        return 'Gira ${dir()}';
      case 'new name':
      case 'continue':
        return 'Prosegui ${dir()}';
      case 'merge':
        return 'Immettiti ${dir()}';
      case 'on ramp':
        return 'Prendi la rampa ${dir()}';
      case 'off ramp':
        return 'Esci ${dir()}';
      case 'fork':
        return 'Al bivio tieni ${dir()}';
      case 'end of road':
        return 'A fine strada gira ${dir()}';
      case 'roundabout':
      case 'rotary':
        return 'Alla rotonda ${dir()}';
      case 'roundabout turn':
        return 'Alla rotonda gira ${dir()}';
      default:
        return 'Prosegui ${dir()}';
    }
  }
}
