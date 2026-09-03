import 'dart:async';
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
import 'package:monster_sync_app/ui/features/dashboard/view_models/dashboard_view_model.dart';
import 'package:monster_sync_app/data/services/weather_service.dart';
import 'package:monster_sync_app/data/services/navigation_service.dart';
import 'package:monster_sync_app/data/services/geocoding_service.dart';

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

  // Stato per la visualizzazione temporanea del pulsante Chiudi (X) tramite swipe down
  bool _showCloseButton = false;
  Timer? _closeButtonTimer;

  // Controller per l'animazione di rotazione 3D dell'icona microfono
  late final AnimationController _rotationController;

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

      setState(() {
        _internalRouteIndex++;
        _myLocation = route.points[_internalRouteIndex];

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
  
  // Coordinate autovelox noti
  final List<LatLng> _autoveloxLocations = [
    const LatLng(43.9980, 11.6450),
    const LatLng(43.9940, 11.6370),
  ];

  // Coordinata distributore IP più vicino
  final LatLng _gasStationLocation = const LatLng(44.0010, 11.6520);

  // Lista di coordinate per tracciare la rotta (polyline)
  List<LatLng> _routePoints = [];

  // Controller per le animazioni del microfono (onda sonora)
  late AnimationController _waveController;

  // Meteo reale (Open-Meteo). Null finche' la prima lettura non arriva.
  WeatherInfo? _weather;

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

    // Simula telemetria attiva in marcia (solo cambio marcia)
    _telemetryTimer = Timer.periodic(const Duration(milliseconds: 800), (timer) {
      if (mounted) {
        setState(() {
          if (timer.tick % 15 == 0) {
            _currentGear = (_currentGear == 3) ? 4 : 3;
          }
        });
      }
    });

    // Meteo vero: serve anche a sapere se l'asfalto e' bagnato, non solo
    // a scrivere i gradi.
    _loadWeather();

    // Avvia un breve ruggito all'avvio della schermata
    _playStartRoar();
  }

  Future<void> _playStartRoar() async {
    try {
      await _audioPlayer.play(AssetSource('engine_roar.ogg'));
    } catch (e) {
      debugPrint("Impossibile riprodurre ruggito iniziale: $e");
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
    _rotationController.dispose();
    _waveController.dispose();
    _audioPlayer.dispose();
    _tts.stop();
    super.dispose();
  }

  // Avvia l'ascolto dell'assistente vocale
  Future<void> _startVoiceListening() async {
    bool available = await _speech.initialize(
      onStatus: (status) => debugPrint('Speech status: $status'),
      onError: (error) => debugPrint('Speech error: $error'),
    );

    if (available) {
      setState(() {
        _isListening = true;
        _assistantText = "Ascolto attivo dalle cuffie...";
        _userSpeechResult = "";
      });
      _waveController.repeat();

      _speech.listen(
        onResult: (result) {
          setState(() {
            _userSpeechResult = result.recognizedWords;
          });
          if (result.finalResult) {
            _processVoiceCommand(_userSpeechResult);
          }
        },
        localeId: "it-IT",
      );

      // Timeout di sicurezza dopo 5 secondi di inattività (simula anche se non parla l'utente)
      Future.delayed(const Duration(seconds: 4), () {
        if (_isListening && _userSpeechResult.isEmpty) {
          _processVoiceCommand("cerca distributore più vicino");
        }
      });
    } else {
      // Se SpeechToText non è disponibile (es. emulatore), simuliamo il riconoscimento vocale
      setState(() {
        _isListening = true;
        _assistantText = "Simulazione input vocale...";
      });
      _waveController.repeat();
      
      Future.delayed(const Duration(seconds: 2), () {
        _processVoiceCommand("cerca distributore");
      });
    }
  }


  // Elabora il comando vocale dell'utente
  void _processVoiceCommand(String command) async {
    _speech.stop();
    _waveController.stop();

    final cmdLower = command.toLowerCase();
    
    if (cmdLower.contains("distributore") || cmdLower.contains("benzina") || cmdLower.contains("carburante")) {
      setState(() {
        _isListening = false;
        _assistantText = "Comando ricevuto: '$command'";
      });

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
      setState(() {
        _isListening = false;
        _assistantText = "Comando non riconosciuto: '$command'. Riprova.";
      });
      await _tts.speak("Non ho capito, puoi ripetere il comando?");
    }
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
          // ── MAPPA COMPLETA A SCHERMO INTERO ─────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _myLocation,
              initialZoom: 17.0,   // Zoom alto stile Waze (vista ravvicinata sulla strada)
              initialRotation: _mapRotation, // heading simulato; diventera' quello vero dal GPS
              minZoom: 14.0,
              maxZoom: 18.0,
              // Colore sotto le tile: copre i bordi che la rotazione di 15°
              // lascerebbe scoperti, invece del nero pieno.
              backgroundColor: const Color(0xFF12151A),
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.none, // Mappa bloccata sul rider come Waze in navigazione
              ),
            ),
            children: [
              // Tema scuro da OSM: INVERSIONE + ROTAZIONE DI TINTA DI 180°.
              //
              // La sola inversione (com'era prima) ribalta anche la tinta: il verde
              // dei parchi diventa viola e le strade illeggibili. Ruotando la tinta
              // di 180° dopo l'inversione, ogni colore torna al suo (il verde resta
              // verde, scuro) e si ottiene un vero tema notturno.
              //
              // CartoDB Dark Matter sarebbe più bella ma ora pretende una API key:
              // senza chiave serve tile con la scritta "API KEY REQUIRED" sopra.
              ColorFiltered(
                colorFilter: const ColorFilter.matrix([
                   0.574, -1.430, -0.144, 0, 255,
                  -0.426, -0.430, -0.144, 0, 255,
                  -0.426, -1.430,  0.856, 0, 255,
                   0.0,    0.0,    0.0,   1, 0,
                ]),
                child: TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.monster_sync_app',
                  // Con la mappa ruotata servono tile oltre il bordo visibile,
                  // altrimenti agli angoli resta il fondo scoperto.
                  panBuffer: 2,
                  keepBuffer: 5,
                ),
              ),

              // Polilinee di Navigazione (Rotta)
              if (_navigationActive)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      color: const Color(0xFF8B5CF6), // Viola stile Waze
                      strokeWidth: 8.0,
                      isDotted: false,
                      borderColor: const Color(0xFF5B21B6),
                      borderStrokeWidth: 3.0,
                    ),
                  ],
                ),

              // Marcatori sulla mappa (Posizione moto con Modello 3D, Autovelox, Distributori)
              MarkerLayer(
                markers: [
                  // 1. Moto (Posizione Attuale con Modello 3D reale che naviga)
                  Marker(
                    point: _myLocation,
                    width: 130,
                    height: 130,
                    alignment: Alignment.center, // il centro del modello sul punto GPS
                    // Il marker NON ruota con la mappa: resta allineato allo schermo,
                    // così la moto punta sempre verso l'alto — la vista che hai
                    // davvero quando ci sei sopra.
                    rotate: true,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Effetto onda di localizzazione pulsante sotto la moto
                        _RippleRing(),
                        IgnorePointer(
                          child: SizedBox(
                            width: 110,
                            height: 110,
                            child: ModelViewer(
                              src: 'assets/ducati_monster_3d.glb',
                              alt: 'Ducati 3D Model',
                              cameraControls: false,
                              disableZoom: true,
                              autoRotate: false,
                              // Vista dall'alto e leggermente da dietro, come se
                              // fossi in sella: phi basso = quasi a piombo.
                              // Se la moto risultasse girata al contrario, cambia
                              // il primo valore da 0deg a 180deg.
                              cameraOrbit: '0deg 22deg 65%',
                              shadowIntensity: 0.0,
                              backgroundColor: Colors.transparent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // 2. Autovelox
                  ..._autoveloxLocations.map((pos) => Marker(
                    point: pos,
                    width: 40,
                    height: 40,
                    child: Container(
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
                        child: Icon(
                          Icons.photo_camera,
                          color: AppTheme.alertRed,
                          size: 18,
                        ),
                      ),
                    ),
                  )),

                  // 3. Distributore IP (se navigazione attiva o mostrato vicino)
                  Marker(
                    point: _gasStationLocation,
                    width: 44,
                    height: 44,
                    child: Container(
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
                        child: Icon(
                          Icons.local_gas_station,
                          color: Colors.amber,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

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
            width: 170,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                              color: Colors.amber, size: 13),
                          const SizedBox(width: 5),
                          Text(
                            "SERBATOIO",
                            style: GoogleFonts.orbitron(
                              fontSize: 8,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        "${(telemetry.fuelBars / 7 * 100).toInt()}%",
                        style: GoogleFonts.orbitron(
                          fontSize: 9,
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
                          height: 7,
                          margin: const EdgeInsets.symmetric(horizontal: 1),
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
                          fontSize: 8,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        "${telemetry.autonomy.toInt()}",
                        style: GoogleFonts.orbitron(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        "KM",
                        style: GoogleFonts.orbitron(
                          fontSize: 8,
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
              "© OpenStreetMap contributors",
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
                    onTap: _startVoiceListening,
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
              left: 190,   // oltre il riquadro carburante
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
                  final bool isActive = (_currentGear == 0 && g == "N") || (_currentGear != 0 && _currentGear.toString() == g);
                  Color activeColor = AppTheme.activeCyan;
                  if (g == "N") {
                    activeColor = Colors.greenAccent.shade400;
                  }
                  
                  return Expanded(
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                      decoration: BoxDecoration(
                        color: isActive ? activeColor.withOpacity(0.2) : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isActive ? activeColor : Colors.white.withOpacity(0.05),
                          width: isActive ? 2 : 1,
                        ),
                        boxShadow: isActive ? [
                          BoxShadow(
                            color: activeColor.withOpacity(0.3),
                            blurRadius: 4,
                          )
                        ] : null,
                      ),
                      child: Center(
                        child: Text(
                          g,
                          style: GoogleFonts.orbitron(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: isActive ? activeColor : Colors.white24,
                          ),
                        ),
                      ),
                    ),
                  );
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
