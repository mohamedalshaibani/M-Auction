import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/profile_avatar.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/unified_app_bar.dart';
import 'listing_flow_gate_page.dart';

class CreateProfilePage extends StatefulWidget {
  const CreateProfilePage({super.key, this.returnAuctionId, this.returnToListing = false});

  final String? returnAuctionId;
  final bool returnToListing;

  @override
  State<CreateProfilePage> createState() => _CreateProfilePageState();
}

class _CreateProfilePageState extends State<CreateProfilePage> {
  final _displayNameController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _firestoreService = FirestoreService();
  bool _isSaving = false;
  String? _errorMessage;
  late String _selectedAvatarId;

  @override
  void initState() {
    super.initState();
    // Suggested avatar: pick one at random on first load (user can change).
    final random = DateTime.now().millisecondsSinceEpoch % kProfileAvatars.length;
    _selectedAvatarId = kProfileAvatars[random].id;
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!mounted) return;

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _errorMessage = 'No user logged in');
      return;
    }

    final displayName = _displayNameController.text.trim();
    final nickname = _nicknameController.text.trim();

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await _firestoreService.createUserAndWallet(
        uid: user.uid,
        displayName: displayName,
        phoneNumber: user.phoneNumber ?? '',
        nickname: nickname.isEmpty ? null : nickname,
        avatarId: _selectedAvatarId,
      );

      if (mounted) {
        if (widget.returnAuctionId != null) {
          Navigator.of(context).popUntil((r) => r.isFirst);
          Navigator.of(context).pushNamed('/auctionDetail?auctionId=${widget.returnAuctionId}');
        } else if (widget.returnToListing) {
          Navigator.of(context).popUntil((r) => r.isFirst);
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const ListingFlowGatePage()),
          );
        } else {
          Navigator.of(context).pushReplacementNamed('/home');
        }
      }
    } catch (e, stackTrace) {
      if (mounted) {
        debugPrint('Create profile error: $e');
        debugPrint(stackTrace.toString());
        setState(() {
          _errorMessage = e is FirebaseException
              ? (e.message ?? 'Error creating profile. Please try again.')
              : 'Error creating profile. Please try again.';
          _isSaving = false;
        });
      }
    }
  }

  void _onCancel() {
    if (widget.returnAuctionId != null) {
      Navigator.of(context).popUntil(
          (Route<dynamic> r) => r.settings.name?.startsWith('/auctionDetail') == true);
    } else if (widget.returnToListing) {
      Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final showCancel = widget.returnAuctionId != null || widget.returnToListing;
    return Scaffold(
      appBar: showCancel
          ? UnifiedAppBar(
              title: 'Create Profile',
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: _onCancel,
              ),
            )
          : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Logo
                      Center(
                        child: Image.asset(
                          'assets/branding/logo_light.png',
                          width: 212,
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Header
                      Text(
                        'Create Your Profile',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Let\'s set up your account',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      
                      // Full name (private, internal only)
                      TextFormField(
                        controller: _displayNameController,
                        enabled: !_isSaving,
                        decoration: const InputDecoration(
                          labelText: 'Your name',
                          hintText: 'e.g. Ahmed',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter your name';
                          }
                          if (value.trim().length < 2) {
                            return 'Name must be at least 2 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your real name is required for legal and support purposes only.\nIt will never be shown publicly.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                      ),
                      const SizedBox(height: 20),

                      // Public nickname (optional)
                      TextFormField(
                        controller: _nicknameController,
                        enabled: !_isSaving,
                        decoration: const InputDecoration(
                          labelText: 'Public nickname (optional)',
                          hintText: 'e.g. Collector — shown in bids & wins',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Avatar
                      Row(
                        children: [
                          Text(
                            'Choose an avatar',
                            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                  color: AppTheme.textPrimary,
                                ),
                          ),
                          const SizedBox(width: 12),
                          TextButton.icon(
                            onPressed: () {
                              final random = DateTime.now().millisecondsSinceEpoch % kProfileAvatars.length;
                              setState(() => _selectedAvatarId = kProfileAvatars[random].id);
                            },
                            icon: const Icon(Icons.shuffle, size: 18),
                            label: const Text('Random avatar'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: kProfileAvatars.map((a) {
                          final selected = a.id == _selectedAvatarId;
                          return GestureDetector(
                            onTap: () => setState(() => _selectedAvatarId = a.id),
                            child: Container(
                              width: 48,
                              height: 48,
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
                                size: 24,
                                color: selected ? AppTheme.primaryBlue : AppTheme.textSecondary,
                              ),
                            ),
                          );
                        }).toList(),
                      ),

                      // Error message
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppTheme.error.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: AppTheme.error,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: AppTheme.error,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      
                      const SizedBox(height: 32),
                      
                      // Continue button
                      ElevatedButton(
                        onPressed: _isSaving ? null : _saveProfile,
                        child: _isSaving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Text('Continue'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
