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
      version: 2,
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
            rpm TEXT
          )
        ''');
        await _insertDemoRides(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
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
