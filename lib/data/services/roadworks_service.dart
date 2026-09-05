import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// CANTIERI LUNGO IL PERCORSO — Overpass, gratis e senza chiave
///
/// ## Il traffico in tempo reale non esiste gratis
/// Non è una scorciatoia: **nessuno lo regala**. TomTom, HERE e Google lo danno
/// solo con una chiave e un contratto; i dati di Waze sono riservati ai
/// partner convenzionati. Chi scrive un'app personale non ha modo di sapere se
/// c'è coda adesso.
///
/// Quello che si può sapere da OpenStreetMap sono i **cantieri**: strade in
/// lavorazione, `highway=construction` e `construction:highway`. Su una
/// statale di montagna un senso unico alternato ti ferma più di una coda in
/// tangenziale, e a differenza della coda **c'è ancora domani**: è il tipo di
/// informazione che ha senso mostrare prima di scegliere il percorso, non
/// durante.
///
/// ## Come si chiede
/// Overpass accetta `around` con una **lista di coordinate**, cioè una
/// spezzata: si chiede una volta sola per tutte le alternative insieme,
/// campionando i tracciati (bastano un punto ogni ~800 m: un cantiere è lungo
/// decine di metri ma il raggio di ricerca è 60, e le strade non fanno salti).
///
/// La risposta arriva in qualche secondo, troppo perché la schermata di scelta
/// aspetti: si mostra subito quello che è già noto e i cantieri compaiono dopo.
/// ─────────────────────────────────────────────────────────────────────────────

class Roadwork {
  final LatLng at;

  /// Nome della strada, quando OSM ce l'ha.
  final String name;

  const Roadwork({required this.at, required this.name});
}

class RoadworksService {
  RoadworksService._();
  static final RoadworksService instance = RoadworksService._();

  /// Quanto lontano dal tracciato cercare.
  static const int _aroundM = 60;

  /// Passo di campionamento del tracciato, in metri.
  static const double _sampleStepM = 800;

  /// Non più di questi punti nella query: Overpass ha un limite di lunghezza
  /// dell'URL e più punti significano una risposta più lenta.
  static const int _maxPoints = 120;

  static const _distance = Distance();

  /// I cantieri attorno ai tracciati passati. Lista vuota se non se ne
  /// trovano, `null` se non è stato possibile chiedere (niente rete).
  Future<List<Roadwork>?> along(List<List<LatLng>> tracciati) async {
    final campione = <LatLng>[];
    for (final t in tracciati) {
      campione.addAll(_sample(t));
    }
    if (campione.isEmpty) return const [];

    // Se le alternative sono tante il campione va diradato ancora.
    final punti = campione.length <= _maxPoints
        ? campione
        : [
            for (var i = 0; i < _maxPoints; i++)
              campione[(i * campione.length / _maxPoints).floor()]
          ];

    final coords = punti
        .map((p) => '${p.latitude.toStringAsFixed(5)},'
            '${p.longitude.toStringAsFixed(5)}')
        .join(',');

    final query = '[out:json][timeout:25];'
        '(way(around:$_aroundM,$coords)[highway=construction];'
        'way(around:$_aroundM,$coords)["construction:highway"];);'
        'out tags center 60;';

    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10);
      final req = await client.postUrl(
          Uri.https('overpass-api.de', '/api/interpreter'));
      req.headers.contentType =
          ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
      req.headers.set(HttpHeaders.userAgentHeader,
          'MonsterSync/1.0 (progetto personale, github.com/Lorenzozero)');
      // In POST, che con 120 coordinate l'URL in GET diventa troppo lungo.
      req.write('data=${Uri.encodeQueryComponent(query)}');
      final res = await req.close().timeout(const Duration(seconds: 40));
      if (res.statusCode != 200) {
        client.close();
        debugPrint('RoadworksService: Overpass HTTP ${res.statusCode}');
        return null;
      }
      final body = await res.transform(utf8.decoder).join();
      client.close();
      return parse(body);
    } catch (e) {
      debugPrint('RoadworksService: Overpass non raggiungibile ($e)');
      return null;
    }
  }

  /// Quanti dei [cantieri] cadono sul tracciato [pts].
  static int countOn(List<Roadwork> cantieri, List<LatLng> pts,
      {double withinM = 80}) {
    var n = 0;
    for (final c in cantieri) {
      for (final p in pts) {
        if (_distance(p, c.at) <= withinM) {
          n++;
          break;
        }
      }
    }
    return n;
  }

  @visibleForTesting
  static List<Roadwork>? parse(String body) {
    try {
      final j = jsonDecode(body) as Map<String, dynamic>;
      final out = <Roadwork>[];
      for (final e in (j['elements'] as List? ?? const [])) {
        if (e is! Map) continue;
        // Le way tornano con `center` perché la query chiede "out center".
        final c = e['center'] as Map?;
        final lat = ((c?['lat'] ?? e['lat']) as num?)?.toDouble();
        final lon = ((c?['lon'] ?? e['lon']) as num?)?.toDouble();
        if (lat == null || lon == null) continue;
        final tags = (e['tags'] as Map?) ?? const {};
        out.add(Roadwork(
          at: LatLng(lat, lon),
          name: '${tags['name'] ?? tags['ref'] ?? 'strada in lavorazione'}',
        ));
      }
      return out;
    } catch (e) {
      debugPrint('RoadworksService: risposta illeggibile ($e)');
      return null;
    }
  }

  /// Un punto ogni [_sampleStepM] metri, estremi compresi.
  static List<LatLng> _sample(List<LatLng> pts) {
    if (pts.length < 2) return pts;
    final out = <LatLng>[pts.first];
    var acc = 0.0;
    for (var i = 1; i < pts.length; i++) {
      acc += _distance(pts[i - 1], pts[i]);
      if (acc >= _sampleStepM) {
        out.add(pts[i]);
        acc = 0;
      }
    }
    out.add(pts.last);
    return out;
  }
}
