import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/backend.dart';
import '../../auth/application/auth_controller.dart';
import '../../demo/application/demo_tables_controller.dart';
import '../data/supabase_tables_repository.dart';

export '../domain/floor_models.dart';

/// Provides the list of dining tables for the active restaurant.
final tablesProvider = FutureProvider<List<DiningTableRecord>>((ref) async {
  final backend = ref.watch(backendProvider);
  final repo = ref.watch(tablesRepositoryProvider);
  final auth = ref.watch(authControllerProvider);
  final restaurantId = auth.activeMembership?.restaurantId;

  if (backend.status == BackendStatus.initialized &&
      repo != null &&
      restaurantId != null) {
    try {
      final sub = repo.watchInvalidations(restaurantId).listen((_) {
        ref.invalidateSelf();
      });
      ref.onDispose(sub.cancel);

      return await repo.listTables(restaurantId);
    } catch (_) {}
  }

  // Fallback to mapped demo dining tables
  final demoList = ref.watch(demoTablesProvider);
  return demoList
      .map(
        (t) => DiningTableRecord(
          id: t.id,
          restaurantId: restaurantId ?? 'demo-rest',
          tableNumber: t.name,
          capacity: t.capacity,
          status: t.status,
          currentOrderNumber: t.currentOrderNumber,
        ),
      )
      .toList();
});

/// Provides configurable floor sections (e.g. Main Dining, Patio, Bar).
final floorSectionsProvider = FutureProvider<List<FloorSection>>((ref) async {
  final backend = ref.watch(backendProvider);
  final repo = ref.watch(tablesRepositoryProvider);
  final auth = ref.watch(authControllerProvider);
  final restaurantId = auth.activeMembership?.restaurantId;

  if (backend.status == BackendStatus.initialized &&
      repo != null &&
      restaurantId != null) {
    try {
      return await repo.listSections(restaurantId);
    } catch (_) {}
  }

  // Default demo sections
  return const [
    FloorSection(
      id: 'sec-main',
      restaurantId: 'demo-rest',
      name: 'Main Dining Room',
      sortOrder: 1,
    ),
    FloorSection(
      id: 'sec-patio',
      restaurantId: 'demo-rest',
      name: 'Outdoor Patio',
      sortOrder: 2,
    ),
    FloorSection(
      id: 'sec-bar',
      restaurantId: 'demo-rest',
      name: 'Bar Counter',
      sortOrder: 3,
    ),
  ];
});

/// Provides active table dining sessions.
final activeTableSessionsProvider = FutureProvider<List<TableSession>>((
  ref,
) async {
  final backend = ref.watch(backendProvider);
  final repo = ref.watch(tablesRepositoryProvider);
  final auth = ref.watch(authControllerProvider);
  final restaurantId = auth.activeMembership?.restaurantId;

  if (backend.status == BackendStatus.initialized &&
      repo != null &&
      restaurantId != null) {
    try {
      return await repo.listActiveSessions(restaurantId);
    } catch (_) {}
  }

  return const [];
});
