import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import '../models/category_model.dart';
import '../models/watch_brand.dart';
import '../services/auction_service.dart';
import '../services/bid_eligibility_service.dart';
import '../services/contract_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/unified_app_bar.dart';
import 'terms_contract_page.dart';
import 'payment_page.dart';
import 'edit_draft_auction_page.dart';

// Bidding card: uniform heights, padding, and corner radius for time pill, bid input, increment buttons
const double _kBidCardRadius = 10.0;
const EdgeInsets _kBidCardPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 10);
const double _kBidCardControlHeight = 44.0;

class AuctionDetailPage extends StatefulWidget {
  final String auctionId;

  const AuctionDetailPage({super.key, required this.auctionId});

  @override
  State<AuctionDetailPage> createState() => _AuctionDetailPageState();
}

class _AuctionDetailPageState extends State<AuctionDetailPage> {
  final AuctionService _auctionService = AuctionService();
  final ContractService _contractService = ContractService();
  final BidEligibilityService _bidEligibility = BidEligibilityService();
  bool _isPlacingBid = false;
  bool _isProcessing = false;
  bool _isSubmitting = false;
  bool _isDeleting = false;
  String? _bidError;
  final _bidController = TextEditingController();
  final FocusNode _bidFocusNode = FocusNode();

  @override
  void dispose() {
    _bidController.dispose();
    _bidFocusNode.dispose();
    super.dispose();
  }

  /// Returns true if user can bid; otherwise shows message and routes to missing step, returns false.
  Future<bool> _checkBidEligibilityAndRoute() async {
    final result = await _bidEligibility.checkEligibility();
    if (result.canBid) return true;
    if (!mounted) return false;
    final step = result.nextStep;
    final message = result.message;
    final nav = Navigator.of(context);
    final args = <String, dynamic>{'returnAuctionId': widget.auctionId};
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Complete setup to bid'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              switch (step) {
                case BidEligibilityStep.login:
                  nav.pushNamed('/login', arguments: args);
                  break;
                case BidEligibilityStep.verifyEmail:
                  nav.pushNamed('/emailVerification', arguments: {...args, 'returnAfterVerify': true});
                  break;
                case BidEligibilityStep.acceptTerms:
                  nav.pushNamed('/acceptTerms', arguments: args);
                  break;
                case BidEligibilityStep.createProfile:
                  nav.pushNamed('/createProfile', arguments: args);
                  break;
                case BidEligibilityStep.addDeposit:
                  nav.pushNamed('/wallet', arguments: args);
                  break;
                case BidEligibilityStep.kyc:
                  nav.pushNamed('/kyc', arguments: args);
                  break;
                case BidEligibilityStep.canBid:
                  break;
              }
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    return false;
  }

  @override
  void initState() {
    super.initState();
    _checkAndEndAuction();
    _setupContactReleaseListener();
  }

  void _setupContactReleaseListener() {
    if (FirebaseAuth.instance.currentUser == null) return;
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

  Future<void> _checkAndEndAuction() async {
    await _auctionService.checkAndEndAuction(widget.auctionId);
  }

  Future<void> _placeBidWithAmount(double amount, double currentPrice, double minIncrement) async {
    if (amount < currentPrice + minIncrement) {
      setState(() => _bidError = 'Minimum bid: AED ${formatMoney(currentPrice + minIncrement)}');
      return;
    }
    setState(() => _bidError = null);
    await _placeBid(amount);
  }

  Future<void> _placeBid(double amount) async {
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
    final userData = userDoc.data();
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

      if (mounted) {
        _bidController.clear();
        setState(() {});
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
            backgroundColor: AppTheme.success,
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

  Future<void> _submitForApproval() async {
    setState(() => _isSubmitting = true);
    
    try {
      await _auctionService.submitForApproval(widget.auctionId);
      
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Auction submitted for admin approval'),
          backgroundColor: AppTheme.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString().replaceFirst('Exception: ', '')}'),
          backgroundColor: AppTheme.error,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _deleteDraft() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Draft?'),
        content: const Text(
          'This will permanently delete this draft auction and all uploaded images. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);

    try {
      // Delete auction document (Storage trigger will handle image cleanup)
      await FirebaseFirestore.instance
          .collection('auctions')
          .doc(widget.auctionId)
          .delete();

      if (!mounted) return;

      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Draft deleted successfully'),
          backgroundColor: AppTheme.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting draft: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    } finally {
      // Always reset state, even if widget unmounted
      if (mounted) {
        setState(() => _isDeleting = false);
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
      color = AppTheme.success;
    } else if (isActive) {
      icon = Icons.radio_button_checked;
      color = AppTheme.primaryBlue;
    } else {
      icon = Icons.radio_button_unchecked;
      color = AppTheme.textSecondary;
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
              color: isComplete || isActive ? AppTheme.textPrimary : AppTheme.textSecondary,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
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
            appBar: UnifiedAppBar(
              title: 'Auction Details',
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
            appBar: UnifiedAppBar(
              title: 'Auction Details',
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
            appBar: UnifiedAppBar(
              title: 'Auction Details',
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
        final isDraft = state == 'DRAFT' || state == 'PENDING_APPROVAL';
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

        return Scaffold(
          backgroundColor: AppTheme.backgroundLight,
          resizeToAvoidBottomInset: false,
          appBar: UnifiedAppBar(
            title: appBarTitle ?? 'Auction',
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          body: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: isDraft
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      child: _buildDraftAuctionUI(data, isSeller, state),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        // ——— Gallery (hero images) ———
                        _buildImageGallery(context, data),
                        // ——— Content block: title → status → price card → details → description ———
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 24),
                              // Title
                              Text(
                                (data['title'] as String?)?.trim() ?? 'Untitled',
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.textPrimary,
                                    ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 10),
                              // Status badge
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? AppTheme.success.withValues(alpha: 0.12)
                                      : AppTheme.textSecondary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isActive ? AppTheme.success.withValues(alpha: 0.4) : AppTheme.border,
                                  ),
                                ),
                                child: Text(
                                  isActive ? 'Active' : 'Ended',
                                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                        color: isActive ? AppTheme.success : AppTheme.textSecondary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              // Price, time, and bid card
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: AppTheme.surface,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: AppTheme.border),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.06),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Current price',
                                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                                      color: AppTheme.textSecondary,
                                                    ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'AED ${formatMoney(currentPrice)}',
                                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                      color: AppTheme.primaryBlue,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '${data['bidCount'] ?? 0} bids',
                                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                      color: AppTheme.textTertiary,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (isActive && endsAtTs != null)
                                          Container(
                                            height: _kBidCardControlHeight,
                                            padding: _kBidCardPadding,
                                            decoration: BoxDecoration(
                                              color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                                              borderRadius: BorderRadius.circular(_kBidCardRadius),
                                            ),
                                            alignment: Alignment.center,
                                            child: CountdownText(endsAt: endsAtTs),
                                          )
                                        else if (isEnded && winnerId != null)
                                          Text(
                                            'Ended',
                                            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                                  color: AppTheme.error,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                      ],
                                    ),
                                    // Place Bid UI shown to everyone; eligibility checked on tap (Place Bid / edit / increments)
                                    if (isActive && !isSeller) ...[
                                      const SizedBox(height: 12),
                                      const Divider(height: 1),
                                      const SizedBox(height: 12),
                                      Builder(
                                        builder: (context) {
                                          final minIncrement = (data['minIncrement'] as num?)?.toDouble() ?? 50.0;
                                          final minBid = currentPrice + minIncrement;
                                          if (_bidController.text.isEmpty) {
                                            WidgetsBinding.instance.addPostFrameCallback((_) {
                                              if (_bidController.text.isEmpty && mounted) {
                                                _bidController.text = (minBid).round().toString();
                                              }
                                            });
                                          }
                                          return Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              TextField(
                                                controller: _bidController,
                                                focusNode: _bidFocusNode,
                                                onTap: () async {
                                                  final ok = await _checkBidEligibilityAndRoute();
                                                  if (ok && mounted) {
                                                    FocusScope.of(context).requestFocus(_bidFocusNode);
                                                  }
                                                },
                                                decoration: InputDecoration(
                                                  labelText: 'Your bid (AED)',
                                                  hintText: formatMoney(minBid),
                                                  isDense: true,
                                                  contentPadding: _kBidCardPadding,
                                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(_kBidCardRadius)),
                                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(_kBidCardRadius)),
                                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(_kBidCardRadius)),
                                                  labelStyle: Theme.of(context).textTheme.bodySmall,
                                                ),
                                                keyboardType: TextInputType.number,
                                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                      color: AppTheme.primaryBlue,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                              ),
                                              const SizedBox(height: 8),
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: _BidIncrementChip(
                                                      label: '+50',
                                                      onTap: () {
                                                        _checkBidEligibilityAndRoute().then((ok) {
                                                          if (ok && mounted) {
                                                            final raw = double.tryParse(_bidController.text.replaceAll(',', '')) ?? minBid;
                                                            _bidController.text = (raw + 50).round().toString();
                                                          }
                                                        });
                                                      },
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Expanded(
                                                    child: _BidIncrementChip(
                                                      label: '+100',
                                                      onTap: () {
                                                        _checkBidEligibilityAndRoute().then((ok) {
                                                          if (ok && mounted) {
                                                            final raw = double.tryParse(_bidController.text.replaceAll(',', '')) ?? minBid;
                                                            _bidController.text = (raw + 100).round().toString();
                                                          }
                                                        });
                                                      },
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Expanded(
                                                    child: _BidIncrementChip(
                                                      label: '+200',
                                                      onTap: () {
                                                        _checkBidEligibilityAndRoute().then((ok) {
                                                          if (ok && mounted) {
                                                            final raw = double.tryParse(_bidController.text.replaceAll(',', '')) ?? minBid;
                                                            _bidController.text = (raw + 200).round().toString();
                                                          }
                                                        });
                                                      },
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 10),
                                              SizedBox(
                                                width: double.infinity,
                                                child: ElevatedButton(
                                                  onPressed: _isPlacingBid
                                                      ? null
                                                      : () async {
                                                          final ok = await _checkBidEligibilityAndRoute();
                                                          if (ok && mounted) {
                                                            final amount = double.tryParse(_bidController.text.replaceAll(',', ''));
                                                            _placeBidWithAmount(amount ?? minBid, currentPrice, minIncrement);
                                                          }
                                                        },
                                                  child: _isPlacingBid
                                                      ? const SizedBox(
                                                          width: 20,
                                                          height: 20,
                                                          child: CircularProgressIndicator(strokeWidth: 2),
                                                        )
                                                      : const Text('Place Bid'),
                                                ),
                                              ),
                                              if (_bidError != null) ...[
                                                const SizedBox(height: 6),
                                                Text(
                                                  _bidError!,
                                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.error),
                                                ),
                                              ],
                                            ],
                                          );
                                        },
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              // Details: 2-column grid with dividers
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: AppTheme.surface,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: AppTheme.border),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Details',
                                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                            color: AppTheme.textSecondary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    const SizedBox(height: 16),
                                    _buildDetailRowWithDivider(
                                      'Brand',
                                      effectiveBrandDisplay(data),
                                      isLast: false,
                                    ),
                                    _buildDetailRowWithDivider(
                                      'Category',
                                      '${categoryGroupDisplayName(effectiveCategoryGroup(data))} / ${subcategoryDisplayName(effectiveSubcategory(data))}',
                                      isLast: false,
                                    ),
                                    _buildDetailRowWithDivider(
                                      'Condition',
                                      (data['condition'] as String? ?? '—').toString(),
                                      isLast: false,
                                    ),
                                    _buildDetailRowWithDivider(
                                      'Item ID',
                                      data['itemIdentifier'] as String? ?? '—',
                                      isLast: true,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              // Description
                              Text(
                                'Description',
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                      color: AppTheme.textSecondary,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                data['description'] as String? ?? 'No description',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: AppTheme.textPrimary,
                                      height: 1.5,
                                    ),
                              ),
                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
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
                              color: AppTheme.primaryBlue.withValues(alpha: 0.1),
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
                                        'Final Price: AED ${formatMoney(finalPrice)}',
                                      ),
                                    Text(
                                      'Buyer Commission Due: AED ${formatMoney(buyerCommissionDue)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.primaryBlue,
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
                                      'Commission Due: AED ${formatMoney(buyerCommissionDue)}',
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
                              color: AppTheme.success.withValues(alpha: 0.1),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: const Row(
                                  children: [
                                    Icon(
                                      Icons.check_circle,
                                      color: AppTheme.success,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Buyer commission paid ✅',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.success,
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
                                  color: AppTheme.success.withValues(alpha: 0.1),
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
                                              color: AppTheme.success,
                                            ),
                                            SizedBox(width: 8),
                                            Text(
                                              'Contact Information Released',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: AppTheme.success,
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

                      bool sellerAccepted = false;
                      if (contractSnapshot.hasData &&
                          contractSnapshot.data!.exists) {
                        final contractData =
                            contractSnapshot.data!.data()
                                as Map<String, dynamic>;
                        sellerAccepted =
                            contractData['termsAcceptedSeller'] as bool? ??
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
                                      'Commission Due: AED ${formatMoney(sellerCommissionDue)}',
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
                                                    AppTheme.success,
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
                                icon: _isProcessing
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                  Colors.white),
                                        ),
                                      )
                                    : const Icon(Icons.payment),
                                label: const Text('Pay Seller Commission'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.warning,
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
                              color: AppTheme.success.withValues(alpha: 0.1),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: const Row(
                                  children: [
                                    Icon(
                                      Icons.check_circle,
                                      color: AppTheme.success,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Seller commission paid ✅',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.success,
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
                              // Get seller commission status for contact gating
                              final sellerCommissionPaidForContact =
                                  data['sellerCommissionPaid'] as bool? ?? false;
                              
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
                                    color: AppTheme.success.withValues(alpha: 0.1),
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
                                                color: AppTheme.success,
                                              ),
                                              SizedBox(width: 8),
                                              Text(
                                                'Buyer Contact Information',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: AppTheme.success,
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
                                    color: AppTheme.warning.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: AppTheme.warning),
                                  ),
                                  child: const Text(
                                    'Waiting for winner to confirm purchase.',
                                  ),
                                );
                              } else if (!buyerCommissionPaidSellerMsg) {
                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppTheme.warning.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: AppTheme.warning),
                                  ),
                                  child: const Text(
                                    'Waiting for buyer to pay commission before contacts can be released.',
                                  ),
                                );
                              } else if (!sellerCommissionPaidSellerMsg) {
                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppTheme.warning.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: AppTheme.warning),
                                  ),
                                  child: const Text(
                                    'Waiting for seller to pay commission before contacts can be released.',
                                  ),
                                );
                              } else if (!contactsUnlockedSellerMsg) {
                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: AppTheme.primaryBlue),
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
                          color: AppTheme.warning.withValues(alpha: 0.1),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Admin Override',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.warning,
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
                                      foregroundColor: AppTheme.warning,
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
                      final depositStatusForDelivery =
                          data['depositStatus'] as String?;
                      
                      // Deposit must be held (or waived) to unlock contacts
                      final depositHeldOrWaivedForDelivery =
                          depositStatusForDelivery == 'held' ||
                              depositStatusForDelivery == 'waived';
                      
                      return StreamBuilder<DocumentSnapshot>(
                        stream: _contractService.streamContract(widget.auctionId),
                        builder: (context, contractSnapshot) {
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
                                                  ? AppTheme.success
                                                  : AppTheme.textSecondary,
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
                                                    backgroundColor: AppTheme.success,
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
                                                  ? AppTheme.success
                                                  : AppTheme.textSecondary,
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
                                                    backgroundColor: AppTheme.success,
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
                                    color: AppTheme.success.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AppTheme.success),
                                  ),
                                  child: const Row(
                                    children: [
                                      Icon(Icons.check_circle, color: AppTheme.success),
                                      SizedBox(width: 8),
                                      Text(
                                        'Delivery confirmed by both parties',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.success,
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
                const Divider(height: 1),
                const SizedBox(height: 20),
                Text(
                  'Recent bids',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                        letterSpacing: 0.5,
                      ),
                ),
                const SizedBox(height: 12),
                StreamBuilder<QuerySnapshot>(
                  stream: _auctionService.streamBids(widget.auctionId),
                  builder: (context, bidsSnapshot) {
                    if (bidsSnapshot.hasError) {
                      return Text(
                        'Unable to load bids',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.error,
                            ),
                      );
                    }

                    if (bidsSnapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )),
                      );
                    }

                    if (!bidsSnapshot.hasData ||
                        bidsSnapshot.data!.docs.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: Text(
                          'No bids yet',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppTheme.textTertiary,
                              ),
                        ),
                      );
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: bidsSnapshot.data!.docs.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final bidDoc = bidsSnapshot.data!.docs[index];
                          final bidData = bidDoc.data() as Map<String, dynamic>;
                          final amount =
                              (bidData['amount'] as num?)?.toDouble() ?? 0.0;
                          final createdAt = bidData['createdAt'] as Timestamp?;

                          String timeText = '—';
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

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'AED ${formatMoney(amount)}',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.textPrimary,
                                      ),
                                ),
                                Text(
                                  timeText,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: AppTheme.textTertiary,
                                      ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
                          ],
                        ),
                      ),
              ],
            ),
          ),
          ),
        );
      },
    );
  }

  Widget _buildDraftAuctionUI(
    Map<String, dynamic> data,
    bool isSeller,
    String state,
  ) {
    final images = data['images'] as List<dynamic>?;
    final hasImages = images != null && images.isNotEmpty;
    final imagesWithUrl = images?.where((img) {
      if (img is! Map<String, dynamic>) return false;
      final url = img['url'] as String?;
      return url != null && url.isNotEmpty;
    }).toList();
    final imageCount = imagesWithUrl?.length ?? 0;
    final isPending = state == 'PENDING_APPROVAL';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Status Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isPending 
                ? AppTheme.warning.withValues(alpha: 0.1)
                : AppTheme.primaryBlue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isPending 
                  ? AppTheme.warning 
                  : AppTheme.primaryBlue,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isPending ? Icons.hourglass_empty : Icons.edit_document,
                color: isPending ? AppTheme.warning : AppTheme.primaryBlue,
                size: 32,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isPending ? 'Pending Approval' : 'Draft',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isPending
                          ? 'Your auction is being reviewed by admin'
                          : 'Complete and submit for approval',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Images Card
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.photo_library, color: AppTheme.primaryBlue),
                    const SizedBox(width: 12),
                    Text(
                      'Images',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: imageCount >= 1
                            ? AppTheme.success.withValues(alpha: 0.1)
                            : AppTheme.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: imageCount >= 1 ? AppTheme.success : AppTheme.error,
                        ),
                      ),
                      child: Text(
                        '$imageCount/6',
                        style: TextStyle(
                          color: imageCount >= 1 ? AppTheme.success : AppTheme.error,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (hasImages && imagesWithUrl!.isNotEmpty)
                  SizedBox(
                    height: 120,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: imagesWithUrl.length,
                      itemBuilder: (context, index) {
                        final img = imagesWithUrl[index] as Map<String, dynamic>;
                        final url = img['url'] as String;
                        final isPrimary = img['isPrimary'] as bool? ?? false;

                        return Container(
                          margin: const EdgeInsets.only(right: 12),
                          width: 120,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isPrimary ? AppTheme.primaryBlue : Colors.grey[300]!,
                              width: isPrimary ? 3 : 1,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.network(
                                  url,
                                  fit: BoxFit.cover,
                                  loadingBuilder: (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return const Center(
                                      child: CircularProgressIndicator(),
                                    );
                                  },
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Icon(Icons.broken_image, size: 48);
                                  },
                                ),
                                if (isPrimary)
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryBlue,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Icon(
                                        Icons.star,
                                        size: 16,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  )
                else
                  Container(
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate, size: 48, color: Colors.grey),
                          SizedBox(height: 8),
                          Text(
                            'No images uploaded yet',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Auction Details Card
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.description, color: AppTheme.primaryBlue),
                    const SizedBox(width: 12),
                    Text(
                      'Auction Details',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildDetailRow('Title', data['title'] as String? ?? 'Not set'),
                _buildDetailRow('Brand', effectiveBrandDisplay(data)),
                _buildDetailRow(
                  'Category',
                  '${categoryGroupDisplayName(effectiveCategoryGroup(data))} / ${subcategoryDisplayName(effectiveSubcategory(data))}',
                ),
                _buildDetailRow('Condition', data['condition'] as String? ?? 'Not set'),
                _buildDetailRow('Item ID', data['itemIdentifier'] as String? ?? 'Not set'),
                _buildDetailRow(
                  'Start Price', 
                  'AED ${formatMoney((data['startPrice'] as num?)?.toDouble() ?? 0.0)}',
                ),
                _buildDetailRow(
                  'Duration',
                  '${data['durationDays'] ?? 'Not set'} days',
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 12),
                Text(
                  'Description',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  data['description'] as String? ?? 'No description provided',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),

        if (isSeller && !isPending) ...[
          const SizedBox(height: 24),
          // Action Buttons for DRAFT state
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isDeleting || _isSubmitting
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => EditDraftAuctionPage(
                                auctionId: widget.auctionId,
                              ),
                            ),
                          );
                        },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    side: const BorderSide(color: AppTheme.primaryBlue),
                  ),
                  icon: const Icon(Icons.edit),
                  label: const Text('Edit'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _isDeleting || _isSubmitting ? null : _submitForApproval,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    padding: const EdgeInsets.all(16),
                  ),
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.send),
                  label: Text(_isSubmitting ? 'Submitting...' : 'Submit for Approval'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isDeleting || _isSubmitting ? null : _deleteDraft,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                side: const BorderSide(color: AppTheme.error),
                foregroundColor: AppTheme.error,
              ),
              icon: _isDeleting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(AppTheme.error),
                      ),
                    )
                  : const Icon(Icons.delete_outline),
              label: Text(_isDeleting ? 'Deleting...' : 'Delete Draft'),
            ),
          ),
        ] else if (isPending) ...[
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.warning),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: AppTheme.warning),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Your auction is awaiting admin approval. You will be notified once it\'s reviewed.',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// Full-width hero gallery (primary image first).
  Widget _buildImageGallery(BuildContext context, Map<String, dynamic> data) {
    final images = data['images'] as List<dynamic>?;
    final hasImages = images != null && images.isNotEmpty;
    final withUrl = images?.where((img) {
      if (img is! Map<String, dynamic>) return false;
      final url = img['url'] as String?;
      return url != null && url.isNotEmpty;
    }).toList() ?? <dynamic>[];
    // Primary first
    withUrl.sort((a, b) {
      final ap = (a as Map)['isPrimary'] == true ? 0 : 1;
      final bp = (b as Map)['isPrimary'] == true ? 0 : 1;
      return ap.compareTo(bp);
    });
    if (withUrl.isEmpty) {
      return Container(
        height: 220,
        width: double.infinity,
        color: AppTheme.backgroundGrey,
        child: Center(
          child: Icon(Icons.image_outlined, size: 48, color: AppTheme.textTertiary),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: SizedBox(
        height: 280,
        width: double.infinity,
        child: PageView.builder(
          itemCount: withUrl.length,
          itemBuilder: (context, index) {
            final img = withUrl[index] as Map<String, dynamic>;
            final url = img['url'] as String? ?? '';
            return Image.network(
              url,
              fit: BoxFit.cover,
              width: double.infinity,
              errorBuilder: (_, __, ___) => Container(
                color: AppTheme.backgroundGrey,
                child: Center(
                  child: Icon(Icons.broken_image_outlined, size: 48, color: AppTheme.textTertiary),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Two-column detail row with optional divider (premium layout).
  Widget _buildDetailRowWithDivider(String label, String value, {required bool isLast}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 96,
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textSecondary,
                      ),
                ),
              ),
              Expanded(
                child: Text(
                  value,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textPrimary,
                      ),
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          Divider(
            height: 1,
            thickness: 1,
            color: AppTheme.divider.withValues(alpha: 0.6),
          ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textPrimary,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BidIncrementChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _BidIncrementChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kBidCardControlHeight,
      child: Material(
        color: AppTheme.primaryBlue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(_kBidCardRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(_kBidCardRadius),
          child: Padding(
            padding: _kBidCardPadding,
            child: Center(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppTheme.primaryBlue,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ),
        ),
      ),
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

  @override
  Widget build(BuildContext context) {
    return Text(
      formatTimeLeftCompact(widget.endsAt),
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: AppTheme.primaryBlue,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
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
                  'Forfeit Amount: AED ${formatMoney(widget.forfeitAmount!)}',
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
                  'Held: AED ${formatMoney(widget.depositHeld!)}',
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
