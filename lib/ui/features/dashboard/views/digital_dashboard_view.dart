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
  double _mapRotation = 15.0;

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
  static const double _pitch = 1.082;               // 62 gradi in radianti
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

  bool _perspectiveOn = true;
  int _styleIndex = 0;

  // ── AUTOVELOX ─────────────────────────────────────────────────────────────
  // Le posizioni stanno in cache sul telefono (vedi SpeedCameraService):
  // l'avviso funziona in galleria e senza campo, che e' quando serve.
  CameraWarning? _cameraWarning;
  final Set<String> _announcedCameras = {};

  /// Rotta attuale in gradi. Serve a non avvisare per l'autovelox che guarda
  /// la carreggiata opposta. Finche' la centralina non c'e', e' quella
  /// calcolata lungo il percorso.
  double _heading = 15.0;
  MapStyle get _style => MapStyle.all[_styleIndex];

  void _cycleStyle() {
    HapticFeedback.selectionClick();
    setState(() => _styleIndex = (_styleIndex + 1) % MapStyle.all.length);
  }

  void _togglePerspective() {
    HapticFeedback.selectionClick();
    setState(() => _perspectiveOn = !_perspectiveOn);
  }

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
    if (picked != null) await _startInternalNavigation(picked);
  }

  // ── NAVIGAZIONE SULLA MAPPA DELL'APP ──────────────────────────────────────
  Future<void> _startInternalNavigation(Place dest) async {
    setState(() {
      _routeLoading = true;
      _selectedDestinationName = dest.name;
    });

    final r = await GeocodingService.instance.route(_myLocation, dest.coord);
    if (!mounted) return;

    setState(() {
      _route = r;
      _routePoints = r.points;
      _stepIndex = 0;
      _internalRouteIndex = 0;
      _internalNavActive = true;
      _navigationActive = true;
      _routeLoading = false;
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

        // Rotta vera lungo il percorso: serve agli autovelox e, quando
        // arrivera' il GPS della centralina, alla rotazione della mappa.
        _heading = GeocodingService.bearing(prev, _myLocation);

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

      _mapController.move(_myLocation, _mapController.camera.zoom);
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

  static String _fmtDistance(double m) =>
      m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '${m.round()} m';

  IconData _maneuverIcon(RouteStep s) {
    if (s.maneuver == 'arrive') return Icons.flag;
    if (s.maneuver == 'roundabout' || s.maneuver == 'rotary') {
      return Icons.roundabout_right;
    }
    switch (s.modifier) {
      case 'left':
        return Icons.turn_left;
      case 'right':
        return Icons.turn_right;
      case 'slight left':
        return Icons.turn_slight_left;
      case 'slight right':
        return Icons.turn_slight_right;
      case 'sharp left':
        return Icons.turn_sharp_left;
      case 'sharp right':
        return Icons.turn_sharp_right;
      case 'uturn':
        return Icons.u_turn_left;
      default:
        return Icons.straight;
    }
  }

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
    if (!_perspectiveOn) return _buildMap();

    final size = MediaQuery.of(context).size;
    return ClipRect(
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, _perspectiveDepth)
          ..translate(0.0, size.height * _cameraShift)
          ..rotateX(-_pitch),
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

  /// Un livello di tile, con l'eventuale filtro colore dello stile.
  Widget _tileLayer(String url, ColorFilter? filter) {
    final layer = TileLayer(
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
    return filter == null
        ? layer
        : ColorFiltered(colorFilter: filter, child: layer);
  }

  /// Raddrizza un marcatore dentro la scena inclinata: resta in piedi sul suo
  /// punto della strada, come un cartello, invece di essere spalmato
  /// sull'asfalto insieme a tutto il resto.
  Widget _billboard(Widget child) {
    if (!_perspectiveOn) return child;
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
        initialRotation: _mapRotation,
        minZoom: 14.0,
        maxZoom: 19.0,
        backgroundColor: const Color(0xFF0A0E14),
        interactionOptions: const InteractionOptions(
          // Mappa agganciata alla moto, come i navigatori in navigazione.
          flags: InteractiveFlag.none,
        ),
      ),
      children: [
        _tileLayer(style.urlTemplate, style.filter),
        // Il satellite da solo non ha i nomi delle strade: glieli rimette
        // sopra questo livello trasparente.
        if (style.overlayUrlTemplate != null)
          _tileLayer(style.overlayUrlTemplate!, null),

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

  Widget _viewButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.85),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppTheme.activeCyan),
            const SizedBox(width: 6),
            Text(
              label,
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
    );
  }

  /// La moto, ancorata dove il centro della mappa finisce sullo schermo.
  Widget _buildRider(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final y = size.height * (0.5 + (_perspectiveOn ? _cameraShift : 0.0));
    return Positioned(
      left: 0,
      right: 0,
      top: y - 66,
      height: 132,
      child: IgnorePointer(
        child: Center(
          child: SizedBox(
            width: 132,
            height: 132,
            child: Stack(
              alignment: Alignment.center,
              children: [
                _RippleRing(),
                SizedBox(
                  width: 118,
                  height: 118,
                  child: ModelViewer(
                    src: 'assets/ducati_monster_3d.glb',
                    alt: 'Ducati 3D Model',
                    cameraControls: false,
                    disableZoom: true,
                    autoRotate: false,
                    // Da dietro e dall'alto, l'inquadratura che hai stando
                    // sopra la moto.
                    cameraOrbit: '0deg 22deg 65%',
                    shadowIntensity: 0.0,
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

          // Velo scuro sopra la mappa. Senza, la fotografia aerea di giorno
          // sbianca tutto e i numeri al neon del cruscotto spariscono. E'
          // fitto in alto (il lontano) e quasi trasparente in basso, dove c'e'
          // la strada che stai per prendere: la stessa cosa che fa la foschia.
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.18, 0.45, 1.0],
                  colors: _style.tintOpacity
                      .map((o) => const Color(0xFF04080E).withOpacity(o))
                      .toList(),
                ),
              ),
              child: const SizedBox.expand(),
            ),
          ),

          // Foschia: copre il bordo alto della mappa e fa da orizzonte.
          IgnorePointer(
            child: Builder(builder: (ctx) {
              final size = MediaQuery.of(ctx).size;
              final edge = _perspectiveOn ? _mapTopEdge(size) : 0.0;
              if (edge <= 1) return const SizedBox.shrink();
              return Align(
                alignment: Alignment.topCenter,
                child: Container(
                  height: edge + 70,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.0, (edge / (edge + 70)).clamp(0.0, 0.95), 1.0],
                      colors: const [
                        Color(0xFF0A0E14),
                        Color(0xCC0A0E14),
                        Color(0x000A0E14),
                      ],
                    ),
                  ),
                ),
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

          // ── COMANDI DELLA VISTA ─────────────────────────────────────
          // Sotto al carburante, lontani dal centro dello schermo che e' dove
          // guardi la strada.
          Positioned(
            top: 148,
            left: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _viewButton(
                  icon: _style.icon,
                  label: _style.name,
                  onTap: _cycleStyle,
                ),
                const SizedBox(height: 8),
                _viewButton(
                  icon: _perspectiveOn
                      ? Icons.threed_rotation
                      : Icons.crop_square,
                  label: _perspectiveOn ? '3D' : '2D',
                  onTap: _togglePerspective,
                ),
              ],
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
                color: Colors.white.withOpacity(0.35),
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
                                    ? _maneuverIcon(_route!.steps[_stepIndex])
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
              color: AppTheme.activeCyan.withOpacity(1.0 - _controller.value),
              width: 1.5,
            ),
          ),
        );
      },
    );
  }
}
