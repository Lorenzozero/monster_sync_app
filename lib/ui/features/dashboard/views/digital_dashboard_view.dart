import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:monster_sync_app/ui/core/theme.dart';
import 'package:monster_sync_app/ui/features/dashboard/view_models/dashboard_view_model.dart';

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

  // Coordinate di riferimento (Passo del Muraglione, Mugello/Toscana)
  final LatLng _myLocation = const LatLng(43.9961, 11.6429);
  
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

  // Controlla se la rete internet è attiva
  Future<bool> _isNetworkAvailable() async {
    try {
      final result = await InternetAddress.lookup('dns.google').timeout(const Duration(seconds: 1));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
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

      // Controlla disponibilità rete
      final hasNet = await _isNetworkAvailable();

      if (hasNet) {
        // Se c'è rete, usa Waze
        final wazeUrl = Uri.parse("waze://?ll=${_gasStationLocation.latitude},${_gasStationLocation.longitude}&navigate=yes");
        final webUrl = Uri.parse("https://waze.com/ul?ll=${_gasStationLocation.latitude},${_gasStationLocation.longitude}&navigate=yes");
        
        await _tts.speak("Rete rilevata. Avvio navigazione su Waze verso il distributore.");
        
        if (await canLaunchUrl(wazeUrl)) {
          await launchUrl(wazeUrl);
        } else {
          await launchUrl(webUrl, mode: LaunchMode.externalApplication);
        }
      } else {
        // Nessuna rete -> usa mappa offline
        setState(() {
          _navigationActive = true;
          // Traccia la rotta verso il distributore IP
          _routePoints = [
            _myLocation,
            const LatLng(43.9980, 11.6450), // Passa dall'autovelox
            _gasStationLocation,
          ];
        });

        // Annuncia il risultato tramite sintesi vocale (TTS)
        await _tts.speak(
          "Nessuna rete. Avvio navigazione offline sulla mappa locale con allerta autovelox attiva sulla rotta."
        );

        // Centra e zooma la mappa per mostrare la rotta
        _mapController.move(LatLng(
          (_myLocation.latitude + _gasStationLocation.latitude) / 2,
          (_myLocation.longitude + _gasStationLocation.longitude) / 2,
        ), 14.5);
      }
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
              initialRotation: 15.0, // Rotazione per simulare la direzione di marcia (heading)
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
          Positioned(
            bottom: 12,
            right: 60, // Lascia spazio per la barra delle marce a destra (48px + margine)
            left: 194,
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
 
                  // Pulsante Navigazione Waze Rapido
                  GestureDetector(
                    onTap: () async {
                      final wazeUrl = Uri.parse("waze://?ll=${_gasStationLocation.latitude},${_gasStationLocation.longitude}&navigate=yes");
                      final webUrl = Uri.parse("https://waze.com/ul?ll=${_gasStationLocation.latitude},${_gasStationLocation.longitude}&navigate=yes");
                      if (await canLaunchUrl(wazeUrl)) {
                        await launchUrl(wazeUrl);
                      } else {
                        await launchUrl(webUrl, mode: LaunchMode.externalApplication);
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
                  const SizedBox(width: 8),

                  // Meteo riposizionato in basso a destra
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Gradi
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.wb_sunny_outlined, color: AppTheme.activeCyan, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              "22°C",
                              style: GoogleFonts.orbitron(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        // Comune, sotto i gradi
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
                        const SizedBox(height: 2),
                        // Avviso pioggia
                        Text(
                          "PIOGGIA TRA 15 MIN ⚠️",
                          style: GoogleFonts.orbitron(
                            fontSize: 7,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.alertRed,
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
