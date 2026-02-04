import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/contract_service.dart';
import '../theme/app_theme.dart';
import '../widgets/unified_app_bar.dart';

class TermsContractPage extends StatefulWidget {
  final String auctionId;
  final bool isSeller;

  const TermsContractPage({
    super.key,
    required this.auctionId,
    required this.isSeller,
  });

  @override
  State<TermsContractPage> createState() => _TermsContractPageState();
}

class _TermsContractPageState extends State<TermsContractPage> {
  final ContractService _contractService = ContractService();
  bool _agreed = false;
  bool _isAccepting = false;
  String? _error;

  Future<void> _acceptTerms() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _error = 'Not logged in');
      return;
    }

    if (!_agreed) {
      setState(() => _error = 'Please agree to the terms');
      return;
    }

    setState(() {
      _isAccepting = true;
      _error = null;
    });

    try {
      await _contractService.acceptTerms(
        auctionId: widget.auctionId,
        userId: user.uid,
        isSeller: widget.isSeller,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Terms accepted successfully'),
            backgroundColor: AppTheme.success,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() {
        _error = 'Error accepting terms: $e';
        _isAccepting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const UnifiedAppBar(title: 'Sale Agreement'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sale Agreement',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 24),
            const Text(
              'Terms and Conditions',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildTermItem('Platform is an intermediary only'),
            _buildTermItem('No liability on platform for transactions'),
            _buildTermItem('Both parties are responsible for the transaction'),
            _buildTermItem('Disputes handled through platform support'),
            _buildTermItem('Deadlines must be respected as per auction terms'),
            _buildTermItem('Contact information will be released after both parties accept'),
            _buildTermItem('Delivery confirmation required from both parties'),
            _buildTermItem('Deposit refund available after delivery confirmation'),
            const SizedBox(height: 24),
            StreamBuilder<DocumentSnapshot>(
              stream: _contractService.streamContract(widget.auctionId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text('Error: ${snapshot.error}');
                }
                if (!snapshot.hasData || !snapshot.data!.exists) {
                  return const SizedBox.shrink();
                }

                final data = snapshot.data!.data() as Map<String, dynamic>;
                final sellerAccepted =
                    data['termsAcceptedSeller'] as bool? ?? false;
                final buyerAccepted =
                    data['termsAcceptedBuyer'] as bool? ?? false;
                final acceptedAtSeller = data['acceptedAtSeller'] as Timestamp?;
                final acceptedAtBuyer = data['acceptedAtBuyer'] as Timestamp?;
                final contractVersion =
                    data['contractVersion'] as String? ?? '1.0';

                final isAccepted = widget.isSeller ? sellerAccepted : buyerAccepted;
                final acceptedAt =
                    widget.isSeller ? acceptedAtSeller : acceptedAtBuyer;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Contract Version: $contractVersion',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Icon(
                          sellerAccepted ? Icons.check_circle : Icons.cancel,
                          color: sellerAccepted ? AppTheme.success : AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        const Text('Seller: '),
                        Text(
                          sellerAccepted ? 'Accepted' : 'Pending',
                          style: TextStyle(
                            color: sellerAccepted ? AppTheme.success : AppTheme.textSecondary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          buyerAccepted ? Icons.check_circle : Icons.cancel,
                          color: buyerAccepted ? AppTheme.success : AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        const Text('Buyer: '),
                        Text(
                          buyerAccepted ? 'Accepted' : 'Pending',
                          style: TextStyle(
                            color: buyerAccepted ? AppTheme.success : AppTheme.textSecondary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    if (isAccepted && acceptedAt != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'You accepted on: ${_formatTimestamp(acceptedAt)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    if (sellerAccepted && buyerAccepted) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.success.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.success),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.check_circle, color: AppTheme.success),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Both parties have accepted. Contacts will be released.',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            if (!_agreed || !_isAccepting)
              StreamBuilder<DocumentSnapshot>(
                stream: _contractService.streamContract(widget.auctionId),
                builder: (context, snapshot) {
                  if (!snapshot.hasData || !snapshot.data!.exists) {
                    return const SizedBox.shrink();
                  }

                  final data = snapshot.data!.data() as Map<String, dynamic>;
                  final sellerAccepted =
                      data['termsAcceptedSeller'] as bool? ?? false;
                  final buyerAccepted =
                      data['termsAcceptedBuyer'] as bool? ?? false;
                  final isAccepted =
                      widget.isSeller ? sellerAccepted : buyerAccepted;

                  if (isAccepted) {
                    return const SizedBox.shrink();
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CheckboxListTile(
                        title: const Text('I agree to the terms and conditions'),
                        value: _agreed,
                        onChanged: _isAccepting
                            ? null
                            : (value) {
                                setState(() => _agreed = value ?? false);
                              },
                      ),
                      const SizedBox(height: 16),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: AppTheme.error),
                          ),
                        ),
                      ElevatedButton(
                        onPressed: (_agreed && !_isAccepting) ? _acceptTerms : null,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: _isAccepting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Accept'),
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTermItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 4, right: 8),
            child: Icon(Icons.circle, size: 6),
          ),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  String _formatTimestamp(Timestamp timestamp) {
    final date = timestamp.toDate();
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
