import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/plant_sensor.dart';
import '../models/sensor_reading.dart';
import '../models/plant_profile.dart';
import '../models/api_provider.dart';
import '../data/default_plants.dart';

class DatabaseService {
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'plant_sense.db');

    return await openDatabase(
      path,
      version: 4,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE sensors (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        mac_address TEXT UNIQUE NOT NULL,
        sensor_type TEXT NOT NULL,
        plant_name TEXT,
        plant_profile_id INTEGER,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE readings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sensor_id INTEGER NOT NULL,
        temperature REAL,
        soil_temperature REAL,
        moisture REAL,
        light REAL,
        conductivity REAL,
        battery INTEGER,
        read_at TEXT NOT NULL,
        FOREIGN KEY (sensor_id) REFERENCES sensors(id) ON DELETE CASCADE
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_readings_sensor_date ON readings(sensor_id, read_at)',
    );

    await _createPlantProfilesTable(db);
    await _insertDefaultPlants(db);
    await _createApiProvidersTable(db);
    await _insertDefaultApiProviders(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createPlantProfilesTable(db);
      await _insertDefaultPlants(db);
      await db.execute(
        'ALTER TABLE sensors ADD COLUMN plant_profile_id INTEGER',
      );
    }
    if (oldVersion < 3) {
      await _createApiProvidersTable(db);
      await _insertDefaultApiProviders(db);
    }
    if (oldVersion < 4) {
      // Add type column to api_providers
      try {
        await db.execute(
          "ALTER TABLE api_providers ADD COLUMN type TEXT NOT NULL DEFAULT 'perenual'",
        );
      } catch (_) {
        // Column may already exist
      }
      // Insert Trefle provider
      await db.insert('api_providers', {
        'name': 'Trefle.io',
        'base_url': 'https://trefle.io/api/v1',
        'api_key': 'usr-6bSrj9_PypaC97Ny32FQbftDj6xe26TE7K_kVRDD0j4',
        'enabled': 1,
        'type': 'trefle',
      });
    }
  }

  Future<void> _createPlantProfilesTable(Database db) async {
    await db.execute('''
      CREATE TABLE plant_profiles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        scientific_name TEXT,
        category TEXT NOT NULL,
        image_url TEXT,
        temperature_min REAL NOT NULL,
        temperature_max REAL NOT NULL,
        moisture_min REAL NOT NULL,
        moisture_max REAL NOT NULL,
        light_min REAL NOT NULL,
        light_max REAL NOT NULL,
        conductivity_min REAL NOT NULL,
        conductivity_max REAL NOT NULL,
        api_id INTEGER
      )
    ''');
  }

  Future<void> _insertDefaultPlants(Database db) async {
    final batch = db.batch();
    for (final plant in defaultPlants) {
      batch.insert('plant_profiles', plant.toMap());
    }
    await batch.commit(noResult: true);
  }

  // --- Sensors CRUD ---

  Future<int> insertSensor(PlantSensor sensor) async {
    final db = await database;
    return await db.insert('sensors', sensor.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<PlantSensor>> getAllSensors() async {
    final db = await database;
    final maps = await db.query('sensors', orderBy: 'name');
    return maps.map((m) => PlantSensor.fromMap(m)).toList();
  }

  Future<PlantSensor?> getSensorByMac(String mac) async {
    final db = await database;
    final maps = await db.query(
      'sensors',
      where: 'mac_address = ?',
      whereArgs: [mac.toUpperCase()],
    );
    if (maps.isEmpty) return null;
    return PlantSensor.fromMap(maps.first);
  }

  Future<void> updateSensor(PlantSensor sensor) async {
    final db = await database;
    await db.update(
      'sensors',
      sensor.toMap(),
      where: 'id = ?',
      whereArgs: [sensor.id],
    );
  }

  Future<void> deleteSensor(int id) async {
    final db = await database;
    await db.delete('readings', where: 'sensor_id = ?', whereArgs: [id]);
    await db.delete('sensors', where: 'id = ?', whereArgs: [id]);
  }

  // --- Readings CRUD ---

  Future<int> insertReading(SensorReading reading) async {
    final db = await database;
    return await db.insert('readings', reading.toMap());
  }

  Future<SensorReading?> getLatestReading(int sensorId) async {
    final db = await database;
    final maps = await db.query(
      'readings',
      where: 'sensor_id = ?',
      whereArgs: [sensorId],
      orderBy: 'read_at DESC',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return SensorReading.fromMap(maps.first);
  }

  Future<List<SensorReading>> getReadings(
    int sensorId, {
    DateTime? since,
  }) async {
    final db = await database;
    String? where = 'sensor_id = ?';
    List<dynamic> whereArgs = [sensorId];

    if (since != null) {
      where += ' AND read_at >= ?';
      whereArgs.add(since.toIso8601String());
    }

    final maps = await db.query(
      'readings',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'read_at ASC',
    );
    return maps.map((m) => SensorReading.fromMap(m)).toList();
  }

  /// Fix corrupted readings with absurd values (e.g. light = 10^158).
  Future<void> sanitizeReadings() async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE readings SET light = NULL WHERE light > 200000',
    );
    await db.rawUpdate(
      'UPDATE readings SET conductivity = NULL WHERE conductivity > 50000',
    );
    await db.rawUpdate(
      'UPDATE readings SET moisture = NULL WHERE moisture > 100 OR moisture < 0',
    );
  }

  Future<void> purgeOldReadings(int keepDays) async {
    final db = await database;
    final cutoff =
        DateTime.now().subtract(Duration(days: keepDays)).toIso8601String();
    await db.delete(
      'readings',
      where: 'read_at < ?',
      whereArgs: [cutoff],
    );
  }

  // --- Plant Profiles CRUD ---

  Future<int> insertPlantProfile(PlantProfile profile) async {
    final db = await database;
    return await db.insert('plant_profiles', profile.toMap());
  }

  Future<List<PlantProfile>> getAllPlantProfiles() async {
    final db = await database;
    final maps = await db.query('plant_profiles', orderBy: 'name');
    return maps.map((m) => PlantProfile.fromMap(m)).toList();
  }

  Future<PlantProfile?> getPlantProfileById(int id) async {
    final db = await database;
    final maps = await db.query(
      'plant_profiles',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return PlantProfile.fromMap(maps.first);
  }

  Future<void> updatePlantProfile(PlantProfile profile) async {
    final db = await database;
    await db.update(
      'plant_profiles',
      profile.toMap(),
      where: 'id = ?',
      whereArgs: [profile.id],
    );
  }

  Future<void> deletePlantProfile(int id) async {
    final db = await database;
    // Unlink sensors referencing this profile
    await db.execute(
      'UPDATE sensors SET plant_profile_id = NULL WHERE plant_profile_id = ?',
      [id],
    );
    await db.delete('plant_profiles', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<PlantProfile>> searchPlantProfiles(String query) async {
    final db = await database;
    final maps = await db.query(
      'plant_profiles',
      where: 'name LIKE ? OR scientific_name LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'name',
    );
    return maps.map((m) => PlantProfile.fromMap(m)).toList();
  }

  // --- API Providers ---

  Future<void> _createApiProvidersTable(Database db) async {
    await db.execute('''
      CREATE TABLE api_providers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        base_url TEXT NOT NULL,
        api_key TEXT NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 1,
        type TEXT NOT NULL DEFAULT 'perenual'
      )
    ''');
  }

  Future<void> _insertDefaultApiProviders(Database db) async {
    await db.insert('api_providers', {
      'name': 'Perenual',
      'base_url': 'https://perenual.com/api/v2',
      'api_key': 'sk-XBGR67d0065e2cf928944',
      'enabled': 1,
      'type': 'perenual',
    });
    await db.insert('api_providers', {
      'name': 'Trefle.io',
      'base_url': 'https://trefle.io/api/v1',
      'api_key': 'usr-6bSrj9_PypaC97Ny32FQbftDj6xe26TE7K_kVRDD0j4',
      'enabled': 1,
      'type': 'trefle',
    });
  }

  Future<int> insertApiProvider(ApiProvider provider) async {
    final db = await database;
    return await db.insert('api_providers', provider.toMap());
  }

  Future<List<ApiProvider>> getAllApiProviders() async {
    final db = await database;
    final maps = await db.query('api_providers', orderBy: 'name');
    return maps.map((m) => ApiProvider.fromMap(m)).toList();
  }

  Future<List<ApiProvider>> getEnabledApiProviders() async {
    final db = await database;
    final maps = await db.query(
      'api_providers',
      where: 'enabled = 1',
      orderBy: 'name',
    );
    return maps.map((m) => ApiProvider.fromMap(m)).toList();
  }

  Future<void> updateApiProvider(ApiProvider provider) async {
    final db = await database;
    await db.update(
      'api_providers',
      provider.toMap(),
      where: 'id = ?',
      whereArgs: [provider.id],
    );
  }

  Future<void> deleteApiProvider(int id) async {
    final db = await database;
    await db.delete('api_providers', where: 'id = ?', whereArgs: [id]);
  }
}
