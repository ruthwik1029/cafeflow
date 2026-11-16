import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/backend.dart';
import '../../auth/application/auth_controller.dart';
import '../data/supabase_kitchen_repository.dart';

export '../domain/kot_models.dart';

/// Provides the list of kitchen stations (e.g. Hot Kitchen, Bar, Bakery).
final kitchenStationsProvider = FutureProvider<List<KitchenStation>>((
  ref,
) async {
  final backend = ref.watch(backendProvider);
  final repo = ref.watch(kitchenRepositoryProvider);
  final auth = ref.watch(authControllerProvider);
  final restaurantId = auth.activeMembership?.restaurantId;

  if (backend.status == BackendStatus.initialized &&
      repo != null &&
      restaurantId != null) {
    try {
      return await repo.listStations(restaurantId);
    } catch (_) {}
  }

  // Fallback default demo stations
  return const [
    KitchenStation(
      id: 'st-main',
      restaurantId: 'demo-rest',
      name: 'Main Kitchen',
      code: 'MAIN',
    ),
    KitchenStation(
      id: 'st-hot',
      restaurantId: 'demo-rest',
      name: 'Hot Kitchen & Grills',
      code: 'HOT',
    ),
    KitchenStation(
      id: 'st-bar',
      restaurantId: 'demo-rest',
      name: 'Beverage Bar & Espresso',
      code: 'BAR',
    ),
    KitchenStation(
      id: 'st-bakery',
      restaurantId: 'demo-rest',
      name: 'Bakery & Pastry',
      code: 'BAKERY',
    ),
  ];
});

/// Parameter for filtering active KOTs.
class KotFilter {
  const KotFilter({this.stationId, this.status});
  final String? stationId;
  final KotStatus? status;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KotFilter &&
          other.stationId == stationId &&
          other.status == status;

  @override
  int get hashCode => Object.hash(stationId, status);
}

/// Provides the active kitchen tickets with realtime auto-refresh.
final activeKotsProvider =
    FutureProvider.family<List<KitchenOrderTicket>, KotFilter>((
      ref,
      filter,
    ) async {
      final backend = ref.watch(backendProvider);
      final repo = ref.watch(kitchenRepositoryProvider);
      final auth = ref.watch(authControllerProvider);
      final restaurantId = auth.activeMembership?.restaurantId;

      if (backend.status == BackendStatus.initialized &&
          repo != null &&
          restaurantId != null) {
        try {
          final sub = repo.watchKitchen(restaurantId).listen((_) {
            ref.invalidateSelf();
          });
          ref.onDispose(sub.cancel);

          return await repo.listKots(
            restaurantId: restaurantId,
            stationId: filter.stationId,
            status: filter.status,
          );
        } catch (_) {}
      }

      return const [];
    });
