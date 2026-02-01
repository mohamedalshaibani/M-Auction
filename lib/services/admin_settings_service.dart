import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/category_model.dart';
import '../models/watch_brand.dart';

class AdminSettingsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Map<String, dynamic>? _cachedSettings;

  Future<Map<String, dynamic>> _fetchSettings() async {
    if (_cachedSettings != null) return _cachedSettings!;

    final doc = await _firestore.collection('adminSettings').doc('main').get();
    if (!doc.exists) {
      throw Exception('Admin settings not found');
    }

    _cachedSettings = doc.data();
    return _cachedSettings!;
  }

  Future<void> refresh() async {
    _cachedSettings = null;
    await _fetchSettings();
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

  // Watch brands: source of truth is Firestore collection watchBrands (doc id = brand id, fields: name, order)
  Future<List<WatchBrand>> getWatchBrands() async {
    try {
      final snapshot = await _firestore.collection('watchBrands').get();
      if (snapshot.docs.isNotEmpty) {
        final list = snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return WatchBrand.fromMap(data);
        }).toList();
        list.sort((a, b) => a.order.compareTo(b.order));
        return list;
      }
    } catch (_) {}
    return List.from(defaultWatchBrands)..sort((a, b) => a.order.compareTo(b.order));
  }

  // Whitelist (legacy — keep for backward compatibility)
  Future<List<String>> getWhitelistBags() async {
    final settings = await _fetchSettings();
    final whitelist = settings['whitelist'] as Map<String, dynamic>?;
    final bags = whitelist?['bags'] as List<dynamic>?;
    return bags?.map((e) => e.toString()).toList() ?? [];
  }

  /// Legacy: returns watch brand names only (from getWatchBrands). Use getWatchBrands() for id+name.
  Future<List<String>> getWhitelistWatches() async {
    final brands = await getWatchBrands();
    return brands.map((b) => b.name).toList();
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

  // Duration options
  Future<List<int>> getDurationOptions() async {
    final settings = await _fetchSettings();
    final durations = settings['durationOptions'] as List<dynamic>?;
    return durations?.map((e) => (e as num).toInt()).toList() ?? [7, 14, 21];
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

  // Deposit rules
  Future<List<Map<String, dynamic>>> getDepositRulesTiers() async {
    final settings = await _fetchSettings();
    final depositRules = settings['depositRules'] as Map<String, dynamic>?;
    final tiers = depositRules?['tiers'] as List<dynamic>?;
    return tiers?.cast<Map<String, dynamic>>() ?? [];
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

  // Compute required deposit based on price and deposit rules
  Future<double> computeRequiredDeposit(double price) async {
    final tiers = await getDepositRulesTiers();
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

  // Calculate maximum bid limit based on eligible deposit
  Future<double> calculateMaxBidLimit(double eligibleDeposit) async {
    final tiers = await getDepositRulesTiers();
    if (tiers.isEmpty) return double.infinity;

    double maxBid = 0.0;

    // Reverse sort tiers by min value to find highest bid we can afford
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

      // Calculate max bid for this tier where requiredDeposit <= eligibleDeposit
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
        // No max means it's the highest tier
        if (maxBidForTier >= minValue) {
          maxBid = maxBidForTier;
          break;
        }
      }
    }

    return maxBid;
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
