/// Minimal shared domain contract. Mapping and persistence wait for the schema.
class MenuItem {
  const MenuItem({
    required this.id,
    required this.name,
    required this.available,
  });
  final String id;
  final String name;
  final bool available;
}

abstract interface class MenuRepository {
  Future<List<MenuItem>> listAvailable({String? restaurantId});

  /// Invalidation events cause an authorized snapshot to be fetched again.
  Stream<void> watchInvalidations({String? restaurantId});
}
