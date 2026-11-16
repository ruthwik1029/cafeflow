import '../../../core/routing/workspace.dart';

enum CafePermission {
  viewDashboard,
  viewMenu,
  manageMenu,
  createOrders,
  viewOrders,
  updateKitchenOrders,
  processPayments,
  manageTables,
  manageInventory,
  viewReports,
  manageStaff,
  manageSettings,
  manageOwnership,
}

class RolePermissions {
  const RolePermissions._();

  static const Map<WorkspaceRole, Set<CafePermission>> _matrix = {
    WorkspaceRole.owner: {
      CafePermission.viewDashboard,
      CafePermission.viewMenu,
      CafePermission.manageMenu,
      CafePermission.createOrders,
      CafePermission.viewOrders,
      CafePermission.updateKitchenOrders,
      CafePermission.processPayments,
      CafePermission.manageTables,
      CafePermission.manageInventory,
      CafePermission.viewReports,
      CafePermission.manageStaff,
      CafePermission.manageSettings,
      CafePermission.manageOwnership,
    },
    WorkspaceRole.admin: {
      CafePermission.viewDashboard,
      CafePermission.viewMenu,
      CafePermission.manageMenu,
      CafePermission.createOrders,
      CafePermission.viewOrders,
      CafePermission.updateKitchenOrders,
      CafePermission.processPayments,
      CafePermission.manageTables,
      CafePermission.manageInventory,
      CafePermission.viewReports,
      CafePermission.manageStaff,
      CafePermission.manageSettings,
      // Note: manageOwnership is explicitly EXCLUDED for ADMIN (SEC-01)
    },
    WorkspaceRole.cashier: {
      CafePermission.viewMenu,
      CafePermission.createOrders,
      CafePermission.viewOrders,
      CafePermission.processPayments,
      CafePermission.manageTables,
    },
    WorkspaceRole.kitchen: {
      CafePermission.viewOrders,
      CafePermission.updateKitchenOrders,
      CafePermission.manageInventory,
    },
    WorkspaceRole.staff: {
      CafePermission.viewMenu,
      CafePermission.createOrders,
      CafePermission.viewOrders,
      CafePermission.manageTables,
    },
  };

  static bool hasPermission(WorkspaceRole role, CafePermission permission) {
    return _matrix[role]?.contains(permission) ?? false;
  }

  static Set<CafePermission> permissionsFor(WorkspaceRole role) {
    return _matrix[role] ?? const {};
  }
}
