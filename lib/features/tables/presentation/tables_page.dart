import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/services/backend.dart';
import '../../../core/widgets/cafe_components.dart';
import '../../../shared/components/section_heading.dart';
import '../../auth/application/auth_controller.dart';
import '../../demo/application/demo_tables_controller.dart';
import '../application/tables_provider.dart';
import '../data/supabase_tables_repository.dart';

class TablesPage extends ConsumerStatefulWidget {
  const TablesPage({this.staff = false, super.key});
  final bool staff;

  @override
  ConsumerState<TablesPage> createState() => _TablesPageState();
}

class _TablesPageState extends ConsumerState<TablesPage> {
  TableStatus? statusFilter;
  String? sectionFilter;
  String searchQuery = '';
  final searchController = TextEditingController();

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backend = ref.watch(backendProvider);
    final auth = ref.watch(authControllerProvider);
    final isLive =
        backend.status == BackendStatus.initialized &&
        auth.activeMembership?.restaurantId != null;

    final allTables = ref.watch(tablesProvider).value ?? [];
    final sections = ref.watch(floorSectionsProvider).value ?? [];

    final filtered = allTables.where((t) {
      if (statusFilter != null && t.status != statusFilter) return false;
      if (sectionFilter != null && t.sectionId != sectionFilter) return false;
      if (searchQuery.isNotEmpty) {
        final q = searchQuery.toLowerCase();
        final matchesNum = t.tableNumber.toLowerCase().contains(q);
        final matchesSec = (t.sectionName ?? '').toLowerCase().contains(q);
        final matchesOrd = (t.currentOrderNumber ?? '').toLowerCase().contains(
          q,
        );
        if (!matchesNum && !matchesSec && !matchesOrd) return false;
      }
      return true;
    }).toList();

    return PageBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isLive) const DemoNotice(),
          if (isLive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer
                    .withAlpha(90),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.table_restaurant_outlined,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Live Table Floor Plan · Realtime Dining Room Management',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          SectionHeading(
            widget.staff ? 'Dining Floor & Tables' : 'Dining Tables Management',
            subtitle: widget.staff
                ? 'Check table seating, assign guests, and review table status.'
                : 'Floor plan overview, table capacities, and active guest sessions.',
            action: widget.staff
                ? null
                : CafeButton(
                    label: 'Add Table',
                    icon: Icons.add,
                    onPressed: () => _addTableDialog(context, isLive, sections),
                  ),
          ),

          // 1. Search and Section Filtering Controls
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 240,
                child: TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    hintText: 'Search tables or orders...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              searchController.clear();
                              setState(() => searchQuery = '');
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onChanged: (val) => setState(() => searchQuery = val.trim()),
                ),
              ),
              if (sections.isNotEmpty) ...[
                ChoiceChip(
                  label: const Text('All Sections'),
                  selected: sectionFilter == null,
                  onSelected: (_) => setState(() => sectionFilter = null),
                ),
                for (final sec in sections)
                  ChoiceChip(
                    label: Text(sec.name),
                    selected: sectionFilter == sec.id,
                    onSelected: (_) => setState(() => sectionFilter = sec.id),
                  ),
              ],
            ],
          ),
          const SizedBox(height: 12),

          // 2. Status Filters
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('All tables'),
                selected: statusFilter == null,
                onSelected: (_) => setState(() => statusFilter = null),
              ),
              ChoiceChip(
                label: const Text('Available'),
                selected: statusFilter == TableStatus.available,
                onSelected: (_) =>
                    setState(() => statusFilter = TableStatus.available),
              ),
              ChoiceChip(
                label: const Text('Occupied'),
                selected: statusFilter == TableStatus.occupied,
                onSelected: (_) =>
                    setState(() => statusFilter = TableStatus.occupied),
              ),
              ChoiceChip(
                label: const Text('Bill Requested'),
                selected: statusFilter == TableStatus.billRequested,
                onSelected: (_) =>
                    setState(() => statusFilter = TableStatus.billRequested),
              ),
              ChoiceChip(
                label: const Text('Cleaning'),
                selected: statusFilter == TableStatus.cleaning,
                onSelected: (_) =>
                    setState(() => statusFilter = TableStatus.cleaning),
              ),
              ChoiceChip(
                label: const Text('Reserved'),
                selected: statusFilter == TableStatus.reserved,
                onSelected: (_) =>
                    setState(() => statusFilter = TableStatus.reserved),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 3. Floor Grid
          if (filtered.isEmpty)
            const CafeEmptyState(
              title: 'No tables in this view',
              message: 'Check another status filter or configure tables.',
              icon: Icons.table_restaurant_outlined,
            )
          else
            AdaptiveColumns(
              minWidth: 280,
              children: [
                for (final table in filtered)
                  CafeCard(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              table.tableNumber,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            StatusPill(
                              switch (table.status) {
                                TableStatus.available => 'Available',
                                TableStatus.occupied => 'Occupied',
                                TableStatus.reserved => 'Reserved',
                                TableStatus.billRequested => 'Bill Requested',
                                TableStatus.cleaning => 'Cleaning',
                                TableStatus.outOfService => 'Out of Service',
                              },
                              icon: switch (table.status) {
                                TableStatus.available =>
                                  Icons.check_circle_outline,
                                TableStatus.occupied => Icons.people,
                                TableStatus.reserved => Icons.bookmark_border,
                                TableStatus.billRequested => Icons.receipt_long,
                                TableStatus.cleaning => Icons.cleaning_services,
                                TableStatus.outOfService =>
                                  Icons.do_not_disturb_on,
                              },
                            ),
                          ],
                        ),
                        if (table.sectionName != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            table.sectionName!,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.chair_outlined, size: 18),
                            const SizedBox(width: 8),
                            Expanded(child: Text('${table.capacity} seats')),
                          ],
                        ),
                        if (table.currentOrderNumber != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.receipt_long_outlined, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Active order: ${table.currentOrderNumber}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (table.occupiedSince != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Occupied for ${_formatDuration(DateTime.now().difference(table.occupiedSince!))}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),

                        // Action Buttons
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (table.status == TableStatus.available) ...[
                              FilledButton(
                                onPressed: () =>
                                    _seatGuestsDialog(context, table, isLive),
                                child: const Text('Seat guests'),
                              ),
                              TextButton(
                                onPressed: () => _setStatus(
                                  context,
                                  table,
                                  TableStatus.reserved,
                                  isLive,
                                ),
                                child: const Text('Reserve'),
                              ),
                            ] else if (table.status ==
                                TableStatus.occupied) ...[
                              FilledButton.tonal(
                                onPressed: () => _setStatus(
                                  context,
                                  table,
                                  TableStatus.billRequested,
                                  isLive,
                                ),
                                child: const Text('Request Bill'),
                              ),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.move_up, size: 16),
                                label: const Text('Transfer'),
                                onPressed: () => _transferTableDialog(
                                  context,
                                  table,
                                  allTables,
                                  isLive,
                                ),
                              ),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.merge_type, size: 16),
                                label: const Text('Merge'),
                                onPressed: () => _mergeTableDialog(
                                  context,
                                  table,
                                  allTables,
                                  isLive,
                                ),
                              ),
                            ] else if (table.status ==
                                TableStatus.billRequested) ...[
                              FilledButton(
                                onPressed: () =>
                                    _closeSession(context, table, isLive),
                                child: const Text('Clear table'),
                              ),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.move_up, size: 16),
                                label: const Text('Transfer'),
                                onPressed: () => _transferTableDialog(
                                  context,
                                  table,
                                  allTables,
                                  isLive,
                                ),
                              ),
                            ] else if (table.status ==
                                TableStatus.cleaning) ...[
                              FilledButton(
                                onPressed: () => _setStatus(
                                  context,
                                  table,
                                  TableStatus.available,
                                  isLive,
                                ),
                                child: const Text('Mark Ready'),
                              ),
                            ] else ...[
                              FilledButton.tonal(
                                onPressed: () => _setStatus(
                                  context,
                                  table,
                                  TableStatus.available,
                                  isLive,
                                ),
                                child: const Text('Clear table'),
                              ),
                              if (table.status != TableStatus.occupied)
                                FilledButton(
                                  onPressed: () =>
                                      _seatGuestsDialog(context, table, isLive),
                                  child: const Text('Seat guests'),
                                ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    if (d.inMinutes < 1) return 'less than a min';
    if (d.inMinutes < 60) return '${d.inMinutes} mins';
    return '${d.inHours}h ${d.inMinutes % 60}m';
  }

  Future<void> _setStatus(
    BuildContext context,
    DiningTableRecord table,
    TableStatus status,
    bool isLive,
  ) async {
    if (isLive) {
      final repo = ref.read(tablesRepositoryProvider);
      final auth = ref.read(authControllerProvider);
      final restId = auth.activeMembership?.restaurantId;

      if (repo != null && restId != null) {
        try {
          await repo.updateTableStatus(
            restaurantId: restId,
            tableId: table.id,
            status: status,
          );
          ref.invalidate(tablesProvider);
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(e is AppFailure ? e.message : 'Error: $e'),
              ),
            );
          }
        }
        return;
      }
    }

    // Demo fallback
    ref.read(demoTablesProvider.notifier).updateStatus(table.id, status);
    ref.invalidate(tablesProvider);
  }

  Future<void> _seatGuestsDialog(
    BuildContext context,
    DiningTableRecord table,
    bool isLive,
  ) async {
    final guestCtrl = TextEditingController(text: '2');
    final notesCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Seat Guests · ${table.tableNumber}'),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: guestCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Number of Guests',
                  hintText: 'e.g. 2',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Session Notes (optional)',
                  hintText: 'e.g. High chair needed',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final count = int.tryParse(guestCtrl.text.trim()) ?? 1;
              final notes = notesCtrl.text.trim();
              Navigator.pop(dialogCtx);

              if (isLive) {
                final repo = ref.read(tablesRepositoryProvider);
                final auth = ref.read(authControllerProvider);
                final restId = auth.activeMembership?.restaurantId;

                if (repo != null && restId != null) {
                  try {
                    await repo.openSession(
                      restaurantId: restId,
                      tableId: table.id,
                      guestCount: count,
                      notes: notes,
                    );
                    ref.invalidate(tablesProvider);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Session started for ${table.tableNumber} ($count guests)',
                          ),
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to open session: $e')),
                      );
                    }
                  }
                  return;
                }
              }

              // Demo fallback
              ref
                  .read(demoTablesProvider.notifier)
                  .updateStatus(table.id, TableStatus.occupied);
              ref.invalidate(tablesProvider);
            },
            child: const Text('Open Session'),
          ),
        ],
      ),
    );
  }

  Future<void> _closeSession(
    BuildContext context,
    DiningTableRecord table,
    bool isLive,
  ) async {
    if (isLive && table.activeSessionId != null) {
      final repo = ref.read(tablesRepositoryProvider);
      final auth = ref.read(authControllerProvider);
      final restId = auth.activeMembership?.restaurantId;

      if (repo != null && restId != null) {
        try {
          await repo.closeSession(
            restaurantId: restId,
            sessionId: table.activeSessionId!,
          );
          ref.invalidate(tablesProvider);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${table.tableNumber} session closed and cleared.',
                ),
              ),
            );
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(e is AppFailure ? e.message : 'Error: $e'),
              ),
            );
          }
        }
        return;
      }
    }

    await _setStatus(context, table, TableStatus.available, isLive);
  }

  Future<void> _transferTableDialog(
    BuildContext context,
    DiningTableRecord sourceTable,
    List<DiningTableRecord> allTables,
    bool isLive,
  ) async {
    final availableTables = allTables
        .where(
          (t) => t.id != sourceTable.id && t.status == TableStatus.available,
        )
        .toList();

    if (availableTables.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No other tables are currently available for transfer.',
          ),
        ),
      );
      return;
    }

    String selectedTargetId = availableTables.first.id;
    final notesCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Transfer Table · ${sourceTable.tableNumber}'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Select destination table:'),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedTargetId,
                  isExpanded: true,
                  items: availableTables.map((t) {
                    return DropdownMenuItem(
                      value: t.id,
                      child: Text('${t.tableNumber} (${t.capacity} seats)'),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) setDialogState(() => selectedTargetId = v);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Transfer reason / notes',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(dialogCtx);
                if (isLive && sourceTable.activeSessionId != null) {
                  final repo = ref.read(tablesRepositoryProvider);
                  final auth = ref.read(authControllerProvider);
                  final restId = auth.activeMembership?.restaurantId;

                  if (repo != null && restId != null) {
                    try {
                      final res = await repo.transferSession(
                        restaurantId: restId,
                        sessionId: sourceTable.activeSessionId!,
                        targetTableId: selectedTargetId,
                        notes: notesCtrl.text.trim(),
                      );
                      ref.invalidate(tablesProvider);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Transferred ${res["source_table_number"]} to ${res["target_table_number"]}',
                            ),
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              e is AppFailure ? e.message : 'Error: $e',
                            ),
                          ),
                        );
                      }
                    }
                    return;
                  }
                }

                // Demo fallback
                ref
                    .read(demoTablesProvider.notifier)
                    .updateStatus(sourceTable.id, TableStatus.available);
                ref
                    .read(demoTablesProvider.notifier)
                    .updateStatus(selectedTargetId, TableStatus.occupied);
                ref.invalidate(tablesProvider);
              },
              child: const Text('Confirm Transfer'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _mergeTableDialog(
    BuildContext context,
    DiningTableRecord sourceTable,
    List<DiningTableRecord> allTables,
    bool isLive,
  ) async {
    final otherOccupiedTables = allTables
        .where(
          (t) =>
              t.id != sourceTable.id &&
              (t.status == TableStatus.occupied ||
                  t.status == TableStatus.billRequested),
        )
        .toList();

    if (otherOccupiedTables.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No other active dining tables available to merge with.',
          ),
        ),
      );
      return;
    }

    String selectedTargetId = otherOccupiedTables.first.id;
    final notesCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Merge Table · ${sourceTable.tableNumber}'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Merge into target table:'),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedTargetId,
                  isExpanded: true,
                  items: otherOccupiedTables.map((t) {
                    return DropdownMenuItem(
                      value: t.id,
                      child: Text(
                        '${t.tableNumber} (Active: ${t.currentOrderNumber ?? "Session"})',
                      ),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) setDialogState(() => selectedTargetId = v);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Merge reason / notes',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(dialogCtx);
                final targetTable = otherOccupiedTables.firstWhere(
                  (t) => t.id == selectedTargetId,
                );

                if (isLive &&
                    sourceTable.activeSessionId != null &&
                    targetTable.activeSessionId != null) {
                  final repo = ref.read(tablesRepositoryProvider);
                  final auth = ref.read(authControllerProvider);
                  final restId = auth.activeMembership?.restaurantId;

                  if (repo != null && restId != null) {
                    try {
                      await repo.mergeSessions(
                        restaurantId: restId,
                        sourceSessionId: sourceTable.activeSessionId!,
                        targetSessionId: targetTable.activeSessionId!,
                        notes: notesCtrl.text.trim(),
                      );
                      ref.invalidate(tablesProvider);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Merged ${sourceTable.tableNumber} into ${targetTable.tableNumber}',
                            ),
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              e is AppFailure ? e.message : 'Error: $e',
                            ),
                          ),
                        );
                      }
                    }
                    return;
                  }
                }

                // Demo fallback
                ref
                    .read(demoTablesProvider.notifier)
                    .updateStatus(sourceTable.id, TableStatus.available);
                ref.invalidate(tablesProvider);
              },
              child: const Text('Confirm Merge'),
            ),
          ],
        ),
      ),
    );
  }

  void _addTableDialog(
    BuildContext context,
    bool isLive,
    List<FloorSection> sections,
  ) {
    final numCtrl = TextEditingController();
    final capCtrl = TextEditingController(text: '4');
    String? selectedSectionId = sections.isNotEmpty ? sections.first.id : null;

    showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Dining Table'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: numCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Table Number *',
                    hintText: 'e.g. Table 07',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: capCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Seating Capacity *',
                  ),
                ),
                if (sections.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedSectionId,
                    decoration: const InputDecoration(
                      labelText: 'Floor Section',
                    ),
                    items: sections.map((s) {
                      return DropdownMenuItem(value: s.id, child: Text(s.name));
                    }).toList(),
                    onChanged: (v) =>
                        setDialogState(() => selectedSectionId = v),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final num = numCtrl.text.trim();
                final cap = int.tryParse(capCtrl.text.trim()) ?? 4;
                if (num.isEmpty) return;

                if (isLive) {
                  final repo = ref.read(tablesRepositoryProvider);
                  final auth = ref.read(authControllerProvider);
                  final restId = auth.activeMembership?.restaurantId;

                  if (repo != null && restId != null) {
                    try {
                      await repo.createTable(
                        restaurantId: restId,
                        tableNumber: num,
                        capacity: cap,
                        sectionId: selectedSectionId,
                      );
                      ref.invalidate(tablesProvider);
                      if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text('Error: $e')));
                      }
                    }
                    return;
                  }
                }

                Navigator.pop(dialogCtx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Demo Mode: Table added.')),
                );
              },
              child: const Text('Add Table'),
            ),
          ],
        ),
      ),
    );
  }
}
