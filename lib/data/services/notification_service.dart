import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

/// Servizio singleton per notifiche native Android/iOS.
/// Deve essere inizializzato in main() PRIMA di runApp().
///
/// Problemi comuni risolti qui:
/// 1. Il canale Android viene creato subito all'avvio (non lazy)
/// 2. Small icon usa @drawable/ic_notification (bianco monocromatico, req. Android 5+)
/// 3. Importance.max garantisce la comparsa nella tendina del Centro Controllo
/// 4. Il permesso POST_NOTIFICATIONS viene richiesto a runtime (Android 13+)
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  String _notificationIcon = 'ic_notification';

  // ── ID canali ────────────────────────────────────────────────────────────────
  static const String _channelIdScadenze = 'monstersync_scadenze_v6';
  static const String _channelIdManutenzione = 'monstersync_manutenzione_v4';

  // ── INIT ─────────────────────────────────────────────────────────────────────
  Future<void> init() async {
    if (_initialized) return;

    // 1. Impostazioni init per piattaforma usando l'icona silhouette per la status bar
    try {
      const AndroidInitializationSettings androidInit =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const DarwinInitializationSettings iosInit = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
        defaultPresentAlert: true,   // Consente notifiche in foreground su iOS
        defaultPresentBadge: true,   // Consente badge in foreground su iOS
        defaultPresentSound: true,   // Consente suoni in foreground su iOS
      );

      await _plugin.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit),
        onDidReceiveNotificationResponse: (_) {},
      );
      _notificationIcon = '@mipmap/ic_launcher';
      debugPrint("NotificationService: inizializzato con successo usando @mipmap/ic_launcher (scudetto Ducati)");
    } catch (e) {
      debugPrint("Errore inizializzazione con ic_notification: $e. Provo fallback con ic_launcher...");
      try {
        const AndroidInitializationSettings androidInitFallback =
            AndroidInitializationSettings('@mipmap/ic_launcher');
        await _plugin.initialize(
          const InitializationSettings(android: androidInitFallback, iOS: DarwinInitializationSettings(
            requestAlertPermission: true,
            requestBadgePermission: true,
            requestSoundPermission: true,
          )),
          onDidReceiveNotificationResponse: (_) {},
        );
        _notificationIcon = '@mipmap/ic_launcher';
        debugPrint("NotificationService: inizializzato con successo usando fallback @mipmap/ic_launcher");
      } catch (err) {
        debugPrint("Errore critico inizializzazione NotificationService: $err");
        // Non rilanciare: le notifiche non funzioneranno ma l'app resta stabile
        _notificationIcon = '@mipmap/ic_launcher';
        _initialized = true;
        return;
      }
    }

    // 2. Crea i canali Android IMMEDIATAMENTE (prima di qualsiasi invio)
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _channelIdScadenze,
              'Scadenze Legali',
              description: 'Notifiche relative a Scadenza Bollo e Assicurazione RCA',
              importance: Importance.max,
              playSound: true,
              enableVibration: true,
            ),
          );

      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _channelIdManutenzione,
              'Manutenzione Moto',
              description: 'Promemoria manutenzione per la tua Ducati',
              importance: Importance.max,
              playSound: true,
              enableVibration: true,
            ),
          );
    } catch (e) {
      debugPrint("Errore creazione canali Android: $e");
    }

    // 3. Richiedi permesso POST_NOTIFICATIONS (Android 13+)
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (e) {
      debugPrint("Errore richiesta permesso notifiche Android: $e");
    }

    // iOS: richiedi permesso usando IOSFlutterLocalNotificationsPlugin
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    _initialized = true;
  }

  // ── VERIFICA STATO PERMESSI SISTEMA OPERATIVO ─────────────────────────────
  Future<bool> areNotificationsEnabled() async {
    try {
      final bool? enabled = await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.areNotificationsEnabled();
      return enabled ?? false;
    } catch (e) {
      debugPrint("Errore verifica areNotificationsEnabled: $e. Uso fallback Permission.");
      final status = await Permission.notification.status;
      return status.isGranted;
    }
  }

  // ── PERMESSO RUNTIME (per chiamata esplicita) ─────────────────────────────
  Future<bool> requestPermission() async {
    // Richiede su Android e iOS
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  // ── SEND SCADENZA ─────────────────────────────────────────────────────────
  Future<void> sendScadenzaNotification({
    required int id,
    required String title,
    String? body,
    String? bigText,
  }) async {
    try {
      if (!_initialized) await init();

      final AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        _channelIdScadenze,
        'Scadenze Veicolo',
        channelDescription: 'Avvisi scadenza',
        importance: Importance.max,
        priority: Priority.high,
        icon: _notificationIcon,
        color: const Color(0xFFCC0000),
        largeIcon: null, // Rimosso per evitare crash in R.drawable poiché launcher_icon risiede in mipmap
        playSound: true,
        enableVibration: true,
        styleInformation: bigText != null
            ? BigTextStyleInformation(
                bigText,
                contentTitle: title,
                summaryText: 'MonsterSync – DB76479',
              )
            : null,
        ticker: title,
      );

      await _plugin.show(
        id,
        title,
        body ?? '',
        NotificationDetails(
          android: androidDetails,
          iOS: const DarwinNotificationDetails(
              presentAlert: true, presentBadge: true, presentSound: true),
        ),
      );
    } catch (e) {
      debugPrint("Errore invio notifica scadenza: $e");
      rethrow;
    }
  }

  // ── SEND MANUTENZIONE ─────────────────────────────────────────────────────
  Future<void> sendManutenzioneNotification({
    required int id,
    required String title,
    String? body,
    String? bigText,
  }) async {
    try {
      if (!_initialized) await init();

      final AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        _channelIdManutenzione,
        'Manutenzione Moto',
        channelDescription: 'Promemoria manutenzione',
        importance: Importance.max,
        priority: Priority.high,
        icon: _notificationIcon,
        color: const Color(0xFFCC6600),
        largeIcon: null, // Rimosso per evitare crash in R.drawable
        playSound: true,
        enableVibration: true,
        styleInformation: bigText != null
            ? BigTextStyleInformation(
                bigText,
                contentTitle: title,
                summaryText: 'MonsterSync – Manutenzione',
              )
            : null,
        ticker: title,
      );

      await _plugin.show(
        id,
        title,
        body ?? '',
        NotificationDetails(
          android: androidDetails,
          iOS: const DarwinNotificationDetails(
              presentAlert: true, presentBadge: true, presentSound: true),
        ),
      );
    } catch (e) {
      debugPrint("Errore invio notifica manutenzione: $e");
      rethrow;
    }
  }
}
