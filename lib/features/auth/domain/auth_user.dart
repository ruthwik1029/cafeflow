import '../../../core/routing/workspace.dart';

class RestaurantMembershipInfo {
  const RestaurantMembershipInfo({
    required this.restaurantId,
    required this.restaurantName,
    required this.role,
  });

  final String restaurantId;
  final String restaurantName;
  final WorkspaceRole role;

  RestaurantMembershipInfo copyWith({
    String? restaurantId,
    String? restaurantName,
    WorkspaceRole? role,
  }) {
    return RestaurantMembershipInfo(
      restaurantId: restaurantId ?? this.restaurantId,
      restaurantName: restaurantName ?? this.restaurantName,
      role: role ?? this.role,
    );
  }
}

class CafeUser {
  const CafeUser({
    required this.id,
    required this.email,
    required this.fullName,
    this.phone = '',
    this.username = '',
    this.memberships = const [],
  });

  final String id;
  final String email;
  final String fullName;
  final String phone;
  final String username;
  final List<RestaurantMembershipInfo> memberships;

  RestaurantMembershipInfo? membershipFor(String restaurantId) {
    for (final m in memberships) {
      if (m.restaurantId == restaurantId) return m;
    }
    return null;
  }
}
