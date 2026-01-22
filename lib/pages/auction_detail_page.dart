import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import '../services/auction_service.dart';
import '../services/firestore_service.dart';
import '../services/contract_service.dart';
import '../services/payment_service.dart';
import 'terms_contract_page.dart';
import 'payment_page.dart';

class AuctionDetailPage extends StatefulWidget {
  final String auctionId;

  const AuctionDetailPage({super.key, required this.auctionId});

  @override
  State<AuctionDetailPage> createState() => _AuctionDetailPageState();
}

class _AuctionDetailPageState extends State<AuctionDetailPage> {
  final _bidController = TextEditingController();
  final AuctionService _auctionService = AuctionService();
  final FirestoreService _firestoreService = FirestoreService();
  final ContractService _contractService = ContractService();
  final PaymentService _paymentService = PaymentService();
  bool _isPlacingBid = false;
  bool _isProcessing = false;
  String? _bidError;
  Map<String, dynamic>? _depositCheck;

  @override
  void initState() {
    super.initState();
    _checkAndEndAuction();
    _setupContactReleaseListener();
  }

  void _setupContactReleaseListener() {
    // Listen for contract changes and automatically release contact when both accept
    _contractService.streamContract(widget.auctionId).listen((
      contractDoc,
    ) async {
      if (!contractDoc.exists) return;

      final contractData = contractDoc.data() as Map<String, dynamic>;
      final sellerAccepted =
          contractData['termsAcceptedSeller'] as bool? ?? false;
      final buyerAccepted =
          contractData['termsAcceptedBuyer'] as bool? ?? false;

      // Check if both accepted and contact not yet released
      if (sellerAccepted && buyerAccepted) {
        try {
          // Get auction doc to check buyerConfirmedPurchase
          final auctionDoc = await FirebaseFirestore.instance
              .collection('auctions')
              .doc(widget.auctionId)
              .get();

          if (auctionDoc.exists) {
            final auctionData = auctionDoc.data() as Map<String, dynamic>;
            final buyerConfirmed =
                auctionData['buyerConfirmedPurchase'] as bool? ?? false;
            final contactReleased =
                auctionData['winnerContactReleased'] as bool? ?? false;

            // Release contact if all conditions met
            if (buyerConfirmed && !contactReleased) {
              await _auctionService.releaseContact(widget.auctionId);
            }
          }
        } catch (e) {
          // Silent fail - will retry on next contract update
          debugPrint('Error releasing contact: $e');
        }
      }
    });
  }

  @override
  void dispose() {
    _bidController.dispose();
    super.dispose();
  }

  Future<void> _checkAndEndAuction() async {
    await _auctionService.checkAndEndAuction(widget.auctionId);
  }

  Future<void> _checkDeposit(double price) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final check = await _auctionService.checkDepositRequirement(
      bidderId: user.uid,
      auctionPrice: price,
      auctionId: widget.auctionId,
    );

    setState(() {
      _depositCheck = Map<String, dynamic>.from(check)
        ..['lastCheckedPrice'] = price;
    });
  }

  Future<void> _placeBid() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _bidError = 'Not logged in');
      return;
    }

    // Check KYC status
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final userData = userDoc.data() as Map<String, dynamic>?;
    final kycStatus = userData?['kycStatus'] as String? ?? 'not_submitted';

    if (kycStatus != 'approved') {
      setState(() {
        _bidError =
            'KYC verification required to place bids. Please complete verification first.';
        _isPlacingBid = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'KYC verification required to place bids. Please complete verification first.',
            ),
          ),
        );
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            Navigator.of(context).pushNamed('/kyc');
          }
        });
      }
      return;
    }

    final amount = double.tryParse(_bidController.text);
    if (amount == null || amount <= 0) {
      setState(() => _bidError = 'Invalid bid amount');
      return;
    }

    setState(() {
      _isPlacingBid = true;
      _bidError = null;
    });

    try {
      await _auctionService.placeBid(
        auctionId: widget.auctionId,
        bidderId: user.uid,
        amount: amount,
      );

      _bidController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bid placed successfully')),
        );
      }
    } catch (e) {
      setState(() => _bidError = 'Error: $e');
    } finally {
      if (mounted) {
        setState(() => _isPlacingBid = false);
      }
    }
  }

  Future<void> _winnerConfirmPurchase() async {
    setState(() => _isProcessing = true);
    try {
      await _auctionService.winnerConfirmPurchase(widget.auctionId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Purchase confirmed. Please accept the agreement.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
  }

  void _openWhatsApp(String phone) async {
    final cleaned = phone.replaceAll(RegExp(r'[^\d]'), '');
    final url = Uri.parse('https://wa.me/$cleaned');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open WhatsApp')),
        );
      }
    }
  }

  Future<void> _confirmDelivery(bool isSeller) async {
    setState(() => _isProcessing = true);
    try {
      await _auctionService.confirmDelivery(
        auctionId: widget.auctionId,
        isSeller: isSeller,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${isSeller ? 'Delivery' : 'Receipt'} confirmed'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _requestRefund() async {
    setState(() => _isProcessing = true);
    try {
      await _auctionService.requestDepositRefund(widget.auctionId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Deposit refund requested')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _reportNoResponse() async {
    setState(() => _isProcessing = true);
    try {
      await _auctionService.reportNoResponse(widget.auctionId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No response reported. Deposit forfeited.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _payBuyerCommission(double amount) async {
    setState(() => _isProcessing = true);
    try {
      // Navigate to PaymentPage for buyer commission
      final success = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (context) => PaymentPage(
            type: 'buyer_commission',
            amount: amount,
            auctionId: widget.auctionId,
            title: 'Pay Buyer Commission',
          ),
        ),
      );

      if (mounted) {
        if (success == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Buyer commission payment successful'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Payment error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  String _formatTimeLeft(Timestamp? endsAt) {
    if (endsAt == null) return 'No end date';
    final now = DateTime.now();
    final endDate = endsAt.toDate();
    final difference = endDate.difference(now);

    if (difference.isNegative) return 'Ended';

    if (difference.inDays > 0) {
      return '${difference.inDays}d ${difference.inHours % 24}h ${difference.inMinutes % 60}m';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ${difference.inMinutes % 60}m';
    } else {
      return '${difference.inMinutes}m';
    }
  }

  Widget _buildStepIndicator({
    required int step,
    required String title,
    required bool isComplete,
    required bool isActive,
  }) {
    IconData icon;
    Color color;

    if (isComplete) {
      icon = Icons.check_circle;
      color = Colors.green;
    } else if (isActive) {
      icon = Icons.radio_button_checked;
      color = Colors.blue;
    } else {
      icon = Icons.radio_button_unchecked;
      color = Colors.grey;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Text(
            '$step. $title',
            style: TextStyle(
              color: isComplete || isActive ? Colors.black : Colors.grey,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimeSince(Timestamp? timestamp) {
    if (timestamp == null) return 'Unknown';
    final now = DateTime.now();
    final time = timestamp.toDate();
    final diff = now.difference(time);

    if (diff.isNegative) return 'In the future';
    if (diff.inDays > 0) return '${diff.inDays}d ${diff.inHours % 24}h ago';
    if (diff.inHours > 0) return '${diff.inHours}h ${diff.inMinutes % 60}m ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }

  // NOTE: Countdown is handled by CountdownText widget (no page-level timer).
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('auctions')
          .doc(widget.auctionId)
          .snapshots(),
      builder: (context, auctionSnapshot) {
        if (auctionSnapshot.hasError) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Auction Details'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            body: Center(child: Text('Error: ${auctionSnapshot.error}')),
          );
        }

        if (auctionSnapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Auction Details'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (!auctionSnapshot.hasData || !auctionSnapshot.data!.exists) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Auction Details'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            body: const Center(child: Text('Auction not found')),
          );
        }

        final data = auctionSnapshot.data!.data() as Map<String, dynamic>;
        final endsAtTs = data['endsAt'] as Timestamp?;
        final sellerId = data['sellerId'] as String? ?? '';
        final winnerId = data['currentWinnerId'] as String?;
        final state = data['state'] as String? ?? 'UNKNOWN';
        final isActive = state == 'ACTIVE';
        final isEnded = state == 'ENDED' || state == 'ENDED_NO_RESPONSE';
        final isSeller = user?.uid == sellerId;
        final isWinner = user?.uid == winnerId;
        final currentPrice = (data['currentPrice'] as num?)?.toDouble() ?? 0.0;

        // Dynamic title: prefer itemNumber or auctionNumber, else title, else shortId
        final itemNumber = (data['itemNumber'] as String?)?.trim();
        final auctionNumber = (data['auctionNumber'] as String?)?.trim();
        final title = (data['title'] as String?)?.trim();
        final shortId =
            widget.auctionId.length > 6 ? widget.auctionId.substring(0, 6) : widget.auctionId;
        
        final appBarTitle = (itemNumber != null && itemNumber.isNotEmpty)
            ? itemNumber
            : (auctionNumber != null && auctionNumber.isNotEmpty)
                ? auctionNumber
                : (title != null && title.isNotEmpty)
                    ? title
                    : shortId;

          // Check deposit requirement for active auctions (recheck when price changes)
          if (isActive && user != null && !isSeller) {
            // Recheck deposit if price changed or not checked yet
            if (_depositCheck == null) {
              _checkDeposit(currentPrice);
            } else {
              // Recheck if current price differs from last checked
              final lastCheckedPrice =
                  _depositCheck!['lastCheckedPrice'] as double?;
              if (lastCheckedPrice == null ||
                  lastCheckedPrice != currentPrice) {
                _checkDeposit(currentPrice);
              }
            }
          }

        return Scaffold(
          appBar: AppBar(
            title: Text(appBarTitle),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  data['title'] as String? ?? 'Untitled',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text('Brand: ${data['brand'] ?? 'Unknown'}'),
                Text('Category: ${data['category'] ?? 'Unknown'}'),
                Text('Condition: ${data['condition'] ?? 'Unknown'}'),
                Text('Item ID: ${data['itemIdentifier'] ?? 'N/A'}'),
                const SizedBox(height: 16),
                Text(
                  'Description:',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(data['description'] as String? ?? 'No description'),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Current Price:',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        currentPrice.toStringAsFixed(2),
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: Colors.blue,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text('Bids: ${data['bidCount'] ?? 0}'),
                      // Debug: show snapshot metadata
                      Text(
                        'DEBUG: cache=${auctionSnapshot.data?.metadata.isFromCache ?? false} pending=${auctionSnapshot.data?.metadata.hasPendingWrites ?? false}',
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                      if (isActive) ...[
                        const SizedBox(height: 8),
                        CountdownText(endsAt: endsAtTs),
                        Text(
                          'DEBUG endsAt: ${endsAtTs?.toDate().toIso8601String() ?? "null"}',
                          style: const TextStyle(fontSize: 10),
                        ),
                      ],
                      if (isEnded && winnerId != null) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Status: Ended',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Deposit requirement for active auctions
                if (isActive &&
                    !isSeller &&
                    user != null &&
                    _depositCheck != null) ...[
                  const SizedBox(height: 24),
                  Builder(
                    builder: (context) {
                      final required = _depositCheck!['required'] as double;
                      final hasEnough = _depositCheck!['hasEnough'] as bool;
                      final vipWaived = _depositCheck!['vipWaived'] as bool;
                      final eligible =
                          (_depositCheck!['eligible'] as num?)?.toDouble() ??
                          0.0;
                      final bidLimit =
                          (_depositCheck!['bidLimit'] as num?)?.toDouble() ??
                          0.0;

                      if (vipWaived) {
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.check_circle, color: Colors.green),
                              SizedBox(width: 8),
                              Text('Deposit requirement waived (VIP)'),
                            ],
                          ),
                        );
                      }

                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: hasEnough
                              ? Colors.green.shade50
                              : Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: hasEnough ? Colors.green : Colors.orange,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  hasEnough
                                      ? Icons.check_circle
                                      : Icons.warning,
                                  color: hasEnough
                                      ? Colors.green
                                      : Colors.orange,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Deposit Status',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Eligible Deposit: ${eligible.toStringAsFixed(2)}',
                            ),
                            Text(
                              'Required for current bid: ${required.toStringAsFixed(2)}',
                            ),
                            if (bidLimit > 0) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Maximum Bid Limit: ${bidLimit.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                ),
                              ),
                            ],
                            if (!hasEnough) ...[
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: () {
                                    Navigator.of(context).pushNamed('/wallet');
                                  },
                                  child: const Text('Add Deposit'),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ],
                // Bidding UI for active auctions
                if (isActive &&
                    !isSeller &&
                    user != null &&
                    _depositCheck != null)
                  Builder(
                    builder: (context) {
                      final vipWaived = _depositCheck!['vipWaived'] as bool;
                      final hasEnough = _depositCheck!['hasEnough'] as bool;
                      final bidLimit =
                          (_depositCheck!['bidLimit'] as num?)?.toDouble() ??
                          0.0;

                      if (!(vipWaived || hasEnough)) {
                        return const SizedBox.shrink();
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 24),
                          Text(
                            'Place Bid:',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (bidLimit > 0 && !vipWaived) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Maximum bid: ${bidLimit.toStringAsFixed(2)} (based on available deposit)',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: Colors.blue),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _bidController,
                                  decoration: InputDecoration(
                                    labelText: 'Bid Amount',
                                    border: const OutlineInputBorder(),
                                    helperText: bidLimit > 0 && !vipWaived
                                        ? 'Max: ${bidLimit.toStringAsFixed(2)}'
                                        : null,
                                  ),
                                  keyboardType: TextInputType.number,
                                  onChanged: (value) {
                                    // Recheck deposit when amount changes
                                    final bidAmount = double.tryParse(value);
                                    if (bidAmount != null &&
                                        bidAmount > currentPrice) {
                                      _checkDeposit(bidAmount);
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: _isPlacingBid ? null : _placeBid,
                                child: _isPlacingBid
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Place Bid'),
                              ),
                            ],
                          ),
                          if (_bidError != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              _bidError!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                // Winner actions for ended auctions
                // Winner section with step indicator
                if (isEnded && isWinner && user != null) ...[
                  const SizedBox(height: 24),
                  Text(
                    'Purchase Steps',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  StreamBuilder<DocumentSnapshot>(
                    stream: _contractService.streamContract(widget.auctionId),
                    builder: (context, contractSnapshot) {
                      final buyerConfirmed =
                          data['buyerConfirmedPurchase'] as bool? ?? false;
                      final contactReleased =
                          data['winnerContactReleased'] as bool? ?? false;
                      final sellerConfirmed =
                          data['sellerConfirmedDelivery'] as bool? ?? false;
                      final buyerConfirmedDelivery =
                          data['buyerConfirmedDelivery'] as bool? ?? false;

                      bool sellerAccepted = false;
                      bool buyerAccepted = false;
                      if (contractSnapshot.hasData &&
                          contractSnapshot.data!.exists) {
                        final contractData =
                            contractSnapshot.data!.data()
                                as Map<String, dynamic>;
                        sellerAccepted =
                            contractData['termsAcceptedSeller'] as bool? ??
                            false;
                        buyerAccepted =
                            contractData['termsAcceptedBuyer'] as bool? ??
                            false;
                      }

                      // Step 1: Confirm Purchase
                      final step1Complete = buyerConfirmed;
                      // Step 2: Accept Agreement
                      final step2Complete = buyerAccepted && sellerAccepted;
                      
                      // Commission payment status
                      final buyerCommissionPaid =
                          data['buyerCommissionPaid'] as bool? ?? false;
                      final buyerCommissionDue =
                          (data['buyerCommissionDue'] as num?)?.toDouble();
                      final commissionStatus =
                          data['commissionStatus'] as String? ?? 'pending';
                      
                      // Step 3: Contacts Released (gated by deposit held AND BOTH commissions paid)
                      // Get seller commission status
                      final sellerCommissionPaidWinner =
                          data['sellerCommissionPaid'] as bool? ?? false;
                      final commissionStatusWinner =
                          data['commissionStatus'] as String? ?? 'pending';
                      final depositStatusWinner =
                          data['depositStatus'] as String?;
                      
                      // Deposit must be held (or waived) to unlock contacts
                      final depositHeldOrWaived = depositStatusWinner == 'held' ||
                          depositStatusWinner == 'waived';
                      
                      // Contacts unlocked = deposit held/waived AND BOTH commissions paid
                      // (as per requirements: depositStatus == held OR waived AND buyerCommissionPaid == true AND sellerCommissionPaid == true)
                      final bothCommissionsPaid = buyerCommissionPaid &&
                          sellerCommissionPaidWinner;
                      final contactsUnlocked = depositHeldOrWaived &&
                          bothCommissionsPaid;
                      final step3Complete = contactsUnlocked;
                      
                      // Step 4: Delivery Confirmed
                      final step4Complete =
                          sellerConfirmed && buyerConfirmedDelivery;

                      final finalPrice =
                          (data['finalPrice'] as num?)?.toDouble();

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Step Indicator
                          _buildStepIndicator(
                            step: 1,
                            title: 'Confirm Purchase',
                            isComplete: step1Complete,
                            isActive: !step1Complete,
                          ),
                          _buildStepIndicator(
                            step: 2,
                            title: 'Accept Agreement',
                            isComplete: step2Complete,
                            isActive: step1Complete && !step2Complete,
                          ),
                          _buildStepIndicator(
                            step: 3,
                            title: 'Contacts Unlocked',
                            isComplete: step3Complete,
                            isActive: step2Complete && !step3Complete,
                          ),
                          _buildStepIndicator(
                            step: 4,
                            title: 'Delivery Confirmed',
                            isComplete: step4Complete,
                            isActive: step3Complete && !step4Complete,
                          ),
                          const SizedBox(height: 24),
                          // Deposit status (for winner, before confirm purchase)
                          if (!step1Complete && isEnded) ...[
                            WinnerDeadlineCard(
                              depositStatus: data['depositStatus'] as String?,
                              depositHeld: (data['depositHeld'] as num?)?.toDouble(),
                              winnerDeadlineAt: data['winnerDeadlineAt'] as Timestamp?,
                              forfeitAmount: (data['forfeitAmount'] as num?)?.toDouble(),
                            ),
                            const SizedBox(height: 16),
                          ],
                          // Commission summary after confirm purchase
                          if (step1Complete && buyerCommissionDue != null) ...[
                            Card(
                              color: Colors.blue.shade50,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Commission (Buyer)',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    if (finalPrice != null)
                                      Text(
                                        'Final Price: AED ${finalPrice.toStringAsFixed(2)}',
                                      ),
                                    Text(
                                      'Buyer Commission Due: AED ${buyerCommissionDue.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          // Step 1: Confirm Purchase Button
                          if (!step1Complete) ...[
                            Builder(
                              builder: (context) {
                                final depositStatusForButton =
                                    data['depositStatus'] as String?;
                                final isInsufficient =
                                    depositStatusForButton == 'insufficient';
                                final isForfeited =
                                    depositStatusForButton == 'forfeited';
                                
                                return SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: (_isProcessing || isInsufficient || isForfeited)
                                        ? null
                                        : _winnerConfirmPurchase,
                                    child: _isProcessing
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Text('Confirm Purchase'),
                                  ),
                                );
                              },
                            ),
                          ],
                          // Step 2: View Agreement Button
                          if (step1Complete && !step2Complete)
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) => TermsContractPage(
                                        auctionId: widget.auctionId,
                                        isSeller: false,
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.description),
                                label: const Text('View Agreement'),
                              ),
                            ),
                          // Pay Buyer Commission Button (after confirm purchase, before contacts)
                          if (step1Complete &&
                              buyerCommissionDue != null &&
                              buyerCommissionDue > 0 &&
                              !buyerCommissionPaid &&
                              (commissionStatus == 'pending' ||
                                  commissionStatus == 'calculated')) ...[
                            const SizedBox(height: 16),
                            Card(
                              color: Colors.orange.shade50,
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Buyer Commission Payment Required',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Commission Due: AED ${buyerCommissionDue.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: _isProcessing
                                            ? null
                                            : () => _payBuyerCommission(
                                                  buyerCommissionDue,
                                                ),
                                        icon: const Icon(Icons.payment),
                                        label: const Text('Pay Buyer Commission'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.orange,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 16,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          // Show paid status if commission already paid
                          if (buyerCommissionPaid) ...[
                            const SizedBox(height: 16),
                            Card(
                              color: Colors.green.shade50,
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: const Row(
                                  children: [
                                    Icon(
                                      Icons.check_circle,
                                      color: Colors.green,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Buyer commission paid ✅',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          // Step 3: Contact Info (when released AND commission paid)
                          if (step3Complete)
                            FutureBuilder<Map<String, String?>>(
                              future:
                                  Future.wait([
                                    _auctionService.getUserPhone(sellerId),
                                    FirebaseFirestore.instance
                                        .collection('users')
                                        .doc(sellerId)
                                        .get()
                                        .then(
                                          (doc) =>
                                              doc.data()?['displayName']
                                                  as String? ??
                                              'N/A',
                                        ),
                                  ]).then(
                                    (results) => {
                                      'sellerPhone': results[0],
                                      'sellerName': results[1],
                                    },
                                  ),
                              builder: (context, phoneSnapshot) {
                                final sellerPhone =
                                    phoneSnapshot.data?['sellerPhone'];
                                final sellerName =
                                    phoneSnapshot.data?['sellerName'] ??
                                    'Seller';

                                return Card(
                                  color: Colors.green.shade50,
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Row(
                                          children: [
                                            Icon(
                                              Icons.check_circle,
                                              color: Colors.green,
                                            ),
                                            SizedBox(width: 8),
                                            Text(
                                              'Contact Information Released',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.green,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 16),
                                        Text('Seller: $sellerName'),
                                        if (sellerPhone != null) ...[
                                          const SizedBox(height: 8),
                                          Text('Phone: $sellerPhone'),
                                          const SizedBox(height: 16),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: OutlinedButton.icon(
                                                  onPressed: () =>
                                                      _openWhatsApp(
                                                        sellerPhone,
                                                      ),
                                                  icon: const Icon(Icons.chat),
                                                  label: const Text('WhatsApp'),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: OutlinedButton.icon(
                                                  onPressed: () =>
                                                      _copyToClipboard(
                                                        sellerPhone,
                                                      ),
                                                  icon: const Icon(Icons.copy),
                                                  label: const Text('Copy'),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                        ],
                      );
                    },
                  ),
                ],
                // Seller section for ended auctions
                if (isEnded &&
                    isSeller &&
                    user != null &&
                    winnerId != null) ...[
                  const SizedBox(height: 24),
                  Text(
                    'Seller Actions',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  StreamBuilder<DocumentSnapshot>(
                    stream: _contractService.streamContract(widget.auctionId),
                    builder: (context, contractSnapshot) {
                      final buyerConfirmed =
                          data['buyerConfirmedPurchase'] as bool? ?? false;
                      final contactReleased =
                          data['winnerContactReleased'] as bool? ?? false;

                      bool sellerAccepted = false;
                      bool buyerAccepted = false;
                      if (contractSnapshot.hasData &&
                          contractSnapshot.data!.exists) {
                        final contractData =
                            contractSnapshot.data!.data()
                                as Map<String, dynamic>;
                        sellerAccepted =
                            contractData['termsAcceptedSeller'] as bool? ??
                            false;
                        buyerAccepted =
                            contractData['termsAcceptedBuyer'] as bool? ??
                            false;
                      }

                      // Get seller commission info
                      final sellerCommissionPaid =
                          data['sellerCommissionPaid'] as bool? ?? false;
                      final sellerCommissionDue =
                          (data['sellerCommissionDue'] as num?)?.toDouble();

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Show View Agreement button after buyer confirms purchase
                          if (buyerConfirmed && !sellerAccepted)
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) => TermsContractPage(
                                        auctionId: widget.auctionId,
                                        isSeller: true,
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.description),
                                label: const Text('View Agreement'),
                              ),
                            ),
                          // Pay Seller Commission button
                          if (buyerConfirmed &&
                              !sellerCommissionPaid &&
                              sellerCommissionDue != null &&
                              sellerCommissionDue > 0) ...[
                            const SizedBox(height: 16),
                            Card(
                              color: Colors.orange.shade50,
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Seller Commission Payment Required',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Commission Due: AED ${sellerCommissionDue.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: _isProcessing
                                            ? null
                                            : () async {
                                                setState(() => _isProcessing = true);
                                                try {
                                                  final success =
                                                      await Navigator.of(context)
                                                          .push<bool>(
                                                    MaterialPageRoute(
                                                      builder: (context) =>
                                                          PaymentPage(
                                                        type: 'seller_commission',
                                                        amount:
                                                            sellerCommissionDue,
                                                        auctionId:
                                                            widget.auctionId,
                                                        title:
                                                            'Pay Seller Commission',
                                                      ),
                                                    ),
                                                  );
                                                  if (mounted && success == true) {
                                                    ScaffoldMessenger.of(context)
                                                        .showSnackBar(
                                                      const SnackBar(
                                                        content: Text(
                                                            'Seller commission payment successful'),
                                                        backgroundColor:
                                                            Colors.green,
                                                      ),
                                                    );
                                                  }
                                                } catch (e) {
                                                  if (mounted) {
                                                    ScaffoldMessenger.of(context)
                                                        .showSnackBar(
                                                      SnackBar(
                                                          content: Text(
                                                              'Payment error: $e')),
                                                    );
                                                  }
                                                } finally {
                                                  if (mounted) {
                                                    setState(() =>
                                                        _isProcessing = false);
                                                  }
                                                }
                                              },
                                        icon: const Icon(Icons.payment),
                                        label: const Text('Pay Seller Commission'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.orange,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 16,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          // Show paid status if commission already paid
                          if (sellerCommissionPaid) ...[
                            const SizedBox(height: 16),
                            Card(
                              color: Colors.green.shade50,
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: const Row(
                                  children: [
                                    Icon(
                                      Icons.check_circle,
                                      color: Colors.green,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Seller commission paid ✅',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          // Show buyer contact info after release AND commission paid
                          Builder(
                            builder: (context) {
                              final buyerCommissionPaidSeller =
                                  data['buyerCommissionPaid'] as bool? ?? false;
                              final contactReleasedSeller =
                                  data['winnerContactReleased'] as bool? ?? false;
                              bool sellerAcceptedForContact = false;
                              bool buyerAcceptedForContact = false;
                              if (contractSnapshot.hasData &&
                                  contractSnapshot.data!.exists) {
                                final contractDataSeller =
                                    contractSnapshot.data!.data()
                                        as Map<String, dynamic>;
                                sellerAcceptedForContact =
                                    contractDataSeller['termsAcceptedSeller']
                                            as bool? ??
                                        false;
                                buyerAcceptedForContact =
                                    contractDataSeller['termsAcceptedBuyer']
                                            as bool? ??
                                        false;
                              }
                              // Get seller commission status for contact gating
                              final sellerCommissionPaidForContact =
                                  data['sellerCommissionPaid'] as bool? ?? false;
                              final commissionStatusForContact =
                                  data['commissionStatus'] as String? ?? 'pending';
                              
                              // Get deposit status for contact gating
                              final depositStatusForContact =
                                  data['depositStatus'] as String?;
                              
                              // Deposit must be held (or waived) to unlock contacts
                              final depositHeldOrWaivedForContact =
                                  depositStatusForContact == 'held' ||
                                      depositStatusForContact == 'waived';
                              
                              // Contacts unlocked = deposit held/waived AND BOTH commissions paid
                              // (as per requirements: depositStatus == held OR waived AND buyerCommissionPaid == true AND sellerCommissionPaid == true)
                              final bothCommissionsPaidForContact =
                                  buyerCommissionPaidSeller &&
                                      sellerCommissionPaidForContact;
                              final contactsUnlockedSeller =
                                  depositHeldOrWaivedForContact &&
                                      bothCommissionsPaidForContact;
                              
                              if (!contactsUnlockedSeller) {
                                return const SizedBox.shrink();
                              }
                              
                              return FutureBuilder<Map<String, String?>>(
                                future: Future.wait([
                                  _auctionService.getUserPhone(winnerId),
                                  FirebaseFirestore.instance
                                      .collection('users')
                                      .doc(winnerId)
                                      .get()
                                      .then(
                                        (doc) =>
                                            doc.data()?['displayName'] as String? ??
                                            'N/A',
                                      ),
                                ]).then(
                                  (results) => {
                                    'buyerPhone': results[0],
                                    'buyerName': results[1],
                                  },
                                ),
                                builder: (context, phoneSnapshot) {
                                  final buyerPhone =
                                      phoneSnapshot.data?['buyerPhone'];
                                  final buyerName =
                                      phoneSnapshot.data?['buyerName'] ?? 'Buyer';

                                  return Card(
                                    color: Colors.green.shade50,
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Row(
                                            children: [
                                              Icon(
                                                Icons.check_circle,
                                                color: Colors.green,
                                              ),
                                              SizedBox(width: 8),
                                              Text(
                                                'Buyer Contact Information',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.green,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 16),
                                          Text('Buyer: $buyerName'),
                                          if (buyerPhone != null) ...[
                                            const SizedBox(height: 8),
                                            Text('Phone: $buyerPhone'),
                                            const SizedBox(height: 16),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: OutlinedButton.icon(
                                                    onPressed: () =>
                                                        _openWhatsApp(buyerPhone),
                                                    icon: const Icon(Icons.chat),
                                                    label: const Text('WhatsApp'),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: OutlinedButton.icon(
                                                    onPressed: () =>
                                                        _copyToClipboard(
                                                          buyerPhone,
                                                        ),
                                                    icon: const Icon(Icons.copy),
                                                    label: const Text('Copy'),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                          // Waiting message or report no response
                          Builder(
                            builder: (context) {
                              final buyerCommissionPaidSellerMsg =
                                  data['buyerCommissionPaid'] as bool? ?? false;
                              final sellerCommissionPaidSellerMsg =
                                  data['sellerCommissionPaid'] as bool? ?? false;
                              final depositStatusSellerMsg =
                                  data['depositStatus'] as String?;
                              final contactReleasedSellerMsg =
                                  data['winnerContactReleased'] as bool? ?? false;
                              bool sellerAcceptedForContactMsg = false;
                              bool buyerAcceptedForContactMsg = false;
                              if (contractSnapshot.hasData &&
                                  contractSnapshot.data!.exists) {
                                final contractDataSellerMsg =
                                    contractSnapshot.data!.data()
                                        as Map<String, dynamic>;
                                sellerAcceptedForContactMsg =
                                    contractDataSellerMsg['termsAcceptedSeller']
                                            as bool? ??
                                        false;
                                buyerAcceptedForContactMsg =
                                    contractDataSellerMsg['termsAcceptedBuyer']
                                            as bool? ??
                                        false;
                              }
                              // Contacts unlocked = deposit held/waived AND BOTH commissions paid
                              // (as per requirements: depositStatus == held OR waived AND buyerCommissionPaid == true AND sellerCommissionPaid == true)
                              final depositHeldOrWaivedSellerMsg =
                                  depositStatusSellerMsg == 'held' ||
                                      depositStatusSellerMsg == 'waived';
                              final bothCommissionsPaidSellerMsg =
                                  buyerCommissionPaidSellerMsg &&
                                      sellerCommissionPaidSellerMsg;
                              final contactsUnlockedSellerMsg =
                                  depositHeldOrWaivedSellerMsg &&
                                      bothCommissionsPaidSellerMsg;
                              
                              if (!buyerConfirmed) {
                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'Waiting for winner to confirm purchase.',
                                  ),
                                );
                              } else if (!buyerCommissionPaidSellerMsg) {
                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'Waiting for buyer to pay commission before contacts can be released.',
                                  ),
                                );
                              } else if (!sellerCommissionPaidSellerMsg) {
                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'Waiting for seller to pay commission before contacts can be released.',
                                  ),
                                );
                              } else if (!contactsUnlockedSellerMsg) {
                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    buyerAcceptedForContactMsg &&
                                            !sellerAcceptedForContactMsg
                                        ? 'Please accept the agreement to release contacts.'
                                        : 'Waiting for both parties to accept the agreement.',
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                        ],
                      );
                    },
                  ),
                ],
                // Admin override for contact release
                if (isEnded && user != null)
                  StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .doc(user.uid)
                        .snapshots(),
                    builder: (context, userSnapshot) {
                      if (!userSnapshot.hasData) return const SizedBox.shrink();
                      final userData =
                          userSnapshot.data?.data() as Map<String, dynamic>?;
                      final role = userData?['role'] as String?;
                      final isAdmin = role == 'admin';
                      final contactReleased =
                          data['winnerContactReleased'] as bool? ?? false;

                      if (!isAdmin || contactReleased)
                        return const SizedBox.shrink();

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Card(
                          color: Colors.orange.shade50,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Admin Override',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: _isProcessing
                                        ? null
                                        : () async {
                                            setState(
                                              () => _isProcessing = true,
                                            );
                                            try {
                                              await _auctionService
                                                  .forceReleaseContact(
                                                    widget.auctionId,
                                                  );
                                              if (mounted) {
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                      'Contact released (Admin override)',
                                                    ),
                                                  ),
                                                );
                                              }
                                            } catch (e) {
                                              if (mounted) {
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  SnackBar(
                                                    content: Text('Error: $e'),
                                                  ),
                                                );
                                              }
                                            } finally {
                                              if (mounted) {
                                                setState(
                                                  () => _isProcessing = false,
                                                );
                                              }
                                            }
                                          },
                                    icon: const Icon(
                                      Icons.admin_panel_settings,
                                    ),
                                    label: const Text('Force Release Contact'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.orange,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                // Delivery confirmation (only after contact released AND commission paid)
                if (isEnded &&
                    (isSeller || isWinner) &&
                    user != null) ...[
                  Builder(
                    builder: (context) {
                      // Compute contactsUnlocked for delivery gating (requires deposit held AND BOTH commissions paid)
                      final buyerCommissionPaidForDelivery =
                          data['buyerCommissionPaid'] as bool? ?? false;
                      final sellerCommissionPaidForDelivery =
                          data['sellerCommissionPaid'] as bool? ?? false;
                      final commissionStatusForDelivery =
                          data['commissionStatus'] as String? ?? 'pending';
                      final depositStatusForDelivery =
                          data['depositStatus'] as String?;
                      final contactReleasedForDelivery =
                          data['winnerContactReleased'] as bool? ?? false;
                      
                      // Deposit must be held (or waived) to unlock contacts
                      final depositHeldOrWaivedForDelivery =
                          depositStatusForDelivery == 'held' ||
                              depositStatusForDelivery == 'waived';
                      
                      // Get contract acceptance status
                      bool contractAcceptedByBoth = false;
                      return StreamBuilder<DocumentSnapshot>(
                        stream: _contractService.streamContract(widget.auctionId),
                        builder: (context, contractSnapshot) {
                          if (contractSnapshot.hasData &&
                              contractSnapshot.data!.exists) {
                            final contractData =
                                contractSnapshot.data!.data()
                                    as Map<String, dynamic>;
                            final sellerAccepted =
                                contractData['termsAcceptedSeller'] as bool? ??
                                    false;
                            final buyerAccepted =
                                contractData['termsAcceptedBuyer'] as bool? ??
                                    false;
                            contractAcceptedByBoth =
                                sellerAccepted && buyerAccepted;
                          }
                          
                          // Contacts unlocked = deposit held/waived AND BOTH commissions paid
                          // (as per requirements: depositStatus == held OR waived AND buyerCommissionPaid == true AND sellerCommissionPaid == true)
                          final bothCommissionsPaidForDelivery =
                              buyerCommissionPaidForDelivery &&
                                  sellerCommissionPaidForDelivery;
                          final contactsUnlockedForDelivery =
                              depositHeldOrWaivedForDelivery &&
                                  bothCommissionsPaidForDelivery;
                          
                          // Only show delivery section if contacts are unlocked
                          if (!contactsUnlockedForDelivery) {
                            return const SizedBox.shrink();
                          }
                          
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 24),
                              Text(
                                'Delivery Status',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: Card(
                                      child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Column(
                                          children: [
                                            Text(
                                              'Seller Confirmed',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
                                            ),
                                            const SizedBox(height: 4),
                                            Icon(
                                              (data['sellerConfirmedDelivery']
                                                          as bool? ??
                                                      false)
                                                  ? Icons.check_circle
                                                  : Icons.cancel,
                                              color: (data['sellerConfirmedDelivery']
                                                          as bool? ??
                                                      false)
                                                  ? Colors.green
                                                  : Colors.grey,
                                            ),
                                            if (!(data['sellerConfirmedDelivery']
                                                        as bool? ??
                                                    false) &&
                                                isSeller) ...[
                                              const SizedBox(height: 8),
                                              SizedBox(
                                                width: double.infinity,
                                                child: ElevatedButton(
                                                  onPressed: _isProcessing
                                                      ? null
                                                      : () => _confirmDelivery(true),
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: Colors.green,
                                                  ),
                                                  child: _isProcessing
                                                      ? const SizedBox(
                                                          width: 16,
                                                          height: 16,
                                                          child:
                                                              CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                          ),
                                                        )
                                                      : const Text('Confirm Delivered'),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Card(
                                      child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Column(
                                          children: [
                                            Text(
                                              'Buyer Confirmed',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
                                            ),
                                            const SizedBox(height: 4),
                                            Icon(
                                              (data['buyerConfirmedDelivery']
                                                          as bool? ??
                                                      false)
                                                  ? Icons.check_circle
                                                  : Icons.cancel,
                                              color: (data['buyerConfirmedDelivery']
                                                          as bool? ??
                                                      false)
                                                  ? Colors.green
                                                  : Colors.grey,
                                            ),
                                            if (!(data['buyerConfirmedDelivery']
                                                        as bool? ??
                                                    false) &&
                                                isWinner) ...[
                                              const SizedBox(height: 8),
                                              SizedBox(
                                                width: double.infinity,
                                                child: ElevatedButton(
                                                  onPressed: _isProcessing
                                                      ? null
                                                      : () => _confirmDelivery(false),
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: Colors.green,
                                                  ),
                                                  child: _isProcessing
                                                      ? const SizedBox(
                                                          width: 16,
                                                          height: 16,
                                                          child:
                                                              CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                          ),
                                                        )
                                                      : const Text('Confirm Received'),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              // Show success state when both confirmed
                              if ((data['sellerConfirmedDelivery'] as bool? ??
                                      false) &&
                                  (data['buyerConfirmedDelivery'] as bool? ??
                                      false)) ...[
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Row(
                                    children: [
                                      Icon(Icons.check_circle, color: Colors.green),
                                      SizedBox(width: 8),
                                      Text(
                                        'Delivery confirmed by both parties',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                      );
                    },
                  ),
                ],
                // Request refund button (after both confirm delivery)
                if ((data['sellerConfirmedDelivery'] as bool? ?? false) &&
                    (data['buyerConfirmedDelivery'] as bool? ?? false) &&
                    isWinner) ...[
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isProcessing ? null : _requestRefund,
                      child: _isProcessing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Request Deposit Refund'),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Text(
                  'Recent Bids:',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                StreamBuilder<QuerySnapshot>(
                  stream: _auctionService.streamBids(widget.auctionId),
                  builder: (context, bidsSnapshot) {
                    if (bidsSnapshot.hasError) {
                      return Text('Error: ${bidsSnapshot.error}');
                    }

                    if (bidsSnapshot.connectionState == ConnectionState.waiting) {
                      return const CircularProgressIndicator();
                    }

                    if (!bidsSnapshot.hasData ||
                        bidsSnapshot.data!.docs.isEmpty) {
                      return const Text('No bids yet');
                    }

                    return ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: bidsSnapshot.data!.docs.length,
                      itemBuilder: (context, index) {
                        final bidDoc = bidsSnapshot.data!.docs[index];
                        final bidData = bidDoc.data() as Map<String, dynamic>;
                        final amount =
                            (bidData['amount'] as num?)?.toDouble() ?? 0.0;
                        final createdAt = bidData['createdAt'] as Timestamp?;

                        String timeText = 'Unknown';
                        if (createdAt != null) {
                          final now = DateTime.now();
                          final created = createdAt.toDate();
                          final diff = now.difference(created);

                          if (diff.inDays > 0) {
                            timeText = '${diff.inDays}d ago';
                          } else if (diff.inHours > 0) {
                            timeText = '${diff.inHours}h ago';
                          } else if (diff.inMinutes > 0) {
                            timeText = '${diff.inMinutes}m ago';
                          } else {
                            timeText = 'Just now';
                          }
                        }

                        return ListTile(
                          title: Text(amount.toStringAsFixed(2)),
                          subtitle: Text(timeText),
                          dense: true,
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class CountdownText extends StatefulWidget {
  final Timestamp? endsAt;

  const CountdownText({super.key, required this.endsAt});

  @override
  State<CountdownText> createState() => _CountdownTextState();
}

class _CountdownTextState extends State<CountdownText> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _formatTimeLeft(Timestamp? endsAt) {
    if (endsAt == null) return 'No end date';
    final now = DateTime.now();
    final endDate = endsAt.toDate();
    final difference = endDate.difference(now);

    if (difference.isNegative) return 'Ended';
    if (difference.inDays > 0) {
      return '${difference.inDays}d ${difference.inHours % 24}h ${difference.inMinutes % 60}m';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ${difference.inMinutes % 60}m';
    } else {
      return '${difference.inMinutes}m ${difference.inSeconds % 60}s';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      'Time left: ${_formatTimeLeft(widget.endsAt)}',
      style: const TextStyle(fontWeight: FontWeight.bold),
    );
  }
}

class WinnerDeadlineCard extends StatefulWidget {
  final String? depositStatus;
  final double? depositHeld;
  final Timestamp? winnerDeadlineAt;
  final double? forfeitAmount;

  const WinnerDeadlineCard({
    super.key,
    required this.depositStatus,
    this.depositHeld,
    this.winnerDeadlineAt,
    this.forfeitAmount,
  });

  @override
  State<WinnerDeadlineCard> createState() => _WinnerDeadlineCardState();
}

class _WinnerDeadlineCardState extends State<WinnerDeadlineCard> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Update every second for real-time countdown
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _formatCountdown(Timestamp? deadlineAt) {
    if (deadlineAt == null) return 'No deadline';
    final now = DateTime.now();
    final deadline = deadlineAt.toDate();
    final diff = deadline.difference(now);
    
    if (diff.isNegative) return 'Deadline passed';
    
    final days = diff.inDays;
    final hours = diff.inHours % 24;
    final minutes = diff.inMinutes % 60;
    final seconds = diff.inSeconds % 60;
    
    if (days > 0) {
      return '${days}d ${hours}h ${minutes}m';
    } else if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  bool _isLessThanOneHour(Timestamp? deadlineAt) {
    if (deadlineAt == null) return false;
    final now = DateTime.now();
    final deadline = deadlineAt.toDate();
    final diff = deadline.difference(now);
    return !diff.isNegative && diff.inHours < 1;
  }

  @override
  Widget build(BuildContext context) {
    final depositStatus = widget.depositStatus;
    
    if (depositStatus == 'forfeited') {
      return Card(
        color: Colors.red.shade50,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.error, color: Colors.red),
                  SizedBox(width: 8),
                  Text(
                    'Deposit Forfeited',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              if (widget.forfeitAmount != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Forfeit Amount: AED ${widget.forfeitAmount!.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 14),
                ),
              ],
              const SizedBox(height: 4),
              const Text(
                'Deposit forfeited due to no response before deadline.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }
    
    if (depositStatus == 'insufficient') {
      return Card(
        color: Colors.orange.shade50,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.warning, color: Colors.orange),
                  SizedBox(width: 8),
                  Text(
                    'Insufficient Deposit',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Insufficient deposit. Please top up to proceed.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }
    
    if (depositStatus == 'waived') {
      return Card(
        color: Colors.green.shade50,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 8),
                  Text(
                    'Deposit Waived (VIP)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    
    if (depositStatus == 'held') {
      final countdown = _formatCountdown(widget.winnerDeadlineAt);
      final isUrgent = _isLessThanOneHour(widget.winnerDeadlineAt);
      
      return Card(
        color: isUrgent ? Colors.red.shade50 : Colors.blue.shade50,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.lock,
                    color: isUrgent ? Colors.red : Colors.blue,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Deposit Held',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              if (widget.depositHeld != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Held: AED ${widget.depositHeld!.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 14),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                countdown,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isUrgent ? Colors.red : Colors.blue,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'You must confirm purchase before the deadline to avoid losing your deposit.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }
    
    return const SizedBox.shrink();
  }
}
