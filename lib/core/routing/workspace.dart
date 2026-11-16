import 'package:flutter/material.dart';

enum InternalTarget { windows, android }

enum WorkspaceRole { admin, cashier, kitchen, owner, staff }

extension WorkspaceRoleX on WorkspaceRole {
  String get label => switch (this) {
    WorkspaceRole.owner => 'Owner',
    WorkspaceRole.admin => 'Admin',
    WorkspaceRole.cashier => 'Cashier',
    WorkspaceRole.kitchen => 'Kitchen',
    WorkspaceRole.staff => 'Staff',
  };
}

class WorkspaceSection {
  const WorkspaceSection(this.id, this.label, this.icon, this.description);
  final String id;
  final String label;
  final IconData icon;
  final String description;
}

class WorkspaceDefinition {
  const WorkspaceDefinition({
    required this.role,
    required this.label,
    required this.eyebrow,
    required this.headline,
    required this.description,
    required this.sections,
  });
  final WorkspaceRole role;
  final String label;
  final String eyebrow;
  final String headline;
  final String description;
  final List<WorkspaceSection> sections;
  String path(String section) => '/${role.name}/$section';
  String get home => path(sections.first.id);
}

List<WorkspaceRole> rolesFor(InternalTarget target) => switch (target) {
  InternalTarget.windows => const [
    WorkspaceRole.admin,
    WorkspaceRole.cashier,
    WorkspaceRole.kitchen,
  ],
  InternalTarget.android => const [WorkspaceRole.owner, WorkspaceRole.staff],
};
