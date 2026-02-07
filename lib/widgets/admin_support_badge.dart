import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/support_unread.dart';
import '../pages/admin_panel_page.dart';

/// Support icon with unread badge for admins. Shows in app bar; navigates to Admin Panel Support tab.
class AdminSupportBadge extends StatefulWidget {
  const AdminSupportBadge({super.key});

  @override
  State<AdminSupportBadge> createState() => _AdminSupportBadgeState();
}

class _AdminSupportBadgeState extends State<AdminSupportBadge> {
  final _firestore = FirebaseFirestore.instance;

  int _countUnread(List<QueryDocumentSnapshot> docs) {
    int count = 0;
    for (final doc in docs) {
      final d = doc.data() as Map<String, dynamic>?;
      if (adminHasUnread(d)) count++;
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();
    return StreamBuilder<DocumentSnapshot>(
      stream: _firestore.collection('users').doc(user.uid).snapshots(),
      builder: (context, userSnap) {
        final userData = userSnap.data?.data() as Map<String, dynamic>?;
        final role = userData?['role'] as String?;
        if (role != 'admin') return const SizedBox.shrink();
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
