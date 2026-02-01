import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../services/listing_eligibility_service.dart';
import 'terms_conditions_page.dart';
import 'sell_create_auction_page.dart';

/// Terms acceptance step in listing flow. User must accept before entering listing details.
class ListingTermsAcceptPage extends StatefulWidget {
  const ListingTermsAcceptPage({super.key});

  @override
  State<ListingTermsAcceptPage> createState() => _ListingTermsAcceptPageState();
}

class _ListingTermsAcceptPageState extends State<ListingTermsAcceptPage> {
  final _eligibility = ListingEligibilityService();
  bool _accepted = false;
  bool _saving = false;
  String? _error;
  String _termsBody = TermsConditionsPage.staticTerms;

  @override
  void initState() {
    super.initState();
    _loadTerms();
  }

  Future<void> _loadTerms() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('content').doc('terms').get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final text = data['text'] as String? ?? data['content'] as String?;
        if (text != null && text.isNotEmpty && mounted) {
          setState(() => _termsBody = text);
        }
      }
    } catch (_) {}
  }

  Future<void> _acceptAndContinue() async {
    if (!_accepted) {
      setState(() => _error = 'You must accept the terms to continue.');
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _error = 'Not signed in.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _eligibility.setTermsAccepted(user.uid);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const SellCreateAuctionPage()),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Auction Terms & Conditions',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Before creating a listing you must read and accept the Auction Terms & Conditions.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Text(
                      _termsBody,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textPrimary,
                            height: 1.6,
                          ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  CheckboxListTile(
                    value: _accepted,
                    onChanged: (v) => setState(() {
                      _accepted = v ?? false;
                      _error = null;
                    }),
                    title: const Text('I have read and accept the Auction Terms & Conditions'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.red, fontSize: 14),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _acceptAndContinue,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Accept and continue to listing'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
