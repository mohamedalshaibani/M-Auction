import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/app_theme.dart';
import 'about_app_page.dart';
import 'contact_us_page.dart';
import 'terms_conditions_page.dart';
import 'help_faq_page.dart';
import 'live_chat_page.dart';
import 'request_ad_page.dart';

/// More / Settings hub: About, Contact, Terms, FAQ, Live Chat, Share App.
class MorePage extends StatelessWidget {
  const MorePage({super.key});

  static const String _appStoreUrl = 'https://apps.apple.com/app/id123456789'; // Placeholder
  static const String _shareText = 'Check out M Auction – premium auctions.';

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
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'More',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
        ),
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
          _MoreTile(
            icon: Icons.chat_bubble_outline,
            title: 'Live Chat',
            subtitle: 'Chat with support',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LiveChatPage()),
            ),
          ),
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
          const SizedBox(height: 12),
          _MoreTile(
            icon: Icons.share_outlined,
            title: 'Share App',
            subtitle: 'Share with friends',
            onTap: () => _shareApp(context),
          ),
        ],
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MoreTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
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
              Icon(icon, size: 24, color: AppTheme.primaryBlue),
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
