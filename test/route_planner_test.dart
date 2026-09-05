import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:monster_sync_app/data/services/route_planner.dart';
import 'package:monster_sync_app/data/services/roadworks_service.dart';
import 'package:monster_sync_app/data/services/speed_camera_service.dart';

void main() {
  group('polilinea di Valhalla', () {
    // Tracciato vero, ritornato da valhalla1.openstreetmap.de il 2026-09-05
    // per un tratto vicino al Passo del Muraglione.
    const shape = '{}{{rAa|teUpGbKdA`AzDnDlCfHd@bEKjFu@|Cf@lN';

    test('decodifica alla precisione giusta', () {
      final pts = RoutePlanner.decodePolyline6(shape);
      expect(pts.length, 9);
      expect(pts.first.latitude, closeTo(43.989486, 1e-6));
      expect(pts.first.longitude, closeTo(11.643857, 1e-6));
      expect(pts.last.latitude, closeTo(43.989143, 1e-6));
      expect(pts.last.longitude, closeTo(11.642852, 1e-6));
    });

    test('la precisione è 1e-6, non quella di Google', () {
      // È l'errore che manda il percorso in mezzo all'oceano: con 1e-5 le
      // stesse cifre darebbero coordinate dieci volte più grandi, fuori dai
      // limiti stessi delle latitudini.
      final pts = RoutePlanner.decodePolyline6(shape);
      for (final p in pts) {
        expect(p.latitude, inInclusiveRange(43.9, 44.0));
        expect(p.longitude, inInclusiveRange(11.6, 11.7));
      }
    });

    test('una stringa vuota non fa cadere niente', () {
      expect(RoutePlanner.decodePolyline6(''), isEmpty);
    });
  });

  group('autovelox sul percorso', () {
    // Un percorso dritto verso nord, lungo circa 1 km.
    final percorso = [
      for (var i = 0; i <= 10; i++) LatLng(44.0 + i * 0.0009, 11.0),
    ];

    test('conta quelli sulla strada e ignora quelli lontani', () {
      SpeedCameraService.instance.camerasForTest = [
        SpeedCamera(at: const LatLng(44.0027, 11.0)), // sul percorso
        SpeedCamera(at: const LatLng(44.0054, 11.0004)), // ~30 m di lato
        SpeedCamera(at: const LatLng(44.0027, 11.0100)), // 800 m di lato
      ];
      expect(RoutePlanner.countSpeedCameras(percorso), 2);
    });

    test('senza autovelox in cache il conto è zero, non un errore', () {
      SpeedCameraService.instance.camerasForTest = [];
      expect(RoutePlanner.countSpeedCameras(percorso), 0);
    });

    test('lo stesso autovelox non si conta due volte', () {
      // Il percorso ha 11 punti e l autovelox e vicino a piu d uno.
      SpeedCameraService.instance.camerasForTest = [
        SpeedCamera(at: const LatLng(44.0045, 11.0)),
      ];
      expect(RoutePlanner.countSpeedCameras(percorso), 1);
    });
  });

  group('cantieri da Overpass', () {
    const risposta = '''
{
  "version": 0.6,
  "elements": [
    {"type":"way","id":23390364,"center":{"lat":43.7827871,"lon":11.2715628},
     "tags":{"highway":"construction","name":"Ponte al Pino","maxweight":"19"}},
    {"type":"way","id":99,"center":{"lat":44.0036,"lon":11.0},
     "tags":{"construction:highway":"secondary","ref":"SP55"}},
    {"type":"way","id":100,"tags":{"highway":"construction"}}
  ]
}''';

    test('legge posizione e nome, e salta le way senza coordinate', () {
      final c = RoadworksService.parse(risposta)!;
      expect(c.length, 2);
      expect(c.first.name, 'Ponte al Pino');
      expect(c[1].name, 'SP55'); // senza name usa ref
    });

    test('conta solo i cantieri che stanno sul percorso', () {
      final cantieri = RoadworksService.parse(risposta)!;
      final percorso = [
        for (var i = 0; i <= 10; i++) LatLng(44.0 + i * 0.0009, 11.0),
      ];
      // Il Ponte al Pino è a Firenze, lontanissimo: non deve contare.
      expect(RoadworksService.countOn(cantieri, percorso), 1);
    });

    test('una risposta rotta torna null, non una lista vuota', () {
      // La differenza conta: null vuol dire "non lo so", lista vuota vuol dire
      // "nessun cantiere". Nell interfaccia sono due cose diverse.
      expect(RoadworksService.parse('<html>502</html>'), isNull);
      expect(RoadworksService.parse('{"elements":[]}'), isEmpty);
    });
  });
}
