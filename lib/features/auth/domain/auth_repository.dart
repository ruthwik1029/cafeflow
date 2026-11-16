import 'auth_user.dart';

abstract interface class AuthRepository {
  Future<CafeUser> loginWithEmail(String email, String password);
  Future<CafeUser> loginWithUsername(String username, String password);
  Future<void> logout();
  Stream<CafeUser?> watchAuthState();
  CafeUser? get currentUser;
  Future<CafeUser?> restoreSession();
}
