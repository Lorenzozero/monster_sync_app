import 'dart:io';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:monster_sync_app/ui/core/theme.dart';
import 'package:monster_sync_app/data/services/pace_notes.dart';
import 'package:monster_sync_app/data/services/weather_service.dart';

/// Carica un GPX e mostra le note del copilota.
/// Le velocità di riferimento tengono conto della condizione dell'asfalto:
/// se ha piovuto, scendono.
class PaceNotesView extends StatefulWidget {
  const PaceNotesView({super.key});

  @override
  State<PaceNotesView> createState() => _PaceNotesViewState();
}

class _PaceNotesViewState extends State<PaceNotesView> {
  List<PaceNote> _notes = const [];
  List<TrackPoint> _points = const [];
  String? _fileName;
  bool _loading = false;
  String? _error;
  WeatherInfo? _weather;

  double get _grip => _weather?.gripFactor ?? 1.0;

  Future<void> _pickAndAnalyze() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: false,
      );
      if (res == null || res.files.single.path == null) {
        setState(() => _loading = false);
        return;
      }
      final path = res.files.single.path!;
      if (!path.toLowerCase().endsWith('.gpx')) {
        setState(() {
          _loading = false;
          _error = 'Serve un file .gpx — questo è ${path.split('.').last}.';
        });
        return;
      }

      final xml = await File(path).readAsString();
      final pts = PaceNotesEngine.parseGpx(xml);
      if (pts.length < 20) {
        setState(() {
          _loading = false;
          _error = 'Nel file ho trovato solo ${pts.length} punti: '
              'troppo pochi per ricavare delle note.';
        });
        return;
      }

      // Meteo sul punto di partenza della traccia: serve a decidere
      // di quanto abbassare le velocità di riferimento.
      final w = await WeatherService.instance
          .forPosition(pts.first.lat, pts.first.lon);

      final notes = PaceNotesEngine.generate(pts,
          gripFactor: w?.gripFactor ?? 1.0);

      setState(() {
        _points = pts;
        _notes = notes;
        _weather = w;
        _fileName = res.files.single.name;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Non sono riuscito a leggere il file: $e';
      });
    }
  }

  double get _trackKm {
    if (_points.length < 2) return 0;
    double m = 0;
    for (var i = 1; i < _points.length; i++) {
      m += PaceNotesEngine.distanceMeters(_points[i - 1], _points[i]);
    }
    return m / 1000;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08090B),
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text('PACE NOTES',
            style: GoogleFonts.orbitron(
                fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 2)),
        iconTheme: const IconThemeData(color: AppTheme.activeCyan),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            if (_error != null) _errorBox(_error!),
            Expanded(
              child: _notes.isEmpty ? _empty() : _list(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        color: Colors.black,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _fileName ?? 'Nessuna traccia caricata',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.orbitron(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: _loading ? null : _pickAndAnalyze,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.activeCyan.withValues(alpha: 0.12),
                    foregroundColor: AppTheme.activeCyan,
                    side: const BorderSide(color: AppTheme.activeCyan),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: _loading
                      ? const SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppTheme.activeCyan))
                      : const Icon(Icons.folder_open, size: 15),
                  label: Text('APRI GPX',
                      style: GoogleFonts.orbitron(
                          fontSize: 9, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            if (_notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  _stat('CURVE', '${_notes.length}'),
                  _stat('PERCORSO', '${_trackKm.toStringAsFixed(1)} km'),
                  _stat('PIÙ STRETTA',
                      '${_notes.map((n) => n.radius).reduce((a, b) => a < b ? a : b).toInt()} m'),
                ],
              ),
            ],
            if (_weather != null) ...[
              const SizedBox(height: 12),
              _weatherBanner(_weather!),
            ],
          ],
        ),
      );

  Widget _stat(String label, String value) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: GoogleFonts.orbitron(
                    fontSize: 7, color: AppTheme.textMuted)),
            const SizedBox(height: 2),
            Text(value,
                style: GoogleFonts.orbitron(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.activeCyan)),
          ],
        ),
      );

  Widget _weatherBanner(WeatherInfo w) {
    final dry = w.road == RoadCondition.dry;
    final color = dry ? AppTheme.activeCyan : AppTheme.alertRed;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(dry ? Icons.wb_sunny_outlined : Icons.water_drop,
                  size: 14, color: color),
              const SizedBox(width: 6),
              Text(w.roadLabel,
                  style: GoogleFonts.orbitron(
                      fontSize: 9, fontWeight: FontWeight.bold, color: color)),
              const Spacer(),
              Text('${w.temperatureC.toStringAsFixed(0)}°C',
                  style: GoogleFonts.orbitron(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
            ],
          ),
          if (!dry) ...[
            const SizedBox(height: 6),
            Text(
              'Pioggia nelle ultime 6 ore: ${w.precipitationLast6hMm.toStringAsFixed(1)} mm. '
              'Velocità di riferimento ridotte del ${((1 - _gripSpeedRatio) * 100).round()}%.',
              style: GoogleFonts.inter(fontSize: 10, color: Colors.white70),
            ),
          ],
          if (w.fromCache) ...[
            const SizedBox(height: 4),
            Text('Dato dalla cache: niente rete al momento della lettura.',
                style: GoogleFonts.inter(
                    fontSize: 9, color: AppTheme.textMuted)),
          ],
        ],
      ),
    );
  }

  // v = sqrt(a·R): la velocità scala con la RADICE del fattore di aderenza,
  // quindi una riduzione del 35% di grip vale ~19% di velocità.
  double get _gripSpeedRatio => math.sqrt(_grip);

  Widget _errorBox(String msg) => Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.alertRed.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.alertRed.withValues(alpha: 0.4)),
        ),
        child: Text(msg,
            style: GoogleFonts.inter(fontSize: 11, color: Colors.white)),
      );

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.route, size: 44, color: AppTheme.textMuted),
              const SizedBox(height: 16),
              Text('Apri un file GPX',
                  style: GoogleFonts.orbitron(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              const SizedBox(height: 10),
              Text(
                'Le note descrivono ogni curva prima che arrivi, come farebbe un '
                'copilota da rally: verso, quanto è stretta in scala 1-6, se si '
                'stringe o si apre, e a che distanza è.\n\n'
                'Se ha piovuto nelle ultime ore, le velocità di riferimento '
                'scendono da sole.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                    fontSize: 11, color: AppTheme.textMuted, height: 1.5),
              ),
            ],
          ),
        ),
      );

  Widget _list() => ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        itemCount: _notes.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) => _noteTile(_notes[i], i + 1),
      );

  Widget _noteTile(PaceNote n, int number) {
    // Più la curva è stretta, più il colore vira al rosso: la scala 1-6 è
    // già una scala di rischio, tanto vale mostrarla.
    final t = ((n.severity - 1) / 5).clamp(0.0, 1.0);
    final color = Color.lerp(AppTheme.alertRed, AppTheme.activeCyan, t)!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          // severità
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2),
            ),
            child: Center(
              child: Text('${n.severity}',
                  style: GoogleFonts.teko(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: color,
                      height: 1.0)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      n.direction == CurveDirection.left
                          ? Icons.turn_left
                          : Icons.turn_right,
                      size: 16,
                      color: color,
                    ),
                    const SizedBox(width: 4),
                    Text(n.text.toUpperCase(),
                        style: GoogleFonts.orbitron(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'raggio ${n.radius.toInt()} m · sviluppo ${n.length.toInt()} m · '
                  'dopo ${n.distanceFromPrevious.toInt()} m',
                  style: GoogleFonts.inter(
                      fontSize: 10, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${n.referenceSpeedKmh.toInt()}',
                  style: GoogleFonts.orbitron(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              Text('km/h rif.',
                  style: GoogleFonts.orbitron(
                      fontSize: 6, color: AppTheme.textMuted)),
            ],
          ),
          const SizedBox(width: 6),
          Text('#$number',
              style: GoogleFonts.orbitron(
                  fontSize: 8, color: Colors.white24)),
        ],
      ),
    );
  }
}
