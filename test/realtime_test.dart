import 'package:cafeflow/core/errors/app_failure.dart';
import 'package:cafeflow/core/services/realtime_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeTransport implements ChangefeedTransport {
  int opened = 0;
  int closed = 0;
  late void Function(RealtimeSignal) signal;
  late void Function(AppFailure) error;
  @override
  CloseSubscription open(
    ChangefeedSpec spec,
    void Function(RealtimeSignal) onSignal,
    void Function(AppFailure) onError,
  ) {
    opened++;
    signal = onSignal;
    error = onError;
    return () async {
      closed++;
    };
  }
}

void main() {
  test(
    'subscription is lazy and removed exactly once on cancellation',
    () async {
      final transport = FakeTransport();
      final stream = RealtimeGateway(transport)
          .watch(const ChangefeedSpec(table: 'test_only'));
      expect(transport.opened, 0);
      final subscription = stream.listen((_) {});
      expect(transport.opened, 1);
      await subscription.cancel();
      await subscription.cancel();
      expect(transport.closed, 1);
      // Late callbacks after disposal must be harmless.
      transport.signal(RealtimeSignal.changed);
      transport.error(const AppFailure('late callback'));
    },
  );
  test(
    'changes and reconnect signals are forwarded, failures are visible',
    () async {
      final transport = FakeTransport();
      final events = <RealtimeSignal>[];
      final errors = <Object>[];
      final subscription = RealtimeGateway(transport)
          .watch(const ChangefeedSpec(table: 'test_only'))
          .listen(events.add, onError: errors.add);
      transport.signal(RealtimeSignal.subscribed);
      transport.signal(RealtimeSignal.changed);
      transport.error(const AppFailure('unavailable'));
      transport.signal(RealtimeSignal.subscribed);
      await Future<void>.delayed(Duration.zero);
      expect(events, [
        RealtimeSignal.subscribed,
        RealtimeSignal.changed,
        RealtimeSignal.subscribed,
      ]);
      expect(errors.single, isA<AppFailure>());
      await subscription.cancel();
    },
  );
}
