import 'package:flutter_test/flutter_test.dart';
import 'package:monster_sync_app/data/services/fuel_price_service.dart';

/// Il CSV del MIMIT ha una forma precisa e il parser ci si appoggia. Questi
/// test la fissano: se il ministero cambia il formato, falliscono qui invece
/// che in moto con un prezzo sbagliato in euro.
void main() {
  String csv(List<String> righe) =>
      ['Estrazione del 2026-09-02', 'idImpianto|descCarburante|prezzo|isSelf|dtComu', ...righe]
          .join('\n');

  /// n righe di benzina self a prezzi crescenti attorno a [centro].
  List<String> benzinaSelf(List<double> prezzi) => [
        for (var i = 0; i < prezzi.length; i++)
          '$i|Benzina|${prezzi[i].toStringAsFixed(3)}|1|01/09/2026 19:30:00',
      ];

  test('prende la mediana, non la media: un prezzo assurdo non la sposta', () {
    // 200 impianti a 1,900 e uno solo a 3,400 in mezzo: la media salirebbe a
    // 1,907, la mediana resta 1,900.
    final prezzi = <double>[
      ...List<double>.filled(100, 1.900),
      3.400,
      ...List<double>.filled(100, 1.900),
    ];
    final out = FuelPriceService.parse(csv(benzinaSelf(prezzi)));
    expect(out, isNotNull);
    expect(out!.euroPerLitre, closeTo(1.900, 0.001));
  });

  test('scarta gasolio, GPL e le benzine speciali da pista', () {
    final righe = [
      ...benzinaSelf(List<double>.filled(150, 1.850)),
      for (var i = 0; i < 300; i++)
        '9$i|Gasolio|1.700|1|01/09/2026 19:30:00',
      for (var i = 0; i < 300; i++) '8$i|GPL|0.849|1|01/09/2026 19:30:00',
      // fuori forbice: comunicazione sbagliata del gestore
      for (var i = 0; i < 50; i++)
        '7$i|Benzina|9.999|1|01/09/2026 19:30:00',
    ];
    final out = FuelPriceService.parse(csv(righe));
    expect(out!.euroPerLitre, closeTo(1.850, 0.001));
    expect(out.samples, 150);
  });

  test('scarta il servito: al self si paga un altro prezzo', () {
    final righe = [
      ...benzinaSelf(List<double>.filled(120, 1.800)),
      for (var i = 0; i < 400; i++)
        '5$i|Benzina|2.300|0|01/09/2026 19:30:00', // servito
    ];
    final out = FuelPriceService.parse(csv(righe));
    expect(out!.euroPerLitre, closeTo(1.800, 0.001));
    expect(out.samples, 120);
  });

  test('legge la data di estrazione dichiarata dal ministero', () {
    final out = FuelPriceService.parse(csv(benzinaSelf(List.filled(120, 2.0))));
    expect(out!.extraction, '2026-09-02');
  });

  test('con troppi pochi impianti non si inventa un prezzo', () {
    // Un download andato male non deve produrre un numero plausibile ma falso.
    expect(FuelPriceService.parse(csv(benzinaSelf(List.filled(12, 2.0)))), isNull);
    expect(FuelPriceService.parse('Estrazione del 2026-09-02'), isNull);
  });

  test('l ultima riga tronca a meta viene ignorata', () {
    final righe = [
      ...benzinaSelf(List<double>.filled(120, 1.999)),
      '999|Benz', // il download si e interrotto qui
    ];
    final out = FuelPriceService.parse(csv(righe));
    expect(out, isNotNull);
    // Le 120 righe buone ci sono tutte: a cadere e solo il frammento finale.
    expect(out!.samples, 120);
  });

  group('RideCost', () {
    // Il prezzo vero misurato il 2026-09-04 sui dati del ministero.
    final prezzo = FuelPrice(
      euroPerLitre: 2.029,
      samples: 7589,
      extraction: '2026-09-02',
      fetchedAt: DateTime(2026, 9, 4),
    );

    test('litri ed euro di un giro reale', () {
      final c = RideCost.compute(km: 45.1, lPer100: 5.9, price: prezzo);
      expect(c.litres, closeTo(2.661, 0.001));
      expect(c.euro, closeTo(5.399, 0.01));
      expect(c.kmPerLitreLabel, '16.9 km/l');
    });
  });
}
