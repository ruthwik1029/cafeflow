/// Safe user-facing failure; raw backend errors must not reach the UI.
class AppFailure implements Exception {
  const AppFailure(this.message);
  final String message;
  @override
  String toString() => message;
}
