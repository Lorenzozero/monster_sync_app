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
  double _currentSpeed = 74.0;
  Timer? _telemetryTimer;

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

    // Simula telemetria attiva in marcia
    _telemetryTimer = Timer.periodic(const Duration(milliseconds: 800), (timer) {
      if (mounted) {
        setState(() {
          // Cambia leggermente velocità ed eventualmente marcia
          _currentSpeed = (70.0 + (timer.tick % 8) * 1.5).clamp(40.0, 130.0);
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
      body: Stack(
        children: [
          // ── MAPPA COMPLETA A SCHERMO INTERO ─────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _myLocation,
              initialZoom: 15.0,
              minZoom: 10.0,
              maxZoom: 18.0,
            ),
            children: [
              // Mappa Dark Cyberpunk (OSM Gratuita + ColorFiltered per inversione/tonalità ciano senza watermark)
              ColorFiltered(
                colorFilter: const ColorFilter.matrix([
                  -1.0,  0.0,  0.0, 0.0, 255,
                   0.0, -1.0,  0.0, 0.0, 255,
                   0.0,  0.0, -0.8, 0.0, 200,
                   0.0,  0.0,  0.0, 1.0, 0,
                ]),
                child: TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.monster_sync_app',
                ),
              ),
              
              // Polilinee di Navigazione (Rotta)
              if (_navigationActive)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      color: AppTheme.activeCyan,
                      strokeWidth: 5.0,
                      isDotted: false,
                      borderColor: Colors.blue.shade900,
                      borderStrokeWidth: 2.0,
                    ),
                  ],
                ),

              // Marcatori sulla mappa (Posizione moto con Modello 3D, Autovelox, Distributori)
              MarkerLayer(
                markers: [
                  // 1. Moto (Posizione Attuale con Modello 3D reale che naviga)
                  Marker(
                    point: _myLocation,
                    width: 90,
                    height: 90,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Effetto onda di localizzazione pulsante sotto la moto
                        _RippleRing(),
                        IgnorePointer(
                          child: SizedBox(
                            width: 70,
                            height: 70,
                            child: ModelViewer(
                              src: 'assets/ducati_monster_3d.glb',
                              alt: 'Ducati 3D Model',
                              cameraControls: false,
                              disableZoom: true,
                              autoRotate: false,
                              cameraOrbit: '165deg 75deg 70%',
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

          // ── TOP HUD BAR (Meteo, Stato e Close) ──────────────────────
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Meteo solo icona e gradi
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.wb_sunny_outlined, color: AppTheme.activeCyan, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        "22°C",
                        style: GoogleFonts.orbitron(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),

                // Pulsante Chiudi
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.85),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.alertRed.withOpacity(0.5)),
                    ),
                    child: const Icon(
                      Icons.close,
                      color: AppTheme.alertRed,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── LEFT HUD (Stato Rider: Marcia, Serbatoio, Autonomia, Velocità) ──
          Positioned(
            left: 12,
            bottom: 12,
            top: 60,
            child: Container(
              width: 170,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.85),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Marciametro Gigante
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "MARCIA",
                            style: GoogleFonts.orbitron(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textMuted,
                            ),
                          ),
                          Text(
                            _currentGear == 0 ? "N" : "$_currentGear",
                            style: GoogleFonts.teko(
                              fontSize: 64,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.activeCyan,
                              height: 0.9,
                            ),
                          ),
                        ],
                      ),
                      // Mappa/R mode indicator
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.alertRed.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppTheme.alertRed),
                        ),
                        child: Text(
                          "R-MODE",
                          style: GoogleFonts.orbitron(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.alertRed,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white10),

                  // Velocità istantanea
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "VELOCITÀ",
                        style: GoogleFonts.orbitron(
                          fontSize: 9,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            "${_currentSpeed.toInt()}",
                            style: GoogleFonts.teko(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            "KM/H",
                            style: GoogleFonts.orbitron(
                              fontSize: 9,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white10),

                  // Autonomia
                  Row(
                    children: [
                      const Icon(Icons.local_gas_station, color: Colors.amber, size: 16),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "AUTONOMIA",
                            style: GoogleFonts.orbitron(
                              fontSize: 8,
                              color: AppTheme.textMuted,
                            ),
                          ),
                          Text(
                            "${telemetry.autonomy.toInt()} KM",
                            style: GoogleFonts.orbitron(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Serbatoio (visual fuel bars)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "SERBATOIO",
                            style: GoogleFonts.orbitron(
                              fontSize: 8,
                              color: AppTheme.textMuted,
                            ),
                          ),
                          Text(
                            "${(telemetry.fuelBars / 7 * 100).toInt()}%",
                            style: GoogleFonts.orbitron(
                              fontSize: 8,
                              color: AppTheme.activeCyan,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Serbatoio a barre neon
                      Row(
                        children: List.generate(7, (index) {
                          final isActive = index < telemetry.fuelBars;
                          return Expanded(
                            child: Container(
                              height: 6,
                              margin: const EdgeInsets.symmetric(horizontal: 1),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? (telemetry.fuelBars <= 2 ? AppTheme.alertRed : AppTheme.activeCyan)
                                    : Colors.white.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white10),

                  // Meteo dettagliato: paese + avviso pioggia
                  Row(
                    children: [
                      const Icon(Icons.location_on, color: AppTheme.activeCyan, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "S. GODENZO (FI)",
                              style: GoogleFonts.orbitron(
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
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
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── BOTTOM WIDGET (Pannello Assistente Vocale / Stato Comandi) ──
          Positioned(
            bottom: 12,
            right: 12,
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
                  // Icona Assistente / Microfono
                  GestureDetector(
                    onTap: _startVoiceListening,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: _isListening ? AppTheme.alertRed.withOpacity(0.2) : AppTheme.activeCyan.withOpacity(0.1),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _isListening ? AppTheme.alertRed : AppTheme.activeCyan,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (_isListening ? AppTheme.alertRed : AppTheme.activeCyan).withOpacity(0.2),
                            blurRadius: 8,
                          )
                        ],
                      ),
                      child: Center(
                        child: Icon(
                          _isListening ? Icons.mic : Icons.mic_none,
                          color: _isListening ? AppTheme.alertRed : AppTheme.activeCyan,
                          size: 24,
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

                  // Animazione onda sonora (visualizer)
                  if (_isListening)
                    Row(
                      children: List.generate(4, (index) {
                        return AnimatedBuilder(
                          animation: _waveController,
                          builder: (context, child) {
                            // Calcola altezze dinamiche basate sull'animazione per emulare l'onda vocale
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
                    // Icona Waze / Navigazione
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
        ],
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
