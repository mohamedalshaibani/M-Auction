import 'package:firebase_auth/firebase_auth.dart';
import 'firestore_service.dart';
import 'auction_service.dart';

/// Step the user must complete before they can place a bid.
/// Order: login → verifyEmail → createProfile → acceptTerms → addDeposit → kyc.
enum BidEligibilityStep {
  /// All checks passed; user can bid.
  canBid,
  /// User must sign in (phone OTP).
  login,
  /// User must verify email.
  verifyEmail,
  /// User must complete profile (create Firestore user doc).
  createProfile,
  /// User must accept auction terms.
  acceptTerms,
  /// User must add/lock required security deposit (wallet).
  addDeposit,
  /// User must submit KYC (ID/passport upload).
  kyc,
}

/// Result of bid eligibility check.
class BidEligibilityResult {
  final bool canBid;
  final BidEligibilityStep nextStep;
  final String message;

  const BidEligibilityResult({
    required this.canBid,
    required this.nextStep,
    required this.message,
  });
}

/// Checks whether the user can place a bid.
/// Order: login → verify email → create profile → accept terms → add deposit → KYC.
class BidEligibilityService {
  final FirestoreService _firestore = FirestoreService();
  final AuctionService _auctionService = AuctionService();

  /// [minBidPrice] optional: used for deposit check (e.g. current price + min increment).
  /// If null, uses a nominal 100 AED to require wallet has some eligible funds.
  Future<BidEligibilityResult> checkEligibility({double? minBidPrice}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const BidEligibilityResult(
        canBid: false,
        nextStep: BidEligibilityStep.login,
        message: 'Sign in to place a bid.',
      );
    }

    final userDoc = await _firestore.getUser(user.uid);
    if (!userDoc.exists) {
      return const BidEligibilityResult(
        canBid: false,
        nextStep: BidEligibilityStep.createProfile,
        message: 'Complete your profile to place a bid.',
      );
    }

    final data = userDoc.data() as Map<String, dynamic>? ?? {};
    final email = data['email'] as String?;
    final emailVerified = data['emailVerified'] as bool? ?? false;
    final termsAccepted = data['termsAccepted'] as bool? ?? false;
    final kycStatus = data['kycStatus'] as String? ?? 'not_submitted';

    if (email == null || email.toString().trim().isEmpty) {
      return const BidEligibilityResult(
        canBid: false,
        nextStep: BidEligibilityStep.verifyEmail,
        message: 'Add and verify your email to place a bid.',
      );
    }

    if (!emailVerified) {
      return const BidEligibilityResult(
        canBid: false,
        nextStep: BidEligibilityStep.verifyEmail,
        message: 'Your email must be verified to place a bid.',
      );
    }

    if (!termsAccepted) {
      return const BidEligibilityResult(
        canBid: false,
        nextStep: BidEligibilityStep.acceptTerms,
        message: 'You must accept the Auction Terms & Conditions to place a bid.',
      );
    }

    // Deposit: wallet must exist and have sufficient eligible deposit for at least a minimal bid
    final priceForDepositCheck = minBidPrice ?? 100.0;
    final depositCheck = await _auctionService.checkDepositRequirement(
      bidderId: user.uid,
      auctionPrice: priceForDepositCheck,
      auctionId: null,
    );
    final hasEnough = depositCheck['hasEnough'] as bool? ?? false;
    final vipWaived = depositCheck['vipWaived'] as bool? ?? false;
    if (!vipWaived && !hasEnough) {
      return const BidEligibilityResult(
        canBid: false,
        nextStep: BidEligibilityStep.addDeposit,
        message: 'Add funds to your wallet. A security deposit is required to place bids.',
      );
    }

    if (kycStatus != 'pending' && kycStatus != 'approved') {
      return const BidEligibilityResult(
        canBid: false,
        nextStep: BidEligibilityStep.kyc,
        message: 'Complete KYC verification (ID/passport) to place a bid.',
      );
    }

    return const BidEligibilityResult(
      canBid: true,
      nextStep: BidEligibilityStep.canBid,
      message: 'You can place a bid.',
    );
  }
}
