import 'package:flutter/material.dart';

/// Predefined date presets for business reporting.
enum AnalyticsTimePreset {
  today,
  yesterday,
  last7Days,
  last30Days,
  thisMonth,
  allTime,
  custom;

  String get label => switch (this) {
    AnalyticsTimePreset.today => 'Today',
    AnalyticsTimePreset.yesterday => 'Yesterday',
    AnalyticsTimePreset.last7Days => 'Last 7 Days',
    AnalyticsTimePreset.last30Days => 'Last 30 Days',
    AnalyticsTimePreset.thisMonth => 'This Month',
    AnalyticsTimePreset.allTime => 'All Time',
    AnalyticsTimePreset.custom => 'Custom Range',
  };

  DateTimeRange getRange([DateTime? referenceNow]) {
    final now = referenceNow ?? DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    return switch (this) {
      AnalyticsTimePreset.today => DateTimeRange(start: todayStart, end: now),
      AnalyticsTimePreset.yesterday => DateTimeRange(
        start: todayStart.subtract(const Duration(days: 1)),
        end: DateTime(now.year, now.month, now.day - 1, 23, 59, 59, 999),
      ),
      AnalyticsTimePreset.last7Days => DateTimeRange(
        start: todayStart.subtract(const Duration(days: 6)),
        end: now,
      ),
      AnalyticsTimePreset.last30Days => DateTimeRange(
        start: todayStart.subtract(const Duration(days: 29)),
        end: now,
      ),
      AnalyticsTimePreset.thisMonth => DateTimeRange(
        start: DateTime(now.year, now.month, 1),
        end: now,
      ),
      AnalyticsTimePreset.allTime => DateTimeRange(
        start: DateTime(2020, 1, 1),
        end: now,
      ),
      AnalyticsTimePreset.custom => DateTimeRange(start: todayStart, end: now),
    };
  }
}

/// Order type breakdown (Dine-In, Takeaway, Delivery).
class OrderTypeMetric {
  const OrderTypeMetric({
    required this.orderType,
    required this.orderCount,
    required this.revenueMinor,
  });

  final String orderType;
  final int orderCount;
  final int revenueMinor;

  factory OrderTypeMetric.fromJson(Map<String, dynamic> json) {
    return OrderTypeMetric(
      orderType: (json['order_type'] as String?) ?? 'Unknown',
      orderCount: (json['order_count'] as num?)?.toInt() ?? 0,
      revenueMinor: (json['revenue_minor'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'order_type': orderType,
    'order_count': orderCount,
    'revenue_minor': revenueMinor,
  };
}

/// Daily sales trend metric.
class DailyTrendMetric {
  const DailyTrendMetric({
    required this.date,
    required this.grossSalesMinor,
    required this.netSalesMinor,
    required this.orderCount,
  });

  final String date;
  final int grossSalesMinor;
  final int netSalesMinor;
  final int orderCount;

  factory DailyTrendMetric.fromJson(Map<String, dynamic> json) {
    return DailyTrendMetric(
      date: (json['date'] as String?) ?? '',
      grossSalesMinor: (json['gross_sales_minor'] as num?)?.toInt() ?? 0,
      netSalesMinor: (json['net_sales_minor'] as num?)?.toInt() ?? 0,
      orderCount: (json['order_count'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'date': date,
    'gross_sales_minor': grossSalesMinor,
    'net_sales_minor': netSalesMinor,
    'order_count': orderCount,
  };
}

/// Product sales volume and revenue snapshot.
class ProductSalesMetric {
  const ProductSalesMetric({
    required this.productName,
    required this.quantitySold,
    required this.revenueMinor,
  });

  final String productName;
  final int quantitySold;
  final int revenueMinor;

  factory ProductSalesMetric.fromJson(Map<String, dynamic> json) {
    return ProductSalesMetric(
      productName: (json['product_name'] as String?) ?? 'Unknown',
      quantitySold: (json['quantity_sold'] as num?)?.toInt() ?? 0,
      revenueMinor: (json['revenue_minor'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'product_name': productName,
    'quantity_sold': quantitySold,
    'revenue_minor': revenueMinor,
  };
}

/// Inventory valuation and wastage analytics.
class InventoryAnalyticsMetric {
  const InventoryAnalyticsMetric({
    required this.totalItemsCount,
    required this.lowStockCount,
    required this.outOfStockCount,
    required this.stockValuationMinor,
    required this.wastageCostMinor,
  });

  final int totalItemsCount;
  final int lowStockCount;
  final int outOfStockCount;
  final int stockValuationMinor;
  final int wastageCostMinor;

  factory InventoryAnalyticsMetric.fromJson(Map<String, dynamic> json) {
    return InventoryAnalyticsMetric(
      totalItemsCount: (json['total_items_count'] as num?)?.toInt() ?? 0,
      lowStockCount: (json['low_stock_count'] as num?)?.toInt() ?? 0,
      outOfStockCount: (json['out_of_stock_count'] as num?)?.toInt() ?? 0,
      stockValuationMinor:
          (json['stock_valuation_minor'] as num?)?.toInt() ?? 0,
      wastageCostMinor: (json['wastage_cost_minor'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'total_items_count': totalItemsCount,
    'low_stock_count': lowStockCount,
    'out_of_stock_count': outOfStockCount,
    'stock_valuation_minor': stockValuationMinor,
    'wastage_cost_minor': wastageCostMinor,
  };
}

/// Kitchen performance indicators.
class KitchenAnalyticsMetric {
  const KitchenAnalyticsMetric({
    required this.avgPrepTimeSeconds,
    required this.activeTicketsCount,
    required this.delayedTicketsCount,
    required this.completedTicketsCount,
  });

  final int avgPrepTimeSeconds;
  final int activeTicketsCount;
  final int delayedTicketsCount;
  final int completedTicketsCount;

  String get formattedAvgPrepTime {
    if (avgPrepTimeSeconds <= 0) return '0m 0s';
    final minutes = avgPrepTimeSeconds ~/ 60;
    final seconds = avgPrepTimeSeconds % 60;
    return '${minutes}m ${seconds}s';
  }

  factory KitchenAnalyticsMetric.fromJson(Map<String, dynamic> json) {
    return KitchenAnalyticsMetric(
      avgPrepTimeSeconds: (json['avg_prep_time_seconds'] as num?)?.toInt() ?? 0,
      activeTicketsCount: (json['active_tickets_count'] as num?)?.toInt() ?? 0,
      delayedTicketsCount:
          (json['delayed_tickets_count'] as num?)?.toInt() ?? 0,
      completedTicketsCount:
          (json['completed_tickets_count'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'avg_prep_time_seconds': avgPrepTimeSeconds,
    'active_tickets_count': activeTicketsCount,
    'delayed_tickets_count': delayedTicketsCount,
    'completed_tickets_count': completedTicketsCount,
  };
}

/// Dining floor and table occupancy metrics.
class TableAnalyticsMetric {
  const TableAnalyticsMetric({
    required this.totalTables,
    required this.occupiedTables,
    required this.occupancyRatePercent,
  });

  final int totalTables;
  final int occupiedTables;
  final double occupancyRatePercent;

  factory TableAnalyticsMetric.fromJson(Map<String, dynamic> json) {
    return TableAnalyticsMetric(
      totalTables: (json['total_tables'] as num?)?.toInt() ?? 0,
      occupiedTables: (json['occupied_tables'] as num?)?.toInt() ?? 0,
      occupancyRatePercent:
          (json['occupancy_rate_percent'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
    'total_tables': totalTables,
    'occupied_tables': occupiedTables,
    'occupancy_rate_percent': occupancyRatePercent,
  };
}

/// Staff attendance and shift operations metric.
class WorkforceAnalyticsMetric {
  const WorkforceAnalyticsMetric({
    required this.currentlyClockedIn,
    required this.currentlyOnBreak,
    required this.lateArrivalsCount,
  });

  final int currentlyClockedIn;
  final int currentlyOnBreak;
  final int lateArrivalsCount;

  factory WorkforceAnalyticsMetric.fromJson(Map<String, dynamic> json) {
    return WorkforceAnalyticsMetric(
      currentlyClockedIn: (json['currently_clocked_in'] as num?)?.toInt() ?? 0,
      currentlyOnBreak: (json['currently_on_break'] as num?)?.toInt() ?? 0,
      lateArrivalsCount: (json['late_arrivals_count'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'currently_clocked_in': currentlyClockedIn,
    'currently_on_break': currentlyOnBreak,
    'late_arrivals_count': lateArrivalsCount,
  };
}

/// Financial aggregates returned by server-side RPC.
class FinancialAnalyticsReport {
  const FinancialAnalyticsReport({
    required this.grossSalesMinor,
    required this.discountsTotalMinor,
    required this.netSalesMinor,
    required this.taxCollectedMinor,
    required this.serviceChargeMinor,
    required this.totalPaymentsMinor,
    required this.cashCollectedMinor,
    required this.upiCollectedMinor,
    required this.cardCollectedMinor,
    required this.otherCollectedMinor,
    required this.refundsTotalMinor,
    required this.netCollectedMinor,
    required this.outstandingBalanceMinor,
    required this.totalOrdersCount,
    required this.paidOrdersCount,
    required this.unpaidOrdersCount,
    required this.avgOrderValueMinor,
  });

  final int grossSalesMinor;
  final int discountsTotalMinor;
  final int netSalesMinor;
  final int taxCollectedMinor;
  final int serviceChargeMinor;
  final int totalPaymentsMinor;
  final int cashCollectedMinor;
  final int upiCollectedMinor;
  final int cardCollectedMinor;
  final int otherCollectedMinor;
  final int refundsTotalMinor;
  final int netCollectedMinor;
  final int outstandingBalanceMinor;
  final int totalOrdersCount;
  final int paidOrdersCount;
  final int unpaidOrdersCount;
  final int avgOrderValueMinor;

  factory FinancialAnalyticsReport.fromJson(Map<String, dynamic> json) {
    return FinancialAnalyticsReport(
      grossSalesMinor: (json['gross_sales_minor'] as num?)?.toInt() ?? 0,
      discountsTotalMinor:
          (json['discounts_total_minor'] as num?)?.toInt() ?? 0,
      netSalesMinor: (json['net_sales_minor'] as num?)?.toInt() ?? 0,
      taxCollectedMinor: (json['tax_collected_minor'] as num?)?.toInt() ?? 0,
      serviceChargeMinor: (json['service_charge_minor'] as num?)?.toInt() ?? 0,
      totalPaymentsMinor: (json['total_payments_minor'] as num?)?.toInt() ?? 0,
      cashCollectedMinor: (json['cash_collected_minor'] as num?)?.toInt() ?? 0,
      upiCollectedMinor: (json['upi_collected_minor'] as num?)?.toInt() ?? 0,
      cardCollectedMinor: (json['card_collected_minor'] as num?)?.toInt() ?? 0,
      otherCollectedMinor:
          (json['other_collected_minor'] as num?)?.toInt() ?? 0,
      refundsTotalMinor: (json['refunds_total_minor'] as num?)?.toInt() ?? 0,
      netCollectedMinor: (json['net_collected_minor'] as num?)?.toInt() ?? 0,
      outstandingBalanceMinor:
          (json['outstanding_balance_minor'] as num?)?.toInt() ?? 0,
      totalOrdersCount: (json['total_orders_count'] as num?)?.toInt() ?? 0,
      paidOrdersCount: (json['paid_orders_count'] as num?)?.toInt() ?? 0,
      unpaidOrdersCount: (json['unpaid_orders_count'] as num?)?.toInt() ?? 0,
      avgOrderValueMinor: (json['avg_order_value_minor'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'gross_sales_minor': grossSalesMinor,
    'discounts_total_minor': discountsTotalMinor,
    'net_sales_minor': netSalesMinor,
    'tax_collected_minor': taxCollectedMinor,
    'service_charge_minor': serviceChargeMinor,
    'total_payments_minor': totalPaymentsMinor,
    'cash_collected_minor': cashCollectedMinor,
    'upi_collected_minor': upiCollectedMinor,
    'card_collected_minor': cardCollectedMinor,
    'other_collected_minor': otherCollectedMinor,
    'refunds_total_minor': refundsTotalMinor,
    'net_collected_minor': netCollectedMinor,
    'outstanding_balance_minor': outstandingBalanceMinor,
    'total_orders_count': totalOrdersCount,
    'paid_orders_count': paidOrdersCount,
    'unpaid_orders_count': unpaidOrdersCount,
    'avg_order_value_minor': avgOrderValueMinor,
  };
}

/// Comprehensive multi-dimensional business analytics container.
class ComprehensiveAnalytics {
  const ComprehensiveAnalytics({
    required this.startDate,
    required this.endDate,
    required this.financial,
    required this.orderTypes,
    required this.dailyTrends,
    required this.topProducts,
    required this.leastProducts,
    required this.inventory,
    required this.kitchen,
    required this.tables,
    required this.workforce,
  });

  final DateTime startDate;
  final DateTime endDate;
  final FinancialAnalyticsReport financial;
  final List<OrderTypeMetric> orderTypes;
  final List<DailyTrendMetric> dailyTrends;
  final List<ProductSalesMetric> topProducts;
  final List<ProductSalesMetric> leastProducts;
  final InventoryAnalyticsMetric inventory;
  final KitchenAnalyticsMetric kitchen;
  final TableAnalyticsMetric tables;
  final WorkforceAnalyticsMetric workforce;

  factory ComprehensiveAnalytics.fromJson(Map<String, dynamic> json) {
    final startStr = json['start_date'] as String?;
    final endStr = json['end_date'] as String?;

    final productMap =
        (json['product_analytics'] as Map<String, dynamic>?) ?? {};
    final topList = (productMap['top_selling'] as List?) ?? [];
    final leastList = (productMap['least_selling'] as List?) ?? [];

    return ComprehensiveAnalytics(
      startDate: startStr != null ? DateTime.parse(startStr) : DateTime.now(),
      endDate: endStr != null ? DateTime.parse(endStr) : DateTime.now(),
      financial: FinancialAnalyticsReport.fromJson(
        (json['financial'] as Map<String, dynamic>?) ?? {},
      ),
      orderTypes: ((json['order_types'] as List?) ?? [])
          .map((e) => OrderTypeMetric.fromJson(e as Map<String, dynamic>))
          .toList(),
      dailyTrends: ((json['daily_trends'] as List?) ?? [])
          .map((e) => DailyTrendMetric.fromJson(e as Map<String, dynamic>))
          .toList(),
      topProducts: topList
          .map((e) => ProductSalesMetric.fromJson(e as Map<String, dynamic>))
          .toList(),
      leastProducts: leastList
          .map((e) => ProductSalesMetric.fromJson(e as Map<String, dynamic>))
          .toList(),
      inventory: InventoryAnalyticsMetric.fromJson(
        (json['inventory'] as Map<String, dynamic>?) ?? {},
      ),
      kitchen: KitchenAnalyticsMetric.fromJson(
        (json['kitchen'] as Map<String, dynamic>?) ?? {},
      ),
      tables: TableAnalyticsMetric.fromJson(
        (json['tables'] as Map<String, dynamic>?) ?? {},
      ),
      workforce: WorkforceAnalyticsMetric.fromJson(
        (json['workforce'] as Map<String, dynamic>?) ?? {},
      ),
    );
  }
}

/// Helper to format currency for CSV exports and human presentation.
String formatMinorToCurrency(int minor) {
  final sign = minor < 0 ? '-' : '';
  final absolute = minor.abs();
  final integerPart = absolute ~/ 100;
  final decimalPart = (absolute % 100).toString().padLeft(2, '0');
  return '$sign₹$integerPart.$decimalPart';
}

/// CSV Export generator for financial, operational, and product reports.
class AnalyticsCsvExporter {
  static String escapeCsv(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  /// Exports executive financial statement to CSV format.
  static String exportFinancialCsv(ComprehensiveAnalytics analytics) {
    final f = analytics.financial;
    final buf = StringBuffer();

    buf.writeln('CafeFlow Financial Summary Report');
    buf.writeln(
      'Period,${analytics.startDate.toIso8601String()} to ${analytics.endDate.toIso8601String()}',
    );
    buf.writeln('Generated,${DateTime.now().toIso8601String()}');
    buf.writeln('');

    buf.writeln('Metric,Amount (INR),Raw Minor Units');
    buf.writeln(
      'Gross Sales,${formatMinorToCurrency(f.grossSalesMinor)},${f.grossSalesMinor}',
    );
    buf.writeln(
      'Discounts Total,${formatMinorToCurrency(f.discountsTotalMinor)},${f.discountsTotalMinor}',
    );
    buf.writeln(
      'Net Sales,${formatMinorToCurrency(f.netSalesMinor)},${f.netSalesMinor}',
    );
    buf.writeln(
      'Tax Collected (GST),${formatMinorToCurrency(f.taxCollectedMinor)},${f.taxCollectedMinor}',
    );
    buf.writeln(
      'Service Charge,${formatMinorToCurrency(f.serviceChargeMinor)},${f.serviceChargeMinor}',
    );
    buf.writeln(
      'Total Payments Collected,${formatMinorToCurrency(f.totalPaymentsMinor)},${f.totalPaymentsMinor}',
    );
    buf.writeln(
      'Refunds Issued,${formatMinorToCurrency(f.refundsTotalMinor)},${f.refundsTotalMinor}',
    );
    buf.writeln(
      'Net Collected,${formatMinorToCurrency(f.netCollectedMinor)},${f.netCollectedMinor}',
    );
    buf.writeln(
      'Outstanding Balance,${formatMinorToCurrency(f.outstandingBalanceMinor)},${f.outstandingBalanceMinor}',
    );
    buf.writeln('');

    buf.writeln('Tender Breakdown,Collected (INR),Raw Minor Units');
    buf.writeln(
      'Cash Tender,${formatMinorToCurrency(f.cashCollectedMinor)},${f.cashCollectedMinor}',
    );
    buf.writeln(
      'UPI / Digital QR,${formatMinorToCurrency(f.upiCollectedMinor)},${f.upiCollectedMinor}',
    );
    buf.writeln(
      'Card POS / Terminal,${formatMinorToCurrency(f.cardCollectedMinor)},${f.cardCollectedMinor}',
    );
    buf.writeln(
      'Other Tenders,${formatMinorToCurrency(f.otherCollectedMinor)},${f.otherCollectedMinor}',
    );
    buf.writeln('');

    buf.writeln('Order Volumes,Count');
    buf.writeln('Total Orders Placed,${f.totalOrdersCount}');
    buf.writeln('Fully Settled Orders,${f.paidOrdersCount}');
    buf.writeln('Unpaid / Tab Orders,${f.unpaidOrdersCount}');
    buf.writeln(
      'Average Ticket Size,${formatMinorToCurrency(f.avgOrderValueMinor)}',
    );
    buf.writeln('');

    if (analytics.dailyTrends.isNotEmpty) {
      buf.writeln('Daily Sales Trend');
      buf.writeln('Date,Orders,Gross Sales (INR),Net Sales (INR)');
      for (final t in analytics.dailyTrends) {
        buf.writeln(
          '${t.date},${t.orderCount},${formatMinorToCurrency(t.grossSalesMinor)},${formatMinorToCurrency(t.netSalesMinor)}',
        );
      }
    }

    return buf.toString();
  }

  /// Exports product sales breakdown to CSV format.
  static String exportProductSalesCsv(ComprehensiveAnalytics analytics) {
    final buf = StringBuffer();

    buf.writeln('CafeFlow Product Sales & Menu Analytics');
    buf.writeln(
      'Period,${analytics.startDate.toIso8601String()} to ${analytics.endDate.toIso8601String()}',
    );
    buf.writeln('Generated,${DateTime.now().toIso8601String()}');
    buf.writeln('');

    buf.writeln('Top-Selling Items');
    buf.writeln('Item Name,Quantity Sold,Revenue (INR),Raw Minor Units');
    for (final p in analytics.topProducts) {
      buf.writeln(
        '${escapeCsv(p.productName)},${p.quantitySold},${formatMinorToCurrency(p.revenueMinor)},${p.revenueMinor}',
      );
    }
    buf.writeln('');

    buf.writeln('Least-Selling Items');
    buf.writeln('Item Name,Quantity Sold,Revenue (INR),Raw Minor Units');
    for (final p in analytics.leastProducts) {
      buf.writeln(
        '${escapeCsv(p.productName)},${p.quantitySold},${formatMinorToCurrency(p.revenueMinor)},${p.revenueMinor}',
      );
    }

    return buf.toString();
  }

  /// Exports comprehensive operational report across all dimensions to CSV format.
  static String exportOperationalCsv(ComprehensiveAnalytics analytics) {
    final buf = StringBuffer();

    buf.writeln('CafeFlow Multi-Dimensional Operational Summary');
    buf.writeln(
      'Period,${analytics.startDate.toIso8601String()} to ${analytics.endDate.toIso8601String()}',
    );
    buf.writeln('Generated,${DateTime.now().toIso8601String()}');
    buf.writeln('');

    // Floor & Kitchen
    buf.writeln('Operational Dimension,Value');
    buf.writeln(
      'Kitchen Average Prep Time,${analytics.kitchen.formattedAvgPrepTime}',
    );
    buf.writeln(
      'Active Kitchen Tickets,${analytics.kitchen.activeTicketsCount}',
    );
    buf.writeln(
      'Delayed Tickets (>20m),${analytics.kitchen.delayedTicketsCount}',
    );
    buf.writeln(
      'Completed Kitchen Tickets,${analytics.kitchen.completedTicketsCount}',
    );
    buf.writeln('Dining Tables Configured,${analytics.tables.totalTables}');
    buf.writeln('Tables Currently Occupied,${analytics.tables.occupiedTables}');
    buf.writeln(
      'Floor Occupancy Rate,${analytics.tables.occupancyRatePercent}%',
    );
    buf.writeln('');

    // Inventory & Stock
    buf.writeln('Inventory Stock & Valuation,Value');
    buf.writeln(
      'Total Catalogued Items,${analytics.inventory.totalItemsCount}',
    );
    buf.writeln('Low-Stock Items,${analytics.inventory.lowStockCount}');
    buf.writeln('Out-of-Stock Items,${analytics.inventory.outOfStockCount}');
    buf.writeln(
      'Stock Valuation,${formatMinorToCurrency(analytics.inventory.stockValuationMinor)}',
    );
    buf.writeln(
      'Wastage & Damage Cost,${formatMinorToCurrency(analytics.inventory.wastageCostMinor)}',
    );
    buf.writeln('');

    // Staff
    buf.writeln('Staff & Workforce,Value');
    buf.writeln(
      'Currently Clocked In,${analytics.workforce.currentlyClockedIn}',
    );
    buf.writeln('Currently on Break,${analytics.workforce.currentlyOnBreak}');
    buf.writeln(
      'Late Arrivals in Period,${analytics.workforce.lateArrivalsCount}',
    );

    return buf.toString();
  }
}
