import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show IconData, Icons;
import 'package:latlong2/latlong.dart';

import 'package:monster_sync_app/data/services/geocoding_service.dart';
import 'package:monster_sync_app/data/services/fuel_price_service.dart';
import 'package:monster_sync_app/data/services/speed_camera_service.dart';
import 'package:monster_sync_app/data/services/pace_notes.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// PERCORSI ALTERNATIVI — Valhalla, gratis e senza chiave
///
/// ## Perché non più OSRM
/// Il server pubblico di OSRM **non sa dare alternative**: è compilato con
/// Contraction Hierarchies, e con quell'algoritmo il parametro `alternatives`
/// viene semplicemente ignorato — chiesto o no, torna sempre una rotta sola.
/// Verificato il 2026-09-05 su due tragitti diversi.
///
/// **Valhalla di FOSSGIS** (`valhalla1.openstreetmap.de`) invece le dà, ed è
/// meglio su altre tre cose:
///  - ha un **profilo `motorcycle`**: non è l'auto riverniciata, evita le
///    strade che una moto non vuole;
///  - le istruzioni **arrivano già in italiano** (`language: it-IT`), quindi
///    sparisce la tabella di traduzione che era scritta a mano;
///  - il riepilogo dichiara `has_toll`, `has_highway`, `has_ferry`: cose che
///    prima di scegliere un percorso vuoi sapere.
///
/// Anche questo è un server di cortesia: una richiesta per ricerca, non di più.
///
/// ## Cosa c'è nel confronto, e cosa manca
/// Per ogni alternativa: tempo, distanza, **euro di benzina** (dal prezzo vero
/// del MIMIT), **quanti autovelox** ci sono sopra (dalla cache locale, quindi
/// anche senza rete), **quante curve** (dal motore delle pace notes, che era
/// già lì), e se passa in autostrada o al pedaggio.
///
/// **Il traffico in tempo reale non c'è, e non è una dimenticanza**: nessuno lo
/// regala. TomTom, HERE e Google lo danno solo con una chiave e un contratto;
/// i dati di Waze sono riservati ai partner. Quello che si può sapere gratis da
/// OpenStreetMap sono i **cantieri**, che li trova [RoadworksService] — e su
/// una statale un cantiere ti ferma più di una coda.
/// ─────────────────────────────────────────────────────────────────────────────

class RouteOption {
  final RouteResult route;

  /// La strada su cui si fanno più chilometri: "SS67", "A1"…
  final String mainRoad;

  final bool hasHighway;
  final bool hasToll;
  final bool hasFerry;

  /// Autovelox che cadono sul percorso. Contati in locale.
  final int speedCameras;

  /// Curve totali e quante sono strette (raggio sotto i 60 m).
  final int curves;
  final int tightCurves;

  /// Benzina, ai prezzi di oggi. Null finché il prezzo non è noto.
  final double? euro;

  /// Cantieri lungo il percorso. Arriva dopo: la risposta di Overpass è lenta.
  final int? roadworks;

  const RouteOption({
    required this.route,
    required this.mainRoad,
    required this.hasHighway,
    required this.hasToll,
    required this.hasFerry,
    required this.speedCameras,
    required this.curves,
    required this.tightCurves,
    this.euro,
    this.roadworks,
  });

  RouteOption withRoadworks(int n) => RouteOption(
        route: route,
        mainRoad: mainRoad,
        hasHighway: hasHighway,
        hasToll: hasToll,
        hasFerry: hasFerry,
        speedCameras: speedCameras,
        curves: curves,
        tightCurves: tightCurves,
        euro: euro,
        roadworks: n,
      );

  String get durationLabel {
    final min = (route.durationS / 60).round();
    if (min < 60) return '$min min';
    return '${min ~/ 60} h ${(min % 60).toString().padLeft(2, '0')}';
  }

  String get euroLabel => euro == null ? '—' : '${euro!.toStringAsFixed(2)} €';
}

class RoutePlanner {
  RoutePlanner._();
  static final RoutePlanner instance = RoutePlanner._();

  static const _host = 'valhalla1.openstreetmap.de';

  /// Le alternative fra [from] e [to], la migliore per prima.
  ///
  /// Non lancia mai: se Valhalla non risponde torna la linea retta, dichiarata
  /// come tale, così la navigazione parte lo stesso.
  Future<List<RouteOption>> alternatives(LatLng from, LatLng to) async {
    final raw = await _ask(from, to);
    if (raw == null) {
      return [_fallback(GeocodingService.instance.straightLine(from, to))];
    }

    final prezzo = await FuelPriceService.instance.current();

    final out = <RouteOption>[];
    for (final trip in raw) {
      final opt = _measure(trip, prezzo);
      if (opt != null) out.add(opt);
    }
    if (out.isEmpty) {
      return [_fallback(GeocodingService.instance.straightLine(from, to))];
    }
    return out;
  }

  RouteOption _fallback(RouteResult r) => RouteOption(
        route: r,
        mainRoad: 'in linea d\'aria',
        hasHighway: false,
        hasToll: false,
        hasFerry: false,
        speedCameras: 0,
        curves: 0,
        tightCurves: 0,
      );

  Future<List<Map<String, dynamic>>?> _ask(LatLng from, LatLng to) async {
    final body = jsonEncode({
      'locations': [
        {'lat': from.latitude, 'lon': from.longitude},
        {'lat': to.latitude, 'lon': to.longitude},
      ],
      // Non l'auto riverniciata: Valhalla ha un profilo moto vero.
      'costing': 'motorcycle',
      'alternates': 2,
      'units': 'kilometers',
      'language': 'it-IT',
    });

    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10);
      final req = await client.postUrl(Uri.https(_host, '/route'));
      req.headers.contentType = ContentType.json;
      req.headers.set(HttpHeaders.userAgentHeader,
          'MonsterSync/1.0 (progetto personale, github.com/Lorenzozero)');
      req.write(body);
      final res = await req.close().timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) {
        client.close();
        debugPrint('RoutePlanner: Valhalla HTTP ${res.statusCode}');
        return null;
      }
      final text = await res.transform(utf8.decoder).join();
      client.close();

      final j = jsonDecode(text) as Map<String, dynamic>;
      final trips = <Map<String, dynamic>>[];
      final main = j['trip'];
      if (main is Map<String, dynamic>) trips.add(main);
      for (final a in (j['alternates'] as List? ?? const [])) {
        final t = (a as Map)['trip'];
        if (t is Map<String, dynamic>) trips.add(t);
      }
      return trips.isEmpty ? null : trips;
    } catch (e) {
      debugPrint('RoutePlanner: Valhalla non raggiungibile ($e)');
      return null;
    }
  }

  /// Da un viaggio di Valhalla al percorso più le sue misure.
  RouteOption? _measure(Map<String, dynamic> trip, FuelPrice prezzo) {
    final legs = trip['legs'] as List? ?? const [];
    if (legs.isEmpty) return null;

    final points = <LatLng>[];
    final steps = <RouteStep>[];
    final kmPerStrada = <String, double>{};

    for (final leg in legs) {
      final l = leg as Map<String, dynamic>;
      final base = points.length;
      points.addAll(decodePolyline6('${l['shape'] ?? ''}'));

      for (final m in (l['maneuvers'] as List? ?? const [])) {
        final man = m as Map<String, dynamic>;
        final nomi = (man['street_names'] as List?)?.cast<String>() ?? const [];
        final km = ((man['length'] as num?) ?? 0).toDouble();
        if (nomi.isNotEmpty) {
          kmPerStrada[nomi.first] = (kmPerStrada[nomi.first] ?? 0) + km;
        }
        final idx = base + (((man['begin_shape_index'] as num?) ?? 0).toInt());
        steps.add(RouteStep(
          // Valhalla la scrive già in italiano: niente tabella di traduzione.
          instruction: '${man['instruction'] ?? ''}',
          streetName: nomi.isEmpty ? '' : nomi.first,
          distanceM: km * 1000,
          maneuver: '${man['type'] ?? 0}',
          modifier: '',
          at: idx >= 0 && idx < points.length ? points[idx] : points.last,
        ));
      }
    }

    if (points.length < 2) return null;

    final summary = (trip['summary'] as Map?) ?? const {};
    final km = ((summary['length'] as num?) ?? 0).toDouble();
    final sec = ((summary['time'] as num?) ?? 0).toDouble();

    // L'etichetta e' la strada su cui si fanno piu' chilometri. Se pero' due
    // alternative divergono solo piu' avanti, la prima strada e' la stessa per
    // entrambe ("via SR302" e "via SR302") e la scheda non aiuta a scegliere:
    // si aggiunge la seconda strada, quando pesa abbastanza da valere il
    // nome — sotto un quinto del percorso e' solo un raccordo.
    final ordinate = kmPerStrada.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final strada = ordinate.isEmpty
        ? ''
        : (ordinate.length > 1 && ordinate[1].value >= km * 0.2
            ? '${ordinate[0].key} e ${ordinate[1].key}'
            : ordinate[0].key);

    final route = RouteResult(
      points: points,
      steps: steps,
      distanceM: km * 1000,
      durationS: sec,
    );

    final note = _curves(points);

    return RouteOption(
      route: route,
      mainRoad: strada.isEmpty ? 'percorso alternativo' : strada,
      hasHighway: summary['has_highway'] == true,
      hasToll: summary['has_toll'] == true,
      hasFerry: summary['has_ferry'] == true,
      speedCameras: countSpeedCameras(points),
      curves: note.$1,
      tightCurves: note.$2,
      euro: RideCost.compute(
              km: km, lPer100: 5.5, price: prezzo)
          .euro,
    );
  }

  /// Curve totali e curve strette, dal motore delle pace notes.
  ///
  /// Su un tracciato di un navigatore i punti sono radi nei rettilinei e fitti
  /// nelle curve: al motore va bene, ricampiona lui a passo costante.
  static (int, int) _curves(List<LatLng> pts) {
    if (pts.length < 8) return (0, 0);
    final track = [
      for (final p in pts) TrackPoint(p.latitude, p.longitude, null)
    ];
    try {
      final note = PaceNotesEngine.generate(track);
      final strette = note.where((n) => n.severity <= 3).length;
      return (note.length, strette);
    } catch (e) {
      debugPrint('RoutePlanner: conteggio curve fallito ($e)');
      return (0, 0);
    }
  }

  /// Quanti autovelox cadono entro 80 m dal percorso.
  ///
  /// Il confronto è per punti e non per segmenti: con i tracciati di Valhalla,
  /// fitti in curva e radi in rettilineo, la differenza non si vede, e questo
  /// gira in locale in pochi millisecondi.
  static int countSpeedCameras(List<LatLng> pts, {double withinM = 80}) {
    const d = Distance();
    final cams = SpeedCameraService.instance.cameras;
    if (cams.isEmpty || pts.isEmpty) return 0;

    var n = 0;
    for (final c in cams) {
      for (final p in pts) {
        if (d(p, c.at) <= withinM) {
          n++;
          break;
        }
      }
    }
    return n;
  }

  /// Decodifica la polilinea di Valhalla (precisione 1e-6, non 1e-5 come
  /// quella di Google: con la costante sbagliata il percorso finisce in mezzo
  /// all'oceano a un decimo delle coordinate giuste).
  @visibleForTesting
  static List<LatLng> decodePolyline6(String encoded) {
    final out = <LatLng>[];
    var index = 0, lat = 0, lon = 0;

    while (index < encoded.length) {
      int shift = 0, result = 0, b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20 && index < encoded.length);
      lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20 && index < encoded.length);
      lon += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      out.add(LatLng(lat / 1e6, lon / 1e6));
    }
    return out;
  }

  /// L'icona della manovra, dal codice numerico di Valhalla.
  static IconData maneuverIcon(String type) {
    switch (int.tryParse(type) ?? 0) {
      case 4:
      case 5:
      case 6:
        return Icons.flag;
      case 9:
      case 23:
        return Icons.turn_slight_right;
      case 10:
        return Icons.turn_right;
      case 11:
        return Icons.turn_sharp_right;
      case 12:
      case 13:
        return Icons.u_turn_left;
      case 14:
        return Icons.turn_sharp_left;
      case 15:
        return Icons.turn_left;
      case 16:
      case 24:
        return Icons.turn_slight_left;
      case 18:
      case 20:
        return Icons.ramp_right;
      case 19:
      case 21:
        return Icons.ramp_left;
      case 25:
        return Icons.merge;
      case 26:
      case 27:
        return Icons.roundabout_right;
      case 28:
      case 29:
        return Icons.directions_boat;
      default:
        return Icons.straight;
    }
  }
}
