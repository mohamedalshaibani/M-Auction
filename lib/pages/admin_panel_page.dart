import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auction_service.dart';
import '../services/admin_settings_service.dart';
import '../services/firestore_service.dart';
import '../services/kyc_service.dart';
import '../services/ads_service.dart';
import '../models/watch_brand.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/support_unread.dart';
import '../widgets/unified_app_bar.dart';
import '../widgets/admin_layout.dart';
import 'admin_support_thread_page.dart';
import 'admin_fees_page.dart';
import 'admin_admins_page.dart';

class AdminPanelPage extends StatefulWidget {
  const AdminPanelPage({super.key, this.initialTabIndex = 0});

  /// Tab index to show on open (0=Auctions, 1=Deposits, 2=KYC, 3=Finance, 4=Ads, 5=Support, 6=Admins).
  final int initialTabIndex;

  @override
  State<AdminPanelPage> createState() => _AdminPanelPageState();
}

class _AdminPanelPageState extends State<AdminPanelPage> {
  final AuctionService _auctionService = AuctionService();
  final AdminSettingsService _adminSettings = AdminSettingsService();
  final FirestoreService _firestoreService = FirestoreService();
  final KycService _kycService = KycService();
  final Map<String, int> _selectedDurations = {};
  bool _isApproving = false;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTabIndex.clamp(0, 6);
  }

  Future<bool> _checkAdmin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    
    final userDoc = await _firestoreService.getUser(user.uid);
    if (!userDoc.exists) return false;
    
    final userData = userDoc.data() as Map<String, dynamic>?;
    final role = userData?['role'] as String?;
    return role == 'admin' || role == 'super_admin';
  }

  Future<void> _approveAndActivate(String auctionId) async {
    final durationDays = _selectedDurations[auctionId];
    if (durationDays == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select duration')),
      );
      return;
    }

    setState(() => _isApproving = true);

    try {
      await _auctionService.adminApprove(auctionId, durationDays);
      await _auctionService.markPaidAndActivate(auctionId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Auction approved and activated')),
        );
        setState(() => _selectedDurations.remove(auctionId));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isApproving = false);
      }
    }
  }

  Future<void> _toggleVipWaiver(String uid, bool currentValue) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'vipDepositWaived': !currentValue,
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            !currentValue
                ? 'VIP deposit waiver enabled'
                : 'VIP deposit waiver disabled',
          ),
        ),
      );
    }
  }

  Future<void> _forceRefund(String uid) async {
    // Note: For full refund functionality, auctionId is needed
    // This method can be enhanced to find auction from user's locked deposits
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Refund/Forfeit available from auction detail page'),
      ),
    );
  }

  Future<void> _forceForfeit(String uid) async {
    // Note: For full forfeit functionality, auctionId is needed
    // This method can be enhanced to find auction from user's locked deposits
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Refund/Forfeit available from auction detail page'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    
    return FutureBuilder<bool>(
      future: _checkAdmin(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        
        final isAdmin = snapshot.data ?? false;
        
        if (!isAdmin || user == null) {
          return Scaffold(
            appBar: const UnifiedAppBar(title: 'Admin Panel'),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.block, size: 64, color: AppTheme.error),
                  const SizedBox(height: 16),
                  Text(
                    'Not Authorized',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You do not have admin privileges.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        
        return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('support_threads')
                .snapshots(),
            builder: (context, snap) {
              final docs = snap.data?.docs ?? [];
              int adminUnread = 0;
              for (final d in docs) {
                final data = d.data() as Map<String, dynamic>?;
                if (adminHasUnread(data)) adminUnread++;
              }
              return Scaffold(
                backgroundColor: AppTheme.backgroundLight,
                appBar: UnifiedAppBar(
                  title: kAdminSectionTitles[_currentIndex],
                ),
                body: IndexedStack(
                  index: _currentIndex,
                  children: [
                    _buildAuctionsTab(),
                    _buildDepositsTab(),
                    _buildKycTab(),
                    _buildFinanceTab(),
                    _buildAdsTab(),
                    _buildSupportTab(),
                    _buildAdminsTab(),
                  ],
                ),
                bottomNavigationBar: AdminBottomNav(
                  currentIndex: _currentIndex,
                  onTap: (index) => setState(() => _currentIndex = index),
                  supportUnreadCount: adminUnread,
                ),
              );
              },
            );
      },
    );
  }

  Widget _buildAuctionsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _auctionService.streamPendingApprovalAuctions(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AdminErrorState(
            message: snapshot.error?.toString() ?? 'Error loading auctions',
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const AdminEmptyState(
            icon: Icons.check_circle_outline,
            title: 'All caught up!',
            subtitle: 'No auctions pending approval',
            iconColor: AppTheme.success,
          );
        }

        // Sort by createdAt (descending - newest first)
        final sortedDocs = List<QueryDocumentSnapshot>.from(
          snapshot.data!.docs,
        )..sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            final aTimestamp = aData['createdAt'] as Timestamp?;
            final bTimestamp = bData['createdAt'] as Timestamp?;

            if (aTimestamp == null && bTimestamp == null) return 0;
            if (aTimestamp == null) return 1;
            if (bTimestamp == null) return -1;

            return bTimestamp.compareTo(aTimestamp); // Descending
          });

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: kAdminCardSpacing),
          itemCount: sortedDocs.length,
          itemBuilder: (context, index) {
            final doc = sortedDocs[index];
            final data = doc.data() as Map<String, dynamic>;
            final auctionId = doc.id;

            final title = data['title'] as String? ?? 'Untitled';
            final brand = effectiveBrandDisplay(data);

            return AdminCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Brand: $brand',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FutureBuilder<List<int>>(
                      future: _adminSettings.getDurationOptions(),
                      builder: (context, durationSnapshot) {
                        if (!durationSnapshot.hasData) {
                          return const SizedBox.shrink();
                        }

                        final durations = durationSnapshot.data!;
                        final currentDuration = _selectedDurations[auctionId];

                        return DropdownButtonFormField<int>(
                          value: currentDuration,
                          decoration: const InputDecoration(
                            labelText: 'Duration (days)',
                          ),
                          items: durations
                              .map((days) => DropdownMenuItem(
                                    value: days,
                                    child: Text('$days days'),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            setState(() {
                              if (value != null) {
                                _selectedDurations[auctionId] = value;
                              }
                            });
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.of(context).pushNamed(
                                '/auctionDetail?auctionId=$auctionId',
                              );
                            },
                            child: const Text('View Details'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: (_isApproving ||
                                    _selectedDurations[auctionId] == null)
                                ? null
                                : () => _approveAndActivate(auctionId),
                            child: _isApproving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Approve & Activate'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
            );
          },
        );
      },
    );
  }

  Widget _buildDepositsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('deposits').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AdminErrorState(
            message: snapshot.error?.toString() ?? 'Error loading deposits',
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const AdminEmptyState(
            icon: Icons.account_balance_wallet_outlined,
            title: 'No deposits found',
            subtitle: 'User deposits will appear here.',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: kAdminCardSpacing),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final doc = snapshot.data!.docs[index];
            final uid = doc.id;
            final data = doc.data() as Map<String, dynamic>;
            final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
            final status = data['status'] as String? ?? 'unknown';

            return FutureBuilder<DocumentSnapshot>(
              future: _firestoreService.getUser(uid),
              builder: (context, userSnapshot) {
                final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
                final userName = userData?['displayName'] as String? ??
                    userData?['phoneNumber'] as String? ??
                    uid;
                final vipWaived =
                    userData?['vipDepositWaived'] as bool? ?? false;

                return FutureBuilder<DocumentSnapshot>(
                  future: _firestoreService.getWallet(uid),
                  builder: (context, walletSnapshot) {
                    final walletData = walletSnapshot.data?.data() as Map<String, dynamic>?;
                    final availableDeposit =
                        (walletData?['availableDeposit'] as num?)?.toDouble() ?? 0.0;
                    final reservedDeposit =
                        (walletData?['reservedDeposit'] as num?)?.toDouble() ?? 0.0;
                    final lockedDeposit =
                        (walletData?['lockedDeposit'] as num?)?.toDouble() ?? 0.0;
                    final heldAmount = reservedDeposit > 0 ? reservedDeposit : lockedDeposit;

                    return AdminCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            userName,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'User ID: $uid',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Total Deposit: ${formatMoney(amount)}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          Text(
                            'Status: $status',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          Text(
                            'Available: ${formatMoney(availableDeposit)}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          Text(
                            'Reserved: ${formatMoney(reservedDeposit)}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          if (lockedDeposit > 0)
                            Text(
                              'Locked (legacy): ${formatMoney(lockedDeposit)}',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          if (vipWaived) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.success.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppTheme.success),
                              ),
                              child: Text(
                                'VIP Deposit Waived',
                                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                  color: AppTheme.success,
                                ),
                              ),
                            ),
                          ],
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              children: [
                                ElevatedButton(
                                  onPressed: () => _toggleVipWaiver(uid, vipWaived),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: vipWaived ? AppTheme.warning : AppTheme.success,
                                  ),
                                  child: Text(vipWaived ? 'Remove VIP' : 'Grant VIP'),
                                ),
                                if (heldAmount > 0) ...[
                                  OutlinedButton(
                                    onPressed: () => _forceRefund(uid),
                                    child: const Text('Force Refund'),
                                  ),
                                  OutlinedButton(
                                    onPressed: () => _forceForfeit(uid),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppTheme.error,
                                    ),
                                    child: const Text('Force Forfeit'),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildKycTab() {
    final user = FirebaseAuth.instance.currentUser;
    return StreamBuilder<QuerySnapshot>(
      stream: _kycService.streamPendingKycRequests(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AdminErrorState(
            message: snapshot.error?.toString() ?? 'Error loading KYC requests',
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const AdminEmptyState(
            icon: Icons.verified_user_outlined,
            title: 'All caught up!',
            subtitle: 'No pending KYC requests',
            iconColor: AppTheme.success,
          );
        }

        final requests = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: kAdminCardSpacing),
          itemCount: requests.length,
          itemBuilder: (context, index) {
            final doc = requests[index];
            final data = doc.data() as Map<String, dynamic>;
            final uid = doc.id;
            // Support new fields (firstName, lastName, nationalityName) and legacy (fullName, nationality)
            final firstName = data['firstName'] as String?;
            final lastName = data['lastName'] as String?;
            final fullNameLegacy = data['fullName'] as String?;
            final displayName = (firstName != null && lastName != null)
                ? '$firstName $lastName'
                : (fullNameLegacy ?? 'N/A');
            final nationalityName = data['nationalityName'] as String?;
            final nationalityLegacy = data['nationality'] as String?;
            final nationality = nationalityName ?? nationalityLegacy ?? 'N/A';
            final idType = data['idType'] as String? ?? 'N/A';
            final idNumber = data['idNumber'] as String? ?? 'N/A';
            final idFrontUrl = data['idFrontUrl'] as String?;
            final idBackUrl = data['idBackUrl'] as String?;
            final selfieUrl = data['selfieUrl'] as String?;
            final proofUrl = data['proofUrl'] as String?;
            final proofNote = data['proofNote'] as String?;

            final rejectController = TextEditingController();

            return AdminCard(
              margin: kAdminCardMargin,
              padding: EdgeInsets.zero,
              child: ExpansionTile(
                title: Text(
                  displayName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                subtitle: Text(
                  'ID: $idNumber',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                children: [
                  Padding(
                    padding: kAdminCardPadding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Name: $displayName',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        Text(
                          'Nationality: $nationality',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        Text(
                          'ID Type: $idType',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        Text(
                          'ID Number: $idNumber',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 16),
                        if (idFrontUrl != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'ID Front:',
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                                GestureDetector(
                                  onTap: () {
                                    showDialog(
                                      context: context,
                                      builder: (context) => Dialog(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            UnifiedAppBar(
                                              title: 'ID Front',
                                              leading: IconButton(
                                                icon: const Icon(Icons.close),
                                                onPressed: () => Navigator.of(context).pop(),
                                              ),
                                            ),
                                            Image.network(idFrontUrl, fit: BoxFit.contain),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                  child: Image.network(
                                    idFrontUrl,
                                    height: 150,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (idBackUrl != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'ID Back:',
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                                GestureDetector(
                                  onTap: () {
                                    showDialog(
                                      context: context,
                                      builder: (context) => Dialog(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            UnifiedAppBar(
                                              title: 'ID Back',
                                              leading: IconButton(
                                                icon: const Icon(Icons.close),
                                                onPressed: () => Navigator.of(context).pop(),
                                              ),
                                            ),
                                            Image.network(idBackUrl, fit: BoxFit.contain),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                  child: Image.network(
                                    idBackUrl,
                                    height: 150,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (selfieUrl != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Selfie:',
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                                GestureDetector(
                                  onTap: () {
                                    showDialog(
                                      context: context,
                                      builder: (context) => Dialog(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            UnifiedAppBar(
                                              title: 'Selfie',
                                              leading: IconButton(
                                                icon: const Icon(Icons.close),
                                                onPressed: () => Navigator.of(context).pop(),
                                              ),
                                            ),
                                            Image.network(selfieUrl, fit: BoxFit.contain),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                  child: Image.network(
                                    selfieUrl,
                                    height: 150,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (proofUrl != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Proof:',
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                                GestureDetector(
                                  onTap: () {
                                    showDialog(
                                      context: context,
                                      builder: (context) => Dialog(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            UnifiedAppBar(
                                              title: 'Proof',
                                              leading: IconButton(
                                                icon: const Icon(Icons.close),
                                                onPressed: () => Navigator.of(context).pop(),
                                              ),
                                            ),
                                            Image.network(proofUrl, fit: BoxFit.contain),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                  child: Image.network(
                                    proofUrl,
                                    height: 150,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 48,
                                child: ElevatedButton.icon(
                                  onPressed: () async {
                                  if (user == null) return;
                                  try {
                                    await _kycService.approveKyc(uid, user.uid);
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('KYC approved')),
                                    );
                                  } catch (e) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Error: $e')),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.check_rounded, size: 20),
                                label: const Text('Approve'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.success,
                                  foregroundColor: Colors.white,
                                ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SizedBox(
                                height: 48,
                                child: ElevatedButton.icon(
                                onPressed: () {
                                  showDialog(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('Reject KYC'),
                                        content: TextField(
                                        controller: rejectController,
                                        decoration: const InputDecoration(
                                          labelText: 'Rejection Reason',
                                        ),
                                        maxLines: 3,
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.of(context).pop(),
                                          child: const Text('Cancel'),
                                        ),
                                        ElevatedButton(
                                          onPressed: () async {
                                            if (rejectController.text.trim().isEmpty) {
                                              if (!mounted) return;
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text('Please provide a rejection reason'),
                                                ),
                                              );
                                              return;
                                            }
                                            if (user == null) return;
                                            try {
                                              await _kycService.rejectKyc(
                                                uid,
                                                rejectController.text.trim(),
                                                user.uid,
                                              );
                                              if (!mounted) return;
                                              Navigator.of(context).pop();
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('KYC rejected')),
                                              );
                                            } catch (e) {
                                              if (!mounted) return;
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(content: Text('Error: $e')),
                                              );
                                            }
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppTheme.error,
                                          ),
                                          child: const Text('Reject'),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.close_rounded, size: 20),
                                label: const Text('Reject'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.error,
                                  foregroundColor: Colors.white,
                                ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Finance tab: Fees config CTA + Revenue list.
  Widget _buildFinanceTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(kAdminContentPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminCard(
            margin: const EdgeInsets.only(bottom: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                  Icon(Icons.savings_outlined, size: 40, color: AppTheme.primaryBlue),
                  const SizedBox(height: 8),
                  Text(
                    'Fees & deposit tiers',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Configure auction fees and deposit tiers (Firestore).',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (context) => AdminLayout.wrap(const AdminFeesPage()),
                        ),
                      );
                    },
                    icon: const Icon(Icons.tune_rounded, size: 22),
                    label: const Text('Manage fees & deposit tiers'),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'Revenue',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          _buildRevenueContent(),
        ],
      ),
    );
  }

  Widget _buildRevenueContent() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('platformRevenue')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AdminErrorState(
            message: snapshot.error?.toString() ?? 'Error loading revenue',
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const AdminEmptyState(
            icon: Icons.attach_money_outlined,
            title: 'No revenue records yet',
            subtitle: 'Revenue will appear here once transactions occur.',
          );
        }
        final records = snapshot.data!.docs;
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: records.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final doc = records[index];
            final data = doc.data() as Map<String, dynamic>;
            return _buildRevenueCard(data);
          },
        );
      },
    );
  }

  Widget _buildRevenueCard(Map<String, dynamic> data) {
    final auctionId = data['auctionId'] as String? ?? 'N/A';
    final type = data['type'] as String? ?? 'unknown';
    final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
    final uid = data['uid'] as String? ?? 'N/A';
    final createdAt = data['createdAt'] as Timestamp?;
    String dateText = 'N/A';
    if (createdAt != null) {
      final date = createdAt.toDate();
      dateText = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
    String typeDisplay = type;
    if (type == 'buyer_commission') typeDisplay = 'Buyer Commission';
    else if (type == 'seller_commission') typeDisplay = 'Seller Commission';
    else if (type == 'forfeit') typeDisplay = 'Forfeit';
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                typeDisplay,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'AED ${formatMoney(amount)}',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Auction: ${auctionId.length > 20 ? '${auctionId.substring(0, 20)}...' : auctionId}', style: Theme.of(context).textTheme.bodySmall),
          Text('User: ${uid.length > 20 ? '${uid.substring(0, 20)}...' : uid}', style: Theme.of(context).textTheme.bodySmall),
          Text('Date: $dateText', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _buildAdminsTab() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(kAdminContentPadding * 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const AdminEmptyState(
              icon: Icons.admin_panel_settings_outlined,
              title: 'Admin roles',
              subtitle: 'Search users by phone or email and assign admin or super_admin role.',
              iconSize: 56,
              iconColor: AppTheme.primaryBlue,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => AdminLayout.wrap(const AdminAdminsPage()),
                  ),
                );
              },
              icon: const Icon(Icons.manage_accounts_rounded, size: 22),
              label: const Text('Manage admin roles'),
            ),
          ],
        ),
      ),
    );
  }

  /// Support list row: real name (KYC or displayName), phone/email, fallback to uid.
  Widget _supportThreadUserInfo(String userId) {
    return FutureBuilder<List<DocumentSnapshot?>>(
      future: Future.wait([
        FirebaseFirestore.instance.collection('users').doc(userId).get(),
        FirebaseFirestore.instance.collection('kycRequests').doc(userId).get(),
      ]),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Text(
            'User: ${userId.length > 12 ? '${userId.substring(0, 12)}...' : userId}',
            style: Theme.of(context).textTheme.titleSmall,
          );
        }
        final userDoc = snapshot.data![0];
        final kycDoc = snapshot.data![1];
        final userData = userDoc?.data() as Map<String, dynamic>?;
        final kycData = kycDoc?.data() as Map<String, dynamic>?;
        final displayName = userData?['displayName'] as String?;
        final phone = userData?['phoneNumber'] as String?;
        final email = userData?['email'] as String?;
        final firstName = kycData?['firstName'] as String?;
        final lastName = kycData?['lastName'] as String?;
        final kycStatus = kycData?['status'] as String?;
        final kycName = (firstName != null && lastName != null && (firstName.trim().isNotEmpty || lastName.trim().isNotEmpty))
            ? '${firstName.trim()} ${lastName.trim()}'.trim()
            : null;
        final name = (kycName != null && kycName.isNotEmpty && kycStatus == 'approved')
            ? kycName
            : (displayName != null && displayName.trim().isNotEmpty)
                ? displayName.trim()
                : 'User: ${userId.length > 12 ? '${userId.substring(0, 12)}...' : userId}';
        final contact = [
          if (phone != null && phone.isNotEmpty) phone,
          if (email != null && email.isNotEmpty) email,
        ].join(' • ');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (contact.isNotEmpty)
              Text(
                contact,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        );
      },
    );
  }

  Widget _buildSupportTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('support_threads').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AdminErrorState(
            message: snapshot.error?.toString() ?? 'Error loading support threads',
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const AdminEmptyState(
            icon: Icons.chat_bubble_outline,
            title: 'No support threads yet',
            subtitle: 'Customer support conversations will appear here.',
          );
        }
        final sorted = List<QueryDocumentSnapshot>.from(docs)
          ..sort((a, b) {
            final aT = getSortTimestamp(a.data() as Map<String, dynamic>?);
            final bT = getSortTimestamp(b.data() as Map<String, dynamic>?);
            if (aT == null && bT == null) return 0;
            if (aT == null) return 1;
            if (bT == null) return -1;
            return bT.compareTo(aT);
          });
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: kAdminCardSpacing),
          itemCount: sorted.length,
          itemBuilder: (context, index) {
            final doc = sorted[index];
            final threadId = doc.id;
            final data = doc.data() as Map<String, dynamic>?;
            final updatedAt = data?['updatedAt'] as Timestamp?;
            final unread = adminHasUnread(data);
            final closed = isThreadClosed(data);
            final userId = data?['userId'] as String? ?? getUserUidFromTicketId(threadId);
            return AdminCard(
              margin: kAdminCardMargin,
              padding: EdgeInsets.zero,
              child: ListTile(
                leading: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      Icons.chat_bubble_outline,
                      color: closed ? AppTheme.textTertiary : AppTheme.primaryBlue,
                    ),
                    if (unread)
                      Positioned(
                        top: -2,
                        right: -2,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: AppTheme.error,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: _supportThreadUserInfo(userId),
                    ),
                    if (closed)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.backgroundGrey,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Text(
                          'Closed',
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
                subtitle: updatedAt != null
                    ? Text(
                        'Updated ${relativeTime(updatedAt.toDate())}',
                        style: Theme.of(context).textTheme.bodySmall,
                      )
                    : null,
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => AdminLayout.wrap(AdminSupportThreadPage(threadId: threadId)),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAdsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: streamAllAds(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AdminErrorState(
            message: snapshot.error?.toString() ?? 'Error loading ads',
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        return Column(
          children: [
            Expanded(
              child: docs.isEmpty
                  ? const AdminEmptyState(
                      icon: Icons.campaign_outlined,
                      title: 'No ads yet',
                      subtitle: 'Add a partner banner below.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: kAdminCardSpacing),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final doc = docs[index];
                        final ad = PartnerAd.fromDoc(doc);
                        return AdminCard(
                          margin: kAdminCardMargin,
                          padding: EdgeInsets.zero,
                          child: ListTile(
                            leading: ad.imageUrl.isNotEmpty
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: Image.network(
                                      ad.imageUrl,
                                      width: 56,
                                      height: 56,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Icon(Icons.campaign_outlined, color: AppTheme.textTertiary),
                                    ),
                                  )
                                : Icon(Icons.campaign_outlined, color: AppTheme.textTertiary, size: 24),
                            title: Text(
                              ad.partnerName,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            subtitle: Text(
                              'Partner ID: ${ad.partnerId} • Order: ${ad.order} • ${ad.active ? "Active" : "Inactive"}',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => _showEditAdDialog(context, ad),
                                ),
                                IconButton(
                                  icon: Icon(Icons.delete_outline, color: AppTheme.error),
                                  onPressed: () async {
                                    if (!context.mounted) return;
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('Delete ad?'),
                                        content: Text('Remove banner for ${ad.partnerName}?'),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.of(ctx).pop(false),
                                            child: const Text('Cancel'),
                                          ),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
                                            onPressed: () => Navigator.of(ctx).pop(true),
                                            child: const Text('Delete'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      try {
                                        await deleteAd(ad.id);
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Ad deleted')),
                                          );
                                        }
                                      } catch (e) {
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('Error: $e')),
                                          );
                                        }
                                      }
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(kAdminContentPadding),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _showAddAdDialog(context),
                    icon: const Icon(Icons.add_rounded, size: 22),
                    label: const Text('Add ad'),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showAddAdDialog(BuildContext context) {
    final partnerIdController = TextEditingController();
    final partnerNameController = TextEditingController();
    final imageUrlController = TextEditingController();
    final linkUrlController = TextEditingController();
    final orderController = TextEditingController(text: '0');
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('Add partner ad'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: partnerIdController,
                    decoration: const InputDecoration(
                      labelText: 'Partner ID (unique)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: partnerNameController,
                    decoration: const InputDecoration(
                      labelText: 'Partner name',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: imageUrlController,
                    decoration: const InputDecoration(
                      labelText: 'Banner image URL',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: linkUrlController,
                    decoration: const InputDecoration(
                      labelText: 'Link URL (optional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: orderController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Order (higher = first)',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final partnerId = partnerIdController.text.trim();
                  final partnerName = partnerNameController.text.trim();
                  final imageUrl = imageUrlController.text.trim();
                  final linkUrl = linkUrlController.text.trim().isEmpty ? null : linkUrlController.text.trim();
                  final order = int.tryParse(orderController.text.trim()) ?? 0;
                  if (partnerId.isEmpty || partnerName.isEmpty || imageUrl.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Partner ID, name and image URL are required')),
                    );
                    return;
                  }
                  try {
                    await createAd(
                      partnerId: partnerId,
                      partnerName: partnerName,
                      imageUrl: imageUrl,
                      linkUrl: linkUrl,
                      order: order,
                    );
                    if (ctx.mounted) Navigator.of(ctx).pop();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Ad added')),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e')),
                      );
                    }
                  }
                },
                child: const Text('Add'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEditAdDialog(BuildContext context, PartnerAd ad) {
    final partnerIdController = TextEditingController(text: ad.partnerId);
    final partnerNameController = TextEditingController(text: ad.partnerName);
    final imageUrlController = TextEditingController(text: ad.imageUrl);
    final linkUrlController = TextEditingController(text: ad.linkUrl ?? '');
    final orderController = TextEditingController(text: '${ad.order}');
    bool active = ad.active;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('Edit ad'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: partnerIdController,
                    decoration: const InputDecoration(
                      labelText: 'Partner ID',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: partnerNameController,
                    decoration: const InputDecoration(
                      labelText: 'Partner name',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: imageUrlController,
                    decoration: const InputDecoration(
                      labelText: 'Banner image URL',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: linkUrlController,
                    decoration: const InputDecoration(
                      labelText: 'Link URL (optional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: orderController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Order',
                    ),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    title: const Text('Active'),
                    value: active,
                    onChanged: (v) {
                      setDialogState(() => active = v ?? true);
                    },
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final partnerId = partnerIdController.text.trim();
                  final partnerName = partnerNameController.text.trim();
                  final imageUrl = imageUrlController.text.trim();
                  final linkUrl = linkUrlController.text.trim().isEmpty ? null : linkUrlController.text.trim();
                  final order = int.tryParse(orderController.text.trim()) ?? 0;
                  if (partnerId.isEmpty || partnerName.isEmpty || imageUrl.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Partner ID, name and image URL are required')),
                    );
                    return;
                  }
                  try {
                    await updateAd(ad.id,
                      partnerId: partnerId,
                      partnerName: partnerName,
                      imageUrl: imageUrl,
                      linkUrl: linkUrl,
                      order: order,
                      active: active,
                    );
                    if (ctx.mounted) Navigator.of(ctx).pop();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Ad updated')),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e')),
                      );
                    }
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }
}
