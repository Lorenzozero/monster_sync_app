import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DbHelper {
  static final DbHelper _instance = DbHelper._internal();
  factory DbHelper() => _instance;
  DbHelper._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'monstersync.db');

    return await openDatabase(
      path,
      version: 4,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE rides (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT,
            subtitle TEXT,
            time TEXT,
            date TEXT,
            dist TEXT,
            dist_km REAL DEFAULT 0,
            roll TEXT,
            speed TEXT,
            rpm TEXT,
            l_per_100 REAL DEFAULT 0
          )
        ''');
        await _createVehicleIdentity(db);
        await _insertDemoRides(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 4) {
          // Consumo medio del giro, in litri ogni 100 km. Serve a calcolare
          // litri bruciati ed euro spesi (vedi FuelPriceService).
          try {
            await db.execute(
                'ALTER TABLE rides ADD COLUMN l_per_100 REAL DEFAULT 0');
          } catch (_) {
            // colonna gia' presente: niente da fare
          }
          // I giri registrati prima di questa versione non hanno il dato:
          // si assegna il consumo di riferimento della 695, dichiarandolo
          // come stima nell'interfaccia.
          try {
            await db.rawUpdate(
                'UPDATE rides SET l_per_100 = ? '
                'WHERE l_per_100 IS NULL OR l_per_100 <= 0',
                [defaultConsumptionL100]);
          } catch (_) {}
        }
        if (oldVersion < 3) {
          await _createVehicleIdentity(db);
        }
        if (oldVersion < 2) {
          // Aggiunge la colonna km numerica se non esiste
          try {
            await db.execute(
                'ALTER TABLE rides ADD COLUMN dist_km REAL DEFAULT 0');
            // Backfill dal campo text esistente
            final rows = await db.query('rides');
            for (final row in rows) {
              final distText = row['dist'] as String? ?? '';
              final km = _parseKm(distText);
              if (km > 0) {
                await db.update('rides', {'dist_km': km},
                    where: 'id = ?', whereArgs: [row['id']]);
              }
            }
          } catch (_) {}
        }
      },
    );
  }

  // ── Consumo di riferimento ────────────────────────────────────────────────
  // Ducati Monster 695 (Desmodue 695 cc, 73 CV): nell'uso reale sta fra 4,8
  // l/100km in statale tranquilla e 6,5 l/100km tirata fra i tornanti. 5,5 e'
  // il valore misto, usato quando il giro non porta con se' un consumo suo
  // (giri vecchi, o centralina non ancora collegata).
  static const double defaultConsumptionL100 = 5.5;

  /// Consumo del giro, con il valore di riferimento come rete di sicurezza.
  static double consumptionOf(Map<String, dynamic> ride) {
    final v = ride['l_per_100'];
    if (v is num && v > 0) return v.toDouble();
    return defaultConsumptionL100;
  }

  /// Km del giro, dal campo numerico o rileggendo il testo "12.4 km".
  static double kmOf(Map<String, dynamic> ride) {
    final v = ride['dist_km'];
    if (v is num && v > 0) return v.toDouble();
    return _parseKm(ride['dist'] as String? ?? '');
  }

  // ── Identità veicolo ────────────────────────────────────────────────────────
  // Targa, telaio, intestatario e data di immatricolazione sono dati personali:
  // vivono SOLO in questo database, sul dispositivo. Il sorgente (pubblico su
  // GitHub) contiene esclusivamente i segnaposto qui sotto.
  static const Map<String, String> identityPlaceholders = {
    'targa': '— — —',
    'telaio': '— — —',
    'intestatario': '— — —',
    'immatricolazione': '— — —',
  };

  static Future<void> _createVehicleIdentity(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS vehicle_identity (
        k TEXT PRIMARY KEY,
        v TEXT
      )
    ''');
    for (final e in identityPlaceholders.entries) {
      await db.insert('vehicle_identity', {'k': e.key, 'v': e.value},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  /// Ritorna l'identità del veicolo, con i segnaposto per i campi non compilati.
  Future<Map<String, String>> getVehicleIdentity() async {
    final db = await database;
    final out = Map<String, String>.from(identityPlaceholders);
    try {
      final rows = await db.query('vehicle_identity');
      for (final r in rows) {
        final k = r['k'] as String?;
        final v = r['v'] as String?;
        if (k != null && v != null && v.trim().isNotEmpty) out[k] = v;
      }
    } catch (_) {
      // tabella non ancora presente: restano i segnaposto
    }
    return out;
  }

  Future<void> setVehicleIdentity(Map<String, String> values) async {
    final db = await database;
    for (final e in values.entries) {
      await db.insert('vehicle_identity', {'k': e.key, 'v': e.value.trim()},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<void> _insertDemoRides(Database db) async {
    await db.insert('rides', {
      'title': 'Giro Recente 1',
      'subtitle': 'Lunghezza: 12.4 km • Rollio max: 42°',
      'time': '15 min fa',
      'date': '28/08/2026 - 19:15',
      'dist': '12.4 km',
      'dist_km': 12.4,
      'roll': '42° (SX) / 38° (DX)',
      'speed': '142 km/h',
      'rpm': '7800 RPM',
      'l_per_100': 6.4,
    });
    await db.insert('rides', {
      'title': 'Giro Recente 2',
      'subtitle': 'Lunghezza: 45.1 km • Velocità max: 148 km/h',
      'time': 'Ieri',
      'date': '27/08/2026 - 14:32',
      'dist': '45.1 km',
      'dist_km': 45.1,
      'roll': '39° (SX) / 41° (DX)',
      'speed': '148 km/h',
      'rpm': '8100 RPM',
      'l_per_100': 5.9,
    });
    await db.insert('rides', {
      'title': 'Prova strada',
      'subtitle': 'Lunghezza: 28.7 km • Giri max: 7100 RPM',
      'time': '2 giorni fa',
      'date': '26/08/2026 - 10:05',
      'dist': '28.7 km',
      'dist_km': 28.7,
      'roll': '35° (SX) / 33° (DX)',
      'speed': '131 km/h',
      'rpm': '7100 RPM',
      'l_per_100': 5.1,
    });
  }

  // ── Parsifica "12.4 km" → 12.4 ────────────────────────────────────────────
  static double _parseKm(String distText) {
    final match = RegExp(r'([\d.]+)\s*km').firstMatch(distText.toLowerCase());
    if (match == null) return 0.0;
    return double.tryParse(match.group(1) ?? '0') ?? 0.0;
  }

  // ── QUERY ─────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getRides() async {
    final db = await database;
    return await db.query('rides', orderBy: 'id DESC');
  }

  /// Totale km registrati in tutte le sessioni (campo numerico dist_km).
  /// Usato dal tagliando per calcolare km percorsi dall'ultimo intervento.
  Future<double> getTotalKm() async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT COALESCE(SUM(dist_km), 0) as total FROM rides');
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  /// Km totali a partire da una data specifica (ISO 8601 string).
  /// Usato per calcolare i km percorsi dall'ultimo intervento di manutenzione.
  Future<double> getKmSince(DateTime since) async {
    final db = await database;
    // Il campo date è nel formato "DD/MM/YYYY - HH:MM" — confrontiamo per id
    // poiché non abbiamo un timestamp Unix. Usiamo la data ISO salvata in prefs
    // come riferimento e contiamo tutte le ride (best effort).
    // Per una stima più precisa salviamo timestamp Unix nella v3 del DB.
    // Per ora restituiamo il totale dall'apertura dell'app.
    return await getTotalKm();
  }

  Future<int> insertRide(Map<String, dynamic> ride) async {
    final db = await database;
    // Calcola dist_km dal campo text se non fornito
    if (!ride.containsKey('dist_km') || (ride['dist_km'] as num?) == 0) {
      ride = Map<String, dynamic>.from(ride);
      ride['dist_km'] = _parseKm(ride['dist'] as String? ?? '');
    }
    return await db.insert('rides', ride);
  }

  Future<int> deleteRide(int id) async {
    final db = await database;
    return await db.delete('rides', where: 'id = ?', whereArgs: [id]);
  }
}
