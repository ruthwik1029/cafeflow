import 'package:flutter/material.dart';

import '../../../core/routing/workspace.dart';

const workspaceCatalog = [
  WorkspaceDefinition(
    role: WorkspaceRole.admin,
    label: 'Admin / Owner',
    eyebrow: 'THE OWNER CONSOLE',
    headline: 'A little more flow.\nA lot more possibility.',
    description: 'One considered space for your café, your team, and everything that comes next.',
    sections: [
      WorkspaceSection(
        'dashboard',
        'Overview dashboard',
        Icons.grid_view_rounded,
        'Executive business metrics, sales, tickets, and floor activity.',
      ),
      WorkspaceSection(
        'orders',
        'Orders',
        Icons.receipt_long_outlined,
        'Track and monitor orders across all tables and takeaway.',
      ),
      WorkspaceSection(
        'menu',
        'Menu management',
        Icons.restaurant_menu_rounded,
        'Organize categories, products, availability, and pricing.',
      ),
      WorkspaceSection(
        'categories',
        'Categories',
        Icons.category_outlined,
        'Manage catalog groupings, visibility, and display ordering.',
      ),
      WorkspaceSection(
        'inventory',
        'Inventory',
        Icons.inventory_2_outlined,
        'Keep track of stock levels, minimum thresholds, and replenishment.',
      ),
      WorkspaceSection(
        'tables',
        'Tables',
        Icons.table_restaurant_outlined,
        'Dining floor plan, seating capacity, and table occupancy.',
      ),
      WorkspaceSection(
        'staff',
        'Staff',
        Icons.people_outline_rounded,
        'Manage team members, roles, shift coverage, and duty statuses.',
      ),
      WorkspaceSection(
        'customers',
        'Customers',
        Icons.person_search_outlined,
        'Customer directory, repeat visit loyalty, and order preferences.',
      ),
      WorkspaceSection(
        'reports',
        'Reports',
        Icons.bar_chart_rounded,
        'Sales revenue reports, category breakdowns, and rush trends.',
      ),
      WorkspaceSection(
        'settings',
        'Settings',
        Icons.tune_rounded,
        'Configure the business outlet, taxes, receipts, and theme.',
      ),
    ],
  ),
  WorkspaceDefinition(
    role: WorkspaceRole.cashier,
    label: 'Cashier',
    eyebrow: 'AT THE COUNTER',
    headline: 'Great service.\nFrom first order to last.',
    description: 'A focused home for billing and orders, designed around the rhythm of the counter.',
    sections: [
      WorkspaceSection(
        'pos',
        'Point of sale',
        Icons.point_of_sale_rounded,
        'Counter ordering, catalog selection, custom discounts, and payment methods.',
      ),
      WorkspaceSection(
        'billing',
        'Billing workspace',
        Icons.receipt_outlined,
        'Review current orders, itemized lines, and guest totals.',
      ),
      WorkspaceSection(
        'orders',
        'Orders',
        Icons.receipt_long_outlined,
        'Track active and settled orders.',
      ),
    ],
  ),
  WorkspaceDefinition(
    role: WorkspaceRole.kitchen,
    label: 'Kitchen / KOT',
    eyebrow: 'BEHIND THE PASS',
    headline: 'Every order.\nA clear next step.',
    description:
        'A calm, legible workspace for the team bringing every order to life.',
    sections: [
      WorkspaceSection(
        'display',
        'Kitchen display',
        Icons.soup_kitchen_outlined,
        'Multi-column display of new, preparing, and ready order tickets.',
      ),
      WorkspaceSection(
        'incoming',
        'Incoming orders',
        Icons.move_to_inbox_outlined,
        'Fresh tickets requiring immediate preparation acknowledgment.',
      ),
      WorkspaceSection(
        'preparation',
        'Preparation status',
        Icons.checklist_rounded,
        'Active tickets currently cooking at the line.',
      ),
    ],
  ),
  WorkspaceDefinition(
    role: WorkspaceRole.owner,
    label: 'Owner',
    eyebrow: 'YOUR CAFÉ, WITH YOU',
    headline: 'Stay close.\nWherever the day takes you.',
    description: 'A compact view of the business, made for the moments between everything else.',
    sections: [
      WorkspaceSection(
        'overview',
        'Sales overview',
        Icons.space_dashboard_outlined,
        'Real-time revenue, active ticket volume, and floor occupancy.',
      ),
      WorkspaceSection(
        'orders',
        'Order overview',
        Icons.receipt_long_outlined,
        'Monitor recent customer orders across the floor.',
      ),
      WorkspaceSection(
        'popular',
        'Popular items',
        Icons.auto_awesome_outlined,
        'High-velocity products and bestseller performance.',
      ),
      WorkspaceSection(
        'inventory',
        'Inventory alerts',
        Icons.warning_amber_rounded,
        'Low-stock warnings for ingredients below safety thresholds.',
      ),
      WorkspaceSection(
        'staff',
        'Staff overview',
        Icons.people_outline_rounded,
        'Today’s scheduled staff and active shift coverage.',
      ),
    ],
  ),
  WorkspaceDefinition(
    role: WorkspaceRole.staff,
    label: 'Staff',
    eyebrow: 'ON THE FLOOR',
    headline: 'More time for\nthe people at your tables.',
    description: 'A pocket-sized workspace for attentive service and an effortless handoff to the kitchen.',
    sections: [
      WorkspaceSection(
        'orders',
        'Take an order',
        Icons.add_circle_outline,
        'Fast table-side mobile order creation and ticket dispatch.',
      ),
      WorkspaceSection(
        'menu',
        'Browse menu',
        Icons.restaurant_menu_rounded,
        'Browse catalog products, ingredients, and real-time availability.',
      ),
      WorkspaceSection(
        'tables',
        'Tables & orders',
        Icons.table_restaurant_outlined,
        'Dining floor status, seating, and table management.',
      ),
      WorkspaceSection(
        'status',
        'Order status',
        Icons.checklist_rounded,
        'Active orders and ready-for-service kitchen alerts.',
      ),
    ],
  ),
];

WorkspaceDefinition workspaceFor(WorkspaceRole role) =>
    workspaceCatalog.firstWhere((workspace) => workspace.role == role);
