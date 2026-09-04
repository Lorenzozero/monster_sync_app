/// ─────────────────────────────────────────────────────────────────────────────
/// QUANDO CAMBIARE MARCIA — Ducati Monster 695 (Desmodue 695 cc, 73 CV)
///
/// I due numeri che contano su questo motore:
///  - **coppia massima a 6.750 giri**, potenza massima a 8.250, limitatore
///    poco oltre i 9.000. Salire di marcia **verso i 7.600** ti rimette
///    subito sotto la coppia piena: tirare fino al limitatore su un bicilindrico
///    ad aria non aggiunge spinta, aggiunge solo calore e rumore.
///  - **sotto i 2.600 giri il Desmodue strappa**: bicilindrico a L, catena di
///    distribuzione e frizione a bagno d'olio non amano il traino basso. Lì la
///    marcia giusta è una in meno.
///
/// In mezzo, fra 2.600 e 7.600, la marcia inserita va bene e non si suggerisce
/// niente: un indicatore che lampeggia sempre è un indicatore che si smette di
/// guardare.
/// ─────────────────────────────────────────────────────────────────────────────
class GearAdvisor {
  /// Oltre questo regime conviene salire.
  static const double upshiftRpm = 7600;

  /// Sotto questo regime il motore strappa: si scala.
  static const double downshiftRpm = 2600;

  /// La 695 ha sei rapporti.
  static const int topGear = 6;

  /// La marcia consigliata, o `null` se quella inserita va bene.
  ///
  /// [currentGear] 0 = folle. In folle non si suggerisce niente: il regime non
  /// dice nulla sulla marcia da mettere.
  static int? suggest({required int currentGear, required double rpm}) {
    if (currentGear <= 0) return null;

    if (rpm >= upshiftRpm && currentGear < topGear) {
      return currentGear + 1;
    }
    if (rpm <= downshiftRpm && currentGear > 1) {
      return currentGear - 1;
    }
    return null;
  }

  /// Quanto è urgente il consiglio, da 0 a 1. Serve a far pulsare la marcia
  /// consigliata più in fretta man mano che il regime sale, invece di
  /// accendersi di colpo.
  static double urgency({required int currentGear, required double rpm}) {
    if (suggest(currentGear: currentGear, rpm: rpm) == null) return 0;
    if (rpm >= upshiftRpm) {
      // da 7.600 (appena consigliato) a 9.000 (limitatore): 0 -> 1
      return ((rpm - upshiftRpm) / (9000 - upshiftRpm)).clamp(0.0, 1.0);
    }
    // scalata: piu' scendi sotto i 2.600, piu' e' urgente
    return ((downshiftRpm - rpm) / 900).clamp(0.0, 1.0);
  }
}
