import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:monster_sync_app/ui/core/theme.dart';
import 'package:monster_sync_app/ui/core/map_styles.dart';
import 'package:monster_sync_app/ui/features/dashboard/view_models/dashboard_view_model.dart';
import 'package:monster_sync_app/data/services/weather_service.dart';
import 'package:monster_sync_app/data/services/navigation_service.dart';
import 'package:monster_sync_app/data/services/geocoding_service.dart';
import 'package:monster_sync_app/data/services/speed_camera_service.dart';
import 'package:monster_sync_app/data/services/gear_advisor.dart';
import 'package:monster_sync_app/data/services/route_planner.dart';
import 'package:monster_sync_app/data/services/roadworks_service.dart';

class DigitalDashboardView extends StatefulWidget {
  final DashboardViewModel viewModel;

  const DigitalDashboardView({
    super.key,
    required this.viewModel,
  });

  @override
  State<DigitalDashboardView> createState() => _DigitalDashboardViewState();
}

class _DigitalDashboardViewState extends State<DigitalDashboardView> with TickerProviderStateMixin {
  late final MapController _mapController;
  late final FlutterTts _tts;
  late final stt.SpeechToText _speech;
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isListening = false;
  String _assistantText = "Tocca il microfono e dì 'cerca distributore' o parla con le cuffie...";
  String _userSpeechResult = "";
  bool _navigationActive = false;
  int _currentGear = 3;

  Timer? _telemetryTimer;
  Timer? _roarStopTimer;

  // Stato per la visualizzazione temporanea del pulsante Chiudi (X) tramite swipe down
  bool _showCloseButton = false;
  Timer? _closeButtonTimer;

  // Controller per l'animazione di rotazione 3D dell'icona microfono
  late final AnimationController _rotationController;

  /// Battito della marcia consigliata. Non lampeggia: sale e scende piano,
  /// perche' deve farsi notare con la coda dell'occhio senza rubarti la
  /// strada.
  late final AnimationController _shiftPulse;

  // Stato e variabili per la navigazione interna simulata (stile Waze)
  bool _internalNavActive = false;
  int _internalRouteIndex = 0;
  Timer? _internalNavTimer;
  String _internalNextTurn = "Via del Muraglione";
  String _internalDistanceToTurn = "300 m";
  String _internalEta = "12:00";
  String _internalRemainingDist = "0.0 km";
  String _selectedDestinationName = "";

  // Percorso calcolato e passo corrente lungo di esso
  RouteResult? _route;
  int _stepIndex = 0;
  bool _routeLoading = false;

  // ── VISTA IN PROSPETTIVA ──────────────────────────────────────────────────
  // flutter_map disegna sempre a piombo: non sa cosa sia l'inclinazione della
  // camera. La si ottiene deformando il widget con una matrice di prospettiva,
  // che e' poi quello che fanno anche i navigatori veri.
  //
  // Questi numeri non sono a occhio: prima di scriverli qui la scena e' stata
  // montata in CSS con le stesse tile e le stesse proporzioni dello schermo.
  //  - 54 gradi e fuoco a 625 px mandano la linea d'orizzonte 454 px sopra il
  //    centro, cioe' fuori dal riquadro: la mappa riempie tutto e non serve
  //    disegnare un cielo ne' resta un bordo scoperto;
  //  - con quella inclinazione il fondo si comprime, quindi il widget della
  //    mappa deve essere largo il doppio e alto 3,6 volte lo schermo, o in
  //    alto restano strisce vuote.
  static const double _pitch = 1.152;               // 66 gradi in radianti
  static const double _perspectiveDepth = 1 / 625.0;
  /// Quanto la scena scende rispetto al centro dello schermo — cioe' dove
  /// finisce la moto.
  ///
  /// A 0,30 la moto cadeva a 0,80 dell'altezza, sotto il pannello
  /// dell'assistente: mezza nascosta. Deve stare **sopra** la barra in basso,
  /// come il segnalino in tutti i navigatori. La sensazione di vicinanza non
  /// la da' questo numero ma l'inclinazione, che infatti e' salita a 62 gradi.
  static const double _cameraShift = 0.16;
  static const double _planeWidthFactor = 1.8;
  static const double _planeHeightFactor = 2.6;

  /// Dove finisce, sullo schermo, il bordo alto della mappa — misurato in
  /// pixel dal bordo alto del riquadro.
  ///
  /// A 62 gradi la compressione prospettica e' cosi' forte che per riempire
  /// anche l'ultima striscia in alto servirebbe un piano alto quindici volte
  /// lo schermo: centocinquanta tile da scaricare per un dito di immagine.
  /// Si ferma prima, e sopra il bordo va una **foschia**, che e' anche quello
  /// che vedresti davvero guardando lontano. Il calcolo e' lo stesso della
  /// matrice, quindi la fascia si adatta da sola a qualunque schermo.
  double _mapTopEdge(Size size) {
    final yTop = -size.height * _planeHeightFactor / 2;
    final w = 1 - _perspectiveDepth * math.sin(_pitch) * yTop;
    final projected =
        (math.cos(_pitch) * yTop + size.height * _cameraShift) / w;
    return (projected + size.height / 2).clamp(0.0, size.height);
  }

  /// Una sola vista, satellite e inclinata. I due pulsanti che ciclavano gli
  /// stili e spegnevano il 3D sono spariti: in moto una scelta da fare e' una
  /// scelta di troppo.
  static const MapStyle _style = MapStyle.chiara;

  // ── VISTA LIBERA ──────────────────────────────────────────────────────────
  // Col dito si sposta la mappa per guardare cosa c'e' piu' avanti. Poi torna
  // da sola sulla moto: in marcia non puoi ricordarti di rimetterla a posto, e
  // una mappa rimasta a spasso e' peggio di nessuna mappa.
  static const Duration _recenterAfter = Duration(seconds: 3);

  bool _freeLook = false;
  Timer? _recenterTimer;
  late final AnimationController _recenterAnim;
  LatLng? _recenterFrom;
  double? _recenterFromRot;

  // ── AUTOVELOX ─────────────────────────────────────────────────────────────
  // Le posizioni stanno in cache sul telefono (vedi SpeedCameraService):
  // l'avviso funziona in galleria e senza campo, che e' quando serve.
  CameraWarning? _cameraWarning;
  final Set<String> _announcedCameras = {};

  /// Rotta attuale in gradi. Serve a non avvisare per l'autovelox che guarda
  /// la carreggiata opposta. Finche' la centralina non c'e', e' quella
  /// calcolata lungo il percorso.
  double _heading = 15.0;

  // ── RICERCA DESTINAZIONE ──────────────────────────────────────────────────
  Future<void> _openDestinationSearch() async {
    final ctl = TextEditingController();
    List<Place> results = const [];
    bool searching = false;

    final picked = await showModalBottomSheet<Place>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0B0D10),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Future<void> doSearch() async {
            setSheet(() => searching = true);
            final r = await GeocodingService.instance
                .search(ctl.text, near: _myLocation);
            setSheet(() {
              results = r;
              searching = false;
            });
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: ctl,
                        autofocus: true,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => doSearch(),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Dove vuoi andare?',
                          hintStyle: const TextStyle(color: Colors.white38),
                          prefixIcon:
                              const Icon(Icons.search, color: AppTheme.activeCyan),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton(
                      onPressed: searching ? null : doSearch,
                      icon: searching
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppTheme.activeCyan))
                          : const Icon(Icons.arrow_forward,
                              color: AppTheme.activeCyan),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (results.isEmpty && !searching)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Text(
                      'Cerca un paese, una via, un passo. I risultati arrivano da '
                      'OpenStreetMap e servono la rete: il percorso poi resta '
                      'disegnato sulla mappa dell\'app.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                          fontSize: 11, color: AppTheme.textMuted, height: 1.5),
                    ),
                  ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: results.length,
                    itemBuilder: (_, i) {
                      final p = results[i];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.place_outlined,
                            color: AppTheme.activeCyan, size: 20),
                        title: Text(p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13)),
                        subtitle: Text(p.detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 10)),
                        onTap: () => Navigator.pop(ctx, p),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    ctl.dispose();
    if (picked != null) await _chooseRoute(picked);
  }

  // ── SCELTA DEL PERCORSO ───────────────────────────────────────────────────
  //
  // Prima si partiva sull'unico percorso che tornava OSRM. Adesso Valhalla ne
  // propone fino a tre e la scelta e' tua, con davanti quello che serve per
  // decidere: quanto ci metti, quanto costa di benzina, quanti autovelox ci
  // sono sopra e quante curve — che su una Monster non e' un dettaglio.
  Future<void> _chooseRoute(Place dest) async {
    setState(() {
      _routeLoading = true;
      _selectedDestinationName = dest.name;
    });

    final opts = await RoutePlanner.instance.alternatives(_myLocation, dest.coord);
    if (!mounted) return;
    setState(() => _routeLoading = false);

    // Una sola possibilita' (o nessuna rete): non c'e' niente da scegliere.
    if (opts.length < 2) {
      await _startWithRoute(dest, opts.first.route);
      return;
    }

    final scelta = await _showRouteOptions(opts);
    if (scelta == null) {
      // Ripensamento: si torna com'era, senza destinazione appesa.
      if (mounted) setState(() => _selectedDestinationName = '');
      return;
    }
    await _startWithRoute(dest, scelta.route);
  }

  /// La schermata di confronto. Ritorna il percorso scelto, o null.
  ///
  /// I cantieri arrivano da Overpass e ci mettono qualche secondo: la
  /// schermata non li aspetta, si apre subito con quello che e' gia' noto e
  /// li aggiunge quando arrivano.
  Future<RouteOption?> _showRouteOptions(List<RouteOption> opts) {
    var lista = opts;
    final piuVeloce = _indiceMin(lista, (o) => o.route.durationS);
    final piuEconomico = _indiceMin(lista, (o) => o.euro ?? 1e9);
    final piuCurve = _indiceMin(lista, (o) => -o.curves.toDouble());

    return showModalBottomSheet<RouteOption>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0B0D10),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          // Una richiesta sola per tutte le alternative insieme.
          if (lista.every((o) => o.roadworks == null)) {
            RoadworksService.instance
                .along([for (final o in lista) o.route.points]).then((cantieri) {
              if (cantieri == null) return;
              setSheet(() {
                lista = [
                  for (final o in lista)
                    o.withRoadworks(
                        RoadworksService.countOn(cantieri, o.route.points))
                ];
              });
            });
          }

          return ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.9),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.alt_route,
                          color: AppTheme.activeCyan, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'PERCORSI PER ${_selectedDestinationName.toUpperCase()}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.orbitron(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                    itemCount: lista.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _routeCard(
                      ctx,
                      lista[i],
                      veloce: i == piuVeloce,
                      economico: i == piuEconomico && piuEconomico != piuVeloce,
                      curve: i == piuCurve &&
                          piuCurve != piuVeloce &&
                          piuCurve != piuEconomico,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                  child: Text(
                    'Tempi e percorsi da Valhalla (OpenStreetMap), costo alla '
                    'benzina di oggi, autovelox e cantieri da OSM. Il traffico '
                    'in tempo reale non è disponibile senza un servizio a '
                    'pagamento.',
                    style: GoogleFonts.inter(
                        fontSize: 9, color: AppTheme.textMuted, height: 1.5),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static int _indiceMin(List<RouteOption> l, double Function(RouteOption) f) {
    var best = 0;
    for (var i = 1; i < l.length; i++) {
      if (f(l[i]) < f(l[best])) best = i;
    }
    return best;
  }

  Widget _routeCard(BuildContext ctx, RouteOption o,
      {required bool veloce, required bool economico, required bool curve}) {
    final etichette = <(String, Color)>[
      if (veloce) ('PIÙ VELOCE', AppTheme.activeCyan),
      if (economico) ('PIÙ ECONOMICO', Colors.amber),
      if (curve) ('PIÙ CURVE', const Color(0xFFB388FF)),
      if (o.hasHighway) ('AUTOSTRADA', Colors.white54),
      if (o.hasToll) ('PEDAGGIO', Colors.white54),
      if (o.hasFerry) ('TRAGHETTO', Colors.white54),
    ];

    return InkWell(
      onTap: () => Navigator.pop(ctx, o),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: veloce
                ? AppTheme.activeCyan.withOpacity(0.5)
                : Colors.white.withOpacity(0.08),
            width: veloce ? 1.5 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _routeThumb(o),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    'via ${o.mainRoad}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.orbitron(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  o.durationLabel,
                  style: GoogleFonts.orbitron(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: veloce ? AppTheme.activeCyan : Colors.white,
                    height: 1.0,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  o.route.distanceLabel,
                  style: GoogleFonts.orbitron(
                      fontSize: 10, color: AppTheme.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _routeStat(Icons.euro, o.euroLabel, Colors.amber),
                _routeStat(Icons.photo_camera, '${o.speedCameras}',
                    o.speedCameras > 0 ? AppTheme.alertRed : AppTheme.textMuted),
                _routeStat(Icons.all_inclusive,
                    '${o.curves} curve · ${o.tightCurves} strette',
                    const Color(0xFFB388FF)),
                // Finché Overpass non risponde qui non c'è niente, invece di
                // uno zero che sembrerebbe "nessun cantiere".
                if (o.roadworks != null)
                  _routeStat(
                      Icons.construction,
                      o.roadworks == 0 ? 'nessun cantiere' : '${o.roadworks}',
                      o.roadworks == 0 ? AppTheme.textMuted : Colors.orange)
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.5, color: Colors.white24),
                      ),
                      const SizedBox(width: 6),
                      Text('cantieri…',
                          style: GoogleFonts.inter(
                              fontSize: 10, color: Colors.white24)),
                    ],
                  ),
              ],
            ),
            if (etichette.isNotEmpty) ...[
              const SizedBox(height: 9),
              Wrap(
                spacing: 6,
                runSpacing: 5,
                children: [
                  for (final (testo, colore) in etichette)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: colore.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: colore.withOpacity(0.45)),
                      ),
                      child: Text(
                        testo,
                        style: GoogleFonts.orbitron(
                          fontSize: 7.5,
                          fontWeight: FontWeight.bold,
                          color: colore,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
                )),
          ],
        ),
      ),
    );
  }

  /// La miniatura del percorso: tutto il tragitto visto dall'alto, in un
  /// francobollo.
  ///
  /// Serve a capire **dove** passa, che i numeri non dicono: due percorsi da
  /// due ore possono girare da due parti opposte della montagna. La mappa e'
  /// bloccata e senza etichette utili a quella scala — quello che conta e' la
  /// forma della linea.
  Widget _routeThumb(RouteOption o) {
    final pts = o.route.points;
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: SizedBox(
        width: 108,
        height: 78,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FlutterMap(
              options: MapOptions(
                // Inquadra tutto il percorso da sola, con un margine perche'
                // la linea non tocchi i bordi.
                initialCameraFit: pts.length >= 2
                    ? CameraFit.bounds(
                        bounds: LatLngBounds.fromPoints(pts),
                        padding: const EdgeInsets.all(10),
                      )
                    : null,
                initialCenter: pts.isEmpty ? _myLocation : pts.first,
                initialZoom: 9,
                backgroundColor: _style.hazeColor,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.none,
                ),
              ),
              children: [
                _tileLayer(_style.urlTemplate),
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: pts,
                      color: const Color(0xFF1565D8),
                      strokeWidth: 3.0,
                      borderColor: Colors.white,
                      borderStrokeWidth: 1.2,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    if (pts.isNotEmpty)
                      Marker(
                        point: pts.first,
                        width: 10,
                        height: 10,
                        child: _puntino(Colors.white, const Color(0xFF1565D8)),
                      ),
                    if (pts.length > 1)
                      Marker(
                        point: pts.last,
                        width: 10,
                        height: 10,
                        child:
                            _puntino(AppTheme.alertRed, Colors.white),
                      ),
                  ],
                ),
              ],
            ),
            // Un velo leggerissimo: la carta chiara a questa taglia e'
            // accecante accanto al nero della scheda.
            IgnorePointer(
              child: Container(color: Colors.black.withOpacity(0.12)),
            ),
          ],
        ),
      ),
    );
  }

  /// Dove cade sullo schermo la moto.
  ///
  /// Finche' la mappa insegue, e' sempre lo stesso punto e si potrebbe
  /// scriverlo fisso. Ma appena la sposti col dito la moto deve restare
  /// **attaccata alla sua strada** e scorrere via insieme all'asfalto: quindi
  /// si proietta la sua coordinata come fa la mappa, e poi si passa la stessa
  /// matrice della scena. Un solo percorso di calcolo per tutti e due i casi:
  /// se fossero due, prima o poi si scollerebbero.
  Offset _riderOnScreen(Size size) {
    final fisso = Offset(size.width / 2, size.height * (0.5 + _cameraShift));
    try {
      final camera = _mapController.camera;
      final pt = camera.latLngToScreenPoint(_myLocation);
      // Dal sistema del widget-mappa (grande PW x PH) a quello centrato
      // sull'origine della rotazione, che e' il centro dello schermo.
      final dx = pt.x - size.width * _planeWidthFactor / 2;
      final dy = pt.y - size.height * _planeHeightFactor / 2;
      final proiettato =
          MatrixUtils.transformPoint(_groundMatrix(size), Offset(dx, dy));
      return Offset(
          size.width / 2 + proiettato.dx, size.height / 2 + proiettato.dy);
    } catch (_) {
      // La mappa non e' ancora stata disegnata: non ha una camera.
      return fisso;
    }
  }

  Widget _puntino(Color dentro, Color bordo) => Container(
        decoration: BoxDecoration(
          color: dentro,
          shape: BoxShape.circle,
          border: Border.all(color: bordo, width: 1.6),
        ),
      );

  Widget _routeStat(IconData icona, String testo, Color colore) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icona, size: 13, color: colore),
          const SizedBox(width: 5),
          Text(testo,
              style: GoogleFonts.inter(
                  fontSize: 11, color: colore, fontWeight: FontWeight.w600)),
        ],
      );

  // ── PARTENZA SUL PERCORSO SCELTO ──────────────────────────────────────────
  Future<void> _startWithRoute(Place dest, RouteResult r) async {
    if (!mounted) return;

    setState(() {
      _route = r;
      _routePoints = r.points;
      _stepIndex = 0;
      _internalRouteIndex = 0;
      _internalNavActive = true;
      _navigationActive = true;
      _routeLoading = false;
      _selectedDestinationName = dest.name;
      _internalEta = r.etaLabel;
      _internalRemainingDist = r.distanceLabel;
      _internalNextTurn = r.steps.isNotEmpty ? r.steps.first.streetName : '';
      _internalDistanceToTurn =
          r.steps.isNotEmpty ? _fmtDistance(r.steps.first.distanceM) : '';
    });

    _mapController.move(_myLocation, 16.0);

    await _tts.speak(r.straightLineFallback
        ? 'Percorso non disponibile senza rete. Traccio la direzione verso ${dest.name}.'
        : 'Navigazione avviata verso ${dest.name}. ${r.distanceLabel}, arrivo previsto alle ${r.etaLabel}.');

    _startRouteProgress();
  }

  /// Fa avanzare la posizione lungo la rotta.
  /// È una simulazione: quando il GPS della centralina sarà collegato,
  /// _myLocation arriverà da lì e questo timer sparisce.
  void _startRouteProgress() {
    _internalNavTimer?.cancel();
    _internalNavTimer =
        Timer.periodic(const Duration(milliseconds: 700), (t) {
      final route = _route;
      if (!mounted || route == null || route.points.length < 2) {
        t.cancel();
        return;
      }
      if (_internalRouteIndex >= route.points.length - 1) {
        t.cancel();
        setState(() {
          _internalNextTurn = 'Arrivato';
          _internalDistanceToTurn = '';
        });
        _tts.speak('Sei arrivato a destinazione.');
        return;
      }

      final prev = _myLocation;

      setState(() {
        _internalRouteIndex++;
        _myLocation = route.points[_internalRouteIndex];

        // Rotta vera lungo il percorso. Filtrata: la direzione fra due
        // punti consecutivi salta a ogni curva stretta, e una mappa che
        // scatta e' peggio di una mappa ferma.
        _heading = _smoothHeading(_heading,
            GeocodingService.bearing(prev, _myLocation));

        // distanza residua lungo i punti che restano
        const d = Distance();
        double rest = 0;
        for (var i = _internalRouteIndex; i < route.points.length - 1; i++) {
          rest += d(route.points[i], route.points[i + 1]);
        }
        _internalRemainingDist = _fmtDistance(rest);

        // passo corrente: il primo la cui manovra è ancora davanti
        if (route.steps.isNotEmpty) {
          while (_stepIndex < route.steps.length - 1 &&
              d(_myLocation, route.steps[_stepIndex].at) < 25) {
            _stepIndex++;
          }
          final s = route.steps[_stepIndex];
          _internalNextTurn = s.streetName;
          _internalDistanceToTurn =
              _fmtDistance(d(_myLocation, s.at).toDouble());
        }
      });

      // La mappa ruota con te: in una vista dalla sella, in alto c'e'
      // sempre la direzione in cui stai andando. Senza questa rotazione la
      // moto punta verso l'alto ma la strada no, e le due cose litigano.
      //
      // Mentre stai guardando in giro col dito pero' non si tocca: sarebbe
      // come farsi strappare la mappa di mano ogni mezzo secondo.
      if (!_freeLook) {
        _mapController.moveAndRotate(
            _myLocation, _mapController.camera.zoom, -_heading);
      }
      _checkSpeedCameras();
    });
  }

  void _stopInternalNavigation() {
    _internalNavTimer?.cancel();
    setState(() {
      _internalNavActive = false;
      _navigationActive = false;
      _route = null;
      _routePoints = [];
      _selectedDestinationName = '';
    });
  }

  /// Media fra la rotta di prima e quella nuova, presa per la via corta.
  ///
  /// Senza il passaggio da -179 a +179 gradi la mappa farebbe un giro
  /// completo su se stessa ogni volta che passi per il nord.
  static double _smoothHeading(double vecchia, double nuova) {
    var delta = (nuova - vecchia + 540) % 360 - 180;
    return (vecchia + delta * 0.35 + 360) % 360;
  }

  static String _fmtDistance(double m) =>
      m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '${m.round()} m';

  void _triggerShowCloseButton() {
    if (!mounted) return;
    setState(() {
      _showCloseButton = true;
    });
    _closeButtonTimer?.cancel();
    _closeButtonTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          _showCloseButton = false;
        });
      }
    });
  }

  // Coordinate di riferimento (Passo del Muraglione, Mugello/Toscana) - NON final per aggiornamento in corsa
  LatLng _myLocation = const LatLng(43.9961, 11.6429);

  // Coordinata distributore IP più vicino
  final LatLng _gasStationLocation = const LatLng(44.0010, 11.6520);

  // Lista di coordinate per tracciare la rotta (polyline)
  List<LatLng> _routePoints = [];

  // Controller per le animazioni del microfono (onda sonora)
  late AnimationController _waveController;

  // Meteo reale (Open-Meteo). Null finche' la prima lettura non arriva.
  WeatherInfo? _weather;

  Future<void> _loadSpeedCameras() async {
    await SpeedCameraService.instance.ensureLoaded(_myLocation);
    if (mounted) setState(() {});
  }

  /// Controlla se c'e' un autovelox davanti e, la prima volta, lo annuncia.
  ///
  /// L'annuncio parte una volta sola per autovelox: ripeterlo ogni mezzo
  /// secondo mentre ti avvicini sarebbe insopportabile. L'elenco di quelli
  /// gia' annunciati si svuota appena nessuno e' piu' in vista, cosi' al
  /// ritorno lo stesso autovelox avvisa di nuovo.
  void _checkSpeedCameras() {
    final w = SpeedCameraService.instance
        .warningFor(_myLocation, heading: _heading);

    if (w == null) {
      if (_cameraWarning != null || _announcedCameras.isNotEmpty) {
        setState(() {
          _cameraWarning = null;
          _announcedCameras.clear();
        });
      }
      return;
    }

    setState(() => _cameraWarning = w);

    final key = '${w.camera.at.latitude},${w.camera.at.longitude}';
    if (_announcedCameras.add(key)) {
      HapticFeedback.heavyImpact();
      final metri = (w.distanceM / 50).round() * 50;
      final limite = w.camera.maxSpeed;
      _tts.speak(limite == null
          ? 'Attenzione, autovelox tra $metri metri.'
          : 'Attenzione, autovelox tra $metri metri. Limite $limite.');
    }
  }

  Future<void> _loadWeather() async {
    final w = await WeatherService.instance
        .forPosition(_myLocation.latitude, _myLocation.longitude);
    if (mounted && w != null) setState(() => _weather = w);
  }

  @override
  void initState() {
    super.initState();
    _mapController = MapController();

    // Forza la modalità Landscape e nascondi le barre di sistema
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Inizializza TTS e Speech Recognition
    _tts = FlutterTts();
    _tts.setLanguage("it-IT");
    _tts.setSpeechRate(0.5);
    _tts.setVolume(1.0);

    _speech = stt.SpeechToText();

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    // Inizializza rotazione 3D microfono
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _shiftPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);

    // Mezzo secondo per tornare sulla moto. Uno scatto secco disorienta:
    // quando la mappa si rimette a posto devi capire da dove sei tornato.
    _recenterAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..addListener(_stepRecenter);

    // Simula telemetria attiva in marcia (solo cambio marcia)
    _telemetryTimer = Timer.periodic(const Duration(milliseconds: 800), (timer) {
      if (!mounted) return;
      setState(() {
        if (timer.tick % 15 == 0) {
          _currentGear = (_currentGear == 3) ? 4 : 3;
        }
      });
      // L'avviso autovelox non dipende dall'avere una rotta impostata: deve
      // funzionare anche quando stai solo girando senza meta.
      _checkSpeedCameras();
    });

    // Meteo vero: serve anche a sapere se l'asfalto e' bagnato, non solo
    // a scrivere i gradi.
    _loadWeather();

    // Autovelox della zona: si scaricano una volta e restano sul telefono.
    _loadSpeedCameras();

    // Ruggito e vibrazione all'apertura del cruscotto: insieme, una volta.
    _playStartRoar();
    _rumble();
  }

  /// Il ruggito all'apertura del cruscotto — e solo li'.
  ///
  /// Tre cose che il semplice `play()` non faceva:
  ///  - **volume al massimo e canale multimediale**: di suo audioplayers
  ///    chiede il canale delle notifiche, che con il telefono in tasca sotto
  ///    la giacca non lo senti;
  ///  - **abbassa la musica invece di fermarla** (duckOthers): tre secondi di
  ///    sgasata non devono mettere in pausa quello che stai ascoltando;
  ///  - **si ferma dopo 3,5 secondi** comunque: dev'essere una sgasata, non un
  ///    sottofondo. E' l'unico suono del cruscotto, a parte la voce che detta
  ///    le indicazioni di navigazione.
  ///
  /// Il percorso audio resta quello di sistema: se hai l'interfono nel casco
  /// il ruggito arriva li', non dall'altoparlante del telefono.
  Future<void> _playStartRoar() async {
    try {
      await _audioPlayer.setReleaseMode(ReleaseMode.stop);
      await _audioPlayer.setAudioContext(
        AudioContextConfig(
          route: AudioContextConfigRoute.system,
          focus: AudioContextConfigFocus.duckOthers,
          respectSilence: false,
        ).build(),
      );
      await _audioPlayer.setVolume(1.0);
      await _audioPlayer.play(AssetSource('engine_roar.ogg'), volume: 1.0);
      _roarStopTimer?.cancel();
    _listenWatchdog?.cancel();
    _speech.cancel();
      _roarStopTimer = Timer(const Duration(milliseconds: 3500), () {
        _audioPlayer.stop();
      });
    } catch (e) {
      debugPrint("Impossibile riprodurre ruggito iniziale: $e");
    }
  }

  /// La vibrazione che accompagna il ruggito.
  ///
  /// Niente pacchetto `vibration`: su questo progetto una dipendenza nativa in
  /// piu' e' gia' costata tre build fallite di fila (file_picker, con lo
  /// scontro fra compileSdk). `HapticFeedback` sta dentro Flutter, non tocca
  /// il build Android, e ripetuto a intervalli stretti da' il rombo invece del
  /// singolo colpetto.
  Future<void> _rumble() async {
    for (var i = 0; i < 10; i++) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 75));
    }
  }

  @override
  void dispose() {
    // Ripristina l'orientamento verticale e mostra le barre di sistema
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    _telemetryTimer?.cancel();
    _closeButtonTimer?.cancel();
    _roarStopTimer?.cancel();
    _rotationController.dispose();
    _shiftPulse.dispose();
    _recenterAnim.dispose();
    _recenterTimer?.cancel();
    _waveController.dispose();
    _audioPlayer.dispose();
    _tts.stop();
    super.dispose();
  }

  // ── ASSISTENTE VOCALE ─────────────────────────────────────────────────────
  //
  // Prima l'ascolto non finiva quasi mai, e per tre motivi diversi:
  //  - `listen()` partiva senza `listenFor` ne' `pauseFor`, quindi il motore
  //    restava aperto a tempo indeterminato;
  //  - `onStatus` scriveva soltanto nel log: quando il riconoscimento si
  //    chiudeva da solo, l'interfaccia restava convinta di stare ancora ad
  //    ascoltare, con i bordi rossi accesi;
  //  - `initialize()` veniva richiamata a ogni tocco, aprendo una sessione
  //    sopra l'altra.
  // In piu' un `Future.delayed` di 4 secondi lanciava da solo il comando
  // "cerca distributore" se non avevi ancora detto niente: cercava benzina
  // mentre stavi ancora prendendo fiato.
  //
  // Adesso l'ascolto ha quattro uscite, e almeno una scatta sempre:
  //  1. hai finito di parlare  -> `pauseFor`, 3 s di silenzio;
  //  2. non parli affatto      -> `listenFor`, 12 s;
  //  3. il motore muore zitto  -> il cane da guardia, 15 s (succede davvero,
  //     soprattutto con l'audio dirottato sull'interfono bluetooth);
  //  4. ritocchi il microfono  -> interrompe.
  bool _speechReady = false;
  Timer? _listenWatchdog;

  Future<void> _ensureSpeechReady() async {
    if (_speechReady) return;
    _speechReady = await _speech.initialize(
      onStatus: (status) {
        // Il motore dichiara di aver smesso: l'interfaccia deve seguirlo,
        // altrimenti resta accesa per sempre.
        if (status == stt.SpeechToText.doneStatus ||
            status == stt.SpeechToText.notListeningStatus) {
          if (_isListening) _stopListening();
        }
      },
      onError: (error) {
        debugPrint('Speech error: ${error.errorMsg}');
        _stopListening(message: 'Non sono riuscito ad ascoltare. Riprova.');
      },
    );
  }

  Future<void> _toggleVoiceListening() async {
    if (_isListening) {
      await _stopListening(message: 'Ascolto interrotto.');
      return;
    }

    await _ensureSpeechReady();
    if (!mounted) return;

    if (!_speechReady) {
      // Niente microfono (permesso negato, o emulatore). Si dice com'e'
      // invece di fingere un comando riconosciuto, come faceva prima.
      setState(() => _assistantText =
          'Microfono non disponibile: controlla i permessi.');
      return;
    }

    setState(() {
      _isListening = true;
      _assistantText = 'Ti ascolto: dimmi dove vuoi andare.';
      _userSpeechResult = '';
    });
    _waveController.repeat();

    await _speech.listen(
      onResult: (result) {
        if (!mounted) return;
        setState(() => _userSpeechResult = result.recognizedWords);
        if (result.finalResult) _processVoiceCommand(_userSpeechResult);
      },
      listenOptions: stt.SpeechListenOptions(
        localeId: 'it-IT',
        partialResults: true,
        // Tre secondi di silenzio e ha finito di parlare.
        pauseFor: const Duration(seconds: 3),
        // Dodici secondi in tutto: piu' di cosi' non e' un comando.
        listenFor: const Duration(seconds: 12),
        cancelOnError: true,
      ),
    );

    _listenWatchdog?.cancel();
    _listenWatchdog = Timer(const Duration(seconds: 15), () {
      if (_isListening) {
        _stopListening(message: 'Non ho sentito niente.');
      }
    });
  }

  /// Chiude l'ascolto e riporta l'interfaccia a riposo. Idempotente: puo'
  /// arrivarci sia il timer, sia `onStatus`, sia il tocco sul microfono.
  Future<void> _stopListening({String? message}) async {
    _listenWatchdog?.cancel();
    _listenWatchdog = null;
    try {
      await _speech.stop();
    } catch (_) {
      // gia' fermo
    }
    if (!mounted) return;
    _waveController.stop();
    _waveController.value = 0;
    setState(() {
      _isListening = false;
      if (message != null) _assistantText = message;
    });
  }

  // Elabora il comando vocale dell'utente
  void _processVoiceCommand(String command) async {
    await _stopListening();
    if (command.trim().isEmpty) {
      if (mounted) {
        setState(() => _assistantText = 'Non ho capito. Riprova.');
      }
      return;
    }

    final cmdLower = command.toLowerCase();

    if (cmdLower.contains("distributore") || cmdLower.contains("benzina") || cmdLower.contains("carburante")) {
      setState(() => _assistantText = "Comando ricevuto: '$command'");

      // Sceglie il navigatore migliore disponibile: OsmAnd (offline, con
      // limiti e autovelox) > Waze (solo con rete) > mappa interna.
      final nav = await NavigationService.instance.navigateTo(
        _gasStationLocation.latitude,
        _gasStationLocation.longitude,
        name: 'Distributore IP',
        fromLat: _myLocation.latitude,
        fromLon: _myLocation.longitude,
      );

      if (nav.target == NavigationTarget.internal) {
        // Nessun navigatore: almeno disegna la rotta sulla mappa dell'app
        setState(() {
          _navigationActive = true;
          _routePoints = [
            _myLocation,
            const LatLng(43.9980, 11.6450), // Passa dall'autovelox
            _gasStationLocation,
          ];
        });
        _mapController.move(
            LatLng(
              (_myLocation.latitude + _gasStationLocation.latitude) / 2,
              (_myLocation.longitude + _gasStationLocation.longitude) / 2,
            ),
            14.5);
      }

      await _tts.speak(nav.spokenMessage);
    } else {
      setState(() =>
          _assistantText = "Non ho capito: '$command'. Prova con 'distributore'.");
      await _tts.speak("Non ho capito, puoi ripetere il comando?");
    }
  }

  // ── LA MAPPA INCLINATA ───────────────────────────────────────
  //
  // Il segno della rotazione e' negativo, e non e' un dettaglio: in CSS un
  // rotateX positivo allontana il bordo alto, in Flutter — dove l'asse y punta
  // in basso — succede l'opposto e la mappa si ribalterebbe verso di te.
  // Verificato con vector_math prima di scriverlo: con +pitch il lontano
  // ingrandisce invece di rimpicciolire.
  Widget _buildGround(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return ClipRect(
      child: Transform(
        alignment: Alignment.center,
        transform: _groundMatrix(size),
        child: OverflowBox(
          minWidth: size.width * _planeWidthFactor,
          maxWidth: size.width * _planeWidthFactor,
          minHeight: size.height * _planeHeightFactor,
          maxHeight: size.height * _planeHeightFactor,
          child: _buildMap(),
        ),
      ),
    );
  }

  /// Un livello di tile.
  Widget _tileLayer(String url) {
    return TileLayer(
      urlTemplate: url,
      userAgentPackageName: 'com.example.monster_sync_app',
      // Con la mappa inclinata servono tile ben oltre il bordo visibile: il
      // fondo della scena e' molto piu' largo di quello che si vede.
      // Il piano e' gia' molto piu' grande dello schermo: un buffer di
      // preload sopra a quello raddoppierebbe le tile da scaricare per
      // niente.
      panBuffer: 0,
      keepBuffer: 3,
    );
  }

  /// Raddrizza un marcatore dentro la scena inclinata: resta in piedi sul suo
  /// punto della strada, come un cartello, invece di essere spalmato
  /// sull'asfalto insieme a tutto il resto.
  Widget _billboard(Widget child) {
    return Transform(
      alignment: Alignment.bottomCenter,
      transform: Matrix4.identity()..rotateX(_pitch),
      child: child,
    );
  }

  Widget _buildMap() {
    final style = _style;
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _myLocation,
        // Zoom alto: in navigazione conta la strada sotto le ruote, non la
        // provincia. La prospettiva ingrandisce ancora il primo piano.
        initialZoom: 18.0,
        initialRotation: -_heading,
        minZoom: 14.0,
        maxZoom: 19.0,
        backgroundColor: _style.hazeColor,
        interactionOptions: const InteractionOptions(
          // Trascinamento e pizzico si', rotazione no: l'orientamento della
          // mappa lo decide la rotta di marcia, non il pollice. Girarla a
          // mano vorrebbe dire perdere il "in alto c'e' dove stai andando",
          // che e' tutto il senso di questa vista.
          flags: InteractiveFlag.drag |
              InteractiveFlag.pinchZoom |
              InteractiveFlag.doubleTapZoom |
              InteractiveFlag.flingAnimation,
        ),
        onMapEvent: _onMapEvent,
      ),
      children: [
        // La carta OSM ha gia' dentro i nomi delle vie: non serve un
        // secondo livello sopra, come serviva alla fotografia aerea.
        _tileLayer(style.urlTemplate),

        if (_navigationActive)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _routePoints,
                color: const Color(0xFF8B5CF6),
                strokeWidth: 8.0,
                borderColor: const Color(0xFF5B21B6),
                borderStrokeWidth: 3.0,
              ),
            ],
          ),

        MarkerLayer(
          markers: [
            // Autovelox veri, da OpenStreetMap
            ...SpeedCameraService.instance.cameras.map((c) => Marker(
                  point: c.at,
                  width: 40,
                  height: 40,
                  alignment: Alignment.bottomCenter,
                  child: _billboard(Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.8),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.alertRed, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.alertRed.withOpacity(0.4),
                          blurRadius: 8,
                        )
                      ],
                    ),
                    child: const Center(
                      child: Icon(Icons.photo_camera,
                          color: AppTheme.alertRed, size: 18),
                    ),
                  )),
                )),

            // Distributore
            Marker(
              point: _gasStationLocation,
              width: 44,
              height: 44,
              alignment: Alignment.bottomCenter,
              child: _billboard(Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.85),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.amber, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.amber.withOpacity(0.3),
                      blurRadius: 8,
                    )
                  ],
                ),
                child: const Center(
                  child: Icon(Icons.local_gas_station,
                      color: Colors.amber, size: 20),
                ),
              )),
            ),
          ],
        ),
      ],
    );
  }

  /// Ogni movimento della mappa passa di qui.
  ///
  /// Si distingue chi l'ha mosso: se e' stato il dito si entra in vista libera
  /// e parte il conto alla rovescia per il rientro; se e' stato il codice
  /// (l'inseguimento della moto, o l'animazione di rientro) non si tocca
  /// niente, o si rientrerebbe all'infinito.
  void _onMapEvent(MapEvent e) {
    const dita = {
      MapEventSource.dragStart,
      MapEventSource.onDrag,
      MapEventSource.dragEnd,
      MapEventSource.multiFingerGestureStart,
      MapEventSource.onMultiFinger,
      MapEventSource.multiFingerEnd,
      MapEventSource.doubleTap,
      MapEventSource.doubleTapHold,
      MapEventSource.flingAnimationController,
      MapEventSource.scrollWheel,
    };

    if (dita.contains(e.source)) {
      _recenterAnim.stop();
      _recenterTimer?.cancel();
      _recenterTimer = Timer(_recenterAfter, _recenterToRider);
      if (!_freeLook) setState(() => _freeLook = true);
      return;
    }

    // Anche senza dito la moto va riposizionata: la mappa si e' mossa e lei
    // sta appesa a una coordinata, non a un punto dello schermo.
    if (mounted) setState(() {});
  }

  /// Riporta la mappa sulla moto, con mezzo secondo di animazione.
  void _recenterToRider() {
    if (!mounted) return;
    try {
      _recenterFrom = _mapController.camera.center;
      _recenterFromRot = _mapController.camera.rotation;
    } catch (_) {
      _recenterFrom = null;
    }
    _recenterAnim.forward(from: 0);
  }

  void _stepRecenter() {
    final da = _recenterFrom;
    final daRot = _recenterFromRot;
    if (da == null || daRot == null) return;

    final t = Curves.easeInOut.transform(_recenterAnim.value);

    // La rotazione si interpola per la via corta, o passando per il nord la
    // mappa fa un giro completo su se stessa.
    var deltaRot = ((-_heading) - daRot + 540) % 360 - 180;

    _mapController.moveAndRotate(
      LatLng(
        da.latitude + (_myLocation.latitude - da.latitude) * t,
        da.longitude + (_myLocation.longitude - da.longitude) * t,
      ),
      _mapController.camera.zoom,
      daRot + deltaRot * t,
    );

    if (_recenterAnim.isCompleted && _freeLook) {
      setState(() => _freeLook = false);
    }
  }

  /// La matrice della scena. Serve a due cose che devono restare d'accordo:
  /// deformare la mappa, e sapere dove finisce sullo schermo un punto che ci
  /// sta sopra.
  Matrix4 _groundMatrix(Size size) => Matrix4.identity()
    ..setEntry(3, 2, _perspectiveDepth)
    ..translate(0.0, size.height * _cameraShift)
    ..rotateX(-_pitch);

  /// La moto, ancorata dove il centro della mappa finisce sullo schermo.
  Widget _buildRider(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final posizione = _riderOnScreen(size);
    return Positioned(
      left: posizione.dx - 66,
      top: posizione.dy - 66,
      width: 132,
      height: 132,
      child: IgnorePointer(
        child: Center(
          child: SizedBox(
            width: 132,
            height: 132,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // L'onda sta per terra, non in aria: schiacciata di cos(62°)
                // diventa l'ellisse che un cerchio disegnato sull'asfalto fa
                // vedere da questa angolazione.
                Transform.scale(
                  // cos(66°): l'ellisse che un cerchio sull'asfalto fa vedere
                  // da questa angolazione.
                  scaleY: 0.41,
                  child: _RippleRing(),
                ),
                SizedBox(
                  width: 118,
                  height: 118,
                  child: ModelViewer(
                    src: 'assets/ducati_monster_3d.glb',
                    alt: 'Ducati 3D Model',
                    cameraControls: false,
                    disableZoom: true,
                    autoRotate: false,
                    // **L'angolo della moto deve essere quello della strada.**
                    // Era a 22 gradi: la moto vista quasi a piombo, appoggiata
                    // su un asfalto inclinato di 66 — due punti di vista
                    // diversi nella stessa immagine, ed e' quello che la faceva
                    // sembrare incollata sopra invece che dentro la scena.
                    // Il secondo valore di cameraOrbit e' l'angolo dalla
                    // verticale: messo a 66 come l'inclinazione del piano, la
                    // moto e la strada si guardano dallo stesso punto.
                    // Piu' lontana del prima (era 65%): vista di taglio la
                    // moto e' lunga, e a distanza ravvicinata il modello
                    // finiva tagliato ai bordi del riquadro.
                    cameraOrbit: '0deg 66deg 105%',
                    // L'ombra la appoggia per terra. Morbida, o sembra
                    // ritagliata col cutter.
                    shadowIntensity: 0.9,
                    shadowSoftness: 1.0,
                    backgroundColor: Colors.transparent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final telemetry = widget.viewModel.data;

    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragUpdate: (details) {
          if (details.delta.dy > 8) {
            _triggerShowCloseButton();
          }
        },
        child: Stack(
          children: [
          // ── LA STRADA, INCLINATA COME LA VEDI DALLA SELLA ───────────
          _buildGround(context),

          // ── LA DISTANZA CHE SBIANCA ─────────────────────────────────
          // Un velo solo, del colore della carta. Fa due lavori in uno:
          // copre il bordo alto della mappa (dove il piano finisce) e da'
          // profondita', perche' e' quello che fa la foschia davvero — il
          // lontano non diventa scuro, diventa lattiginoso.
          //
          // Sulla fotografia aerea di prima il velo era nero, per non farsi
          // sbiancare i numeri al neon dal sole sui tetti. Su una carta chiara
          // un velo nero farebbe fango: i riquadri dell'interfaccia hanno gia'
          // il loro fondo scuro e si leggono da soli.
          IgnorePointer(
            child: Builder(builder: (ctx) {
              final size = MediaQuery.of(ctx).size;
              final edge = _mapTopEdge(size);
              final fine = ((edge + size.height * 0.42) / size.height)
                  .clamp(0.0, 1.0);
              return DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [
                      0.0,
                      (edge / size.height).clamp(0.0, fine),
                      fine,
                      1.0,
                    ],
                    colors: [
                      _style.hazeColor,
                      _style.hazeColor.withOpacity(0.82),
                      _style.hazeColor.withOpacity(0.0),
                      _style.hazeColor.withOpacity(0.0),
                    ],
                  ),
                ),
                child: const SizedBox.expand(),
              );
            }),
          ),

          // ── LA MOTO ───────────────────────────────────
          // Sta fuori dalla mappa, non dentro: se fosse un marcatore la
          // prospettiva la schiaccerebbe insieme all'asfalto. Cosi' resta
          // nitida e in piedi, e tu la guardi da dietro e dall'alto.
          _buildRider(context),

          // ── PULSANTE CHIUDI A SCOMPARSA (Swipe down per visualizzarlo al centro in alto) ──
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            top: _showCloseButton ? 16 : -80,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: () {
                  Navigator.of(context).pop();
                },
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.9),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.alertRed, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.alertRed.withOpacity(0.4),
                        blurRadius: 10,
                        spreadRadius: 2,
                      )
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.close,
                      color: AppTheme.alertRed,
                      size: 26,
                    ),
                  ),
                ),
              ),
            ),
          ),


          // ── METEO (angolo in alto a destra, a fianco della barra marce) ──
          Positioned(
            top: 12,
            right: 60,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.85),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.wb_sunny_outlined, color: AppTheme.activeCyan, size: 15),
                      const SizedBox(width: 5),
                      Text(
                        _weather == null
                            ? "--°C"
                            : "${_weather!.temperatureC.toStringAsFixed(0)}°C",
                        style: GoogleFonts.orbitron(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.location_on, color: AppTheme.activeCyan, size: 11),
                      const SizedBox(width: 3),
                      Text(
                        "S. GODENZO (FI)",
                        style: GoogleFonts.orbitron(
                          fontSize: 7,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  // Condizione dell'asfalto: e' l'informazione che serve
                  // davvero in moto, molto piu' dei gradi.
                  Text(
                    _weather == null
                        ? "METEO NON DISPONIBILE"
                        : (_weather!.road == RoadCondition.dry
                            ? "ASFALTO ASCIUTTO"
                            : "${_weather!.roadLabel} ⚠️"),
                    style: GoogleFonts.orbitron(
                      fontSize: 7,
                      fontWeight: FontWeight.bold,
                      color: (_weather?.road ?? RoadCondition.dry) ==
                              RoadCondition.dry
                          ? AppTheme.activeCyan
                          : AppTheme.alertRed,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── CARBURANTE (angolo in alto a sinistra: serbatoio + autonomia) ──
          Positioned(
            top: 12,
            left: 12,
            width: 212,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.85),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.local_gas_station,
                              color: Colors.amber, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            "SERBATOIO",
                            style: GoogleFonts.orbitron(
                              fontSize: 10,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        "${(telemetry.fuelBars / 7 * 100).toInt()}%",
                        style: GoogleFonts.orbitron(
                          fontSize: 12,
                          color: telemetry.fuelBars <= 2
                              ? AppTheme.alertRed
                              : AppTheme.activeCyan,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Barre neon
                  Row(
                    children: List.generate(7, (index) {
                      final isActive = index < telemetry.fuelBars;
                      return Expanded(
                        child: Container(
                          height: 10,
                          margin: const EdgeInsets.symmetric(horizontal: 1.5),
                          decoration: BoxDecoration(
                            color: isActive
                                ? (telemetry.fuelBars <= 2
                                    ? AppTheme.alertRed
                                    : AppTheme.activeCyan)
                                : Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 8),
                  const Divider(color: Colors.white12, height: 1),
                  const SizedBox(height: 8),
                  // Autonomia, nello stesso riquadro del serbatoio
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        "AUTONOMIA",
                        style: GoogleFonts.orbitron(
                          fontSize: 10,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        "${telemetry.autonomy.toInt()}",
                        style: GoogleFonts.orbitron(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        "KM",
                        style: GoogleFonts.orbitron(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Attribuzione cartografica: piccola ma dovuta (OpenStreetMap)
          Positioned(
            left: 16,
            bottom: 2,
            child: Text(
              _style.attribution,
              style: GoogleFonts.orbitron(
                fontSize: 6,
                color: _style.inkColor,
              ),
            ),
          ),

          // ── BOTTOM WIDGET (Pannello Assistente Vocale / Stato Comandi) ──
          // Centrato nello spazio disponibile: la barra delle marce occupa 48 px
          // a destra, quindi il centro ottico non coincide col centro schermo.
          Positioned(
            bottom: 12,
            left: 12,
            right: 60,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.85),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Row(
                children: [
                  // Icona Assistente / Microfono (Stile Siri: rosso con rotazione 3D sull'asse Y)
                  GestureDetector(
                    onTap: _toggleVoiceListening,
                    child: AnimatedBuilder(
                      animation: _rotationController,
                      builder: (context, child) {
                        return Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.002) // effetto prospettiva 3D
                            ..rotateY(_rotationController.value * 2 * 3.14159265),
                          child: child,
                        );
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppTheme.alertRed.withOpacity(0.2),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppTheme.alertRed,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.alertRed.withOpacity(0.4),
                              blurRadius: 8,
                            )
                          ],
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.mic,
                            color: AppTheme.alertRed,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Cerca una destinazione e naviga sulla mappa dell'app
                  GestureDetector(
                    onTap: _openDestinationSearch,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.activeCyan.withOpacity(0.15),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.activeCyan, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.activeCyan.withOpacity(0.2),
                            blurRadius: 8,
                          )
                        ],
                      ),
                      child: const Icon(Icons.search,
                          color: AppTheme.activeCyan, size: 22),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Navigazione rapida: OsmAnd se c'è, altrimenti Waze
                  GestureDetector(
                    onTap: () async {
                      final nav = await NavigationService.instance.navigateTo(
                        _gasStationLocation.latitude,
                        _gasStationLocation.longitude,
                        name: 'Distributore IP',
                        fromLat: _myLocation.latitude,
                        fromLon: _myLocation.longitude,
                      );
                      if (nav.target == NavigationTarget.internal) {
                        await _tts.speak(nav.spokenMessage);
                      }
                    },
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.15),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.amber,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.amber.withOpacity(0.2),
                            blurRadius: 8,
                          )
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.navigation,
                          color: Colors.amber,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Messaggio dell'assistente vocale
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _isListening ? "ASSISTENTE VOCALE ATTIVO (CUFFIE)" : "MONSTERSYNC ASSISTANT",
                          style: GoogleFonts.orbitron(
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            color: _isListening ? AppTheme.alertRed : AppTheme.activeCyan,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _assistantText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Animazione onda sonora (visualizer)
                  if (_isListening)
                    Row(
                      children: List.generate(4, (index) {
                        return AnimatedBuilder(
                          animation: _waveController,
                          builder: (context, child) {
                            final animValue = _waveController.value;
                            double height = 4.0 + (index % 2 == 0 ? animValue : 1 - animValue) * 16.0;
                            return Container(
                              width: 3,
                              height: height,
                              margin: const EdgeInsets.symmetric(horizontal: 1.5),
                              decoration: BoxDecoration(
                                color: AppTheme.alertRed,
                                borderRadius: BorderRadius.circular(1.5),
                              ),
                            );
                          },
                        );
                      }),
                    )
                  else if (_navigationActive)
                    Row(
                      children: [
                        const Icon(Icons.directions, color: AppTheme.activeCyan, size: 20),
                        const SizedBox(width: 4),
                        Text(
                          "NAV LIVE",
                          style: GoogleFonts.orbitron(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.activeCyan,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
                ),
              ),
            ),
          ),

          // ── RIQUADRO INDICAZIONI (in alto al centro, stile navigatore) ──
          // Compare solo con la navigazione attiva: a moto ferma o senza rotta
          // il centro dello schermo resta libero, che è dove guardi la strada.
          if (_internalNavActive || _routeLoading)
            Positioned(
              top: 12,
              left: 236,   // oltre il riquadro carburante, ora piu' largo
              right: 210,  // prima del meteo e della barra marce
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B6B3A).withOpacity(0.95),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.15), width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.5),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: _routeLoading
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              ),
                              const SizedBox(width: 12),
                              Text('Calcolo del percorso…',
                                  style: GoogleFonts.orbitron(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white)),
                            ],
                          )
                        : Row(
                            children: [
                              Icon(
                                _route != null && _route!.steps.isNotEmpty
                                    ? RoutePlanner.maneuverIcon(
                                        _route!.steps[_stepIndex].maneuver)
                                    : Icons.straight,
                                color: Colors.white,
                                size: 34,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _internalDistanceToTurn.isEmpty
                                          ? (_route != null &&
                                                  _route!.steps.isNotEmpty
                                              ? _route!
                                                  .steps[_stepIndex].instruction
                                              : '')
                                          : _internalDistanceToTurn,
                                      style: GoogleFonts.orbitron(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        height: 1.0,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      _internalNextTurn.isEmpty
                                          ? _selectedDestinationName
                                          : _internalNextTurn,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white.withOpacity(0.9),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              // ETA e distanza residua
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_internalEta,
                                      style: GoogleFonts.orbitron(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white)),
                                  Text(_internalRemainingDist,
                                      style: GoogleFonts.orbitron(
                                          fontSize: 9,
                                          color:
                                              Colors.white.withOpacity(0.75))),
                                ],
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: _stopInternalNavigation,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.close,
                                      size: 15, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),

          // ── AVVISO AUTOVELOX ────────────────────────────────────────
          if (_cameraWarning != null)
            Positioned(
              // In alto al centro, sotto la scheda delle indicazioni quando
              // c'e'. Non in basso: li' ci sono la moto e il pannello
              // dell'assistente, e un avviso che copre la moto e' un avviso
              // messo male. In alto invece copre solo la foschia.
              top: (_internalNavActive || _routeLoading) ? 82 : 12,
              left: 236,
              right: 210,
              child: Center(
                child: AnimatedBuilder(
                  animation: _shiftPulse,
                  builder: (context, child) {
                    // Sotto i 200 m pulsa; prima resta fisso, per non
                    // trasformare un avviso in un allarme continuo.
                    final vicino = _cameraWarning!.distanceM < 200;
                    final o = vicino ? 0.75 + 0.25 * _shiftPulse.value : 1.0;
                    return Opacity(opacity: o, child: child);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 9),
                    decoration: BoxDecoration(
                      color: const Color(0xFFB01414).withOpacity(0.95),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.2), width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.alertRed.withOpacity(0.45),
                          blurRadius: 16,
                        )
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.photo_camera,
                            color: Colors.white, size: 20),
                        const SizedBox(width: 10),
                        Text(
                          'AUTOVELOX ${_cameraWarning!.distanceLabel}',
                          style: GoogleFonts.orbitron(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                        if (_cameraWarning!.camera.maxSpeed != null) ...[
                          const SizedBox(width: 12),
                          // Il cartello del limite, tondo e rosso come quello vero
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: const Color(0xFFD32F2F), width: 3),
                            ),
                            child: Center(
                              child: Text(
                                '${_cameraWarning!.camera.maxSpeed}',
                                style: GoogleFonts.orbitron(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // ── VISTA LIBERA ────────────────────────────────────────────
          // Compare solo mentre stai guardando in giro col dito. Serve a
          // spiegare perche' la mappa non ti sta piu' seguendo — senza,
          // sembrerebbe che si sia impiantata — e a tornare subito senza
          // aspettare i tre secondi.
          if (_freeLook)
            Positioned(
              left: 12,
              bottom: 86,
              child: GestureDetector(
                onTap: () {
                  _recenterTimer?.cancel();
                  _recenterToRider();
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppTheme.activeCyan.withOpacity(0.55)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.my_location,
                          size: 13, color: AppTheme.activeCyan),
                      const SizedBox(width: 7),
                      Text(
                        'VISTA LIBERA · TOCCA PER TORNARE',
                        style: GoogleFonts.orbitron(
                          fontSize: 7.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── BARRA DELLE MARCE LATERALE DX (Full Height) ──
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            width: 48,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.9),
                border: const Border(
                  left: BorderSide(color: Colors.white10, width: 1),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: ["6", "5", "4", "3", "2", "N", "1"].map((g) {
                  final bool isActive = (_currentGear == 0 && g == "N") ||
                      (_currentGear != 0 && _currentGear.toString() == g);

                  Color activeColor = AppTheme.activeCyan;
                  if (g == "N") {
                    activeColor = Colors.greenAccent.shade400;
                  }

                  // Solo questa cella segue i giri, e li segue in diretta: il
                  // resto del cruscotto si ridisegna ogni 800 ms, che per un
                  // consiglio di cambiata sarebbe tardi. Il ListenableBuilder
                  // tiene il ridisegno confinato alla barra delle marce invece
                  // di rifare tutta la mappa venti volte al secondo.
                  final cell = AnimatedBuilder(
                    animation: Listenable.merge([_shiftPulse, widget.viewModel]),
                    builder: (context, _) {
                      final rpm = widget.viewModel.data.rpm;
                      final suggested = GearAdvisor.suggest(
                          currentGear: _currentGear, rpm: rpm);
                      final bool isSuggested =
                          suggested != null && suggested.toString() == g;

                      // Il respiro non scende mai a zero: la marcia consigliata
                      // resta leggibile anche nel punto piu' basso del battito.
                      // Piu' sali di giri, piu' il battito e' marcato.
                      final urgenza =
                          GearAdvisor.urgency(currentGear: _currentGear, rpm: rpm);
                      final glow = isSuggested
                          ? 0.35 + 0.65 * _shiftPulse.value * (0.5 + urgenza / 2)
                          : 0.0;

                      final Color borderColor = isActive
                          ? activeColor
                          : (isSuggested
                              ? Colors.amber.withOpacity(0.35 + glow * 0.65)
                              : Colors.white.withOpacity(0.05));

                      return Container(
                        width: double.infinity,
                        margin: const EdgeInsets.symmetric(
                            vertical: 2, horizontal: 4),
                        decoration: BoxDecoration(
                          color: isActive
                              ? activeColor.withOpacity(0.2)
                              : (isSuggested
                                  ? Colors.amber.withOpacity(0.06 + glow * 0.16)
                                  : Colors.transparent),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: borderColor,
                            width: (isActive || isSuggested) ? 2 : 1,
                          ),
                          boxShadow: isActive
                              ? [
                                  BoxShadow(
                                    color: activeColor.withOpacity(0.3),
                                    blurRadius: 4,
                                  )
                                ]
                              : (isSuggested
                                  ? [
                                      BoxShadow(
                                        color:
                                            Colors.amber.withOpacity(glow * 0.55),
                                        blurRadius: 6 + glow * 12,
                                        spreadRadius: glow * 1.5,
                                      )
                                    ]
                                  : null),
                        ),
                        child: Center(
                          child: Text(
                            g,
                            style: GoogleFonts.orbitron(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: isActive
                                  ? activeColor
                                  : (isSuggested
                                      ? Colors.amber
                                          .withOpacity(0.55 + glow * 0.45)
                                      : Colors.white24),
                            ),
                          ),
                        ),
                      );
                    },
                  );

                  return Expanded(child: cell);
                }).toList(),
              ),
            ),
          ),

          // ── BORDI DELLA GUI COLORATI E GLOWING IN ASCOLTO (Siri-style) ──
          if (_isListening)
            IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: AppTheme.alertRed,
                    width: 4,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.alertRed.withOpacity(0.4),
                      blurRadius: 16,
                      spreadRadius: 2,
                    )
                  ],
                ),
              ),
            ),
        ],
      ),
     ),
    );
  }
}

// Cerchio pulsante di localizzazione
class _RippleRing extends StatefulWidget {
  @override
  State<_RippleRing> createState() => _RippleRingState();
}

class _RippleRingState extends State<_RippleRing> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 32 + _controller.value * 28,
          height: 32 + _controller.value * 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              // Blu pieno, non il ciano del cruscotto: su una carta chiara
              // il ciano al neon e' quasi bianco e l'onda sparisce.
              color: const Color(0xFF1565D8)
                  .withOpacity(1.0 - _controller.value),
              width: 1.5,
            ),
          ),
        );
      },
    );
  }
}
