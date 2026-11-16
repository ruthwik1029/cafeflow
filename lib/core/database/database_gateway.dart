import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors/app_failure.dart';
import '../services/backend.dart';

abstract interface class DatabaseGateway {
  Future<List<Map<String, dynamic>>> readRows(
    String relation, {
    Map<String, Object> equals = const {},
    int limit = 100,
  });
}

/// Repositories own relation names and mapping. RLS remains the authorization boundary.
class SupabaseDatabaseGateway implements DatabaseGateway {
  const SupabaseDatabaseGateway(this.client);
  final SupabaseClient client;

  @override
  Future<List<Map<String, dynamic>>> readRows(
    String relation, {
    Map<String, Object> equals = const {},
    int limit = 100,
  }) async {
    if (limit < 1 || limit > 1000) {
      throw ArgumentError.value(limit, 'limit', 'Use 1–1000 rows.');
    }
    try {
      var query = client.from(relation).select();
      for (final entry in equals.entries) {
        query = query.eq(entry.key, entry.value);
      }
      return await query.limit(limit).timeout(const Duration(seconds: 15));
    } on PostgrestException catch (error) {
      if (error.code == '42501') {
        throw const AppFailure('You do not have access to this data.');
      }
      throw const AppFailure('Data could not be loaded. Please try again.');
    } catch (_) {
      throw const AppFailure(
        'The data service is unavailable. Check your connection and try again.',
      );
    }
  }
}

final databaseGatewayProvider = Provider<DatabaseGateway>(
  (ref) => SupabaseDatabaseGateway(ref.watch(supabaseClientProvider)),
);
