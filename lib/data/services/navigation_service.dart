import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// NAVIGAZIONE VERSO UN PUNTO
///
/// L'ordine di preferenza non è casuale:
///
/// 1. OSMAND — mappe scaricate sul telefono, calcolo del percorso **offline**,
///    limiti di velocità presi da OpenStreetMap e avvisi vocali autovelox.
///    In moto, in montagna, senza campo, è l'unica che continua a funzionare.
/// 2. WAZE — solo se c'è rete. Ha traffico in tempo reale e segnalazioni degli
///    utenti, che OsmAnd non può avere: quando la linea c'è, è la scelta
///    migliore per andare da A a B in città.
/// 3. Mappa interna — ultimo fallback: disegna la rotta ma non naviga.
///
/// Nota su OsmAnd: nella versione pubblicata su Google Play gli avvisi
/// autovelox sono disattivati per policy in alcuni paesi. Si riattivano dalle
/// impostazioni del profilo, oppure installando la versione dal sito o da
/// F-Droid. Non è qualcosa che l'app possa fare da sola.
/// ─────────────────────────────────────────────────────────────────────────────

enum NavigationTarget { osmand, waze, internal }

class NavigationResult {
  final NavigationTarget target;
  final String spokenMessage;
  const NavigationResult(this.target, this.spokenMessage);
}

class NavigationService {
  NavigationService._();
  static final NavigationService instance = NavigationService._();

  bool? _osmandCache;

  /// True se OsmAnd risponde a un intent di navigazione.
  /// Richiede le <queries> nel manifest: da Android 11 senza quelle
  /// canLaunchUrl mente e risponde sempre false.
  Future<bool> get osmandAvailable async {
    if (_osmandCache != null) return _osmandCache!;
    try {
      _osmandCache = await canLaunchUrl(Uri.parse('osmand.api://navigate'));
    } catch (_) {
      _osmandCache = false;
    }
    return _osmandCache!;
  }

  Future<bool> hasNetwork() async {
    try {
      final r = await InternetAddress.lookup('dns.google')
          .timeout(const Duration(seconds: 1));
      return r.isNotEmpty && r.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Avvia la navigazione verso [lat],[lon] scegliendo il navigatore migliore
  /// disponibile in quel momento. Ritorna cosa ha usato e la frase da leggere
  /// nell'interfono, così il chiamante non deve duplicare la logica.
  Future<NavigationResult> navigateTo(
    double lat,
    double lon, {
    String name = 'Destinazione',
    double? fromLat,
    double? fromLon,
  }) async {
    // 1. OsmAnd, se c'è: funziona anche senza campo
    if (await osmandAvailable) {
      final params = <String, String>{
        'dest_lat': lat.toStringAsFixed(6),
        'dest_lon': lon.toStringAsFixed(6),
        'dest_name': name,
        'profile': 'car',
        'force': 'true',
      };
      if (fromLat != null && fromLon != null) {
        params['start_lat'] = fromLat.toStringAsFixed(6);
        params['start_lon'] = fromLon.toStringAsFixed(6);
      }
      final uri = Uri(
        scheme: 'osmand.api',
        host: 'navigate',
        queryParameters: params,
      );
      if (await _tryLaunch(uri)) {
        return const NavigationResult(
          NavigationTarget.osmand,
          'Avvio la navigazione su OsmAnd. Funziona anche senza rete, '
              'con i limiti di velocità.',
        );
      }
      // Alcune versioni non espongono osmand.api: si ricade sullo schema geo,
      // che OsmAnd gestisce comunque.
      final geo = Uri.parse('geo:$lat,$lon?q=$lat,$lon(${Uri.encodeComponent(name)})');
      if (await _tryLaunch(geo)) {
        return const NavigationResult(
          NavigationTarget.osmand,
          'Apro la destinazione sulla mappa offline.',
        );
      }
    }

    // 2. Waze, solo con rete
    if (await hasNetwork()) {
      final waze = Uri.parse('waze://?ll=$lat,$lon&navigate=yes');
      if (await _tryLaunch(waze)) {
        return const NavigationResult(
          NavigationTarget.waze,
          'Rete disponibile. Avvio la navigazione su Waze.',
        );
      }
      final web = Uri.parse('https://waze.com/ul?ll=$lat,$lon&navigate=yes');
      if (await _tryLaunch(web, external: true)) {
        return const NavigationResult(
          NavigationTarget.waze,
          'Avvio la navigazione su Waze nel browser.',
        );
      }
    }

    // 3. Niente da lanciare: se ne occupa la mappa interna
    return const NavigationResult(
      NavigationTarget.internal,
      'Nessun navigatore disponibile e nessuna rete. '
          'Traccio la rotta sulla mappa interna.',
    );
  }

  Future<bool> _tryLaunch(Uri uri, {bool external = false}) async {
    try {
      if (!await canLaunchUrl(uri)) return false;
      return await launchUrl(
        uri,
        mode: external
            ? LaunchMode.externalApplication
            : LaunchMode.externalNonBrowserApplication,
      );
    } catch (e) {
      debugPrint('NavigationService: $uri non lanciabile ($e)');
      return false;
    }
  }
}
