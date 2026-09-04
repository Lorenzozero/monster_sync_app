import 'package:flutter/material.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// STILI DELLA MAPPA — tutti gratuiti e senza chiave API
///
/// ## Perché non Google
/// Google Maps non regala le tile. Servono un account Cloud con carta di
/// credito, una API key e l'uso obbligatorio dell'SDK: le condizioni d'uso
/// vietano esplicitamente di pescare le tile e disegnarle in un'altra mappa,
/// che è quello che farebbe questa app. Fuori dal credito mensile si paga a
/// consumo. Per un progetto personale non ha senso.
///
/// ## Cosa si usa al suo posto
/// **Esri World Imagery**: la stessa fotografia aerea che sta sotto ArcGIS,
/// servita senza chiave. È la mappa "realistica" — vedi i tetti, gli alberi,
/// il colore vero dell'asfalto — e sopra ci va il layer *World Transportation*,
/// trasparente, che rimette i nomi delle strade sulla foto.
///
/// Provati tutti il 2026-09-04, HTTP 200 senza chiave né referer.
/// Restano fuori Carto e Stadia/Stamen: oggi pretendono una chiave e senza di
/// quella servono tile con sopra scritto "API KEY REQUIRED".
/// ─────────────────────────────────────────────────────────────────────────────

class MapStyle {
  final String name;

  /// Icona del pulsante che cicla fra gli stili.
  final IconData icon;

  final String urlTemplate;

  /// Secondo livello trasparente, disegnato sopra il primo. Serve al satellite,
  /// che da solo non ha nomi di strade.
  final String? overlayUrlTemplate;

  /// Filtro colore applicato alle tile. Null = colori veri.
  final ColorFilter? filter;

  /// Velo scuro sopra la mappa: senza, la fotografia diurna sbianca il cruscotto
  /// e i numeri al neon spariscono. Va dal più fitto in alto (lontano) al più
  /// leggero in basso (la strada che stai per prendere), che è anche il modo in
  /// cui la foschia si comporta davvero.
  final List<double> tintOpacity;

  final String attribution;

  const MapStyle({
    required this.name,
    required this.icon,
    required this.urlTemplate,
    this.overlayUrlTemplate,
    this.filter,
    required this.tintOpacity,
    required this.attribution,
  });

  static const _osmNightFilter = ColorFilter.matrix([
    0.574, -1.430, -0.144, 0, 255, //
    -0.426, -0.430, -0.144, 0, 255, //
    -0.426, -1.430, 0.856, 0, 255, //
    0.0, 0.0, 0.0, 1, 0, //
  ]);

  static const List<MapStyle> all = [
    // 1. Realistica. È quella che si vede aprendo il cruscotto.
    MapStyle(
      name: 'SATELLITE',
      icon: Icons.satellite_alt,
      urlTemplate:
          'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
      overlayUrlTemplate:
          'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Transportation/MapServer/tile/{z}/{y}/{x}',
      tintOpacity: [0.92, 0.66, 0.40, 0.16],
      attribution: 'Esri · Maxar · Earthstar Geographics',
    ),

    // 2. Cartografica a colori veri: si legge meglio della foto quando piove
    //    o quando la zona è tutta bosco e dall'alto sono tutti uguali.
    MapStyle(
      name: 'STRADE',
      icon: Icons.map_outlined,
      urlTemplate:
          'https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}',
      tintOpacity: [0.86, 0.58, 0.34, 0.12],
      attribution: 'Esri · HERE · Garmin · OpenStreetMap',
    ),

    // 3. Il tema notte di prima: OSM invertito e con la tinta ruotata di 180°,
    //    così il verde resta verde scuro invece di diventare viola.
    MapStyle(
      name: 'NOTTE',
      icon: Icons.dark_mode_outlined,
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      filter: _osmNightFilter,
      tintOpacity: [0.55, 0.30, 0.14, 0.0],
      attribution: '© OpenStreetMap contributors',
    ),
  ];
}
