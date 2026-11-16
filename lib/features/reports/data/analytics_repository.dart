import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/backend.dart';
import '../../demo/data/demo_operations.dart';
import '../../inventory/domain/inventory_models.dart';
import '../../orders/domain/cafe_order.dart';
import '../../tables/domain/floor_models.dart';
import '../domain/analytics_models.dart';

abstract class AnalyticsRepository {
  Future<ComprehensiveAnalytics> fetchComprehensiveAnalytics({
    required String restaurantId,
    required DateTime startDate,
    required DateTime endDate,
  });

  Stream<void> watchAnalyticsInvalidations({required String restaurantId});
}

class SupabaseAnalyticsRepository implements AnalyticsRepository {
  SupabaseAnalyticsRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<ComprehensiveAnalytics> fetchComprehensiveAnalytics({
    required String restaurantId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final response = await _client.rpc(
      'get_comprehensive_business_analytics',
      params: {
        'p_restaurant_id': restaurantId,
        'p_start_date': startDate.toIso8601String(),
        'p_end_date': endDate.toIso8601String(),
      },
    );

    if (response is Map<String, dynamic>) {
      return ComprehensiveAnalytics.fromJson(response);
    }
    throw StateError('Invalid response payload from analytics RPC');
  }

  @override
  Stream<void> watchAnalyticsInvalidations({required String restaurantId}) {
    // Listens to channel broadcast on orders, payments, and inventory
    final controller = StreamController<void>.broadcast();
    final channel = _client.channel('analytics-realtime-$restaurantId');

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'restaurant_id',
            value: restaurantId,
          ),
          callback: (_) => controller.add(null),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'payments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'restaurant_id',
            value: restaurantId,
          ),
          callback: (_) => controller.add(null),
        )
        .subscribe();

    controller.onCancel = () {
      channel.unsubscribe();
      controller.close();
    };

    return controller.stream;
  }
}

/// Fallback analytics generator for offline/demo operation.
class DemoAnalyticsRepository implements AnalyticsRepository {
  const DemoAnalyticsRepository();

  @override
  Future<ComprehensiveAnalytics> fetchComprehensiveAnalytics({
    required String restaurantId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    return generateDemoAnalytics(startDate, endDate);
  }

  @override
  Stream<void> watchAnalyticsInvalidations({required String restaurantId}) {
    return const Stream.empty();
  }

  static ComprehensiveAnalytics generateDemoAnalytics(
    DateTime startDate,
    DateTime endDate, {
    List<CafeOrder>? orders,
    List<InventoryItem>? inventory,
    List<DiningTableRecord>? tables,
  }) {
    final orderList = orders ?? demoOrders;

    // Filter orders by date range
    final inRangeOrders = orderList.where((o) {
      return o.createdAt.isAfter(
            startDate.subtract(const Duration(seconds: 1)),
          ) &&
          o.createdAt.isBefore(endDate.add(const Duration(seconds: 1)));
    }).toList();

    final validOrders = inRangeOrders
        .where((o) => o.status != OrderStatus.cancelled)
        .toList();

    int grossSales = 0;
    int discounts = 0;
    int tax = 0;
    int totalPayments = 0;
    int cash = 0;
    int upi = 0;
    int card = 0;
    int refunds = 0;
    int outstanding = 0;

    final Map<String, int> productQty = {};
    final Map<String, int> productRev = {};
    final Map<String, int> orderTypeCount = {
      'Dine-In': 0,
      'Takeaway': 0,
      'Delivery': 0,
    };
    final Map<String, int> orderTypeRev = {
      'Dine-In': 0,
      'Takeaway': 0,
      'Delivery': 0,
    };

    for (final order in validOrders) {
      grossSales += order.totalMinor;
      discounts += order.discountMinor;
      tax += order.taxMinor;
      refunds += order.refundedMinor;
      totalPayments += order.paidMinor;
      outstanding += order.outstandingMinor;

      // Tender estimation for demo
      if (order.isFullyPaid) {
        if (order.number.endsWith('1') || order.number.endsWith('4')) {
          cash += order.paidMinor;
        } else if (order.number.endsWith('2') || order.number.endsWith('5')) {
          upi += order.paidMinor;
        } else {
          card += order.paidMinor;
        }
      }

      // Order type
      final type = (order.table.toLowerCase().contains('takeaway'))
          ? 'Takeaway'
          : (order.table.toLowerCase().contains('delivery'))
          ? 'Delivery'
          : 'Dine-In';
      orderTypeCount[type] = (orderTypeCount[type] ?? 0) + 1;
      orderTypeRev[type] = (orderTypeRev[type] ?? 0) + order.totalMinor;

      // Lines
      for (final line in order.lines) {
        productQty[line.name] = (productQty[line.name] ?? 0) + line.quantity;
        productRev[line.name] = (productRev[line.name] ?? 0) + line.totalMinor;
      }
    }

    final netSales = grossSales - discounts;
    final avgOrderValue = validOrders.isEmpty
        ? 0
        : grossSales ~/ validOrders.length;

    // Top & least products
    final sortedProductKeys = productQty.keys.toList()
      ..sort((a, b) => (productQty[b] ?? 0).compareTo(productQty[a] ?? 0));

    final topProducts = sortedProductKeys.take(5).map((name) {
      return ProductSalesMetric(
        productName: name,
        quantitySold: productQty[name] ?? 0,
        revenueMinor: productRev[name] ?? 0,
      );
    }).toList();

    final leastProducts = sortedProductKeys.reversed.take(3).map((name) {
      return ProductSalesMetric(
        productName: name,
        quantitySold: productQty[name] ?? 0,
        revenueMinor: productRev[name] ?? 0,
      );
    }).toList();

    // Inventory metrics
    int stockValuation = 0;
    int lowStockCount = 0;
    int outOfStockCount = 0;
    int totalItems = 0;

    if (inventory != null && inventory.isNotEmpty) {
      totalItems = inventory.length;
      for (final item in inventory) {
        stockValuation += (item.currentStock * item.costPerUnitMinor).round();
        if (item.currentStock <= 0) {
          outOfStockCount++;
        } else if (item.isLow) {
          lowStockCount++;
        }
      }
    } else {
      totalItems = demoInventory.length;
      for (final item in demoInventory) {
        stockValuation += (item.quantity * 35000).round();
        if (item.quantity <= 0) {
          outOfStockCount++;
        } else if (item.isLow) {
          lowStockCount++;
        }
      }
    }

    // Table occupancy
    final int totalTables;
    final int occupiedTables;
    if (tables != null && tables.isNotEmpty) {
      totalTables = tables.length;
      occupiedTables = tables
          .where((t) => t.status == TableStatus.occupied)
          .length;
    } else {
      totalTables = demoTables.length;
      occupiedTables = demoTables
          .where((t) => t.status == TableStatus.occupied)
          .length;
    }
    final occupancyRate = totalTables == 0
        ? 0.0
        : (occupiedTables / totalTables) * 100.0;

    // Kitchen
    final activeTickets = validOrders
        .where(
          (o) =>
              o.status == OrderStatus.newOrder ||
              o.status == OrderStatus.preparing,
        )
        .length;
    final completedTickets = validOrders
        .where(
          (o) =>
              o.status == OrderStatus.ready ||
              o.status == OrderStatus.completed,
        )
        .length;

    final orderTypeMetrics = orderTypeCount.entries.map((e) {
      return OrderTypeMetric(
        orderType: e.key,
        orderCount: e.value,
        revenueMinor: orderTypeRev[e.key] ?? 0,
      );
    }).toList();

    return ComprehensiveAnalytics(
      startDate: startDate,
      endDate: endDate,
      financial: FinancialAnalyticsReport(
        grossSalesMinor: grossSales,
        discountsTotalMinor: discounts,
        netSalesMinor: netSales,
        taxCollectedMinor: tax,
        serviceChargeMinor: 0,
        totalPaymentsMinor: totalPayments,
        cashCollectedMinor: cash,
        upiCollectedMinor: upi,
        cardCollectedMinor: card,
        otherCollectedMinor: 0,
        refundsTotalMinor: refunds,
        netCollectedMinor: totalPayments - refunds,
        outstandingBalanceMinor: outstanding,
        totalOrdersCount: inRangeOrders.length,
        paidOrdersCount: validOrders.where((o) => o.isFullyPaid).length,
        unpaidOrdersCount: validOrders.where((o) => !o.isFullyPaid).length,
        avgOrderValueMinor: avgOrderValue,
      ),
      orderTypes: orderTypeMetrics,
      dailyTrends: [
        DailyTrendMetric(
          date:
              '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}',
          grossSalesMinor: grossSales,
          netSalesMinor: netSales,
          orderCount: validOrders.length,
        ),
      ],
      topProducts: topProducts,
      leastProducts: leastProducts,
      inventory: InventoryAnalyticsMetric(
        totalItemsCount: totalItems,
        lowStockCount: lowStockCount,
        outOfStockCount: outOfStockCount,
        stockValuationMinor: stockValuation,
        wastageCostMinor: 45000, // INR 450 demo wastage
      ),
      kitchen: KitchenAnalyticsMetric(
        avgPrepTimeSeconds: 490, // 8m 10s
        activeTicketsCount: activeTickets,
        delayedTicketsCount: 0,
        completedTicketsCount: completedTickets,
      ),
      tables: TableAnalyticsMetric(
        totalTables: totalTables,
        occupiedTables: occupiedTables,
        occupancyRatePercent: double.parse(occupancyRate.toStringAsFixed(1)),
      ),
      workforce: const WorkforceAnalyticsMetric(
        currentlyClockedIn: 3,
        currentlyOnBreak: 1,
        lateArrivalsCount: 0,
      ),
    );
  }
}

final analyticsRepositoryProvider = Provider<AnalyticsRepository>((ref) {
  final backend = ref.watch(backendProvider);
  if (backend.status == BackendStatus.initialized) {
    try {
      final client = Supabase.instance.client;
      return SupabaseAnalyticsRepository(client);
    } catch (_) {}
  }
  return const DemoAnalyticsRepository();
});
