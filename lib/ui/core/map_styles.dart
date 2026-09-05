/// ─────────────────────────────────────────────────────────────────────────────
/// LA MAPPA DEL CRUSCOTTO — una sola, satellite
///
/// C'erano tre stili e un pulsante che li ciclava. Sono spariti: in moto una
/// scelta da fare e' una scelta di troppo, e la vista giusta e' una sola.
/// Resta questa.
///
/// ## Perché non Google
/// Google Maps non regala le tile. Servono un account Cloud con carta di
/// credito, una API key e l'uso obbligatorio dell'SDK: le condizioni d'uso
/// vietano esplicitamente di pescare le tile e disegnarle in un'altra mappa,
/// che è quello che fa questa app. Fuori dal credito mensile si paga a
/// consumo.
///
/// ## Cosa si usa al suo posto
/// **Esri World Imagery**: la stessa fotografia aerea che sta sotto ArcGIS,
/// servita senza chiave. Vedi i tetti, gli alberi, il colore vero
/// dell'asfalto. Da sola non ha i nomi delle strade, quindi sopra ci va
/// *World Transportation*, un secondo livello trasparente che glieli rimette.
///
/// Provati il 2026-09-04, HTTP 200 senza chiave né referer. Restano fuori
/// Carto e Stadia/Stamen: oggi pretendono una chiave e senza quella servono
/// tile con sopra scritto "API KEY REQUIRED".
/// ─────────────────────────────────────────────────────────────────────────────

class MapStyle {
  final String urlTemplate;

  /// Secondo livello trasparente, disegnato sopra il primo: i nomi delle
  /// strade, che la fotografia da sola non ha.
  final String overlayUrlTemplate;

  /// Velo scuro sopra la mappa, dal più fitto in alto (lontano) al più
  /// leggero in basso (la strada che stai per prendere). Senza, la fotografia
  /// diurna sbianca il cruscotto e i numeri al neon spariscono. È anche il
  /// modo in cui la foschia si comporta davvero.
  final List<double> tintOpacity;

  final String attribution;

  const MapStyle({
    required this.urlTemplate,
    required this.overlayUrlTemplate,
    required this.tintOpacity,
    required this.attribution,
  });

  static const satellite = MapStyle(
    urlTemplate:
        'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    overlayUrlTemplate:
        'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Transportation/MapServer/tile/{z}/{y}/{x}',
    tintOpacity: [0.92, 0.66, 0.40, 0.16],
    attribution: 'Esri · Maxar · Earthstar Geographics',
  );
}
