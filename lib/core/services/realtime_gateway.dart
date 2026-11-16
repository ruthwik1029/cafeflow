import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors/app_failure.dart';
import 'backend.dart';

enum RealtimeSignal { subscribed, changed }

class ChangefeedSpec {
  const ChangefeedSpec({required this.table, this.filter});
  final String table;
  final PostgresChangeFilter? filter;
}

typedef CloseSubscription = Future<void> Function();

abstract interface class ChangefeedTransport {
  CloseSubscription open(
    ChangefeedSpec spec,
    void Function(RealtimeSignal) onSignal,
    void Function(AppFailure) onError,
  );
}

class SupabaseChangefeedTransport implements ChangefeedTransport {
  SupabaseChangefeedTransport(this.client);
  final SupabaseClient client;
  int _nextId = 0;

  @override
  CloseSubscription open(
    ChangefeedSpec spec,
    void Function(RealtimeSignal) onSignal,
    void Function(AppFailure) onError,
  ) {
    final channel = client.channel('cafeflow:${spec.table}:${_nextId++}');
    var closing = false;
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: spec.table,
      filter: spec.filter,
      callback: (_) {
        if (!closing) onSignal(RealtimeSignal.changed);
      },
    );
    channel.subscribe((status, error) {
      if (closing) return;
      switch (status) {
        case RealtimeSubscribeStatus.subscribed:
          // Refetch on initial connect AND reconnect to cover missed events.
          onSignal(RealtimeSignal.subscribed);
        case RealtimeSubscribeStatus.channelError:
        case RealtimeSubscribeStatus.timedOut:
        case RealtimeSubscribeStatus.closed:
          onError(
            const AppFailure(
              'Live updates are unavailable. Refresh to check the latest data.',
            ),
          );
      }
    });
    return () async {
      if (closing) return;
      closing = true;
      await client.removeChannel(channel);
    };
  }
}

/// Each listened stream owns exactly one channel; cancellation removes it.
/// Share it with a Riverpod auto-disposed StreamProvider in future feature code.
class RealtimeGateway {
  const RealtimeGateway(this.transport);
  final ChangefeedTransport transport;

  Stream<RealtimeSignal> watch(ChangefeedSpec spec) {
    CloseSubscription? close;
    var active = true;
    late final StreamController<RealtimeSignal> controller;
    controller = StreamController<RealtimeSignal>(
      onListen: () {
        try {
          close = transport.open(
            spec,
            (signal) {
              if (active) controller.add(signal);
            },
            (error) {
              if (active) controller.addError(error);
            },
          );
        } catch (_) {
          controller.addError(
            const AppFailure('Live updates could not start.'),
          );
        }
      },
      onCancel: () async {
        active = false;
        await close?.call();
      },
    );
    return controller.stream;
  }
}

final realtimeGatewayProvider = Provider<RealtimeGateway>(
  (ref) => RealtimeGateway(
    SupabaseChangefeedTransport(ref.watch(supabaseClientProvider)),
  ),
);
