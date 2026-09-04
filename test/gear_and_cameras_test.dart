import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:monster_sync_app/data/services/gear_advisor.dart';
import 'package:monster_sync_app/data/services/speed_camera_service.dart';

void main() {
  group('GearAdvisor — quando cambiare marcia sulla 695', () {
    test('sopra i 7.600 giri consiglia la marcia successiva', () {
      expect(GearAdvisor.suggest(currentGear: 3, rpm: 7800), 4);
      expect(GearAdvisor.suggest(currentGear: 1, rpm: 8500), 2);
    });

    test('sotto i 2.600 il Desmodue strappa: consiglia di scalare', () {
      expect(GearAdvisor.suggest(currentGear: 4, rpm: 2200), 3);
      expect(GearAdvisor.suggest(currentGear: 6, rpm: 1800), 5);
    });

    test('in mezzo non dice niente: un indicatore sempre acceso si ignora', () {
      for (final rpm in [3000.0, 4500.0, 6000.0, 7000.0, 7500.0]) {
        expect(GearAdvisor.suggest(currentGear: 3, rpm: rpm), isNull,
            reason: 'a $rpm giri la terza va bene');
      }
    });

    test('non consiglia una settima che non esiste, ne una marcia sotto la prima', () {
      expect(GearAdvisor.suggest(currentGear: 6, rpm: 8800), isNull);
      expect(GearAdvisor.suggest(currentGear: 1, rpm: 1200), isNull);
    });

    test('in folle non consiglia niente: i giri non dicono che marcia mettere', () {
      expect(GearAdvisor.suggest(currentGear: 0, rpm: 8000), isNull);
      expect(GearAdvisor.suggest(currentGear: 0, rpm: 1000), isNull);
    });

    test('urgenza: cresce salendo di giri, e il battito con lei', () {
      final appena = GearAdvisor.urgency(currentGear: 3, rpm: 7650);
      final tirata = GearAdvisor.urgency(currentGear: 3, rpm: 8600);
      final limite = GearAdvisor.urgency(currentGear: 3, rpm: 9500);
      expect(appena, lessThan(tirata));
      expect(tirata, lessThan(1.0));
      expect(limite, 1.0); // oltre il limitatore non puo' essere piu' urgente
      expect(GearAdvisor.urgency(currentGear: 3, rpm: 5000), 0);
    });
  });

  group('SpeedCameraService — lettura di Overpass', () {
    // Risposta vera di Overpass, accorciata: due nodi presi attorno al
    // Passo del Muraglione il 2026-09-04.
    const risposta = '''
{
  "version": 0.6,
  "elements": [
    {"type":"node","id":1776817925,"lat":43.9433953,"lon":11.4215709,
     "tags":{"direction":"275","highway":"speed_camera","maxspeed":"50"}},
    {"type":"node","id":87615340,"lat":43.8651155,"lon":11.5306958,
     "tags":{"direction":"333","highway":"speed_camera"}},
    {"type":"node","id":5,"lat":43.9,"lon":11.5,
     "tags":{"highway":"speed_camera","maxspeed":"70 km/h"}}
  ]
}''';

    test('legge posizione, limite e direzione', () {
      final cams = SpeedCameraService.parse(risposta)!;
      expect(cams.length, 3);
      expect(cams.first.at.latitude, closeTo(43.9433953, 1e-6));
      expect(cams.first.maxSpeed, 50);
      expect(cams.first.direction, 275);
    });

    test('un autovelox senza limite dichiarato resta valido', () {
      final cams = SpeedCameraService.parse(risposta)!;
      expect(cams[1].maxSpeed, isNull);
      expect(cams[1].direction, 333);
    });

    test('"70 km/h" e un limite di 70, non un errore', () {
      final cams = SpeedCameraService.parse(risposta)!;
      expect(cams[2].maxSpeed, 70);
    });

    test('una risposta rotta non fa cadere niente', () {
      expect(SpeedCameraService.parse('<html>errore</html>'), isNull);
      expect(SpeedCameraService.parse('{"elements":[]}'), isEmpty);
    });
  });

  group('SpeedCameraService — chi avvisare e chi no', () {
    // Un autovelox 300 m a nord, uno 300 m a sud.
    const io = LatLng(44.0000, 11.0000);
    final avanti = SpeedCamera(at: LatLng(44.0027, 11.0000), maxSpeed: 70);
    final dietro = SpeedCamera(at: LatLng(43.9973, 11.0000), maxSpeed: 50);

    setUp(() {
      SpeedCameraService.instance.camerasForTest = [avanti, dietro];
    });

    test('andando a nord avvisa per quello davanti, non per quello dietro', () {
      final w = SpeedCameraService.instance.warningFor(io, heading: 0);
      expect(w, isNotNull);
      expect(w!.camera.maxSpeed, 70);
      expect(w.distanceM, closeTo(300, 20));
    });

    test('girata la moto, avvisa per l altro', () {
      final w = SpeedCameraService.instance.warningFor(io, heading: 180);
      expect(w!.camera.maxSpeed, 50);
    });

    test('senza rotta nota avvisa comunque: meglio un avviso in piu', () {
      expect(SpeedCameraService.instance.warningFor(io), isNotNull);
    });

    test('oltre i 600 m non avvisa', () {
      SpeedCameraService.instance.camerasForTest = [
        SpeedCamera(at: const LatLng(44.0090, 11.0000)), // ~1 km a nord
      ];
      expect(SpeedCameraService.instance.warningFor(io, heading: 0), isNull);
    });

    test('la distanza si arrotonda a cinquanta metri: in moto non leggi 287 m', () {
      final w = SpeedCameraService.instance.warningFor(io, heading: 0);
      expect(w!.distanceLabel, anyOf('300 m', '250 m', '350 m'));
    });
  });
}
