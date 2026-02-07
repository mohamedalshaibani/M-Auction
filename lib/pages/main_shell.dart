import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'home_page.dart';
import 'explore_page.dart';
import 'wallet_page.dart';
import 'profile_page.dart';
import 'more_page.dart';
import '../theme/app_theme.dart';
import '../services/push_notification_service.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    PushNotificationService().initialize();
  }

  List<Widget> get _pages => [
    const HomePage(),
    const ExplorePage(),
    WalletPage(onNotNow: () => setState(() => _currentIndex = 0)),
    ProfilePage(onNotNow: () => setState(() => _currentIndex = 0)),
    const MorePage(),
  ];

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: user == null
          ? _buildNavBar(false)
          : StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('support_threads')
                  .doc(user.uid)
                  .snapshots(),
              builder: (context, snap) {
                final hasUnread = _userHasUnread(snap.data?.data());
                return _buildNavBar(hasUnread);
              },
            ),
    );
  }

  bool _userHasUnread(Object? data) {
    if (data == null || data is! Map<String, dynamic>) return false;
    final lastAdmin = data['lastAdminMessageAt'];
    if (lastAdmin == null) return false;
    final lastRead = data['lastUserReadAt'];
    if (lastRead == null) return true;
    return lastAdmin is Timestamp &&
        lastRead is Timestamp &&
        lastAdmin.compareTo(lastRead) > 0;
  }

  Widget _buildNavBar(bool moreHasUnread) {
    return NavigationBar(
      selectedIndex: _currentIndex,
      onDestinationSelected: (index) {
        setState(() {
          _currentIndex = index;
        });
      },
      backgroundColor: AppTheme.surface,
      indicatorColor: AppTheme.primaryBlue.withValues(alpha: 0.2),
      surfaceTintColor: AppTheme.primaryBlue,
      destinations: [
        const NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: 'Home',
        ),
        const NavigationDestination(
          icon: Icon(Icons.explore_outlined),
          selectedIcon: Icon(Icons.explore),
          label: 'Explore',
        ),
        const NavigationDestination(
          icon: Icon(Icons.account_balance_wallet_outlined),
          selectedIcon: Icon(Icons.account_balance_wallet),
          label: 'Wallet',
        ),
        const NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: 'Profile',
        ),
        NavigationDestination(
          icon: Badge(
            isLabelVisible: moreHasUnread,
            smallSize: 8,
            child: const Icon(Icons.more_horiz),
          ),
          selectedIcon: Badge(
            isLabelVisible: moreHasUnread,
            smallSize: 8,
            child: const Icon(Icons.more_horiz),
          ),
          label: 'More',
        ),
      ],
    );
  }
}
