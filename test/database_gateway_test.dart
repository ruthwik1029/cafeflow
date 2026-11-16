import 'package:cafeflow/core/database/database_gateway.dart';
import 'package:cafeflow/core/errors/app_failure.dart';
import 'package:cafeflow/core/services/backend.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FailingClient extends Fake implements SupabaseClient {
  FailingClient(this.failure);
  final Object failure;
  @override
  SupabaseQueryBuilder from(String table) => throw failure;
}

void main() {
  test('unconfigured client cannot be used by repositories', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      () => container.read(supabaseClientProvider),
      throwsA(
        isA<Exception>().having(
          (failure) => failure.toString(),
          'message',
          contains('Backend is unavailable.'),
        ),
      ),
    );
  });
  test('database gateway bounds reads before executing a query', () async {
    final gateway = SupabaseDatabaseGateway(
      FailingClient(StateError('must not run')),
    );
    for (final limit in [0, -1, 1001]) {
      await expectLater(
        gateway.readRows('example', limit: limit),
        throwsArgumentError,
      );
    }
  });
  test(
    'database gateway sanitizes permission and transport failures',
    () async {
      final denied = SupabaseDatabaseGateway(
        FailingClient(
          const PostgrestException(
            message: 'private database diagnostic',
            code: '42501',
          ),
        ),
      );
      await expectLater(
        denied.readRows('example'),
        throwsA(
          isA<AppFailure>().having(
            (failure) => failure.message,
            'message',
            'You do not have access to this data.',
          ),
        ),
      );
      final offline = SupabaseDatabaseGateway(
        FailingClient(StateError('private diagnostic')),
      );
      await expectLater(
        offline.readRows('example'),
        throwsA(
          isA<AppFailure>().having(
            (failure) => failure.message,
            'message',
            isNot(contains('private diagnostic')),
          ),
        ),
      );
    },
  );
}
