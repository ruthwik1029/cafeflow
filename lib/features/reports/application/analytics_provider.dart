import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/backend.dart';
import '../../auth/application/auth_controller.dart';
import '../../inventory/application/inventory_provider.dart';
import '../../orders/application/orders_provider.dart';
import '../../tables/application/tables_provider.dart';
import '../data/analytics_repository.dart';
import '../domain/analytics_models.dart';

export '../domain/analytics_models.dart';
export '../data/analytics_repository.dart'
    show
        AnalyticsRepository,
        DemoAnalyticsRepository,
        SupabaseAnalyticsRepository,
        analyticsRepositoryProvider;

/// Filter argument for analytics queries.
class AnalyticsFilterArgs {
  const AnalyticsFilterArgs({
    this.preset = AnalyticsTimePreset.today,
    this.customRange,
  });

  final AnalyticsTimePreset preset;
  final DateTimeRange? customRange;

  DateTimeRange resolveRange() {
    if (preset == AnalyticsTimePreset.custom && customRange != null) {
      return customRange!;
    }
    return preset.getRange();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnalyticsFilterArgs &&
          other.preset == preset &&
          other.customRange == customRange;

  @override
  int get hashCode => Object.hash(preset, customRange);
}

/// Comprehensive multi-dimensional analytics provider.
final comprehensiveAnalyticsProvider =
    FutureProvider.family<ComprehensiveAnalytics, AnalyticsFilterArgs?>((
      ref,
      args,
    ) async {
      final backend = ref.watch(backendProvider);
      final auth = ref.watch(authControllerProvider);
      final repo = ref.watch(analyticsRepositoryProvider);
      final restaurantId = auth.activeMembership?.restaurantId;

      final effectiveArgs = args ?? const AnalyticsFilterArgs();
      final range = effectiveArgs.resolveRange();

      // Reactive data watchers for demo fallback
      final orders = ref.watch(ordersProvider).value;
      final inventory = ref.watch(inventoryProvider).value;
      final tables = ref.watch(tablesProvider).value;

      final isLive =
          backend.status == BackendStatus.initialized &&
          restaurantId != null &&
          repo is SupabaseAnalyticsRepository;

      if (isLive) {
        try {
          // Listen to realtime invalidations
          final sub = repo
              .watchAnalyticsInvalidations(restaurantId: restaurantId)
              .listen((_) {
                ref.invalidateSelf();
              });
          ref.onDispose(sub.cancel);

          return await repo.fetchComprehensiveAnalytics(
            restaurantId: restaurantId,
            startDate: range.start,
            endDate: range.end,
          );
        } catch (_) {
          // If RPC fails (e.g., during network glitch or insufficient role), gracefully calculate locally
        }
      }

      // Demo/offline calculation using in-memory state
      return DemoAnalyticsRepository.generateDemoAnalytics(
        range.start,
        range.end,
        orders: orders,
        inventory: inventory,
        tables: tables,
      );
    });
