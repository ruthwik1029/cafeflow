import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/backend.dart';
import '../../auth/application/auth_controller.dart';
import '../../demo/data/demo_operations.dart';
import '../data/supabase_customers_repository.dart';

final customersProvider = FutureProvider.family<List<CustomerRecord>, String>((
  ref,
  search,
) async {
  final backend = ref.watch(backendProvider);
  final repo = ref.watch(customersRepositoryProvider);
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

      return await repo.listCustomers(
        restaurantId: restaurantId,
        search: search,
      );
    } catch (_) {}
  }

  // Fallback to mapped demo customers
  final cleanSearch = search.trim().toLowerCase();
  return demoCustomers
      .where((c) {
        if (cleanSearch.isEmpty) return true;
        return c.name.toLowerCase().contains(cleanSearch) ||
            c.phone.contains(cleanSearch);
      })
      .map(
        (c) => CustomerRecord(
          id: c.id,
          restaurantId: restaurantId ?? 'demo-rest',
          name: c.name,
          phone: c.phone,
          visitsCount: c.visits,
          favoriteItem: c.favoriteItem,
          totalSpendMinor: c.totalSpendMinor,
        ),
      )
      .toList();
});
