import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:monster_sync_app/data/services/pace_notes.dart';

/// Costruisce una traccia sintetica: rettilineo, arco di raggio noto, rettilineo.
/// [signedRadius] positivo = curva a destra, negativo = a sinistra.
List<TrackPoint> buildTrack({
  required double signedRadius,
  double arcDegrees = 90,
  double straightBefore = 200,
  double straightAfter = 200,
  double lat0 = 44.0,
  double lon0 = 11.0,
}) {
  const earthR = 6371000.0;
  final cosLat = math.cos(lat0 * math.pi / 180);
  // converte metri locali -> gradi
  double toLat(double y) => lat0 + (y / earthR) * 180 / math.pi;
  double toLon(double x) => lon0 + (x / (earthR * cosLat)) * 180 / math.pi;

  final pts = <TrackPoint>[];
  const step = 5.0;

  // rettilineo verso nord
  for (double d = 0; d < straightBefore; d += step) {
    pts.add(TrackPoint(toLat(d), toLon(0)));
  }

  // arco: centro a destra (x = +R) se signedRadius > 0
  final r = signedRadius.abs();
  final sign = signedRadius.sign;
  final cx = sign * r, cy = straightBefore;
  final totalArc = arcDegrees * math.pi / 180;
  final steps = (r * totalArc / step).round();
  for (var i = 0; i <= steps; i++) {
    final a = totalArc * i / steps;
    // parte da angolo che guarda verso il centro
    final x = cx - sign * r * math.cos(a);
    final y = cy + r * math.sin(a);
    pts.add(TrackPoint(toLat(y), toLon(x)));
  }

  // rettilineo finale nella direzione di uscita
  final lastX = cx - sign * r * math.cos(totalArc);
  final lastY = cy + r * math.sin(totalArc);
  final dirX = sign * math.sin(totalArc), dirY = math.cos(totalArc);
  for (double d = step; d <= straightAfter; d += step) {
    pts.add(TrackPoint(toLat(lastY + dirY * d), toLon(lastX + dirX * d)));
  }
  return pts;
}

void main() {
  group('PaceNotesEngine', () {
    test('trova una curva a destra di raggio 50 m e la classifica come 3', () {
      final notes = PaceNotesEngine.generate(buildTrack(signedRadius: 50));
      expect(notes, isNotEmpty);
      final c = notes.reduce((a, b) => a.length >= b.length ? a : b);
      expect(c.direction, CurveDirection.right);
      // tolleranza ampia: lisciatura e ricampionamento allargano un po' il raggio
      expect(c.radius, greaterThan(35));
      expect(c.radius, lessThan(75));
      expect(c.severity, 3);
    });

    test('distingue il verso: raggio negativo = sinistra', () {
      final notes = PaceNotesEngine.generate(buildTrack(signedRadius: -50));
      final c = notes.reduce((a, b) => a.length >= b.length ? a : b);
      expect(c.direction, CurveDirection.left);
    });

    test('un tornante da 12 m e un curvone da 200 m finiscono in classi opposte',
        () {
      final stretta = PaceNotesEngine.generate(buildTrack(signedRadius: 12, arcDegrees: 160))
          .reduce((a, b) => a.length >= b.length ? a : b);
      final larga = PaceNotesEngine.generate(buildTrack(signedRadius: 200))
          .reduce((a, b) => a.length >= b.length ? a : b);
      expect(stretta.severity, lessThan(larga.severity));
      expect(stretta.referenceSpeedKmh, lessThan(larga.referenceSpeedKmh));
    });

    test('un rettilineo puro non genera note', () {
      final pts = <TrackPoint>[];
      for (var i = 0; i < 200; i++) {
        pts.add(TrackPoint(44.0 + i * 0.00005, 11.0));
      }
      expect(PaceNotesEngine.generate(pts), isEmpty);
    });

    test('con asfalto bagnato la velocita di riferimento scende', () {
      final asciutto = PaceNotesEngine.referenceSpeedKmh(60, 1.0);
      final bagnato = PaceNotesEngine.referenceSpeedKmh(60, 0.65);
      expect(bagnato, lessThan(asciutto));
      // sqrt(0.65) ~ 0.806
      expect(bagnato / asciutto, closeTo(math.sqrt(0.65), 0.02));
    });

    test('il parser GPX legge lat, lon e quota', () {
      const gpx = '''
<gpx><trk><trkseg>
  <trkpt lat="44.0000" lon="11.0000"><ele>350.5</ele></trkpt>
  <trkpt lat="44.0010" lon="11.0005"><ele>352.0</ele></trkpt>
  <trkpt lat="44.0020" lon="11.0011"></trkpt>
</trkseg></trk></gpx>''';
      final pts = PaceNotesEngine.parseGpx(gpx);
      expect(pts.length, 3);
      expect(pts.first.lat, closeTo(44.0, 1e-9));
      expect(pts.first.ele, closeTo(350.5, 1e-9));
    });
  });
  _noiseTests();
}

// ─────────────────────────────────────────────────────────────────────────────
// Robustezza al rumore GPS: e' il test che ha guidato la taratura del motore.
// Le curve strette devono reggere sempre, perche' sono quelle che generano
// l'avviso che conta.
// ─────────────────────────────────────────────────────────────────────────────
List<TrackPoint> _withNoise(List<TrackPoint> pts, double sigmaM, int seed) {
  final rnd = math.Random(seed);
  const earthR = 6371000.0;
  final cosLat = math.cos(pts.first.lat * math.pi / 180);
  double g() =>
      (rnd.nextDouble() + rnd.nextDouble() + rnd.nextDouble() + rnd.nextDouble() - 2.0) *
      sigmaM;
  return pts
      .map((p) => TrackPoint(
            p.lat + (g() / earthR) * 180 / math.pi,
            p.lon + (g() / (earthR * cosLat)) * 180 / math.pi,
          ))
      .toList();
}

void _noiseTests() {
  group('robustezza al rumore GPS', () {
    for (final r in [12.0, 25.0, 50.0]) {
      test('curva stretta R=${r.toInt()}m: classe corretta anche con 3 m di rumore',
          () {
        final atteso = PaceNotesEngine.severityForRadius(r);
        var ok = 0;
        for (var seed = 0; seed < 5; seed++) {
          final pts = _withNoise(
              buildTrack(signedRadius: r, arcDegrees: r < 20 ? 160 : 90), 3.0, seed);
          final notes = PaceNotesEngine.generate(pts);
          if (notes.isEmpty) continue;
          final c = notes.reduce((a, b) => a.length >= b.length ? a : b);
          if (c.severity == atteso) ok++;
        }
        expect(ok, greaterThanOrEqualTo(4), reason: 'solo $ok/5 classificazioni corrette');
      });
    }

    test('curvone R=200m: corretto con rumore realistico (1,5 m)', () {
      var ok = 0;
      for (var seed = 0; seed < 5; seed++) {
        final pts = _withNoise(buildTrack(signedRadius: 200), 1.5, seed);
        final notes = PaceNotesEngine.generate(pts);
        if (notes.isEmpty) continue;
        final c = notes.reduce((a, b) => a.length >= b.length ? a : b);
        if (c.severity >= 5) ok++;
      }
      expect(ok, greaterThanOrEqualTo(4));
    });
  });
}
