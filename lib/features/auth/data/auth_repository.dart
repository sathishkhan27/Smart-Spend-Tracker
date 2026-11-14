import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/errors/failures.dart';

class AuthRepository {
  AuthRepository(this._auth);
  final FirebaseAuth _auth;

  Stream<User?> authStateChanges() => _auth.userChanges();
  User? get currentUser => _auth.currentUser;

  Future<User> register({required String name, required String email, required String password}) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
      final user = cred.user!;
      await user.updateDisplayName(name.trim());
      await user.sendEmailVerification();
      await user.reload();
      return _auth.currentUser!;
    } catch (e) {
      throw ErrorHandler.map(e);
    }
  }

  Future<User> login({required String email, required String password}) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
      return cred.user!;
    } catch (e) {
      throw ErrorHandler.map(e);
    }
  }

  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } catch (e) {
      throw ErrorHandler.map(e);
    }
  }

  Future<void> resendVerification() async {
    try {
      await _auth.currentUser?.sendEmailVerification();
    } catch (e) {
      throw ErrorHandler.map(e);
    }
  }

  /// Reloads the user and returns whether the email is now verified.
  Future<bool> refreshVerification() async {
    await _auth.currentUser?.reload();
    final user = _auth.currentUser;
    if (user != null && user.emailVerified) {
      // Refresh ID token so Firestore rules see email_verified = true.
      await user.getIdToken(true);
    }
    return user?.emailVerified ?? false;
  }

  Future<void> updateDisplayName(String name) async => _auth.currentUser?.updateDisplayName(name);

  Future<void> signOut() => _auth.signOut();
}
