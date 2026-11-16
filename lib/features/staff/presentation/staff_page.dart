import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/routing/workspace.dart';
import '../../../core/services/backend.dart';
import '../../../core/widgets/cafe_components.dart';
import '../../../shared/components/section_heading.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/permissions.dart';
import '../application/staff_provider.dart';

class StaffPage extends ConsumerStatefulWidget {
  const StaffPage({this.compact = false, super.key});
  final bool compact;

  @override
  ConsumerState<StaffPage> createState() => _StaffPageState();
}

class _StaffPageState extends ConsumerState<StaffPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Attendance terminal state
  String? _selectedAttendanceUserId;
  String? _selectedAttendanceShiftId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final backend = ref.watch(backendProvider);
    final isLive =
        backend.status == BackendStatus.initialized &&
        auth.activeMembership?.restaurantId != null;

    final callerRole = auth.activeRole ?? WorkspaceRole.owner;
    final callerUserId = auth.user?.id ?? 'demo-user';
    final canManageStaff =
        auth.hasPermission(CafePermission.manageStaff) || !auth.isAuthenticated;

    final staffMembers = ref.watch(staffListProvider).value ?? [];

    if (widget.compact) {
      return PageBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeading(
              'Staff Overview',
              subtitle: 'Current staff scheduled and active on duty today.',
            ),
            const SizedBox(height: 16),
            _buildRosterGrid(
              staffMembers,
              callerRole,
              callerUserId,
              canManageStaff: false,
              isLive: isLive,
            ),
          ],
        ),
      );
    }

    return PageBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isLive) const DemoNotice(),
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            tabs: const [
              Tab(icon: Icon(Icons.people_alt_outlined), text: 'Team Roster'),
              Tab(icon: Icon(Icons.schedule_outlined), text: 'Shifts & Hours'),
              Tab(
                icon: Icon(Icons.fingerprint_outlined),
                text: 'Attendance Terminal',
              ),
              Tab(
                icon: Icon(Icons.security_outlined),
                text: 'Role Permissions Matrix',
              ),
              Tab(
                icon: Icon(Icons.history_edu_outlined),
                text: 'Activity Audit Log',
              ),
            ],
          ),
          const SizedBox(height: 20),
          AnimatedBuilder(
            animation: _tabController,
            builder: (context, _) {
              return switch (_tabController.index) {
                0 => _buildRosterTab(
                  context,
                  staffMembers,
                  callerRole,
                  callerUserId,
                  canManageStaff,
                  isLive,
                ),
                1 => _buildShiftsTab(context, canManageStaff, isLive),
                2 => _buildAttendanceTab(
                  context,
                  staffMembers,
                  callerRole,
                  isLive,
                ),
                3 => _buildPermissionsMatrixTab(context),
                4 => _buildAuditLogTab(context),
                _ => _buildRosterTab(
                  context,
                  staffMembers,
                  callerRole,
                  callerUserId,
                  canManageStaff,
                  isLive,
                ),
              };
            },
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 0: Team Roster
  // ---------------------------------------------------------------------------

  Widget _buildRosterTab(
    BuildContext context,
    List<StaffMemberRecord> members,
    WorkspaceRole callerRole,
    String callerUserId,
    bool canManageStaff,
    bool isLive,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SectionHeading(
                'Team & Staff Management',
                subtitle: 'Team roster, assigned roles, shift coverage, and duty statuses under SEC-01 RBAC.',
              ),
            ),
            if (canManageStaff) ...[
              const SizedBox(width: 12),
              CafeButton(
                label: 'Add Team Member',
                icon: Icons.person_add_rounded,
                onPressed: () =>
                    _showAddStaffDialog(context, callerRole, isLive),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),

        // Security Credential Policy Card
        Container(
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest
                .withAlpha(120),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withAlpha(40),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.shield_outlined,
                size: 22,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Staff Credential & Access Control Policy (SEC-01)',
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Staff members cannot self-service reset passwords or change usernames; credential administration and role assignments are strictly managed by authorized cafe administrators under SEC-01 RBAC policies.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        _buildRosterGrid(
          members,
          callerRole,
          callerUserId,
          canManageStaff: canManageStaff,
          isLive: isLive,
        ),
      ],
    );
  }

  Widget _buildRosterGrid(
    List<StaffMemberRecord> members,
    WorkspaceRole callerRole,
    String callerUserId, {
    required bool canManageStaff,
    required bool isLive,
  }) {
    if (members.isEmpty) {
      return const CafeEmptyState(
        title: 'No staff members found',
        message: 'Add members to build your cafe roster.',
        icon: Icons.people_outline,
      );
    }

    return AdaptiveColumns(
      minWidth: 290,
      children: [
        for (final member in members)
          CafeCard(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .primaryContainer,
                  child: Text(
                    member.name.isNotEmpty
                        ? member.name.substring(0, 1).toUpperCase()
                        : 'S',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          Text(
                            member.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          StatusPill(
                            member.active ? 'Active' : 'Inactive',
                            icon: member.active
                                ? Icons.check_circle_outline
                                : Icons.cancel_outlined,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Role: ${member.role.name.toUpperCase()} (${member.role.label})',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Dept: ${member.department} · ${member.employmentStatus.label}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                      ),
                      if (member.username.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Username: @${member.username}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      if (member.phone.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Phone: ${member.phone}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      if (member.emergencyContactName.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Emergency: ${member.emergencyContactName} (${member.emergencyContactPhone})',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                        ),
                      ],
                      if (canManageStaff && !widget.compact) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed:
                                  (callerRole == WorkspaceRole.admin &&
                                          member.role == WorkspaceRole.owner) ||
                                      callerUserId == member.id
                                  ? null
                                  : () => _showEditRoleDialog(
                                      context,
                                      member,
                                      callerRole,
                                      callerUserId,
                                      isLive,
                                    ),
                              icon: const Icon(Icons.edit_outlined, size: 14),
                              label: const Text('Edit Role'),
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                textStyle: const TextStyle(fontSize: 12),
                              ),
                            ),
                            if (member.active)
                              OutlinedButton.icon(
                                onPressed:
                                    (callerRole == WorkspaceRole.admin &&
                                            member.role ==
                                                WorkspaceRole.owner) ||
                                        callerUserId == member.id
                                    ? null
                                    : () => _deactivateMember(
                                        context,
                                        member,
                                        callerRole,
                                        callerUserId,
                                        isLive,
                                      ),
                                icon: const Icon(
                                  Icons.person_off_outlined,
                                  size: 14,
                                ),
                                label: const Text('Deactivate'),
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  foregroundColor: Theme.of(context)
                                      .colorScheme
                                      .error,
                                  textStyle: const TextStyle(fontSize: 12),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 1: Shifts & Scheduling
  // ---------------------------------------------------------------------------

  Widget _buildShiftsTab(
    BuildContext context,
    bool canManageStaff,
    bool isLive,
  ) {
    final shiftsAsync = ref.watch(shiftsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(
          'Shift Scheduling & Coverage',
          subtitle: 'Define operational shift windows, department coverage, and roster schedules.',
          action: canManageStaff
              ? CafeButton(
                  label: 'Add Shift',
                  icon: Icons.add_alarm_outlined,
                  onPressed: () => _showCreateShiftDialog(context, isLive),
                )
              : null,
        ),
        const SizedBox(height: 16),
        shiftsAsync.when(
          data: (shifts) {
            if (shifts.isEmpty) {
              return const CafeEmptyState(
                title: 'No shifts defined',
                message:
                    'Create daily shift profiles to track roster coverage.',
                icon: Icons.schedule_outlined,
              );
            }

            return AdaptiveColumns(
              minWidth: 290,
              children: [
                for (final shift in shifts)
                  CafeCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                shift.name,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                            StatusPill(
                              shift.isActive ? 'Active Shift' : 'Inactive',
                              icon: shift.isActive
                                  ? Icons.check_circle_outline
                                  : Icons.cancel_outlined,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.access_time_filled,
                              size: 16,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${shift.startTime.substring(0, 5)} – ${shift.endTime.substring(0, 5)}',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontSize: 18),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Department: ${shift.department}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Text('Error loading shifts: $err'),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 2: Attendance Terminal
  // ---------------------------------------------------------------------------

  Widget _buildAttendanceTab(
    BuildContext context,
    List<StaffMemberRecord> members,
    WorkspaceRole callerRole,
    bool isLive,
  ) {
    final attendanceAsync = ref.watch(attendanceListProvider);
    final shifts = ref.watch(shiftsProvider).value ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(
          'Attendance & Time Tracking',
          subtitle: 'Duty timeclock, shift clock-in/out, break monitoring, and live attendance tracking.',
        ),
        const SizedBox(height: 12),

        // Interactive Terminal Card
        CafeCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.fingerprint_rounded,
                    size: 24,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Duty Timeclock Terminal',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Engine Guarantee: The database enforces idx_unique_active_clock_in to prevent duplicate concurrent active shifts per employee.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.outline),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue:
                          _selectedAttendanceUserId ??
                          (members.isNotEmpty ? members.first.id : null),
                      decoration: const InputDecoration(
                        labelText: 'Select Staff Member',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: members.map((m) {
                        return DropdownMenuItem(
                          value: m.id,
                          child: Text(
                            '${m.name} (${m.role.name.toUpperCase()})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (val) =>
                          setState(() => _selectedAttendanceUserId = val),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue:
                          _selectedAttendanceShiftId ??
                          (shifts.isNotEmpty ? shifts.first.id : null),
                      decoration: const InputDecoration(
                        labelText: 'Select Shift (Optional)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text(
                            'No Shift / General Duty',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        ...shifts.map((s) {
                          return DropdownMenuItem(
                            value: s.id,
                            child: Text(
                              '${s.name} (${s.startTime.substring(0, 5)})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }),
                      ],
                      onChanged: (val) =>
                          setState(() => _selectedAttendanceShiftId = val),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => _handleClockIn(context, isLive),
                    icon: const Icon(Icons.login_rounded, size: 16),
                    label: const Text('Clock In (Start Duty)'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _handleClockOutDialog(
                      context,
                      attendanceAsync.value ?? [],
                      isLive,
                    ),
                    icon: const Icon(Icons.logout_rounded, size: 16),
                    label: const Text('Clock Out (End Duty)'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        Text(
          'Live Attendance Ledger',
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),

        attendanceAsync.when(
          data: (records) {
            if (records.isEmpty) {
              return const CafeEmptyState(
                title: 'No attendance records',
                message:
                    'Clock-in events will appear here in chronological order.',
                icon: Icons.fingerprint_outlined,
              );
            }

            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: records.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final rec = records[index];
                final isClockedIn = rec.status == AttendanceStatus.clockedIn;
                return CafeCard(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isClockedIn
                              ? Colors.green.withAlpha(30)
                              : Colors.grey.withAlpha(30),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isClockedIn ? Icons.login : Icons.logout,
                          size: 18,
                          color: isClockedIn ? Colors.green : Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  rec.userName,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                StatusPill(
                                  rec.status.label,
                                  icon: isClockedIn
                                      ? Icons.timelapse
                                      : Icons.check,
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Shift: ${rec.shiftName ?? 'General'} · In: ${rec.clockIn.toLocal().toString().substring(11, 16)}${rec.clockOut != null ? ' · Out: ${rec.clockOut!.toLocal().toString().substring(11, 16)}' : ''}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (rec.totalBreakMinutes > 0 || rec.isLate) ...[
                              const SizedBox(height: 2),
                              Text(
                                '${rec.isLate ? 'Late Arrival · ' : ''}Break: ${rec.totalBreakMinutes} mins${rec.notes.isNotEmpty ? ' · Notes: ${rec.notes}' : ''}',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: rec.isLate
                                          ? Theme.of(context).colorScheme.error
                                          : Theme.of(context)
                                                .colorScheme
                                                .outline,
                                    ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Text('Error loading attendance: $err'),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 3: Role Permissions Matrix
  // ---------------------------------------------------------------------------

  Widget _buildPermissionsMatrixTab(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(
          'Role & Permissions Matrix (SEC-01)',
          subtitle: 'Strict Role-Based Access Control matrix governing features, workspaces, and administrative actions.',
        ),
        const SizedBox(height: 16),
        CafeCard(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 24,
              columns: const [
                DataColumn(
                  label: Text(
                    'Capability / Permission',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Owner',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Admin',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Cashier',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Kitchen',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Staff',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
              rows: [
                _buildMatrixRow(
                  'Manage Restaurant Settings',
                  owner: true,
                  admin: false,
                  cashier: false,
                  kitchen: false,
                  staff: false,
                ),
                _buildMatrixRow(
                  'Provision & Manage Staff',
                  owner: true,
                  admin: true, // SEC-01 guard applies
                  cashier: false,
                  kitchen: false,
                  staff: false,
                ),
                _buildMatrixRow(
                  'Manage Catalog & Menu',
                  owner: true,
                  admin: true,
                  cashier: false,
                  kitchen: false,
                  staff: false,
                ),
                _buildMatrixRow(
                  'POS & Create Orders',
                  owner: true,
                  admin: true,
                  cashier: true,
                  kitchen: false,
                  staff: true,
                ),
                _buildMatrixRow(
                  'Process Payments & Refunds',
                  owner: true,
                  admin: true,
                  cashier: true,
                  kitchen: false,
                  staff: false,
                ),
                _buildMatrixRow(
                  'Manage Tables & Floor',
                  owner: true,
                  admin: true,
                  cashier: true,
                  kitchen: false,
                  staff: true,
                ),
                _buildMatrixRow(
                  'Kitchen Display & KOT',
                  owner: true,
                  admin: true,
                  cashier: false,
                  kitchen: true,
                  staff: true,
                ),
                _buildMatrixRow(
                  'Adjust Inventory & Wastage',
                  owner: true,
                  admin: true,
                  cashier: false,
                  kitchen: true,
                  staff: false,
                ),
                _buildMatrixRow(
                  'Purchase Orders & Receiving',
                  owner: true,
                  admin: true,
                  cashier: false,
                  kitchen: false,
                  staff: false,
                ),
                _buildMatrixRow(
                  'Financial Analytics & Reports',
                  owner: true,
                  admin: true,
                  cashier: false,
                  kitchen: false,
                  staff: false,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  DataRow _buildMatrixRow(
    String capability, {
    required bool owner,
    required bool admin,
    required bool cashier,
    required bool kitchen,
    required bool staff,
  }) {
    Widget check(bool allowed) => Icon(
      allowed ? Icons.check_circle_rounded : Icons.remove_circle_outline,
      size: 18,
      color: allowed ? Colors.green : Colors.grey.withAlpha(100),
    );

    return DataRow(
      cells: [
        DataCell(
          Text(capability, style: const TextStyle(fontWeight: FontWeight.w500)),
        ),
        DataCell(check(owner)),
        DataCell(check(admin)),
        DataCell(check(cashier)),
        DataCell(check(kitchen)),
        DataCell(check(staff)),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 4: Activity Audit Log
  // ---------------------------------------------------------------------------

  Widget _buildAuditLogTab(BuildContext context) {
    final auditAsync = ref.watch(staffAuditEventsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(
          'Workforce & Operational Audit',
          subtitle: 'Immutable audit trail of staff provisioning, role updates, deactivations, shift changes, and receipts.',
        ),
        const SizedBox(height: 16),
        auditAsync.when(
          data: (events) {
            if (events.isEmpty) {
              return const CafeEmptyState(
                title: 'No audit events recorded',
                message: 'All administrative activities are recorded here.',
                icon: Icons.history_edu_outlined,
              );
            }

            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: events.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final ev = events[index];
                return CafeCard(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary
                              .withAlpha(25),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.security,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  ev.eventType,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  ev.createdAt.toLocal().toString().substring(
                                    0,
                                    16,
                                  ),
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outline,
                                        fontSize: 11,
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Target: ${ev.targetUserName ?? ev.targetUserId ?? 'System'} · By: ${ev.performedByName ?? 'Administrator'}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (ev.details.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                'Details: ${ev.details.toString()}',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outline,
                                    ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Text('Error loading audit log: $err'),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Dialogs & Actions
  // ---------------------------------------------------------------------------

  void _showAddStaffDialog(
    BuildContext context,
    WorkspaceRole callerRole,
    bool isLive,
  ) {
    final userIdController = TextEditingController();
    final nameController = TextEditingController();
    final usernameController = TextEditingController();
    final phoneController = TextEditingController();
    final deptController = TextEditingController(text: 'Front of House');

    WorkspaceRole selectedRole = WorkspaceRole.staff;
    EmploymentStatus selectedStatus = EmploymentStatus.fullTime;

    final allowedRoles = callerRole == WorkspaceRole.owner
        ? WorkspaceRole.values
        : WorkspaceRole.values.where((r) => r != WorkspaceRole.owner).toList();

    showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Provision Staff Member'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer
                          .withAlpha(50),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary
                            .withAlpha(60),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.security_outlined,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            callerRole == WorkspaceRole.admin
                                ? 'SEC-01 Guard: Admins cannot provision OWNER accounts.'
                                : 'Owner provisioning mode with full role assignment.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextField(
                    controller: userIdController,
                    decoration: const InputDecoration(
                      labelText: 'User ID (Auth UUID) *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Full Name *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: usernameController,
                    decoration: const InputDecoration(
                      labelText: 'Username (Optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: phoneController,
                    decoration: const InputDecoration(
                      labelText: 'Phone (Optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: deptController,
                    decoration: const InputDecoration(
                      labelText: 'Department',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<WorkspaceRole>(
                    initialValue: selectedRole,
                    decoration: const InputDecoration(
                      labelText: 'Assigned Role',
                      border: OutlineInputBorder(),
                    ),
                    items: allowedRoles.map((role) {
                      return DropdownMenuItem(
                        value: role,
                        child: Text(
                          '${role.name.toUpperCase()} — ${role.label}',
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => selectedRole = val);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<EmploymentStatus>(
                    initialValue: selectedStatus,
                    decoration: const InputDecoration(
                      labelText: 'Employment Status',
                      border: OutlineInputBorder(),
                    ),
                    items: EmploymentStatus.values.map((st) {
                      return DropdownMenuItem(value: st, child: Text(st.label));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => selectedStatus = val);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final uid = userIdController.text.trim();
                final name = nameController.text.trim();
                if (uid.isEmpty || name.isEmpty) return;

                if (isLive) {
                  final staffRepo = ref.read(staffRepositoryProvider);
                  final auth = ref.read(authControllerProvider);
                  final restId = auth.activeMembership?.restaurantId;

                  if (staffRepo != null && restId != null) {
                    try {
                      await staffRepo.provisionStaff(
                        restaurantId: restId,
                        targetUserId: uid,
                        role: selectedRole,
                        fullName: name,
                        callerRole: callerRole,
                        phone: phoneController.text.trim().isNotEmpty
                            ? phoneController.text.trim()
                            : null,
                        username: usernameController.text.trim().isNotEmpty
                            ? usernameController.text.trim()
                            : null,
                        department: deptController.text.trim(),
                        employmentStatus: selectedStatus,
                      );
                      ref.invalidate(staffListProvider);
                      ref.invalidate(staffAuditEventsProvider);
                      if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Staff member $name provisioned.'),
                          ),
                        );
                      }
                    } catch (err) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              err is AppFailure
                                  ? err.message
                                  : 'Provisioning failed: $err',
                            ),
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .error,
                          ),
                        );
                      }
                    }
                    return;
                  }
                }

                Navigator.of(dialogCtx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Demo Mode: Staff provisioning simulated.'),
                  ),
                );
              },
              child: const Text('Provision Member'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditRoleDialog(
    BuildContext context,
    StaffMemberRecord member,
    WorkspaceRole callerRole,
    String callerUserId,
    bool isLive,
  ) {
    if (callerRole == WorkspaceRole.admin &&
        member.role == WorkspaceRole.owner) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SEC-01 Guard: Admins cannot modify Owner accounts.'),
        ),
      );
      return;
    }

    if (callerUserId == member.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Security Guard: Users cannot alter their own role (anti-self-promotion).',
          ),
        ),
      );
      return;
    }

    WorkspaceRole selectedRole = member.role;
    final allowedRoles = callerRole == WorkspaceRole.owner
        ? WorkspaceRole.values
        : WorkspaceRole.values.where((r) => r != WorkspaceRole.owner).toList();

    showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Update Role for ${member.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Current Role: ${member.role.name.toUpperCase()}'),
              const SizedBox(height: 16),
              DropdownButtonFormField<WorkspaceRole>(
                initialValue: allowedRoles.contains(selectedRole)
                    ? selectedRole
                    : allowedRoles.first,
                decoration: const InputDecoration(
                  labelText: 'New Role',
                  border: OutlineInputBorder(),
                ),
                items: allowedRoles.map((role) {
                  return DropdownMenuItem(
                    value: role,
                    child: Text('${role.name.toUpperCase()} — ${role.label}'),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setDialogState(() => selectedRole = val);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (isLive) {
                  final staffRepo = ref.read(staffRepositoryProvider);
                  final auth = ref.read(authControllerProvider);
                  final restId = auth.activeMembership?.restaurantId;

                  if (staffRepo != null && restId != null) {
                    try {
                      await staffRepo.updateStaffRole(
                        restaurantId: restId,
                        targetUserId: member.id,
                        newRole: selectedRole,
                        callerRole: callerRole,
                        callerUserId: callerUserId,
                        targetCurrentRole: member.role,
                      );
                      ref.invalidate(staffListProvider);
                      ref.invalidate(staffAuditEventsProvider);
                      if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Role updated to ${selectedRole.name}.',
                            ),
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              e is AppFailure ? e.message : 'Update failed: $e',
                            ),
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .error,
                          ),
                        );
                      }
                    }
                    return;
                  }
                }

                Navigator.of(dialogCtx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Demo Mode: Role update simulated.'),
                  ),
                );
              },
              child: const Text('Save Role'),
            ),
          ],
        ),
      ),
    );
  }

  void _deactivateMember(
    BuildContext context,
    StaffMemberRecord member,
    WorkspaceRole callerRole,
    String callerUserId,
    bool isLive,
  ) async {
    if (isLive) {
      final staffRepo = ref.read(staffRepositoryProvider);
      final auth = ref.read(authControllerProvider);
      final restId = auth.activeMembership?.restaurantId;
      if (staffRepo != null && restId != null) {
        try {
          await staffRepo.deactivateStaff(
            restaurantId: restId,
            targetUserId: member.id,
            callerRole: callerRole,
            callerUserId: callerUserId,
            targetCurrentRole: member.role,
          );
          ref.invalidate(staffListProvider);
          ref.invalidate(staffAuditEventsProvider);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${member.name} deactivated.')),
            );
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Deactivation failed: $e')));
          }
        }
        return;
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Demo Mode: Deactivated ${member.name}.')),
    );
  }

  void _showCreateShiftDialog(BuildContext context, bool isLive) {
    final nameCtrl = TextEditingController(text: 'Afternoon Barista Shift');
    final startCtrl = TextEditingController(text: '12:00:00');
    final endCtrl = TextEditingController(text: '20:00:00');
    final deptCtrl = TextEditingController(text: 'Front of House');

    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Create Work Shift'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Shift Name *'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: startCtrl,
              decoration: const InputDecoration(
                labelText: 'Start Time (HH:MM:SS) *',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: endCtrl,
              decoration: const InputDecoration(
                labelText: 'End Time (HH:MM:SS) *',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: deptCtrl,
              decoration: const InputDecoration(labelText: 'Department'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;

              if (isLive) {
                final staffRepo = ref.read(staffRepositoryProvider);
                final auth = ref.read(authControllerProvider);
                final restId = auth.activeMembership?.restaurantId;

                if (staffRepo != null && restId != null) {
                  try {
                    await staffRepo.createShift(
                      restaurantId: restId,
                      name: name,
                      startTime: startCtrl.text.trim(),
                      endTime: endCtrl.text.trim(),
                      department: deptCtrl.text.trim(),
                    );
                    ref.invalidate(shiftsProvider);
                    if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error creating shift: $e')),
                      );
                    }
                  }
                  return;
                }
              }

              Navigator.pop(dialogCtx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Demo Mode: Shift creation simulated.'),
                ),
              );
            },
            child: const Text('Save Shift'),
          ),
        ],
      ),
    );
  }

  void _handleClockIn(BuildContext context, bool isLive) async {
    if (isLive) {
      final staffRepo = ref.read(staffRepositoryProvider);
      final auth = ref.read(authControllerProvider);
      final restId = auth.activeMembership?.restaurantId;

      if (staffRepo != null && restId != null) {
        try {
          await staffRepo.clockIn(
            restaurantId: restId,
            targetUserId: _selectedAttendanceUserId,
            shiftId: _selectedAttendanceShiftId,
          );
          ref.invalidate(attendanceListProvider);
          ref.invalidate(staffAuditEventsProvider);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Successfully clocked in. Duty shift active.'),
              ),
            );
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  e is AppFailure
                      ? e.message
                      : 'Clock-in failed: already clocked in.',
                ),
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
            );
          }
        }
        return;
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Demo Mode: Clock-in recorded successfully.'),
      ),
    );
  }

  void _handleClockOutDialog(
    BuildContext context,
    List<StaffAttendanceRecord> records,
    bool isLive,
  ) {
    final activeRecords = records
        .where(
          (r) =>
              r.status == AttendanceStatus.clockedIn ||
              r.status == AttendanceStatus.onBreak,
        )
        .toList();

    if (activeRecords.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active clocked-in shifts found.')),
      );
      return;
    }

    StaffAttendanceRecord selected = activeRecords.first;
    final notesCtrl = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Clock Out of Duty'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<StaffAttendanceRecord>(
                initialValue: selected,
                items: activeRecords.map((r) {
                  return DropdownMenuItem(
                    value: r,
                    child: Text('${r.userName} (${r.shiftName ?? 'Duty'})'),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setDialogState(() => selected = val);
                  }
                },
                decoration: const InputDecoration(labelText: 'Active Session'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Shift notes / handover',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (isLive) {
                  final staffRepo = ref.read(staffRepositoryProvider);
                  final auth = ref.read(authControllerProvider);
                  final restId = auth.activeMembership?.restaurantId;

                  if (staffRepo != null && restId != null) {
                    try {
                      await staffRepo.clockOut(
                        restaurantId: restId,
                        attendanceId: selected.id,
                        notes: notesCtrl.text.trim(),
                      );
                      ref.invalidate(attendanceListProvider);
                      ref.invalidate(staffAuditEventsProvider);
                      if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Duty shift ended. Clock-out saved.'),
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Clock-out failed: $e')),
                        );
                      }
                    }
                    return;
                  }
                }

                Navigator.pop(dialogCtx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Demo Mode: Clock-out recorded.'),
                  ),
                );
              },
              child: const Text('Confirm Clock Out'),
            ),
          ],
        ),
      ),
    );
  }
}
