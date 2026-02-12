import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../models/profile_avatar.dart';
import '../services/firestore_service.dart';
import '../widgets/guest_sign_in_prompt.dart';
import '../widgets/header_logo.dart';
import '../widgets/unified_app_bar.dart';
import '../widgets/admin_support_badge.dart';
import 'create_profile_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, this.onNotNow});

  final VoidCallback? onNotNow;

  Future<void> _signOut(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      Navigator.of(context).pushReplacementNamed('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        backgroundColor: AppTheme.backgroundLight,
        appBar: const UnifiedAppBar(
          title: 'Profile',
          actions: [AdminSupportBadge()],
        ),
        body: GuestSignInPrompt(
          title: 'Profile',
          icon: Icons.person_outline,
          onNotNow: onNotNow,
          onContinue: () => Navigator.of(context).pushNamed('/login'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: UnifiedAppBar(
        titleWidget: Row(
          children: [
            const HeaderLogo(),
            const SizedBox(width: 12),
            Text(
              'Profile',
              style: Theme.of(context).appBarTheme.titleTextStyle?.copyWith(
                    color: Theme.of(context).appBarTheme.foregroundColor ?? AppTheme.textPrimary,
                  ),
            ),
          ],
        ),
        actions: const [AdminSupportBadge()],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ErrorState(
              message: 'Error loading profile',
              onRetry: () {},
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return _MissingProfileState(
              onCompleteSetup: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => const CreateProfilePage(),
                  ),
                );
              },
            );
          }

          final userData = snapshot.data!.data() as Map<String, dynamic>? ?? {};
          return _ProfileBody(
            user: user,
            userData: userData,
            onSignOut: () => _signOut(context),
          );
        },
      ),
    );
  }
}

class _ProfileBody extends StatelessWidget {
  const _ProfileBody({
    required this.user,
    required this.userData,
    required this.onSignOut,
  });

  final User user;
  final Map<String, dynamic> userData;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final displayName = userData['displayName'] as String? ?? 'User';
    final nickname = userData['nickname'] as String?;
    final publicName = getPublicDisplayName(userData, fallback: displayName);
    final avatarId = userData['avatarId'] as String? ?? kDefaultAvatarId;
    final avatar = getProfileAvatarById(avatarId);
    final kycStatus = userData['kycStatus'] as String? ?? 'not_submitted';
    final role = userData['role'] as String?;
    final vipDepositWaived = userData['vipDepositWaived'] as bool? ?? false;
    final email = userData['email'] as String? ?? user.email;
    final emailVerified = userData['emailVerified'] as bool? ?? user.emailVerified;
    final phoneNumber = user.phoneNumber ?? userData['phoneNumber'] as String?;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // —— Identity hero (who you are on the platform) ——
          _IdentityCard(
            avatar: avatar,
            publicName: publicName,
            hasNickname: nickname != null && nickname.trim().isNotEmpty,
            vipDepositWaived: vipDepositWaived,
            userData: userData,
          ),
          const SizedBox(height: 16),

          // —— Verification (trust & clarity) ——
          _VerificationSection(
            kycStatus: kycStatus,
            emailVerified: emailVerified == true,
            email: email,
            phoneNumber: phoneNumber,
          ),
          const SizedBox(height: 16),

          // —— My activity (profile-related links; no Wallet – it's in bottom nav) ——
          _SectionHeader(title: 'My activity'),
          const SizedBox(height: 6),
          _ProfileCard(
            children: [
              _ProfileMenuItem(
                icon: Icons.list_outlined,
                label: 'My Auctions',
                subtitle: 'Listings you created',
                onTap: () => Navigator.of(context).pushNamed('/sellerMyAuctions'),
              ),
              const Divider(height: 1),
              _ProfileMenuItem(
                icon: Icons.emoji_events_outlined,
                label: 'My Wins',
                subtitle: 'Auctions you won',
                onTap: () => Navigator.of(context).pushNamed('/myWins'),
              ),
            ],
          ),
          if (role == 'admin' || role == 'super_admin') ...[
            const SizedBox(height: 16),
            _SectionHeader(title: 'Administration'),
            const SizedBox(height: 6),
            _ProfileCard(
              children: [
                _ProfileMenuItem(
                  icon: Icons.admin_panel_settings_outlined,
                  label: 'Admin Panel',
                  subtitle: 'Manage platform',
                  onTap: () => Navigator.of(context).pushNamed('/adminPanel'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),

          // —— Sign out ——
          OutlinedButton.icon(
            onPressed: onSignOut,
            icon: const Icon(Icons.logout, size: 20),
            label: const Text('Sign Out'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              side: const BorderSide(color: AppTheme.border),
              foregroundColor: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _IdentityCard extends StatefulWidget {
  const _IdentityCard({
    required this.avatar,
    required this.publicName,
    required this.hasNickname,
    required this.vipDepositWaived,
    required this.userData,
  });

  final ProfileAvatar avatar;
  final String publicName;
  final bool hasNickname;
  final bool vipDepositWaived;
  final Map<String, dynamic> userData;

  @override
  State<_IdentityCard> createState() => _IdentityCardState();
}

class _IdentityCardState extends State<_IdentityCard> {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryBlue.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Avatar (tappable to change) — ~12% smaller
          GestureDetector(
            onTap: () => _showAvatarPicker(context),
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: AppTheme.primaryLight.withValues(alpha: 0.4),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.25),
                  width: 2,
                ),
              ),
              child: Icon(
                widget.avatar.icon,
                size: 38,
                color: AppTheme.primaryBlue,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap to change avatar',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppTheme.textTertiary,
                ),
          ),
          const SizedBox(height: 8),
          // Public name (editable) — same row, less vertical gap
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  widget.publicName,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                onPressed: () => _showNicknameEditor(context),
                icon: const Icon(Icons.edit_outlined, size: 18),
                style: IconButton.styleFrom(
                  foregroundColor: AppTheme.primaryBlue,
                  padding: const EdgeInsets.all(2),
                  minimumSize: const Size(32, 32),
                ),
              ),
            ],
          ),
          if (!widget.hasNickname)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Add a nickname to appear in bids & wins',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textTertiary,
                    ),
              ),
            ),
          if (widget.vipDepositWaived) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified_user_outlined, size: 16, color: AppTheme.success),
                  const SizedBox(width: 6),
                  Text(
                    'VIP Member',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: AppTheme.success,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'Your identity on M Auction',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSecondary,
                ),
          ),
        ],
      ),
    );
  }

  void _showAvatarPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _AvatarPickerSheet(
        currentAvatarId: getProfileAvatarById(widget.userData['avatarId'] as String?).id,
        onSelect: (id) async {
          Navigator.of(ctx).pop();
          await FirestoreService().updateUserProfile(
            uid: FirebaseAuth.instance.currentUser!.uid,
            avatarId: id,
          );
        },
      ),
    );
  }

  void _showNicknameEditor(BuildContext context) {
    final controller = TextEditingController(text: widget.publicName);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Public nickname',
              style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Shown in bids and wins. Your real name stays private.',
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'e.g. Collector',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
              onSubmitted: (_) => _saveNickname(ctx, controller.text.trim()),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => _saveNickname(ctx, controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveNickname(BuildContext context, String value) async {
    Navigator.of(context).pop();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirestoreService().updateUserProfile(uid: uid, nickname: value.isEmpty ? null : value);
  }
}

class _AvatarPickerSheet extends StatelessWidget {
  const _AvatarPickerSheet({
    required this.currentAvatarId,
    required this.onSelect,
  });

  final String currentAvatarId;
  final void Function(String) onSelect;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose your avatar',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'This appears next to your nickname in bids and activity.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: kProfileAvatars.map((a) {
                final selected = a.id == currentAvatarId;
                return GestureDetector(
                  onTap: () => onSelect(a.id),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: selected
                          ? AppTheme.primaryBlue.withValues(alpha: 0.15)
                          : AppTheme.primaryLight.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? AppTheme.primaryBlue : AppTheme.border,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Icon(
                      a.icon,
                      size: 28,
                      color: selected ? AppTheme.primaryBlue : AppTheme.textSecondary,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _VerificationSection extends StatelessWidget {
  const _VerificationSection({
    required this.kycStatus,
    required this.emailVerified,
    this.email,
    this.phoneNumber,
  });

  final String kycStatus;
  final bool emailVerified;
  final String? email;
  final String? phoneNumber;

  @override
  Widget build(BuildContext context) {
    final hasPhone = phoneNumber != null && phoneNumber!.trim().isNotEmpty;
    final phoneValue = hasPhone ? phoneNumber!.trim() : null;
    final emailValue = (email != null && email!.trim().isNotEmpty) ? email!.trim() : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: 'Verification'),
        const SizedBox(height: 4),
        Text(
          'Verification unlocks bidding and listing features.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.textSecondary,
                height: 1.35,
              ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            children: [
              _VerificationRow(
                icon: hasPhone ? Icons.check_circle : Icons.phone_outlined,
                label: 'Phone number',
                value: phoneValue,
                status: hasPhone ? 'Verified' : 'Not added',
                statusColor: hasPhone ? AppTheme.success : AppTheme.textTertiary,
                onTap: !hasPhone ? () => Navigator.of(context).pushNamed('/login') : null,
                actionLabel: !hasPhone ? 'Add' : null,
              ),
              const Divider(height: 12),
              _VerificationRow(
                icon: emailVerified ? Icons.check_circle : Icons.mail_outline,
                label: 'Email',
                value: emailValue,
                status: emailVerified ? 'Verified' : 'Not verified',
                statusColor: emailVerified ? AppTheme.success : AppTheme.textTertiary,
                onTap: !emailVerified
                    ? () => Navigator.of(context).pushNamed('/emailVerification')
                    : null,
                actionLabel: emailVerified ? null : 'Verify',
              ),
              const Divider(height: 12),
              _VerificationRow(
                icon: _kycIcon(kycStatus),
                label: 'Identity (KYC)',
                value: null,
                status: _kycStatusText(kycStatus),
                statusColor: _kycColor(kycStatus),
                onTap: (kycStatus == 'not_submitted' || kycStatus == 'rejected')
                    ? () => Navigator.of(context).pushNamed('/kyc')
                    : null,
                actionLabel: (kycStatus == 'not_submitted' || kycStatus == 'rejected')
                    ? 'Verify'
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  IconData _kycIcon(String status) {
    switch (status) {
      case 'approved':
        return Icons.check_circle;
      case 'pending':
      case 'submitted':
        return Icons.pending;
      case 'rejected':
        return Icons.cancel;
      default:
        return Icons.badge_outlined;
    }
  }

  Color _kycColor(String status) {
    switch (status) {
      case 'approved':
        return AppTheme.success;
      case 'pending':
      case 'submitted':
        return AppTheme.warning;
      case 'rejected':
        return AppTheme.error;
      default:
        return AppTheme.textTertiary;
    }
  }

  String _kycStatusText(String status) {
    switch (status) {
      case 'approved':
        return 'Verified';
      case 'pending':
      case 'submitted':
        return 'Under review';
      case 'rejected':
        return 'Rejected';
      default:
        return 'Not verified';
    }
  }
}

class _VerificationRow extends StatelessWidget {
  const _VerificationRow({
    required this.icon,
    required this.label,
    required this.status,
    required this.statusColor,
    this.value,
    this.onTap,
    this.actionLabel,
  });

  final IconData icon;
  final String label;
  final String status;
  final Color statusColor;
  final String? value;
  final VoidCallback? onTap;
  final String? actionLabel;

  static const double _valueLineHeight = 18;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 20, color: statusColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                      ),
                ),
                SizedBox(
                  height: _valueLineHeight,
                  child: value != null && value!.isNotEmpty
                      ? Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            value!,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppTheme.textSecondary,
                                  fontSize: 12,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                Text(
                  status,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                ),
              ],
            ),
          ),
          if (actionLabel != null && onTap != null)
            TextButton(
              onPressed: onTap,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                actionLabel!,
                style: const TextStyle(
                  color: AppTheme.primaryBlue,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
            letterSpacing: 0.5,
          ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(children: children),
    );
  }
}

class _ProfileMenuItem extends StatelessWidget {
  const _ProfileMenuItem({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      dense: true,
      leading: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppTheme.primaryLight.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 20, color: AppTheme.primaryBlue),
      ),
      title: Text(
        label,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textTertiary,
                  ),
            )
          : null,
      trailing: Icon(Icons.chevron_right, size: 20, color: AppTheme.textTertiary),
      onTap: onTap,
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: AppTheme.error),
            const SizedBox(height: 16),
            Text(
              message,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppTheme.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _MissingProfileState extends StatelessWidget {
  const _MissingProfileState({required this.onCompleteSetup});

  final VoidCallback onCompleteSetup;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_outline, size: 64, color: AppTheme.textTertiary),
            const SizedBox(height: 16),
            Text(
              'Profile missing',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Please complete setup',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: onCompleteSetup,
              child: const Text('Complete Setup'),
            ),
          ],
        ),
      ),
    );
  }
}
