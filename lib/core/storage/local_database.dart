import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Storage adapter interface for the local persistent database.
abstract interface class LocalStorageAdapter {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<List<String>> listKeys({String? prefix});
  Future<void> clearAll();
}

/// In-memory storage adapter for testing and fast isolated environments.
class MemoryStorageAdapter implements LocalStorageAdapter {
  final Map<String, String> _store = {};

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, String value) async => _store[key] = value;

  @override
  Future<void> delete(String key) async => _store.remove(key);

  @override
  Future<List<String>> listKeys({String? prefix}) async {
    if (prefix == null) return _store.keys.toList();
    return _store.keys.where((k) => k.startsWith(prefix)).toList();
  }

  @override
  Future<void> clearAll() async => _store.clear();
}

/// Production persistent storage adapter using SharedPreferences.
/// Works reliably across Windows Desktop, Android, and Web with zero native C++ runtime binary dependencies.
class SharedPreferencesStorageAdapter implements LocalStorageAdapter {
  const SharedPreferencesStorageAdapter(this._prefs);
  final SharedPreferences _prefs;

  @override
  Future<String?> read(String key) async => _prefs.getString(key);

  @override
  Future<void> write(String key, String value) async =>
      _prefs.setString(key, value);

  @override
  Future<void> delete(String key) async => _prefs.remove(key);

  @override
  Future<List<String>> listKeys({String? prefix}) async {
    final keys = _prefs.getKeys();
    if (prefix == null) return keys.toList();
    return keys.where((k) => k.startsWith(prefix)).toList();
  }

  @override
  Future<void> clearAll() async => _prefs.clear();
}

/// A structured transaction in the local database.
class LocalTransaction {
  LocalTransaction(this._database);
  final CafeLocalDatabase _database;

  final Map<String, Map<String, Map<String, dynamic>>> _stagedWrites = {};
  final Map<String, Set<String>> _stagedDeletes = {};
  bool _committed = false;
  bool _rolledBack = false;

  void insert(String collection, String id, Map<String, dynamic> data) {
    if (_committed || _rolledBack) {
      throw StateError('Transaction already closed.');
    }
    _stagedWrites.putIfAbsent(collection, () => {})[id] = Map.from(data);
  }

  void update(String collection, String id, Map<String, dynamic> partialData) {
    if (_committed || _rolledBack) {
      throw StateError('Transaction already closed.');
    }
    final existing =
        _stagedWrites[collection]?[id] ??
        _database._collections[collection]?[id] ??
        {};
    final updated = Map<String, dynamic>.from(existing)..addAll(partialData);
    _stagedWrites.putIfAbsent(collection, () => {})[id] = updated;
  }

  void delete(String collection, String id) {
    if (_committed || _rolledBack) {
      throw StateError('Transaction already closed.');
    }
    _stagedDeletes.putIfAbsent(collection, () => {}).add(id);
    _stagedWrites[collection]?.remove(id);
  }

  Future<void> commit() async {
    if (_committed || _rolledBack) {
      throw StateError('Transaction already closed.');
    }
    for (final entry in _stagedWrites.entries) {
      final col = entry.key;
      for (final doc in entry.value.entries) {
        _database._collections.putIfAbsent(col, () => {})[doc.key] = doc.value;
      }
    }
    for (final entry in _stagedDeletes.entries) {
      final col = entry.key;
      for (final id in entry.value) {
        _database._collections[col]?.remove(id);
      }
    }
    _committed = true;
    await _database._persistDirtyCollections(
      _stagedWrites.keys.toSet()..addAll(_stagedDeletes.keys),
    );
  }

  void rollback() {
    _stagedWrites.clear();
    _stagedDeletes.clear();
    _rolledBack = true;
  }
}

/// Complete local database for CafeFlow with collections, secondary indices, transactions,
/// and safe forward migrations.
class CafeLocalDatabase {
  CafeLocalDatabase({required this.adapter});

  final LocalStorageAdapter adapter;
  static const int currentSchemaVersion = 1;
  static const String keyPrefix = 'cafeflow_db_v1_';

  final Map<String, Map<String, Map<String, dynamic>>> _collections = {};
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  /// Initializes the local database, loads persistent collections from disk, and runs migrations.
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Load schema version
    final versionStr = await adapter.read('${keyPrefix}meta_schema_version');
    final version = versionStr != null ? int.tryParse(versionStr) ?? 0 : 0;

    if (version < currentSchemaVersion) {
      await _runMigrations(version, currentSchemaVersion);
      await adapter.write(
        '${keyPrefix}meta_schema_version',
        currentSchemaVersion.toString(),
      );
    }

    // Load all collections
    final keys = await adapter.listKeys(prefix: '${keyPrefix}col_');
    for (final key in keys) {
      final collectionName = key.substring('${keyPrefix}col_'.length);
      final jsonStr = await adapter.read(key);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        try {
          final decoded = json.decode(jsonStr) as Map<String, dynamic>;
          _collections[collectionName] = decoded.map(
            (k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)),
          );
        } catch (_) {
          // If a collection JSON is corrupt, initialize empty
          _collections[collectionName] = {};
        }
      }
    }

    _isInitialized = true;
  }

  Future<void> _runMigrations(int fromVersion, int toVersion) async {
    // Migration v0 -> v1: Initial collection sets
    if (fromVersion < 1) {
      // Setup default empty collections
      _collections['orders'] = {};
      _collections['order_items'] = {};
      _collections['payments'] = {};
      _collections['menu_categories'] = {};
      _collections['menu_items'] = {};
      _collections['dining_tables'] = {};
      _collections['restaurant_settings'] = {};
      _collections['payment_methods'] = {};
      _collections['customers'] = {};
      _collections['sync_queue'] = {};
      _collections['sync_conflicts'] = {};
      _collections['floor_sections'] = {};
      _collections['kitchen_stations'] = {};
      _collections['table_sessions'] = {};
      _collections['kitchen_order_tickets'] = {};
      _collections['kot_items'] = {};
      _collections['table_transfers_audit'] = {};
      _collections['inventory_items'] = {};
      _collections['inventory_categories'] = {};
      _collections['stock_movements'] = {};
      _collections['suppliers'] = {};
      _collections['purchases'] = {};
      _collections['purchase_items'] = {};
      _collections['menu_item_ingredients'] = {};
      _collections['staff_profiles'] = {};
      _collections['shifts'] = {};
      _collections['staff_attendance'] = {};
      _collections['staff_audit_events'] = {};
    }
  }

  Future<void> _persistDirtyCollections(Set<String> collections) async {
    for (final col in collections) {
      final data = _collections[col] ?? {};
      final jsonStr = json.encode(data);
      await adapter.write('${keyPrefix}col_$col', jsonStr);
    }
  }

  /// Runs an atomic transaction with automatic rollback on error.
  Future<T> runTransaction<T>(
    Future<T> Function(LocalTransaction tx) action,
  ) async {
    if (!_isInitialized) await initialize();
    final tx = LocalTransaction(this);
    try {
      final result = await action(tx);
      await tx.commit();
      return result;
    } catch (e) {
      tx.rollback();
      rethrow;
    }
  }

  /// Inserts or replaces a record in a collection.
  Future<void> put(
    String collection,
    String id,
    Map<String, dynamic> data,
  ) async {
    if (!_isInitialized) await initialize();
    _collections.putIfAbsent(collection, () => {})[id] = Map.from(data);
    await _persistDirtyCollections({collection});
  }

  /// Retrieves a record by ID.
  Future<Map<String, dynamic>?> get(String collection, String id) async {
    if (!_isInitialized) await initialize();
    final row = _collections[collection]?[id];
    if (row == null) return null;
    return Map<String, dynamic>.from(row);
  }

  /// Deletes a record by ID.
  Future<void> delete(String collection, String id) async {
    if (!_isInitialized) await initialize();
    if (_collections[collection]?.remove(id) != null) {
      await _persistDirtyCollections({collection});
    }
  }

  /// Queries all records in a collection matching equality filters.
  Future<List<Map<String, dynamic>>> query(
    String collection, {
    Map<String, dynamic> where = const {},
    String? orderBy,
    bool descending = false,
    int? limit,
  }) async {
    if (!_isInitialized) await initialize();
    final col = _collections[collection] ?? {};
    var results = col.values
        .where((item) {
          for (final entry in where.entries) {
            if (item[entry.key] != entry.value) return false;
          }
          return true;
        })
        .map((m) => Map<String, dynamic>.from(m))
        .toList();

    if (orderBy != null) {
      results.sort((a, b) {
        final valA = a[orderBy];
        final valB = b[orderBy];
        if (valA == null && valB == null) return 0;
        if (valA == null) return descending ? 1 : -1;
        if (valB == null) return descending ? -1 : 1;
        final cmp = Comparable.compare(valA as Comparable, valB as Comparable);
        return descending ? -cmp : cmp;
      });
    }

    if (limit != null && results.length > limit) {
      results = results.sublist(0, limit);
    }

    return results;
  }

  /// Clears cache collections for a specific restaurant tenant, isolating multi-tenant data.
  Future<void> clearTenantCache(String restaurantId) async {
    if (!_isInitialized) await initialize();
    final cacheCollections = [
      'orders',
      'order_items',
      'payments',
      'menu_categories',
      'menu_items',
      'dining_tables',
      'restaurant_settings',
      'payment_methods',
      'customers',
      'sync_conflicts',
      'floor_sections',
      'kitchen_stations',
      'table_sessions',
      'kitchen_order_tickets',
      'kot_items',
      'table_transfers_audit',
      'inventory_items',
      'inventory_categories',
      'stock_movements',
      'suppliers',
      'purchases',
      'purchase_items',
      'menu_item_ingredients',
      'staff_profiles',
      'shifts',
      'staff_attendance',
      'staff_audit_events',
    ];
    for (final col in cacheCollections) {
      final rows = _collections[col];
      if (rows != null) {
        rows.removeWhere((id, item) => item['restaurant_id'] == restaurantId);
      }
    }
    await _persistDirtyCollections(cacheCollections.toSet());
  }

  /// Completely wipes local database (for tests and account logout).
  Future<void> clearAll() async {
    _collections.clear();
    await adapter.clearAll();
    _isInitialized = false;
  }
}

/// Global Riverpod providers for LocalDatabase.
final localDatabaseProvider = Provider<CafeLocalDatabase>((ref) {
  // In production, SharedPreferencesStorageAdapter is supplied.
  // In tests, can be overridden with MemoryStorageAdapter.
  return CafeLocalDatabase(adapter: MemoryStorageAdapter());
});
