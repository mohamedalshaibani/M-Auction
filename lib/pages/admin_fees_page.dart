import 'package:flutter/material.dart';
import '../services/admin_settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/unified_app_bar.dart';

/// Super Admin screen: manage auction fees and deposit tiers (adminSettings/fees).
/// No hardcoding: feeRules, depositTiers, depositMaxAmount persisted in Firestore.
class AdminFeesPage extends StatefulWidget {
  const AdminFeesPage({super.key});

  @override
  State<AdminFeesPage> createState() => _AdminFeesPageState();
}

class _AdminFeesPageState extends State<AdminFeesPage> {
  final AdminSettingsService _adminSettings = AdminSettingsService();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  // Editable state
  List<Map<String, dynamic>> _depositTiers = [];
  double _depositMaxAmount = 10000;
  Map<String, dynamic> _feeRules = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final config = await _adminSettings.getFeesConfig();
      final tiers = config['depositTiers'] as List<dynamic>?;
      _depositTiers = tiers != null
          ? tiers
              .map((e) => Map<String, dynamic>.from(e as Map))
              .where((t) => t['amount'] != null && t['maxBidLimit'] != null)
              .toList()
          : [];
      _depositTiers.sort((a, b) =>
          (a['amount'] as num).compareTo(b['amount'] as num));

      final max = config['depositMaxAmount'];
      _depositMaxAmount = max is num
          ? max.toDouble()
          : (double.tryParse(max?.toString() ?? '') ?? 10000);

      _feeRules = config['feeRules'] is Map
          ? Map<String, dynamic>.from(config['feeRules'] as Map)
          : {};
    } catch (e) {
      final msg = e.toString();
      final friendly = msg.contains('unavailable') || msg.contains('UNAVAILABLE')
          ? 'Firestore is temporarily unavailable. Please try again in a moment.'
          : msg.contains('permission') || msg.contains('PERMISSION_DENIED')
              ? 'Permission denied. Check your admin role.'
              : 'Could not load config. Please try again.';
      setState(() => _error = friendly);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _adminSettings.setFeesConfig({
        'depositTiers': _depositTiers,
        'depositMaxAmount': _depositMaxAmount,
        'feeRules': _feeRules,
      });
      await _adminSettings.refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Fees and deposit config saved'),
            backgroundColor: AppTheme.primaryBlue,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString();
        final friendly = msg.contains('unavailable') || msg.contains('UNAVAILABLE')
            ? 'Firestore is temporarily unavailable. Please try again.'
            : 'Could not save. Please try again.';
        setState(() => _error = friendly);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _addTier() {
    setState(() {
      _depositTiers.add({
        'amount': 100.0,
        'maxBidLimit': 10000.0,
      });
      _depositTiers.sort((a, b) =>
          (a['amount'] as num).compareTo(b['amount'] as num));
    });
  }

  void _removeTier(int index) {
    setState(() => _depositTiers.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: UnifiedAppBar(title: 'Fees & Deposits'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppTheme.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.error),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _error!,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.error),
                          ),
                          const SizedBox(height: 12),
                          TextButton.icon(
                            onPressed: () {
                              setState(() => _error = null);
                              _load();
                            },
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ],
                  // Deposit tiers
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Deposit tiers',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const Spacer(),
                              TextButton.icon(
                                onPressed: _addTier,
                                icon: const Icon(Icons.add, size: 22),
                                label: const Text('Add tier'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Each tier: deposit amount (AED) → max bid limit (AED). Users choose a tier when adding deposit.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: AppTheme.textSecondary,
                                ),
                          ),
                          const SizedBox(height: 12),
                          if (_depositTiers.isEmpty)
                            Text(
                              'No tiers. Add one to use tier-based deposits.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: AppTheme.textTertiary,
                                    fontStyle: FontStyle.italic,
                                  ),
                            )
                          else
                            ...List.generate(_depositTiers.length, (i) {
                              final t = _depositTiers[i];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 90,
                                      child: TextFormField(
                                        initialValue:
                                            (t['amount'] as num).toString(),
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                                decimal: true),
                                        decoration: const InputDecoration(
                                          labelText: 'AED',
                                          isDense: true,
                                        ),
                                        onChanged: (v) {
                                          final n = double.tryParse(v);
                                          if (n != null) {
                                            setState(() =>
                                                t['amount'] = n);
                                          }
                                        },
                                      ),
                                    ),
                                    const Padding(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 8),
                                      child: Text('→'),
                                    ),
                                    Expanded(
                                      child: TextFormField(
                                        initialValue: (t['maxBidLimit'] as num)
                                            .toString(),
                                        keyboardType: const TextInputType
                                            .numberWithOptions(decimal: true),
                                        decoration: const InputDecoration(
                                          labelText: 'Max bid (AED)',
                                          isDense: true,
                                        ),
                                        onChanged: (v) {
                                          final n = double.tryParse(v);
                                          if (n != null) {
                                            setState(() =>
                                                t['maxBidLimit'] = n);
                                          }
                                        },
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.remove_circle_outline),
                                      onPressed: () => _removeTier(i),
                                    ),
                                  ],
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Deposit max cap
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Max deposit amount (AED)',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Hard cap to prevent abuse. Leave 0 or empty for no cap.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: AppTheme.textSecondary,
                                ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            initialValue: _depositMaxAmount.isFinite &&
                                    _depositMaxAmount > 0
                                ? _depositMaxAmount.toStringAsFixed(0)
                                : '',
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: false),
                            decoration: const InputDecoration(
                              hintText: 'e.g. 10000 (or empty = no cap)',
                            ),
                            onChanged: (v) {
                              final n = double.tryParse(v);
                              setState(() => _depositMaxAmount =
                                  (n != null && n > 0) ? n : 0);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Fee rules summary (optional: expand for listing/buyer/seller)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Fee rules',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Listing, buyer and seller fees are still read from Admin Settings (main). Use this section later for overrides.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: AppTheme.textSecondary,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_rounded, size: 22),
                    label: Text(_saving ? 'Saving...' : 'Save to Firestore'),
                  ),
                ],
              ),
            ),
    );
  }
}
