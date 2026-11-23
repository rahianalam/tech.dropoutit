import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth.dart';

/// Firebase settings come from --dart-define, so the app builds and runs without
/// any Firebase files; push simply stays off until these are set.
const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
const _senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
const _androidAppId = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
const _iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');

bool get pushConfigured {
  if (kIsWeb || _projectId.isEmpty || _apiKey.isEmpty || _senderId.isEmpty) return false;
  return defaultTargetPlatform == TargetPlatform.iOS ? _iosAppId.isNotEmpty : _androidAppId.isNotEmpty;
}

/// Registers this phone's push token for the signed-in user, and removes it on logout.
final pushProvider = Provider<Push>((ref) {
  final push = Push(ref);
  ref.read(authProvider.notifier).beforeLogout = push.forget;
  ref.listen(authProvider.select((a) => a.me?.id), (_, now) {
    if (now != null) push.register();
  }, fireImmediately: true);
  return push;
});

class Push {
  Push(this.ref);
  final Ref ref;
  String? _token;
  bool _started = false;

  Future<bool> _init() async {
    if (!pushConfigured) return false;
    if (!_started) {
      _started = true;
      await Firebase.initializeApp(
        options: FirebaseOptions(
          apiKey: _apiKey,
          appId: defaultTargetPlatform == TargetPlatform.iOS ? _iosAppId : _androidAppId,
          messagingSenderId: _senderId,
          projectId: _projectId,
        ),
      );
      // Registration tokens still work with the FCM HTTP v1 API the server uses;
      // move to register()/onRegistered when the server switches to installation IDs.
      // ignore: deprecated_member_use
      FirebaseMessaging.instance.onTokenRefresh.listen((t) => _send(t));
    }
    return true;
  }

  Future<void> register() async {
    try {
      if (!await _init()) return;
      final perm = await FirebaseMessaging.instance.requestPermission();
      if (perm.authorizationStatus == AuthorizationStatus.denied) return;
      // ignore: deprecated_member_use
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _send(token);
    } catch (e) {
      debugPrint('push: $e'); // push is best-effort; the in-app list still works
    }
  }

  Future<void> _send(String token) async {
    _token = token;
    await ref.read(apiProvider).post('/me/devices', {
      'token': token,
      'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'IOS' : 'ANDROID',
    });
  }

  /// Called before logout, while the request is still authorised.
  Future<void> forget() async {
    final token = _token;
    _token = null;
    if (token == null) return;
    await ref.read(apiProvider).delete('/me/devices/${Uri.encodeComponent(token)}');
  }
}
