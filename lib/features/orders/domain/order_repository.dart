class OrderReference {
  const OrderReference({required this.id, required this.displayNumber});
  final String id;
  final String displayNumber;
}

/// No concrete implementation is registered until Auth, schema and RLS exist.
abstract interface class OrderRepository {
  Future<List<OrderReference>> listActive({String? restaurantId});
  Stream<void> watchInvalidations({String? restaurantId});
}
