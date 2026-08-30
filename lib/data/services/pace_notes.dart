import 'dart:math' as math;

/// ─────────────────────────────────────────────────────────────────────────────
/// GENERATORE DI PACE NOTES
///
/// Prende una traccia GPS e produce le note del copilota da rally:
///   "in 240 m destra 3, si stringe"
///
/// Il valore non sta nel disegnare la curva, sta nell'anticiparla: la nota
/// arriva PRIMA, e non occupa gli occhi. È la versione realizzabile della
/// traiettoria in realtà aumentata, con un decimo della complessità.
///
/// REGOLA DI PROGETTO, non negoziabile: il sistema può solo dire "rallenta".
/// Non suggerisce mai di andare più forte di come stai andando. Un assistente
/// che incoraggia è un assistente che prima o poi ti mette nei guai.
///
/// PRECISIONE MISURATA (test/pace_notes_test.dart, archi di raggio noto):
///
///   rumore GPS   tornanti e curve strette   curve veloci e curvoni
///   ----------   ------------------------   ----------------------
///   0 m          100% delle classi giuste   100%
///   1,5 m        100%                       ~80% (errori solo al confine
///                                            fra due classi contigue)
///   3 m          100%                       inaffidabile
///
/// Il limite sui curvoni è geometria, non software: con raggio 200 m la
/// freccia su 30 m di base è mezzo metro, cioè meno dell'errore del GPS.
/// Con un ricevitore 10 Hz e cielo libero si sta intorno a 1-1,5 m; sotto
/// gli alberi o fra i palazzi si peggiora, e lì le classi alte vanno prese
/// con le pinze. Le curve strette — quelle che contano per un avviso —
/// reggono in ogni condizione provata.
/// ─────────────────────────────────────────────────────────────────────────────

class TrackPoint {
  final double lat;
  final double lon;
  final double? ele;
  const TrackPoint(this.lat, this.lon, [this.ele]);
}

enum CurveDirection { left, right }

/// Come varia il raggio lungo la curva.
enum CurveTrend { tightens, opens, constant }

class PaceNote {
  final CurveDirection direction;

  /// Severità in scala rally: 1 = tornante, 6 = piega appena.
  final int severity;

  /// Raggio medio della curva, in metri.
  final double radius;

  /// Sviluppo della curva, in metri.
  final double length;

  /// Distanza dalla fine della curva precedente, in metri.
  final double distanceFromPrevious;

  final CurveTrend trend;

  /// Velocità di riferimento per una guida tranquilla, in km/h.
  /// Non è un limite e non è un obiettivo: è il valore oltre il quale la curva
  /// richiede più piega di quella che si tiene normalmente su strada.
  final double referenceSpeedKmh;

  /// Indice del punto di inizio curva nella traccia ricampionata.
  final int startIndex;

  const PaceNote({
    required this.direction,
    required this.severity,
    required this.radius,
    required this.length,
    required this.distanceFromPrevious,
    required this.trend,
    required this.referenceSpeedKmh,
    required this.startIndex,
  });

  String get directionLabel =>
      direction == CurveDirection.left ? 'sinistra' : 'destra';

  String get trendLabel {
    switch (trend) {
      case CurveTrend.tightens:
        return 'si stringe';
      case CurveTrend.opens:
        return 'si apre';
      case CurveTrend.constant:
        return '';
    }
  }

  /// La nota come la leggerebbe un copilota.
  String get text {
    final parts = <String>['$directionLabel $severity'];
    if (length > 120) parts.add('lunga');
    if (trend != CurveTrend.constant) parts.add(trendLabel);
    return parts.join(', ');
  }

  /// Nota completa con la distanza di avvicinamento.
  String textWithDistance() {
    final d = distanceFromPrevious;
    if (d >= 1000) {
      return 'tra ${(d / 1000).toStringAsFixed(1)} km, $text';
    }
    return 'tra ${(d / 50).round() * 50} metri, $text';
  }
}

class PaceNotesEngine {
  // Distanza di ricampionamento: un punto ogni 10 m.
  static const double _resampleStep = 5.0;

  // La curvatura si calcola a DUE SCALE, e non è un vezzo.
  //
  // Su una curva stretta basta una base corta: lo scostamento dalla retta è
  // grande e si misura bene. Su un curvone no: con raggio 200 m, su una base
  // di 30 m la freccia è mezzo metro — meno del rumore del GPS, che quindi
  // domina e fa sembrare stretta una curva larga.
  // Su una base lunga vale l'opposto: i curvoni si misurano bene, i tornanti
  // vengono appiattiti.
  // Quindi: si calcola con entrambe e si tiene quella adatta al raggio trovato.
  static const int _spanFine = 3;    // ±15 m: tornanti e curve strette
  static const int _spanCoarse = 8;  // ±40 m: curve veloci e curvoni
  static const double _coarseThreshold = 80.0; // sopra questo raggio vince la base lunga

  // Sotto questo sviluppo non è una curva, è rumore.
  static const double _minCurveLength = 20.0;

  // Sopra questo raggio la strada è dritta.
  static const double _straightRadius = 400.0;

  /// Accelerazione laterale di riferimento su asfalto asciutto, in g.
  /// 0,50 g corrisponde a circa 27° di piega: andatura da strada, non da pista.
  static const double _baseLateralG = 0.50;

  // ── Parsing GPX ───────────────────────────────────────────────────────────
  //
  // Parser mirato: estrae <trkpt>/<rtept> con lat/lon e l'eventuale <ele>.
  // I GPX sono generati da macchine e questa forma è stabile; un parser XML
  // completo sarebbe più robusto ma qui aggiungerebbe una dipendenza per
  // leggere tre attributi.
  static List<TrackPoint> parseGpx(String gpx) {
    final re = RegExp(
      r'<(?:trkpt|rtept)[^>]*\blat\s*=\s*"([-\d.]+)"[^>]*\blon\s*=\s*"([-\d.]+)"[^>]*>'
      r'(?:(?!</(?:trkpt|rtept)>).)*?(?:<ele>([-\d.]+)</ele>)?',
      dotAll: true,
    );
    final pts = <TrackPoint>[];
    for (final m in re.allMatches(gpx)) {
      final lat = double.tryParse(m.group(1) ?? '');
      final lon = double.tryParse(m.group(2) ?? '');
      if (lat == null || lon == null) continue;
      pts.add(TrackPoint(lat, lon, double.tryParse(m.group(3) ?? '')));
    }
    return pts;
  }

  // ── Geometria ─────────────────────────────────────────────────────────────

  static const double _earthR = 6371000.0;

  static double distanceMeters(TrackPoint a, TrackPoint b) {
    final dLat = _rad(b.lat - a.lat);
    final dLon = _rad(b.lon - a.lon);
    final la1 = _rad(a.lat), la2 = _rad(b.lat);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(la1) * math.cos(la2) * math.sin(dLon / 2) * math.sin(dLon / 2);
    return 2 * _earthR * math.asin(math.min(1.0, math.sqrt(h)));
  }

  static double _rad(double d) => d * math.pi / 180.0;

  /// Proiezione equirettangolare locale: sufficiente su distanze di un giro,
  /// e molto più economica di una proiezione vera.
  static List<List<double>> _toLocalXY(List<TrackPoint> pts) {
    final lat0 = _rad(pts.map((p) => p.lat).reduce((a, b) => a + b) / pts.length);
    final cosLat0 = math.cos(lat0);
    final lon0 = pts.first.lon, latOrigin = pts.first.lat;
    return pts
        .map((p) => [
              _rad(p.lon - lon0) * _earthR * cosLat0,
              _rad(p.lat - latOrigin) * _earthR,
            ])
        .toList();
  }

  /// Ricampiona la polilinea a passo costante: il GPS a 10 Hz dà punti fitti e
  /// irregolari, e la curvatura calcolata su punti irregolari è inutilizzabile.
  static List<List<double>> _resample(List<List<double>> xy, double step) {
    if (xy.length < 2) return xy;
    final out = <List<double>>[xy.first];
    double carry = 0.0;
    for (var i = 1; i < xy.length; i++) {
      final ax = xy[i - 1][0], ay = xy[i - 1][1];
      final bx = xy[i][0], by = xy[i][1];
      final segLen = math.sqrt(math.pow(bx - ax, 2) + math.pow(by - ay, 2));
      if (segLen < 1e-9) continue;
      double t = (step - carry) / segLen;
      while (t <= 1.0) {
        out.add([ax + (bx - ax) * t, ay + (by - ay) * t]);
        t += step / segLen;
      }
      carry = (carry + segLen) % step;
    }
    return out;
  }

  /// Media mobile sulle coordinate: toglie il tremolio residuo del GPS.
  static List<List<double>> _smooth(List<List<double>> xy, int window) {
    if (xy.length < window * 2 + 1) return xy;
    final out = <List<double>>[];
    for (var i = 0; i < xy.length; i++) {
      final lo = math.max(0, i - window), hi = math.min(xy.length - 1, i + window);
      double sx = 0, sy = 0;
      for (var j = lo; j <= hi; j++) {
        sx += xy[j][0];
        sy += xy[j][1];
      }
      final n = (hi - lo + 1).toDouble();
      out.add([sx / n, sy / n]);
    }
    return out;
  }

  /// Curvatura di Menger con segno.
  /// R = (|AB|·|BC|·|CA|) / (4·Area) — il segno del prodotto vettoriale
  /// distingue destra da sinistra.
  /// Ritorna il raggio in metri (positivo = destra, negativo = sinistra),
  /// oppure null se il tratto è rettilineo.
  static double? _signedRadius(List<double> a, List<double> b, List<double> c) {
    final abx = b[0] - a[0], aby = b[1] - a[1];
    final bcx = c[0] - b[0], bcy = c[1] - b[1];
    final cax = a[0] - c[0], cay = a[1] - c[1];

    final ab = math.sqrt(abx * abx + aby * aby);
    final bc = math.sqrt(bcx * bcx + bcy * bcy);
    final ca = math.sqrt(cax * cax + cay * cay);
    if (ab < 1e-6 || bc < 1e-6 || ca < 1e-6) return null;

    final cross = abx * bcy - aby * bcx; // z del prodotto vettoriale
    final area2 = cross.abs();
    if (area2 < 1e-9) return null; // allineati: rettilineo

    final r = (ab * bc * ca) / (2 * area2);
    if (!r.isFinite || r > _straightRadius) return null;
    // cross > 0 = svolta a sinistra nel piano XY (x est, y nord)
    return cross > 0 ? -r : r;
  }

  /// Scala rally: 1 = tornante, 6 = piega appena.
  static int severityForRadius(double r) {
    if (r < 15) return 1;
    if (r < 30) return 2;
    if (r < 60) return 3;
    if (r < 120) return 4;
    if (r < 250) return 5;
    return 6;
  }

  /// v = sqrt(a_lat · R). Con gripFactor < 1 (asfalto bagnato) la velocità di
  /// riferimento scende, ed è tutto il senso di collegare il meteo alle note.
  static double referenceSpeedKmh(double radius, double gripFactor) {
    final aLat = _baseLateralG * 9.81 * gripFactor;
    final v = math.sqrt(aLat * radius); // m/s
    return (v * 3.6).clamp(15.0, 160.0);
  }

  // ── Generazione ───────────────────────────────────────────────────────────

  /// [gripFactor] 1.0 = asciutto, < 1 = aderenza ridotta (vedi WeatherService).
  static List<PaceNote> generate(List<TrackPoint> points,
      {double gripFactor = 1.0}) {
    if (points.length < 8) return const [];

    final resampled = _resample(_toLocalXY(points), _resampleStep);
    // Ogni scala ha la lisciatura che le serve: quella corta dev'essere quasi
    // intatta per non appiattire i tornanti, quella lunga puo' essere lisciata
    // di piu' perche' lavora su raggi grandi e ha bisogno di togliere rumore.
    final xy = _smooth(resampled, 1);        // base corta
    final xyCoarse = _smooth(resampled, 3);  // base lunga
    if (xy.length < _spanCoarse * 2 + 3) return const [];

    // 1. raggio con segno a due scale, punto per punto
    final fineR = List<double?>.filled(xy.length, null);
    final coarseR = List<double?>.filled(xy.length, null);
    for (var i = _spanCoarse; i < xy.length - _spanCoarse; i++) {
      fineR[i] = _signedRadius(xy[i - _spanFine], xy[i], xy[i + _spanFine]);
      coarseR[i] = _signedRadius(
          xyCoarse[i - _spanCoarse], xyCoarse[i], xyCoarse[i + _spanCoarse]);
    }

    // La segmentazione usa la scala CORTA, che vede tutto: i tornanti li
    // misura bene e i curvoni almeno li rileva.
    // La scelta della scala si fa poi PER CURVA, non punto per punto: su un
    // singolo campione il rumore decide, su una curva intera no.
    final radii = fineR;

    // 2. raggruppa i punti consecutivi che curvano nello stesso verso
    final notes = <PaceNote>[];
    int? segStart;
    double lastCurveEndDist = 0.0;

    void closeSegment(int endExclusive) {
      if (segStart == null) return;
      final s = segStart!;
      final n = endExclusive - s;
      segStart = null;
      final length = n * _resampleStep;
      if (length < _minCurveLength) return;

      final vals = <double>[];
      for (var i = s; i < endExclusive; i++) {
        final r = radii[i];
        if (r != null) vals.add(r.abs());
      }
      if (vals.isEmpty) return;

      // Raggio rappresentativo: NON la media e nemmeno la mediana, ma il
      // 30esimo percentile — cioè la parte piu' stretta della curva.
      //
      // Due motivi. Primo, la semantica: una curva che si stringe fino a 30 m
      // e' una "2" anche se inizia a 80, perche' e' il punto stretto quello che
      // devi passare. Secondo, la misura: il ricampionamento e la lisciatura
      // spalmano la curva dentro i rettilinei adiacenti, e quei punti di
      // transizione hanno raggi grandi che tirerebbero su la mediana.
      // Il percentile basso e' anche coerente con la regola di progetto:
      // nel dubbio si avvisa di piu', mai di meno.
      vals.sort();
      double radius = vals[(vals.length * 0.30).floor().clamp(0, vals.length - 1)];

      // Se la curva e' larga, la base corta stava misurando soprattutto rumore:
      // su raggio 200 m la freccia su 30 m di base e' mezzo metro, meno
      // dell'errore del GPS. Si rimisura lo stesso tratto con la base lunga,
      // che su quei raggi e' accurata. Sui tornanti non si entra qui, ed e'
      // giusto: li' la base lunga scavalcherebbe la curva.
      if (radius >= _coarseThreshold) {
        final cvals = <double>[];
        for (var i = s; i < endExclusive; i++) {
          final r = coarseR[i];
          if (r != null) cvals.add(r.abs());
        }
        if (cvals.isNotEmpty) {
          cvals.sort();
          radius = cvals[cvals.length ~/ 2];
        }
      }

      // Andamento: primo terzo contro ultimo terzo
      final third = math.max(1, vals.length ~/ 3);
      double meanOf(Iterable<double> v) =>
          v.isEmpty ? radius : v.reduce((a, b) => a + b) / v.length;
      final rIn = meanOf(vals.take(third));
      final rOut = meanOf(vals.skip(vals.length - third));
      CurveTrend trend = CurveTrend.constant;
      if (rOut < rIn * 0.75) {
        trend = CurveTrend.tightens;
      } else if (rOut > rIn * 1.35) {
        trend = CurveTrend.opens;
      }

      final dir =
          (radii[s] ?? 1) > 0 ? CurveDirection.right : CurveDirection.left;

      notes.add(PaceNote(
        direction: dir,
        severity: severityForRadius(radius),
        radius: radius,
        length: length,
        distanceFromPrevious: (s * _resampleStep) - lastCurveEndDist,
        trend: trend,
        referenceSpeedKmh: referenceSpeedKmh(radius, gripFactor),
        startIndex: s,
      ));
      lastCurveEndDist = endExclusive * _resampleStep;
    }

    for (var i = 0; i < xy.length; i++) {
      final r = radii[i];
      if (r == null) {
        closeSegment(i);
        continue;
      }
      if (segStart == null) {
        segStart = i;
        continue;
      }
      // cambio di verso: chiudi e riapri
      final prev = radii[i - 1];
      if (prev != null && prev.sign != r.sign) {
        closeSegment(i);
        segStart = i;
      }
    }
    closeSegment(xy.length);

    return notes;
  }
}
