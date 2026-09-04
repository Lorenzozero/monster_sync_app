import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// AUTOVELOX — dati OpenStreetMap, avviso locale
///
/// Le posizioni arrivano da **Overpass**, l'interrogazione pubblica di
/// OpenStreetMap: gratuita, senza chiave, senza registrazione.
///
///   [out:json];node(around:25000,LAT,LON)[highway=speed_camera];out body;
///
/// Molti nodi portano anche `maxspeed` (il limite in quel punto) e `direction`
/// (verso quale rotta guarda l'obiettivo, in gradi).
///
/// ## Perché l'avviso è locale e non "in diretta"
/// In moto la rete non c'è quando serve. Gli autovelox di una zona si
/// scaricano **una volta**, si mettono in cache sul telefono e da lì in poi
/// l'avviso funziona anche in galleria e senza campo. Si riscarica solo quando
/// ti allontani di oltre 15 km dal punto dell'ultimo scaricamento, cioè quando
/// stai davvero uscendo dalla zona coperta.
///
/// Overpass è un servizio di cortesia: una richiesta ogni tanto va bene,
/// martellarlo no. Da qui la cache e la soglia dei 15 km.
/// ─────────────────────────────────────────────────────────────────────────────

class SpeedCamera {
  final LatLng at;

  /// Limite in quel punto, se OSM lo conosce.
  final int? maxSpeed;

  /// Direzione verso cui punta l'obiettivo, in gradi (0 = nord). Serve a non
  /// avvisare per un autovelox che guarda la corsia opposta.
  final double? direction;

  const SpeedCamera({required this.at, this.maxSpeed, this.direction});

  Map<String, dynamic> toJson() => {
        'lat': at.latitude,
        'lon': at.longitude,
        if (maxSpeed != null) 'ms': maxSpeed,
        if (direction != null) 'dir': direction,
      };

  static SpeedCamera? fromJson(Map<String, dynamic> j) {
    final lat = (j['lat'] as num?)?.toDouble();
    final lon = (j['lon'] as num?)?.toDouble();
    if (lat == null || lon == null) return null;
    return SpeedCamera(
      at: LatLng(lat, lon),
      maxSpeed: (j['ms'] as num?)?.toInt(),
      direction: (j['dir'] as num?)?.toDouble(),
    );
  }
}

/// Un autovelox che sta arrivando, con la distanza che manca.
class CameraWarning {
  final SpeedCamera camera;
  final double distanceM;
  const CameraWarning(this.camera, this.distanceM);

  String get distanceLabel => distanceM >= 1000
      ? '${(distanceM / 1000).toStringAsFixed(1)} km'
      : '${(distanceM / 50).round() * 50} m';
}

class SpeedCameraService {
  SpeedCameraService._();
  static final SpeedCameraService instance = SpeedCameraService._();

  static const _kCameras = 'speed_cameras_json';
  static const _kCenterLat = 'speed_cameras_center_lat';
  static const _kCenterLon = 'speed_cameras_center_lon';

  /// Raggio dello scaricamento. 25 km coprono un giro in valle senza dover
  /// ritornare in rete.
  static const int _radiusM = 25000;

  /// Oltre questa distanza dal centro dell'ultimo scaricamento si riscarica.
  static const double _refreshAfterM = 15000;

  /// Da qui in giù si comincia ad avvisare.
  static const double warnDistanceM = 600;

  static const _distance = Distance();

  List<SpeedCamera> _cameras = const [];
  LatLng? _center;
  bool _loading = false;

  List<SpeedCamera> get cameras => _cameras;

  @visibleForTesting
  set camerasForTest(List<SpeedCamera> value) => _cameras = value;

  /// Carica dalla cache e, se serve, riscarica. Non lancia mai: senza rete
  /// resta quello che c'è in cache, che è esattamente il punto.
  Future<void> ensureLoaded(LatLng around) async {
    if (_loading) return;
    _loading = true;
    try {
      final prefs = await SharedPreferences.getInstance();

      if (_cameras.isEmpty) {
        final raw = prefs.getString(_kCameras);
        final lat = prefs.getDouble(_kCenterLat);
        final lon = prefs.getDouble(_kCenterLon);
        if (raw != null && lat != null && lon != null) {
          _cameras = _decode(raw);
          _center = LatLng(lat, lon);
        }
      }

      final tooFar = _center == null ||
          _distance(_center!, around) > _refreshAfterM;
      if (!tooFar) return;

      final fresh = await _download(around);
      if (fresh == null) return; // niente rete: si tiene la cache

      _cameras = fresh;
      _center = around;
      await prefs.setString(_kCameras,
          jsonEncode(fresh.map((c) => c.toJson()).toList()));
      await prefs.setDouble(_kCenterLat, around.latitude);
      await prefs.setDouble(_kCenterLon, around.longitude);
      debugPrint('SpeedCameraService: ${fresh.length} autovelox in cache');
    } finally {
      _loading = false;
    }
  }

  List<SpeedCamera> _decode(String raw) {
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => SpeedCamera.fromJson(e as Map<String, dynamic>))
          .whereType<SpeedCamera>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<SpeedCamera>?> _download(LatLng around) async {
    final query = '[out:json][timeout:25];'
        'node(around:$_radiusM,${around.latitude},${around.longitude})'
        '[highway=speed_camera];out body;';
    final uri = Uri.https(
        'overpass-api.de', '/api/interpreter', {'data': query});
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10);
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.userAgentHeader,
          'MonsterSync/1.0 (progetto personale, github.com/Lorenzozero)');
      final res = await req.close().timeout(const Duration(seconds: 40));
      if (res.statusCode != 200) {
        client.close();
        debugPrint('SpeedCameraService: Overpass HTTP ${res.statusCode}');
        return null;
      }
      final body = await res.transform(utf8.decoder).join();
      client.close();
      return _parse(body);
    } catch (e) {
      debugPrint('SpeedCameraService: Overpass non raggiungibile ($e)');
      return null;
    }
  }

  @visibleForTesting
  static List<SpeedCamera>? parse(String body) => _parse(body);

  static List<SpeedCamera>? _parse(String body) {
    try {
      final j = jsonDecode(body) as Map<String, dynamic>;
      final els = j['elements'] as List? ?? const [];
      final out = <SpeedCamera>[];
      for (final e in els) {
        if (e is! Map) continue;
        final lat = (e['lat'] as num?)?.toDouble();
        final lon = (e['lon'] as num?)?.toDouble();
        if (lat == null || lon == null) continue;
        final tags = (e['tags'] as Map?) ?? const {};
        out.add(SpeedCamera(
          at: LatLng(lat, lon),
          // maxspeed puo' essere "50" o "50 km/h": si prende il numero.
          maxSpeed: _firstInt('${tags['maxspeed'] ?? ''}'),
          direction: double.tryParse('${tags['direction'] ?? ''}'),
        ));
      }
      return out;
    } catch (e) {
      debugPrint('SpeedCameraService: risposta Overpass illeggibile ($e)');
      return null;
    }
  }

  static int? _firstInt(String s) {
    final m = RegExp(r'\d+').firstMatch(s);
    return m == null ? null : int.tryParse(m.group(0)!);
  }

  /// L'autovelox da segnalare adesso, o null.
  ///
  /// Due filtri, entrambi necessari per non gridare al lupo:
  ///  - **distanza** entro [warnDistanceM];
  ///  - **direzione**: l'autovelox dev'essere davanti, non alle spalle. Con il
  ///    [heading] noto si scarta chi sta a più di 75° dalla rotta; senza
  ///    heading si avvisa e basta.
  CameraWarning? warningFor(LatLng position, {double? heading}) {
    CameraWarning? best;
    for (final c in _cameras) {
      final d = _distance(position, c.at).toDouble();
      if (d > warnDistanceM) continue;

      if (heading != null) {
        final bearing = _bearing(position, c.at);
        if (_angleDiff(bearing, heading) > 75) continue;
      }

      if (best == null || d < best.distanceM) {
        best = CameraWarning(c, d);
      }
    }
    return best;
  }

  /// Rotta da [a] verso [b], in gradi da nord.
  static double _bearing(LatLng a, LatLng b) {
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  /// Differenza fra due angoli, sempre fra 0 e 180.
  static double _angleDiff(double a, double b) {
    final d = (a - b).abs() % 360;
    return d > 180 ? 360 - d : d;
  }
}
