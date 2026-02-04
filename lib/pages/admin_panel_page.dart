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
import '../widgets/unified_app_bar.dart';

class AdminPanelPage extends StatefulWidget {
  const AdminPanelPage({super.key});

  @override
  State<AdminPanelPage> createState() => _AdminPanelPageState();
}

class _AdminPanelPageState extends State<AdminPanelPage>
    with SingleTickerProviderStateMixin {
  final AuctionService _auctionService = AuctionService();
  final AdminSettingsService _adminSettings = AdminSettingsService();
  final FirestoreService _firestoreService = FirestoreService();
  final KycService _kycService = KycService();
  final Map<String, int> _selectedDurations = {};
  bool _isApproving = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  Future<bool> _checkAdmin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    
    final userDoc = await _firestoreService.getUser(user.uid);
    if (!userDoc.exists) return false;
    
    final userData = userDoc.data() as Map<String, dynamic>?;
    final role = userData?['role'] as String?;
    return role == 'admin';
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
        
        return Scaffold(
          appBar: UnifiedAppBar(
            title: 'Admin Panel',
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Auctions'),
                Tab(text: 'Deposits'),
                Tab(text: 'KYC Requests'),
                Tab(text: 'Revenue'),
                Tab(text: 'Ads'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildAuctionsTab(),
              _buildDepositsTab(),
              _buildKycTab(),
              _buildRevenueTab(),
              _buildAdsTab(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAuctionsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _auctionService.streamPendingApprovalAuctions(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: AppTheme.error),
                const SizedBox(height: 16),
                Text(
                  'Error loading auctions',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  '${snapshot.error}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline, size: 64, color: AppTheme.success),
                const SizedBox(height: 16),
                Text(
                  'All caught up!',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'No auctions pending approval',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
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
          itemCount: sortedDocs.length,
          itemBuilder: (context, index) {
            final doc = sortedDocs[index];
            final data = doc.data() as Map<String, dynamic>;
            final auctionId = doc.id;

            final title = data['title'] as String? ?? 'Untitled';
            final brand = effectiveBrandDisplay(data);

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text('Brand: $brand'),
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
                            border: OutlineInputBorder(),
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
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: AppTheme.error),
                const SizedBox(height: 16),
                Text(
                  'Error loading deposits',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  '${snapshot.error}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.account_balance_wallet_outlined, size: 64, color: AppTheme.textTertiary),
                const SizedBox(height: 16),
                Text(
                  'No deposits found',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
          );
        }

        return ListView.builder(
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
                    final lockedDeposit =
                        (walletData?['lockedDeposit'] as num?)?.toDouble() ?? 0.0;

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              userName,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 4),
                            Text('User ID: $uid'),
                            const SizedBox(height: 8),
                            Text('Total Deposit: ${formatMoney(amount)}'),
                            Text('Status: $status'),
                            Text('Available: ${formatMoney(availableDeposit)}'),
                            Text('Locked: ${formatMoney(lockedDeposit)}'),
                            if (vipWaived) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.success.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppTheme.success),
                                ),
                                child: const Text(
                                  'VIP Deposit Waived',
                                  style: TextStyle(
                                    color: AppTheme.success,
                                    fontWeight: FontWeight.bold,
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
                                if (lockedDeposit > 0) ...[
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
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: AppTheme.error),
                const SizedBox(height: 16),
                Text(
                  'Error loading KYC requests',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  '${snapshot.error}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.verified_user_outlined, size: 64, color: AppTheme.success),
                const SizedBox(height: 16),
                Text(
                  'All caught up!',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'No pending KYC requests',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          );
        }

        final requests = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: requests.length,
          itemBuilder: (context, index) {
            final doc = requests[index];
            final data = doc.data() as Map<String, dynamic>;
            final uid = doc.id;
            final fullName = data['fullName'] as String? ?? 'N/A';
            final nationality = data['nationality'] as String? ?? 'N/A';
            final idType = data['idType'] as String? ?? 'N/A';
            final idNumber = data['idNumber'] as String? ?? 'N/A';
            final proofType = data['proofType'] as String? ?? 'N/A';
            final idFrontUrl = data['idFrontUrl'] as String?;
            final idBackUrl = data['idBackUrl'] as String?;
            final selfieUrl = data['selfieUrl'] as String?;
            final proofUrl = data['proofUrl'] as String?;
            final proofNote = data['proofNote'] as String?;

            final rejectController = TextEditingController();

            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              child: ExpansionTile(
                title: Text(fullName),
                subtitle: Text('ID: $idNumber | Proof: $proofType'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Full Name: $fullName'),
                        Text('Nationality: $nationality'),
                        Text('ID Type: $idType'),
                        Text('ID Number: $idNumber'),
                        Text('Proof Type: $proofType'),
                        if (proofNote != null) Text('Proof Note: $proofNote'),
                        const SizedBox(height: 16),
                        if (idFrontUrl != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('ID Front:', style: TextStyle(fontWeight: FontWeight.bold)),
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
                                const Text('ID Back:', style: TextStyle(fontWeight: FontWeight.bold)),
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
                                const Text('Selfie:', style: TextStyle(fontWeight: FontWeight.bold)),
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
                                const Text('Proof:', style: TextStyle(fontWeight: FontWeight.bold)),
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
                                icon: const Icon(Icons.check),
                                label: const Text('Approve'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.success,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  showDialog(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('Reject KYC'),
                                      content: TextField(
                                        controller: rejectController,
                                        decoration: const InputDecoration(
                                          labelText: 'Rejection Reason',
                                          border: OutlineInputBorder(),
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
                                icon: const Icon(Icons.close),
                                label: const Text('Reject'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.error,
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

  Widget _buildRevenueTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('platformRevenue')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: AppTheme.error),
                const SizedBox(height: 16),
                Text(
                  'Error loading revenue',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  '${snapshot.error}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.attach_money_outlined, size: 64, color: AppTheme.textTertiary),
                const SizedBox(height: 16),
                Text(
                  'No revenue records',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Revenue will appear here once transactions occur',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          );
        }

        final records = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: records.length,
          itemBuilder: (context, index) {
            final doc = records[index];
            final data = doc.data() as Map<String, dynamic>;
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

            // Format type for display
            String typeDisplay = type;
            if (type == 'buyer_commission') {
              typeDisplay = 'Buyer Commission';
            } else if (type == 'seller_commission') {
              typeDisplay = 'Seller Commission';
            } else if (type == 'forfeit') {
              typeDisplay = 'Forfeit';
            }

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          typeDisplay,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'AED ${formatMoney(amount)}',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.success,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('Auction ID: ${auctionId.length > 20 ? '${auctionId.substring(0, 20)}...' : auctionId}'),
                    Text('User ID: ${uid.length > 20 ? '${uid.substring(0, 20)}...' : uid}'),
                    Text('Date: $dateText'),
                  ],
                ),
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
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: AppTheme.error),
                const SizedBox(height: 16),
                Text(
                  'Error loading ads',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  '${snapshot.error}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
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
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.campaign_outlined, size: 64, color: AppTheme.textTertiary),
                          const SizedBox(height: 16),
                          Text(
                            'No ads yet',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Add a partner banner below',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final doc = docs[index];
                        final ad = PartnerAd.fromDoc(doc);
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: ad.imageUrl.isNotEmpty
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      ad.imageUrl,
                                      width: 56,
                                      height: 56,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Icon(Icons.campaign_outlined, color: AppTheme.textTertiary),
                                    ),
                                  )
                                : Icon(Icons.campaign_outlined, color: AppTheme.textTertiary),
                            title: Text(ad.partnerName),
                            subtitle: Text('Partner ID: ${ad.partnerId} • Order: ${ad.order} • ${ad.active ? "Active" : "Inactive"}'),
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
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _showAddAdDialog(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add ad'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryBlue,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
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
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: partnerNameController,
                    decoration: const InputDecoration(
                      labelText: 'Partner name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: imageUrlController,
                    decoration: const InputDecoration(
                      labelText: 'Banner image URL',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: linkUrlController,
                    decoration: const InputDecoration(
                      labelText: 'Link URL (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: orderController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Order (higher = first)',
                      border: OutlineInputBorder(),
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
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: partnerNameController,
                    decoration: const InputDecoration(
                      labelText: 'Partner name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: imageUrlController,
                    decoration: const InputDecoration(
                      labelText: 'Banner image URL',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: linkUrlController,
                    decoration: const InputDecoration(
                      labelText: 'Link URL (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: orderController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Order',
                      border: OutlineInputBorder(),
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
