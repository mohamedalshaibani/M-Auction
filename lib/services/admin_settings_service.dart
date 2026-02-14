import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/category_model.dart';

class AdminSettingsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Map<String, dynamic>? _cachedSettings;
  Map<String, dynamic>? _cachedFees;

  Future<Map<String, dynamic>> _fetchSettings() async {
    if (_cachedSettings != null) return _cachedSettings!;

    final doc = await _firestore.collection('adminSettings').doc('main').get();
    if (!doc.exists) {
      throw Exception('Admin settings not found');
    }

    _cachedSettings = doc.data();
    return _cachedSettings!;
  }

  /// Fees/deposit config: adminSettings/fees (feeRules, depositTiers, depositMaxAmount).
  Future<Map<String, dynamic>> _fetchFees() async {
    if (_cachedFees != null) return _cachedFees!;
    final doc = await _firestore.collection('adminSettings').doc('fees').get();
    _cachedFees = doc.exists ? (doc.data() ?? {}) : {};
    return _cachedFees!;
  }

  Future<void> refresh() async {
    _cachedSettings = null;
    _cachedFees = null;
    await _fetchSettings();
    await _fetchFees();
  }

  /// Save fees config (admin only). Persists to adminSettings/fees.
  Future<void> setFeesConfig(Map<String, dynamic> config) async {
    await _firestore.collection('adminSettings').doc('fees').set(
      {...config, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
    _cachedFees = null;
  }

  /// Load full fees config for Super Admin UI (feeRules, depositTiers, depositMaxAmount, depositHoldRules).
  Future<Map<String, dynamic>> getFeesConfig() async {
    final fees = await _fetchFees();
    return Map<String, dynamic>.from(fees);
  }

  /// Stripe publishable key (client-safe). Stored in adminSettings/main.stripePublishableKey.
  Future<String?> getStripePublishableKey() async {
    try {
      final settings = await _fetchSettings();
      final key = settings['stripePublishableKey'] as String?;
      return (key != null && key.toString().trim().isNotEmpty) ? key.toString().trim() : null;
    } catch (_) {
      return null;
    }
  }

  // Commission settings (buyer/seller)
  Future<double> getBuyerCommissionPercent() async {
    final settings = await _fetchSettings();
    return (settings['buyerCommissionPercent'] as num?)?.toDouble() ?? 0.0;
  }

  Future<double> getBuyerCommissionMin() async {
    final settings = await _fetchSettings();
    return (settings['buyerCommissionMin'] as num?)?.toDouble() ?? 0.0;
  }

  Future<double> getSellerCommissionPercent() async {
    final settings = await _fetchSettings();
    return (settings['sellerCommissionPercent'] as num?)?.toDouble() ?? 0.0;
  }

  Future<double> getSellerCommissionMin() async {
    final settings = await _fetchSettings();
    return (settings['sellerCommissionMin'] as num?)?.toDouble() ?? 0.0;
  }

  // Categories (new structure) — source of truth; fallback to defaults
  Future<List<CategoryGroup>> getTopLevelCategories() async {
    try {
      final settings = await _fetchSettings();
      final list = settings['categories'] as List<dynamic>?;
      if (list != null && list.isNotEmpty) {
        return list
            .map((e) => CategoryGroup.fromMap(e as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order));
      }
    } catch (_) {}
    return List.from(defaultTopLevelCategories)..sort((a, b) => a.order.compareTo(b.order));
  }

  Future<List<Subcategory>> getSubcategories(String parentId) async {
    try {
      final settings = await _fetchSettings();
      final list = settings['subcategories'] as List<dynamic>?;
      if (list != null && list.isNotEmpty) {
        final all = list
            .map((e) => Subcategory.fromMap(e as Map<String, dynamic>))
            .where((s) => s.parentId == parentId)
            .toList();
        all.sort((a, b) => a.order.compareTo(b.order));
        return all;
      }
    } catch (_) {}
    return defaultSubcategories
        .where((s) => s.parentId == parentId)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
  }

  // Min increment
  Future<double> getMinIncrementDefault() async {
    final settings = await _fetchSettings();
    return (settings['minIncrementDefault'] as num?)?.toDouble() ?? 0.0;
  }

  // Anti-sniping
  Future<int> getAntiSnipingWindowMinutes() async {
    final settings = await _fetchSettings();
    final antiSniping = settings['antiSniping'] as Map<String, dynamic>?;
    return (antiSniping?['windowMinutes'] as num?)?.toInt() ?? 2;
  }

  Future<int> getAntiSnipingExtendMinutes() async {
    final settings = await _fetchSettings();
    final antiSniping = settings['antiSniping'] as Map<String, dynamic>?;
    return (antiSniping?['extendMinutes'] as num?)?.toInt() ?? 2;
  }

  // Duration options (3, 5, 7 days only; filter to these if admin has others)
  Future<List<int>> getDurationOptions() async {
    const allowed = [3, 5, 7];
    final settings = await _fetchSettings();
    final durations = settings['durationOptions'] as List<dynamic>?;
    if (durations == null || durations.isEmpty) {
      return List.from(allowed);
    }
    final list = durations.map((e) => (e as num).toInt()).where((d) => allowed.contains(d)).toList();
    return list.isEmpty ? List.from(allowed) : list..sort();
  }

  // Listing fee
  Future<List<Map<String, dynamic>>> getListingFeeTiers() async {
    final settings = await _fetchSettings();
    final listingFee = settings['listingFee'] as Map<String, dynamic>?;
    final tiers = listingFee?['tiers'] as List<dynamic>?;
    return tiers?.cast<Map<String, dynamic>>() ?? [];
  }

  Future<double> getListingFeeMin() async {
    final settings = await _fetchSettings();
    final listingFee = settings['listingFee'] as Map<String, dynamic>?;
    return (listingFee?['min'] as num?)?.toDouble() ?? 0.0;
  }

  Future<double> getListingFeeMax() async {
    final settings = await _fetchSettings();
    final listingFee = settings['listingFee'] as Map<String, dynamic>?;
    return (listingFee?['max'] as num?)?.toDouble() ?? 0.0;
  }

  Future<double> getListingFeeRate() async {
    final settings = await _fetchSettings();
    final listingFee = settings['listingFee'] as Map<String, dynamic>?;
    return (listingFee?['rate'] as num?)?.toDouble() ?? 0.0;
  }

  Future<Map<String, double>> getDurationFeeAdders() async {
    final settings = await _fetchSettings();
    final listingFee = settings['listingFee'] as Map<String, dynamic>?;
    final adders = listingFee?['durationFeeAdders'] as Map<String, dynamic>?;
    if (adders == null) return {};
    return adders.map((key, value) =>
        MapEntry(key, (value as num).toDouble()));
  }

  // Deposit rules (main doc: min/max/rate tiers for backward compatibility)
  Future<List<Map<String, dynamic>>> getDepositRulesTiers() async {
    final settings = await _fetchSettings();
    final depositRules = settings['depositRules'] as Map<String, dynamic>?;
    final tiers = depositRules?['tiers'] as List<dynamic>?;
    return tiers?.cast<Map<String, dynamic>>() ?? [];
  }

  /// Deposit tiers from fees config: [{ amount, maxBidLimit }]. Empty if not set.
  Future<List<Map<String, dynamic>>> getDepositTiersList() async {
    final fees = await _fetchFees();
    final list = fees['depositTiers'] as List<dynamic>?;
    if (list == null || list.isEmpty) return [];
    return list
        .map((e) => (e as Map<String, dynamic>))
        .where((t) =>
            (t['amount'] is num) &&
            (t['maxBidLimit'] is num))
        .toList();
  }

  /// Max allowed deposit amount (cap). No cap if null or <= 0.
  Future<double> getDepositMaxAmount() async {
    final fees = await _fetchFees();
    final v = fees['depositMaxAmount'];
    if (v == null) return double.infinity;
    final n = (v is num) ? v.toDouble() : double.tryParse(v.toString());
    return (n != null && n > 0) ? n : double.infinity;
  }

  // Forfeit rules
  Future<List<Map<String, dynamic>>> getForfeitRulesTiers() async {
    final settings = await _fetchSettings();
    final forfeitRules = settings['forfeitRules'] as Map<String, dynamic>?;
    final tiers = forfeitRules?['tiers'] as List<dynamic>?;
    return tiers?.cast<Map<String, dynamic>>() ?? [];
  }

  // Winner deadline hours
  Future<int> getWinnerDeadlineHours() async {
    final settings = await _fetchSettings();
    return (settings['winnerDeadlineHours'] as num?)?.toInt() ?? 48;
  }

  /// Days after delivery confirmation request before auto-release or admin review (e.g. 7).
  /// Used by backend for fallback when buyer doesn't confirm; deposit release gate is buyer confirm.
  Future<int> getDeliveryConfirmationTimeoutDays() async {
    final fees = await _fetchFees();
    final v = fees['deliveryConfirmationTimeoutDays'];
    if (v == null) return 7;
    return (v is num) ? (v as num).toInt() : (int.tryParse(v.toString()) ?? 7);
  }

  // Compute required deposit based on price (tier-based from fees, else rate-based from main)
  Future<double> computeRequiredDeposit(double price) async {
    final tierList = await getDepositTiersList();
    if (tierList.isNotEmpty) {
      // Tier-based: smallest amount such that maxBidLimit >= price
      double best = double.infinity;
      for (final t in tierList) {
        final maxBid = (t['maxBidLimit'] as num).toDouble();
        if (maxBid >= price) {
          final amt = (t['amount'] as num).toDouble();
          if (amt < best) best = amt;
        }
      }
      return best.isFinite ? best : 0.0;
    }

    final tiers = await getDepositRulesTiers();
    if (tiers.isEmpty) return 0.0;

    for (final tier in tiers) {
      final minValue = (tier['min'] as num?)?.toDouble() ?? 0.0;
      final maxValue = tier['max'] as num?;
      final rate = (tier['rate'] as num?)?.toDouble() ?? 0.0;

      if (maxValue != null) {
        final max = maxValue.toDouble();
        if (price >= minValue && price <= max) return price * rate;
      } else {
        if (price >= minValue) return price * rate;
      }
    }
    return 0.0;
  }

  // Compute forfeit amount based on price and forfeit rules
  Future<double> computeForfeitAmountFromPrice(double price) async {
    final tiers = await getForfeitRulesTiers();
    if (tiers.isEmpty) return 0.0;

    // Find matching tier
    for (final tier in tiers) {
      final minValue = (tier['min'] as num?)?.toDouble() ?? 0.0;
      final maxValue = tier['max'] as num?;
      final rate = (tier['rate'] as num?)?.toDouble() ?? 0.0;

      if (maxValue != null) {
        final max = maxValue.toDouble();
        if (price >= minValue && price <= max) {
          return price * rate;
        }
      } else {
        // No max means it's the highest tier
        if (price >= minValue) {
          return price * rate;
        }
      }
    }

    return 0.0;
  }

  // Calculate maximum bid limit based on eligible deposit (tier-based from fees, else rate-based from main)
  Future<double> calculateMaxBidLimit(double eligibleDeposit) async {
    final tierList = await getDepositTiersList();
    if (tierList.isNotEmpty) {
      // Tier-based: highest maxBidLimit among tiers with amount <= eligibleDeposit
      double best = 0.0;
      for (final t in tierList) {
        final amt = (t['amount'] as num).toDouble();
        if (amt <= eligibleDeposit) {
          final maxBid = (t['maxBidLimit'] as num).toDouble();
          if (maxBid > best) best = maxBid;
        }
      }
      return best;
    }

    final tiers = await getDepositRulesTiers();
    if (tiers.isEmpty) return double.infinity;

    double maxBid = 0.0;
    final sortedTiers = List<Map<String, dynamic>>.from(tiers)
      ..sort((a, b) {
        final aMin = (a['min'] as num?)?.toDouble() ?? 0.0;
        final bMin = (b['min'] as num?)?.toDouble() ?? 0.0;
        return bMin.compareTo(aMin);
      });

    for (final tier in sortedTiers) {
      final minValue = (tier['min'] as num?)?.toDouble() ?? 0.0;
      final maxValue = tier['max'] as num?;
      final rate = (tier['rate'] as num?)?.toDouble() ?? 0.0;
      if (rate == 0) continue;
      final maxRequiredDeposit = eligibleDeposit;
      final maxBidForTier = maxRequiredDeposit / rate;

      if (maxValue != null) {
        final max = maxValue.toDouble();
        if (maxBidForTier >= minValue && maxBidForTier <= max) {
          maxBid = maxBidForTier;
          break;
        } else if (maxBidForTier > max) {
          maxBid = max;
        }
      } else {
        if (maxBidForTier >= minValue) {
          maxBid = maxBidForTier;
          break;
        }
      }
    }
    return maxBid;
  }

  /// For a given deposit amount, return the maxBidLimit from the matching tier (exact or nearest).
  /// Returns null if amount is not in any tier or no tiers configured.
  Future<double?> getMaxBidLimitForDepositAmount(double amount) async {
    final tierList = await getDepositTiersList();
    if (tierList.isEmpty) return null;
    // Exact match first
    for (final t in tierList) {
      final a = (t['amount'] as num).toDouble();
      if (a == amount) return (t['maxBidLimit'] as num).toDouble();
    }
    // Nearest tier (smallest tier >= amount, or largest tier < amount)
    List<Map<String, dynamic>> sorted = List.from(tierList)
      ..sort((a, b) => (a['amount'] as num).compareTo(b['amount'] as num));
    double? nearestMaxBid;
    for (final t in sorted) {
      final a = (t['amount'] as num).toDouble();
      if (a <= amount) nearestMaxBid = (t['maxBidLimit'] as num).toDouble();
      else break;
    }
    return nearestMaxBid;
  }

  // Compute forfeit amount based on locked deposit and forfeit rules
  Future<double> computeForfeitAmount(double lockedAmount) async {
    final tiers = await getForfeitRulesTiers();
    if (tiers.isEmpty) return lockedAmount; // Default: forfeit all

    // Find matching tier
    for (final tier in tiers) {
      final minValue = (tier['min'] as num?)?.toDouble() ?? 0.0;
      final maxValue = tier['max'] as num?;
      final rate = (tier['rate'] as num?)?.toDouble() ?? 1.0;

      if (maxValue != null) {
        final max = maxValue.toDouble();
        if (lockedAmount >= minValue && lockedAmount <= max) {
          return lockedAmount * rate;
        }
      } else {
        // No max means it's the highest tier
        if (lockedAmount >= minValue) {
          return lockedAmount * rate;
        }
      }
    }

    return lockedAmount; // Default: forfeit all
  }

  // Compute listing fee preview
  Future<double> computeListingFeePreview({
    required double startPrice,
    required int durationDays,
  }) async {
    final rate = await getListingFeeRate();
    final baseFee = startPrice * rate;
    final minFee = await getListingFeeMin();
    final maxFee = await getListingFeeMax();
    final durationAdders = await getDurationFeeAdders();

    double fee = baseFee.clamp(minFee, maxFee);

    final adderKey = durationDays.toString();
    if (durationAdders.containsKey(adderKey)) {
      fee += durationAdders[adderKey]!;
    }

    return fee;
  }
}
