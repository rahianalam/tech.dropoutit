import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api.dart';

final apiProvider = Provider<Api>((ref) => Api());

class Me {
  Me(this.json);
  final Map<String, dynamic> json;
  String get id => json['id'] as String;
  String get name => json['name'] as String;
  List<String> get roles => (json['roles'] as List).cast<String>();
  bool get isAdmin => roles.contains('ADMIN');
  bool get isTeacher => roles.contains('TEACHER');
  bool get isEmployer => roles.contains('EMPLOYER');
  bool get isSeeker => roles.contains('JOB_SEEKER');
}

class AuthState {
  const AuthState({this.me, this.ready = false});
  final Me? me;
  final bool ready;
  bool get loggedIn => me != null;
}

final authProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);

class AuthController extends Notifier<AuthState> {
  Api get _api => ref.read(apiProvider);

  @override
  AuthState build() {
    _api.onSessionExpired = () => state = const AuthState(ready: true);
    _restore();
    return const AuthState();
  }

  Future<void> _restore() async {
    if (await _api.restore()) {
      try {
        return await reload();
      } catch (_) {}
    }
    state = const AuthState(ready: true);
  }

  Future<void> reload() async {
    final me = await _api.get<Map<String, dynamic>>('/auth/me');
    state = AuthState(me: Me(me), ready: true);
  }

  Future<void> login(String identifier, String password) async {
    await _api.saveTokens(await _api.post('/auth/login', {'identifier': identifier, 'password': password}));
    await reload();
  }

  Future<void> register({required String name, required String identifier, required String password}) async {
    final body = {
      'name': name,
      'password': password,
      if (identifier.contains('@')) 'email': identifier else 'phone': identifier,
    };
    await _api.saveTokens(await _api.post('/auth/register', body));
    await reload();
  }

  /// Runs while still signed in, e.g. to unregister this phone from push.
  Future<void> Function()? beforeLogout;

  Future<void> logout() async {
    try {
      await beforeLogout?.call();
    } catch (_) {}
    await _api.clear();
    state = const AuthState(ready: true);
  }
}
