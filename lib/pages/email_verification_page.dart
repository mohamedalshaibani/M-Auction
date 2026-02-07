import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_theme.dart';
import '../widgets/unified_app_bar.dart';
import '../services/listing_eligibility_service.dart';
import 'listing_flow_gate_page.dart';

/// Email verification step: send link via Firebase [User.verifyBeforeUpdateEmail].
/// Link is single-use and time-limited; users can request a new link if they see "expired or already used".
/// When [returnAfterVerify] is true (e.g. from bidding flow), pop after verification instead of pushing ListingFlowGatePage.
class EmailVerificationPage extends StatefulWidget {
  const EmailVerificationPage({
    super.key,
    this.returnAfterVerify = false,
    this.returnAuctionId,
    this.returnToListing = false,
  });
  final bool returnAfterVerify;
  final String? returnAuctionId;
  final bool returnToListing;

  @override
  State<EmailVerificationPage> createState() => _EmailVerificationPageState();
}

class _EmailVerificationPageState extends State<EmailVerificationPage> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _eligibility = ListingEligibilityService();
  bool _sending = false;
  bool _sent = false;
  bool _resendSuccess = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prefillEmail();
  }

  Future<void> _prefillEmail() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user?.email != null && user!.email!.trim().isNotEmpty) {
      _emailController.text = user.email!.trim();
      if (user.emailVerified) {
        if (mounted) setState(() => _sent = true);
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendVerification({bool isResend = false}) async {
    if (!_formKey.currentState!.validate()) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _error = 'Not signed in');
      return;
    }
    final email = _emailController.text.trim();
    setState(() {
      _sending = true;
      _error = null;
      if (!isResend) _resendSuccess = false;
    });
    try {
      await user.verifyBeforeUpdateEmail(email);
      await _eligibility.setEmail(user.uid, email, verified: false);
      if (mounted) {
        setState(() {
          _sending = false;
          _sent = true;
          _error = null;
          _resendSuccess = isResend;
        });
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        switch (e.code) {
          case 'requires-recent-login':
            setState(() => _error =
                'For security, please sign out and sign in again, then try verifying your email.');
            return;
          case 'too-many-requests':
            setState(() => _error =
                'Too many attempts. Please wait a few minutes before requesting another link.');
            return;
          default:
            setState(() => _error = e.message ?? e.code);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = 'Something went wrong. Please try again.';
        });
      }
    }
  }

  Future<void> _checkVerifiedAndContinue() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _error = null);
    try {
      // Reload user so we get the latest emailVerified from the server (set when they clicked the link).
      await user.reload();
      // Use the same user reference; reload() updates it in place.
      User? updated = FirebaseAuth.instance.currentUser;
      if (updated?.emailVerified != true) {
        // Server can take a moment to propagate; retry once after a short delay.
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        await user.reload();
        updated = FirebaseAuth.instance.currentUser;
      }
      if (updated?.emailVerified == true) {
        await _eligibility.setEmailVerified(user.uid);
        if (!mounted) return;
        if (widget.returnAfterVerify) {
          if (widget.returnAuctionId != null) {
            Navigator.of(context).popUntil((r) => r.isFirst);
            Navigator.of(context).pushNamed(
                '/auctionDetail?auctionId=${widget.returnAuctionId}');
          } else {
            Navigator.of(context).pop();
          }
        } else {
          Navigator.of(context).pop();
          Navigator.of(context).push(
            MaterialPageRoute<void>(
                builder: (_) => const ListingFlowGatePage()),
          );
        }
      } else {
        if (mounted) {
          setState(() => _error =
              'Not verified yet. Open the link in your email (check Spam/Junk), then tap Continue. If the link says "expired or already used", tap "Send new link" below.');
        }
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          switch (e.code) {
            case 'requires-recent-login':
              _error = 'For security, please sign out and sign in again, then tap Continue.';
              break;
            case 'network-request-failed':
              _error = 'No connection. Check your network and try again.';
              break;
            default:
              _error = e.message ?? 'Could not check verification. Please try again.';
          }
        });
      }
      debugPrint('Email verification check (Auth): ${e.code} - ${e.message}');
    } catch (e, stack) {
      debugPrint('Email verification check error: $e');
      debugPrint(stack.toString());
      if (mounted) {
        setState(() => _error = 'Could not check verification. Please try again.');
      }
    }
  }

  void _onCancel() {
    if (widget.returnAuctionId != null) {
      Navigator.of(context).popUntil(
          (Route<dynamic> r) =>
              r.settings.name?.startsWith('/auctionDetail') == true);
    } else if (widget.returnToListing) {
      Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final showCancel =
        widget.returnAuctionId != null || widget.returnToListing;
    return Scaffold(
      appBar: UnifiedAppBar(
        title: 'Verify Email',
        leading: showCancel
            ? IconButton(icon: const Icon(Icons.close), onPressed: _onCancel)
            : null,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'To list or bid you must add and verify your email address.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppTheme.primaryBlue.withValues(alpha: 0.3)),
                ),
                child: Text(
                  'The verification link is for one-time use and expires after a few days. '
                  'Open the link only once (e.g. copy link and paste in your browser, or use a private/incognito window) so your email provider doesn\'t use it first. '
                  'If you see "expired or already used", tap "Send new link" below. Check Spam or Junk if you don\'t see the email.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textPrimary, height: 1.4),
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _emailController,
                enabled: !_sending,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Enter your email';
                  if (!v.contains('@') || !v.contains('.')) return 'Enter a valid email';
                  return null;
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline, color: AppTheme.error, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _error!,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.error),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              if (!_sent) ...[
                FilledButton(
                  onPressed: _sending ? null : () => _sendVerification(isResend: false),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _sending
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Send verification link'),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.success),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.mark_email_read_outlined,
                              color: AppTheme.success, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Link sent to ${_emailController.text}',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.textPrimary),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Open the link in that email (check Spam/Junk if needed), then tap "I\'ve verified – Continue" below.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textPrimary, height: 1.4),
                      ),
                    ],
                  ),
                ),
                if (_resendSuccess) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle_outline,
                            color: AppTheme.success, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'New link sent. Use the link in the latest email; the previous link no longer works.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppTheme.textPrimary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _checkVerifiedAndContinue,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('I\'ve verified my email – Continue'),
                ),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: _sending
                      ? null
                      : () => _sendVerification(isResend: true),
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 20),
                  label: Text(
                    _sending ? 'Sending…' : 'Link expired or already used? Send new link',
                    style: TextStyle(color: AppTheme.primaryBlue),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
