import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_service.dart';
import '../pages/admin_panel_page.dart';

/// Support icon with unread badge for admins. Shows in app bar; navigates to Admin Panel Support tab.
class AdminSupportBadge extends StatefulWidget {
  const AdminSupportBadge({super.key});

  @override
  State<AdminSupportBadge> createState() => _AdminSupportBadgeState();
}

class _AdminSupportBadgeState extends State<AdminSupportBadge> {
  final _firestore = FirebaseFirestore.instance;
  final _firestoreService = FirestoreService();

  Future<bool> _isAdmin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final doc = await _firestoreService.getUser(user.uid);
    final data = doc.data() as Map<String, dynamic>?;
    final role = data?['role'] as String?;
    return role == 'admin';
  }

  int _countUnread(List<QueryDocumentSnapshot> docs) {
    int count = 0;
    for (final doc in docs) {
      final d = doc.data() as Map<String, dynamic>? ?? {};
      final lastUser = d['lastMessageFromUserAt'] as Timestamp?;
      final lastRead = d['lastAdminReadAt'] as Timestamp?;
      if (lastUser != null && (lastRead == null || lastUser.compareTo(lastRead) > 0)) {
        count++;
      }
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _isAdmin(),
      builder: (context, adminSnap) {
        if (!adminSnap.hasData || adminSnap.data != true) {
          return const SizedBox.shrink();
        }
        return StreamBuilder<QuerySnapshot>(
          stream: _firestore.collection('support_threads').snapshots(),
          builder: (context, snapshot) {
            final count = snapshot.hasData ? _countUnread(snapshot.data!.docs) : 0;
            return IconButton(
              icon: Badge(
                isLabelVisible: count > 0,
                label: count > 99 ? const Text('99+') : Text('$count'),
                child: const Icon(Icons.support_agent_outlined),
              ),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminPanelPage(initialTabIndex: 5),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
