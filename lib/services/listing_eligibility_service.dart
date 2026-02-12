import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firestore_service.dart';

/// Step the user must complete before they can create a listing.
enum ListingEligibilityStep {
  /// All checks passed; user can proceed to create listing.
  createListing,
  /// User must verify phone (e.g. complete phone OTP).
  verifyPhone,
  /// User must verify email (add email + verify via link/OTP).
  verifyEmail,
  /// User must accept auction terms before listing.
  acceptTerms,
}

/// Result of listing eligibility check.
class ListingEligibilityResult {
  final bool canProceed;
  final ListingEligibilityStep nextStep;
  final String message;

  const ListingEligibilityResult({
    required this.canProceed,
    required this.nextStep,
    required this.message,
  });
}

/// Checks whether the user can create a listing (verified account, terms accepted).
class ListingEligibilityService {
  final FirestoreService _firestore = FirestoreService();

  /// Runs eligibility check. Returns next step and message.
  /// Order: verify phone → verify email → accept terms → create listing.
  Future<ListingEligibilityResult> checkEligibility() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const ListingEligibilityResult(
        canProceed: false,
        nextStep: ListingEligibilityStep.verifyPhone,
        message: 'You must be signed in to list an item.',
      );
    }

    final userDoc = await _firestore.getUser(user.uid);
    if (!userDoc.exists) {
      return const ListingEligibilityResult(
        canProceed: false,
        nextStep: ListingEligibilityStep.verifyPhone,
        message: 'Profile not found. Please complete sign up.',
      );
    }

    final data = userDoc.data() as Map<String, dynamic>? ?? {};
    final phoneVerified = data['phoneVerified'] as bool? ?? false;
    final email = data['email'] as String?;
    final emailVerified = data['emailVerified'] as bool? ?? false;
    final termsAccepted = data['termsAccepted'] as bool? ?? false;

    // If user signed in with phone, consider phone verified (backfill for existing users)
    final hasPhone = user.phoneNumber != null && user.phoneNumber!.trim().isNotEmpty;
    final effectivePhoneVerified = phoneVerified || hasPhone;

    if (!effectivePhoneVerified) {
      return const ListingEligibilityResult(
        canProceed: false,
        nextStep: ListingEligibilityStep.verifyPhone,
        message: 'Your phone number must be verified before you can list items.',
      );
    }

    if (email == null || email.trim().isEmpty) {
      return const ListingEligibilityResult(
        canProceed: false,
        nextStep: ListingEligibilityStep.verifyEmail,
        message: 'Please add and verify your email address before listing.',
      );
    }

    if (!emailVerified) {
      return const ListingEligibilityResult(
        canProceed: false,
        nextStep: ListingEligibilityStep.verifyEmail,
        message: 'Your email must be verified before you can list items.',
      );
    }

    if (!termsAccepted) {
      return const ListingEligibilityResult(
        canProceed: false,
        nextStep: ListingEligibilityStep.acceptTerms,
        message: 'You must accept the Auction Terms & Conditions before listing.',
      );
    }

    return const ListingEligibilityResult(
      canProceed: true,
      nextStep: ListingEligibilityStep.createListing,
      message: 'You can create a listing.',
    );
  }

  /// Mark phone as verified (e.g. after OTP). Call after successful phone sign-in / profile creation.
  Future<void> setPhoneVerified(String uid) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'phoneVerified': true,
      'phoneVerifiedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Store email and optionally mark verified (e.g. after Firebase email verification).
  Future<void> setEmail(String uid, String email, {bool verified = false}) async {
    final trimmed = email.trim();
    final updates = <String, dynamic>{
      'email': trimmed,
      'emailLower': trimmed.isEmpty ? null : trimmed.toLowerCase(),
      'emailVerified': verified,
    };
    if (verified) {
      updates['emailVerifiedAt'] = FieldValue.serverTimestamp();
    }
    await FirebaseFirestore.instance.collection('users').doc(uid).update(updates);
  }

  /// Mark email as verified (call after user completes email verification link).
  Future<void> setEmailVerified(String uid) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'emailVerified': true,
      'emailVerifiedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Record terms acceptance for listing.
  Future<void> setTermsAccepted(String uid, {String termsVersion = 'v1.0'}) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'termsAccepted': true,
      'termsAcceptedAt': FieldValue.serverTimestamp(),
      'termsVersion': termsVersion,
    });
  }
}
