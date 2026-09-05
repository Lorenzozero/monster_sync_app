import 'dart:ui' show Color;

/// ─────────────────────────────────────────────────────────────────────────────
/// LA MAPPA DEL CRUSCOTTO — cartografia chiara, inclinata
///
/// Prima era la fotografia aerea. Bella, ma in moto la strada bisogna
/// **leggerla**, non riconoscerla: su una foto l'asfalto e il tetto di un
/// capannone hanno lo stesso grigio, e a 90 all'ora quel grigio non ti dice
/// dove svoltare. Una carta disegnata invece traccia le strade in bianco, le
/// separa dal costruito e ci scrive sopra i nomi.
///
/// ## Perché OSM standard e non le carte Esri
/// Provate tutte a schermo inclinato il 2026-09-04:
///  - **Esri World Street Map** è pulita ma a zoom 19 si svuota: resta una
///    strada su un campo beige, senza edifici. In città non dice più niente.
///  - **Esri Light Gray Canvas** a zoom 18 e oltre risponde "Map data not yet
///    available": semplicemente non ha tile a quel dettaglio.
///  - **OSM standard** tiene: strade bianche larghe, sagome degli edifici,
///    parchi in verde, nomi delle vie. È la struttura che serve.
///
/// Google resta fuori: le tile non le regala, servono account con carta e
/// chiave API, e le condizioni vietano di ridisegnarle in un'altra mappa.
///
/// ## Nota sul server
/// `tile.openstreetmap.org` è il server di cortesia del progetto. Per un'app
/// personale con un utente va bene, purché si dichiari uno User-Agent vero e
/// non si martelli. Un'app distribuita a molti dovrebbe passare a un'istanza
/// propria.
///
/// ## Gli edifici in rilievo
/// Il riferimento da cui nasce questa vista (un navigatore commerciale) ha i
/// palazzi **estrusi in 3D**. Qui non si può: le tile raster sono immagini
/// piatte, e per alzare i palazzi servirebbero tile vettoriali più un
/// rendering 3D — un progetto a sé. Quello che si ottiene è la pianta vera
/// vista di taglio, che a queste velocità dice la stessa cosa.
/// ─────────────────────────────────────────────────────────────────────────────

class MapStyle {
  final String urlTemplate;

  /// Il colore del "cielo": tinge la foschia in fondo alla scena e il fondo
  /// sotto le tile. Deve essere il colore della carta, o all'orizzonte si vede
  /// dove finisce la mappa.
  final Color hazeColor;

  /// Colore per le scritte sovrapposte alla mappa (attribuzione): scuro su
  /// carta chiara, o sparisce.
  final Color inkColor;

  final String attribution;

  const MapStyle({
    required this.urlTemplate,
    required this.hazeColor,
    required this.inkColor,
    required this.attribution,
  });

  static const chiara = MapStyle(
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    // Lo stesso beige chiarissimo del fondo delle tile OSM: la foschia si
    // fonde con la carta invece di tagliarla.
    hazeColor: Color(0xFFF2EFE9),
    inkColor: Color(0x99000000),
    attribution: '© OpenStreetMap contributors',
  );
}
