import 'dart:async';

import 'package:cafeflow/core/config/config_loader.dart';
import 'package:cafeflow/core/database/database_gateway.dart';
import 'package:cafeflow/core/errors/app_failure.dart';
import 'package:cafeflow/core/routing/workspace.dart';
import 'package:cafeflow/core/services/backend.dart';
import 'package:cafeflow/core/services/cafe_realtime_service.dart';
import 'package:cafeflow/core/services/realtime_gateway.dart';
import 'package:cafeflow/core/storage/local_database.dart';
import 'package:cafeflow/features/auth/application/auth_controller.dart';
import 'package:cafeflow/features/auth/domain/auth_user.dart';
import 'package:cafeflow/features/menu/application/catalog_provider.dart';
import 'package:cafeflow/features/menu/data/supabase_menu_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class MockDatabaseGateway implements DatabaseGateway {
  MockDatabaseGateway(this.tables);
  final Map<String, List<Map<String, dynamic>>> tables;

  @override
  Future<List<Map<String, dynamic>>> readRows(
    String relation, {
    Map<String, Object> equals = const {},
    int limit = 100,
  }) async {
    final rows = tables[relation] ?? [];
    return rows.where((row) {
      for (final entry in equals.entries) {
        if (row[entry.key] != entry.value) return false;
      }
      return true;
    }).toList();
  }
}

class MockChangefeedTransport implements ChangefeedTransport {
  final _controller = StreamController<RealtimeSignal>.broadcast();

  void emit(RealtimeSignal signal) => _controller.add(signal);

  @override
  CloseSubscription open(
    ChangefeedSpec spec,
    void Function(RealtimeSignal) onSignal,
    void Function(AppFailure) onError,
  ) {
    final sub = _controller.stream.listen(
      onSignal,
      onError: (e) {
        if (e is AppFailure) onError(e);
      },
    );
    return () async => sub.cancel();
  }
}

void main() {
  group('End-to-End Connectivity & Catalog Synchronization Tests', () {
    test('loadAppConfig resolves valid AppConfig without crashing', () {
      final config = loadAppConfig();
      expect(config, isNotNull);
      expect(config.environment, isNotEmpty);
    });

    test(
      'catalogProvider serves demo catalog when backend is unconfigured',
      () async {
        final container = ProviderContainer(
          overrides: [
            backendProvider.overrideWithValue(
              const BackendState(BackendStatus.unconfigured, 'Not configured.'),
            ),
            menuRepositoryProvider.overrideWithValue(null),
          ],
        );
        addTearDown(container.dispose);

        final snapshot = await container.read(catalogProvider.future);
        expect(snapshot.isDemo, isTrue);
        expect(snapshot.categories.isNotEmpty, isTrue);
        expect(snapshot.products.isNotEmpty, isTrue);
      },
    );

    test('catalogProvider on public website fetches live published catalog from Supabase without authenticated user', () async {
      final mockGateway = MockDatabaseGateway({
        'menu_categories': [
          {
            'id': 'cat-pub-1',
            'restaurant_id': 'rest-flagship',
            'name': 'Artisan Brews',
            'is_active': true,
          },
        ],
        'menu_items': [
          {
            'id': 'item-pub-1',
            'restaurant_id': 'rest-flagship',
            'category_id': 'cat-pub-1',
            'name': 'Cold Brew Reserve',
            'price_minor': 26000,
            'description': '18-hour cold brew',
            'image_url': 'assets/images/coffee.jpg',
            'is_available': true,
            'is_archived': false,
            'is_featured': true,
          },
        ],
      });

      final mockTransport = MockChangefeedTransport();
      final realtimeGateway = RealtimeGateway(mockTransport);
      final realtimeService = CafeRealtimeService(realtimeGateway);
      final menuRepo = SupabaseMenuRepository(
        gateway: mockGateway,
        realtime: realtimeService,
      );

      final container = ProviderContainer(
        overrides: [
          backendProvider.overrideWithValue(
            const BackendState(
              BackendStatus.initialized,
              'Client initialized.',
            ),
          ),
          menuRepositoryProvider.overrideWithValue(menuRepo),
          // Unauthenticated customer context (no active membership)
          authControllerProvider.overrideWith(
            () => _FakeAuthController(
              const AuthState(status: AuthStatus.unauthenticated),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final snapshot = await container.read(catalogProvider.future);
      expect(snapshot.isDemo, isFalse);
      expect(snapshot.categories.length, 1);
      expect(snapshot.categories.first.name, 'Artisan Brews');
      expect(snapshot.products.length, 1);
      expect(snapshot.products.first.name, 'Cold Brew Reserve');
      expect(snapshot.products.first.priceMinor, 26000);
    });

    test('Owner updating menu item triggers realtime invalidation reflected on public catalog', () async {
      final tables = <String, List<Map<String, dynamic>>>{
        'menu_categories': [
          {
            'id': 'cat-1',
            'restaurant_id': 'rest-1',
            'name': 'Coffee',
            'is_active': true,
          },
        ],
        'menu_items': [
          {
            'id': 'item-1',
            'restaurant_id': 'rest-1',
            'category_id': 'cat-1',
            'name': 'Espresso',
            'price_minor': 18000,
            'description': 'Classic shot',
            'image_url': '',
            'is_available': true,
            'is_archived': false,
            'is_featured': false,
          },
        ],
      };

      final mockGateway = MockDatabaseGateway(tables);
      final mockTransport = MockChangefeedTransport();
      final realtimeGateway = RealtimeGateway(mockTransport);
      final realtimeService = CafeRealtimeService(realtimeGateway);
      final menuRepo = SupabaseMenuRepository(
        gateway: mockGateway,
        realtime: realtimeService,
      );

      // Public website container (unauthenticated)
      final publicContainer = ProviderContainer(
        overrides: [
          backendProvider.overrideWithValue(
            const BackendState(BackendStatus.initialized, 'Ready'),
          ),
          menuRepositoryProvider.overrideWithValue(menuRepo),
          authControllerProvider.overrideWith(
            () => _FakeAuthController(
              const AuthState(status: AuthStatus.unauthenticated),
            ),
          ),
        ],
      );
      addTearDown(publicContainer.dispose);

      // 1. Initial public read
      final initialSnapshot = await publicContainer.read(
        catalogProvider.future,
      );
      expect(initialSnapshot.products.first.name, 'Espresso');
      expect(initialSnapshot.products.first.priceMinor, 18000);

      // 2. Owner updates the price and name in the database table
      tables['menu_items']![0]['name'] = 'Double Espresso Reserve';
      tables['menu_items']![0]['price_minor'] = 22000;

      // 3. Supabase broadcasts a Realtime change event on table 'menu_items'
      mockTransport.emit(RealtimeSignal.changed);

      // Wait a microtask for stream processing
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // 4. Public catalog provider has automatically invalidated and re-read from Supabase
      final updatedSnapshot = await publicContainer.read(
        catalogProvider.future,
      );
      expect(updatedSnapshot.products.first.name, 'Double Espresso Reserve');
      expect(updatedSnapshot.products.first.priceMinor, 22000);
    });

    test('Owner in live mode saves new item and invalidates catalog', () async {
      final tables = <String, List<Map<String, dynamic>>>{
        'menu_categories': [
          {
            'id': 'cat-1',
            'restaurant_id': 'rest-1',
            'name': 'Tea',
            'is_active': true,
          },
        ],
        'menu_items': [],
      };
      final mockGateway = MockDatabaseGateway(tables);
      final mockTransport = MockChangefeedTransport();
      final realtimeGateway = RealtimeGateway(mockTransport);
      final realtimeService = CafeRealtimeService(realtimeGateway);
      final menuRepo = SupabaseMenuRepository(
        gateway: mockGateway,
        realtime: realtimeService,
      );

      const ownerMembership = RestaurantMembershipInfo(
        restaurantId: 'rest-1',
        restaurantName: 'Flagship Bistro',
        role: WorkspaceRole.owner,
      );

      const ownerUser = CafeUser(
        id: 'user-owner',
        email: 'owner@cafeflow.com',
        fullName: 'Bistro Owner',
        memberships: [ownerMembership],
      );

      final container = ProviderContainer(
        overrides: [
          localDatabaseProvider.overrideWithValue(
            CafeLocalDatabase(adapter: MemoryStorageAdapter()),
          ),
          backendProvider.overrideWithValue(
            const BackendState(BackendStatus.initialized, 'Ready'),
          ),
          menuRepositoryProvider.overrideWithValue(menuRepo),
          authControllerProvider.overrideWith(
            () => _FakeAuthController(
              const AuthState(
                status: AuthStatus.authenticated,
                user: ownerUser,
                activeMembership: ownerMembership,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Simulate item insertion into live database
      tables['menu_items']!.add({
        'id': 'item-matcha',
        'restaurant_id': 'rest-1',
        'category_id': 'cat-1',
        'name': 'Ceremonial Matcha Latte',
        'price_minor': 32000,
        'description': 'Stone-ground Uji matcha with oat milk',
        'image_url': 'assets/images/coffee.jpg',
        'is_available': true,
        'is_archived': false,
        'is_featured': true,
      });

      container.invalidate(catalogProvider);
      final snapshot = await container.read(catalogProvider.future);
      expect(snapshot.isDemo, isFalse);
      expect(snapshot.products.length, 1);
      expect(snapshot.products.first.name, 'Ceremonial Matcha Latte');
      expect(snapshot.products.first.priceMinor, 32000);
    });
  });
}

class _FakeAuthController extends AuthController {
  _FakeAuthController(this._initial);
  final AuthState _initial;

  @override
  AuthState build() => _initial;
}
