import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/app_theme.dart';
import '../services/firestore_service.dart';
import '../widgets/unified_app_bar.dart';
import '../widgets/admin_support_badge.dart';
import 'about_app_page.dart';
import 'contact_us_page.dart';
import 'terms_conditions_page.dart';
import 'help_faq_page.dart';
import 'live_chat_page.dart';
import 'request_ad_page.dart';

/// More / Settings hub: About, Contact, Terms, FAQ, Live Chat, Share App.
class MorePage extends StatefulWidget {
  const MorePage({super.key});

  @override
  State<MorePage> createState() => _MorePageState();
}

class _MorePageState extends State<MorePage> {
  String _version = '—';
  String _buildNumber = '—';
  bool _isAdmin = false;

  static const String _appStoreUrl = 'https://apps.apple.com/app/id123456789'; // Placeholder
  static const String _shareText = 'Check out M Auction – premium auctions.';

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _loadAdminStatus();
  }

  Future<void> _loadAdminStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final doc = await FirestoreService().getUser(user.uid);
    final data = doc.data() as Map<String, dynamic>?;
    final role = data?['role'] as String?;
    if (mounted) setState(() => _isAdmin = role == 'admin');
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _version = info.version;
          _buildNumber = info.buildNumber;
        });
      }
    } catch (_) {}
  }

  Future<void> _shareApp(BuildContext context) async {
    const shareContent = '$_shareText $_appStoreUrl';
    try {
      await Share.share(shareContent, subject: 'M Auction');
    } catch (_) {
      if (!context.mounted) return;
      try {
        await Clipboard.setData(const ClipboardData(text: shareContent));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Link copied to clipboard'),
              backgroundColor: AppTheme.success,
            ),
          );
        }
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Share not available on this device')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: const UnifiedAppBar(
        title: 'More',
        actions: [AdminSupportBadge()],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          _MoreTile(
            icon: Icons.info_outline,
            title: 'About App',
            subtitle: 'Overview, vision & version',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AboutAppPage()),
            ),
          ),
          const SizedBox(height: 12),
          _MoreTile(
            icon: Icons.contact_support_outlined,
            title: 'Contact Us',
            subtitle: 'Email & contact form',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ContactUsPage()),
            ),
          ),
          const SizedBox(height: 12),
          _MoreTile(
            icon: Icons.description_outlined,
            title: 'Terms & Conditions',
            subtitle: 'Legal terms',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TermsConditionsPage()),
            ),
          ),
          const SizedBox(height: 12),
          _MoreTile(
            icon: Icons.help_outline,
            title: 'Help & FAQ',
            subtitle: 'Frequently asked questions',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HelpFaqPage()),
            ),
          ),
          const SizedBox(height: 12),
          _MoreTileWithSupportBadge(
            icon: Icons.chat_bubble_outline,
            title: 'Live Chat',
            subtitle: 'Chat with support',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LiveChatPage()),
            ),
          ),
          if (!_isAdmin) ...[
            const SizedBox(height: 12),
            _MoreTile(
              icon: Icons.campaign_outlined,
              title: 'Request an Ad',
              subtitle: 'Partner advertising',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RequestAdPage()),
              ),
            ),
          ],
          const SizedBox(height: 12),
          _MoreTile(
            icon: Icons.share_outlined,
            title: 'Share App',
            subtitle: 'Share with friends',
            onTap: () => _shareApp(context),
          ),
          const SizedBox(height: 28),
          Center(
            child: Text(
              'Version $_version ($_buildNumber)',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _MoreTileWithSupportBadge extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MoreTileWithSupportBadge({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return StreamBuilder<DocumentSnapshot>(
      stream: user != null
          ? FirebaseFirestore.instance
              .collection('support_threads')
              .doc(user.uid)
              .snapshots()
          : Stream<DocumentSnapshot>.empty(),
      builder: (context, snap) {
        final hasUnread = user != null &&
            snap.hasData &&
            snap.data!.exists &&
            _isUnread(snap.data!.data());
        return _MoreTile(
          icon: icon,
          title: title,
          subtitle: subtitle,
          onTap: onTap,
          showBadge: hasUnread,
        );
      },
    );
  }

  static bool _isUnread(Object? data) {
    if (data == null || data is! Map<String, dynamic>) return false;
    final lastAdmin = data['lastAdminMessageAt'];
    if (lastAdmin == null) return false;
    final lastRead = data['lastUserReadAt'];
    if (lastRead == null) return true;
    return lastAdmin is Timestamp &&
        lastRead is Timestamp &&
        lastAdmin.compareTo(lastRead) > 0;
  }
}

class _MoreTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool showBadge;

  const _MoreTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.showBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, size: 24, color: AppTheme.primaryBlue),
                  if (showBadge)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 22, color: AppTheme.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
