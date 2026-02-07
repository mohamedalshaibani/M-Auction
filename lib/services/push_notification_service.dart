import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/platform_io.dart' if (dart.library.html) '../utils/platform_stub.dart' as platform_impl;

/// Handles FCM token: request permission, save to users/{uid}, refresh, and admin topic subscription.
class PushNotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String _adminsTopic = 'admins';

  /// Call on app start and after login. Requests permission, gets token, saves to Firestore, subscribes admins to "admins".
  Future<void> initialize() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      if (settings.authorizationStatus == AuthorizationStatus.notDetermined) {
        // Try again or accept provisional
        await _messaging.requestPermission(provisional: true);
      }

      final token = await _messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await _saveTokenToFirestore(user.uid, token);
      }

      _messaging.onTokenRefresh.listen((newToken) {
        if (FirebaseAuth.instance.currentUser != null && newToken.isNotEmpty) {
          _saveTokenToFirestore(FirebaseAuth.instance.currentUser!.uid, newToken);
        }
      });

      final isAdmin = await _isAdmin(user.uid);
      if (isAdmin) {
        await _messaging.subscribeToTopic(_adminsTopic);
      } else {
        await _messaging.unsubscribeFromTopic(_adminsTopic);
      }
    } catch (e) {
      // Permission or token errors (e.g. simulator without APNs)
      assert(() {
        // ignore: avoid_print
        print('PushNotificationService.initialize: $e');
        return true;
      }());
    }
  }

  String get _platform => platform_impl.platform;

  Future<bool> _isAdmin(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    final role = doc.data()?['role'] as String?;
    return role == 'admin';
  }

  Future<void> _saveTokenToFirestore(String uid, String token) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        'fcmToken': token,
        'platform': _platform,
        'tokenUpdatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // User doc may not exist yet (e.g. before profile created); token will be set on next init.
    }
  }
}
