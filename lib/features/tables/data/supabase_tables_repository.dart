import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/database_gateway.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/backend.dart';
import '../../../core/services/cafe_realtime_service.dart';
import '../../../core/services/realtime_gateway.dart';
import '../domain/floor_models.dart';

export '../domain/floor_models.dart';

class SupabaseTablesRepository {
  SupabaseTablesRepository({required this.gateway, this.client, this.realtime});

  final DatabaseGateway gateway;
  final SupabaseClient? client;
  final CafeRealtimeService? realtime;

  // --------------------------------------------------------------------------
  // Floor Sections
  // --------------------------------------------------------------------------

  Future<List<FloorSection>> listSections(String restaurantId) async {
    final rows = await gateway.readRows(
      'floor_sections',
      equals: {'restaurant_id': restaurantId, 'is_active': true},
      limit: 50,
    );
    final sections = rows.map(FloorSection.fromMap).toList();
    sections.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return sections;
  }

  Future<FloorSection> createSection({
    required String restaurantId,
    required String name,
    String description = '',
    int sortOrder = 0,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw const AppFailure('Floor section name cannot be empty.');
    }
    if (client == null) {
      throw const AppFailure('Database client is not available.');
    }

    try {
      final res = await client!
          .from('floor_sections')
          .insert({
            'restaurant_id': restaurantId,
            'name': trimmedName,
            'description': description.trim(),
            'sort_order': sortOrder,
            'is_active': true,
          })
          .select()
          .single()
          .timeout(const Duration(seconds: 15));

      return FloorSection.fromMap(res);
    } on PostgrestException catch (e) {
      if (e.code == '42501') {
        throw const AppFailure(
          'Unauthorized: only admins can create floor sections.',
        );
      }
      throw AppFailure(e.message);
    } catch (_) {
      throw const AppFailure('Network failure while creating floor section.');
    }
  }

  // --------------------------------------------------------------------------
  // Dining Tables
  // --------------------------------------------------------------------------

  Future<List<DiningTableRecord>> listTables(String restaurantId) async {
    // 1. Fetch tables
    final tableRows = await gateway.readRows(
      'dining_tables',
      equals: {'restaurant_id': restaurantId, 'deleted_at': 'null'},
      limit: 150,
    );

    // 2. Fetch sections for mapping section names
    Map<String, String> sectionNameMap = {};
    try {
      final sections = await listSections(restaurantId);
      for (final s in sections) {
        sectionNameMap[s.id] = s.name;
      }
    } catch (_) {}

    // 3. Fetch active sessions to map active order and session details
    Map<String, Map<String, dynamic>> activeSessionMap = {};
    try {
      final sessionRows = await gateway.readRows(
        'table_sessions',
        equals: {'restaurant_id': restaurantId, 'status': 'ACTIVE'},
        limit: 150,
      );
      for (final sess in sessionRows) {
        activeSessionMap[sess['table_id'] as String] = sess;
      }
    } catch (_) {}

    return tableRows.map((row) {
      final rawStatus = (row['status'] as String? ?? 'AVAILABLE').toUpperCase();
      final status = TableStatusX.fromDb(rawStatus);
      final tableId = row['id'] as String;
      final sectionId = row['section_id'] as String?;
      final activeSession = activeSessionMap[tableId];

      return DiningTableRecord(
        id: tableId,
        restaurantId: row['restaurant_id'] as String,
        tableNumber: row['table_number'] as String,
        capacity: (row['capacity'] as num?)?.toInt() ?? 4,
        status: status,
        sectionId: sectionId,
        sectionName: sectionId != null ? sectionNameMap[sectionId] : null,
        activeSessionId:
            (activeSession?['id'] as String?) ??
            (row['active_session_id'] as String?),
        currentOrderId: activeSession?['current_order_id'] as String?,
        occupiedSince: activeSession?['opened_at'] != null
            ? DateTime.tryParse(activeSession!['opened_at'] as String)
            : null,
      );
    }).toList();
  }

  Future<void> updateTableStatus({
    required String restaurantId,
    required String tableId,
    required TableStatus status,
  }) async {
    if (client == null) {
      throw const AppFailure('Database client is not available.');
    }

    try {
      await client!
          .from('dining_tables')
          .update({
            'status': status.dbValue,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', tableId)
          .eq('restaurant_id', restaurantId)
          .timeout(const Duration(seconds: 15));
    } on PostgrestException catch (e) {
      if (e.code == '42501') {
        throw AppFailure('Permission denied: ${e.message}');
      }
      throw AppFailure(e.message);
    } catch (_) {
      throw const AppFailure('Network failure while updating table status.');
    }
  }

  Future<DiningTableRecord> createTable({
    required String restaurantId,
    required String tableNumber,
    required int capacity,
    String? sectionId,
  }) async {
    final trimmedNum = tableNumber.trim();
    if (trimmedNum.isEmpty) {
      throw const AppFailure('Table number cannot be empty.');
    }
    if (capacity <= 0) {
      throw const AppFailure('Capacity must be greater than zero.');
    }
    if (client == null) {
      throw const AppFailure('Database client is not available.');
    }

    try {
      final res = await client!
          .from('dining_tables')
          .insert({
            'restaurant_id': restaurantId,
            'table_number': trimmedNum,
            'capacity': capacity,
            'section_id': sectionId,
            'status': 'AVAILABLE',
          })
          .select()
          .single()
          .timeout(const Duration(seconds: 15));

      return DiningTableRecord.fromMap(res);
    } on PostgrestException catch (e) {
      if (e.code == '42501') {
        throw const AppFailure(
          'Unauthorized: only staff and admins can create tables.',
        );
      }
      throw AppFailure(e.message);
    } catch (_) {
      throw const AppFailure('Network failure while creating table.');
    }
  }

  // --------------------------------------------------------------------------
  // Table Sessions Management
  // --------------------------------------------------------------------------

  Future<Map<String, dynamic>> openSession({
    required String restaurantId,
    required String tableId,
    int guestCount = 1,
    String notes = '',
  }) async {
    if (client == null) {
      throw const AppFailure('Database client is not available.');
    }

    try {
      final res = await client!
          .rpc(
            'open_table_session',
            params: {
              'p_restaurant_id': restaurantId,
              'p_table_id': tableId,
              'p_guest_count': guestCount,
              'p_notes': notes,
            },
          )
          .timeout(const Duration(seconds: 15));

      return Map<String, dynamic>.from(res as Map);
    } on PostgrestException catch (e) {
      throw AppFailure(e.message);
    } catch (e) {
      throw AppFailure('Failed to open table session: $e');
    }
  }

  Future<Map<String, dynamic>> closeSession({
    required String restaurantId,
    required String sessionId,
    bool force = false,
  }) async {
    if (client == null) {
      throw const AppFailure('Database client is not available.');
    }

    try {
      final res = await client!
          .rpc(
            'close_table_session',
            params: {
              'p_restaurant_id': restaurantId,
              'p_session_id': sessionId,
              'p_force': force,
            },
          )
          .timeout(const Duration(seconds: 15));

      return Map<String, dynamic>.from(res as Map);
    } on PostgrestException catch (e) {
      throw AppFailure(e.message);
    } catch (e) {
      throw AppFailure('Failed to close table session: $e');
    }
  }

  Future<Map<String, dynamic>> transferSession({
    required String restaurantId,
    required String sessionId,
    required String targetTableId,
    String notes = '',
  }) async {
    if (client == null) {
      throw const AppFailure('Database client is not available.');
    }

    try {
      final res = await client!
          .rpc(
            'transfer_table_session',
            params: {
              'p_restaurant_id': restaurantId,
              'p_session_id': sessionId,
              'p_target_table_id': targetTableId,
              'p_notes': notes,
            },
          )
          .timeout(const Duration(seconds: 15));

      return Map<String, dynamic>.from(res as Map);
    } on PostgrestException catch (e) {
      throw AppFailure(e.message);
    } catch (e) {
      throw AppFailure('Failed to transfer table session: $e');
    }
  }

  Future<Map<String, dynamic>> mergeSessions({
    required String restaurantId,
    required String sourceSessionId,
    required String targetSessionId,
    String notes = '',
  }) async {
    if (client == null) {
      throw const AppFailure('Database client is not available.');
    }

    try {
      final res = await client!
          .rpc(
            'merge_table_sessions',
            params: {
              'p_restaurant_id': restaurantId,
              'p_source_session_id': sourceSessionId,
              'p_target_session_id': targetSessionId,
              'p_notes': notes,
            },
          )
          .timeout(const Duration(seconds: 15));

      return Map<String, dynamic>.from(res as Map);
    } on PostgrestException catch (e) {
      throw AppFailure(e.message);
    } catch (e) {
      throw AppFailure('Failed to merge table sessions: $e');
    }
  }

  Future<List<TableSession>> listActiveSessions(String restaurantId) async {
    final rows = await gateway.readRows(
      'table_sessions',
      equals: {'restaurant_id': restaurantId, 'status': 'ACTIVE'},
      limit: 100,
    );
    final sessions = rows.map(TableSession.fromMap).toList();
    sessions.sort((a, b) => b.openedAt.compareTo(a.openedAt));
    return sessions;
  }

  Stream<void> watchInvalidations(String restaurantId) {
    if (realtime == null) return const Stream.empty();
    return realtime!
        .watchDiningTables(restaurantId: restaurantId)
        .transform(
          StreamTransformer<RealtimeSignal, void>.fromHandlers(
            handleData: (signal, sink) => sink.add(null),
            handleError: (error, stackTrace, sink) {},
          ),
        );
  }
}

final tablesRepositoryProvider = Provider<SupabaseTablesRepository?>((ref) {
  final backend = ref.watch(backendProvider);
  if (backend.status != BackendStatus.initialized) {
    return null;
  }
  return SupabaseTablesRepository(
    gateway: ref.watch(databaseGatewayProvider),
    client: backend.client,
    realtime: ref.watch(cafeRealtimeServiceProvider),
  );
});
