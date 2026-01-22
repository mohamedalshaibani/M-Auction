import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FirestoreService _firestoreService = FirestoreService();

  Future<void> _signOut(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      Navigator.of(context).pushReplacementNamed('/authGate');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _signOut(context),
            tooltip: 'Sign out',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Phone Number:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              user?.phoneNumber ?? 'Not available',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            Text(
              'KYC Status:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            StreamBuilder<String>(
              stream: user != null
                  ? _firestoreService.kycStatusStream(user.uid)
                  : Stream.value('not_submitted'),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const CircularProgressIndicator();
                }
                return Text(
                  snapshot.data ?? 'not_submitted',
                  style: Theme.of(context).textTheme.bodyLarge,
                );
              },
            ),
            const SizedBox(height: 24),
            Text(
              'Wallet Balance:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            StreamBuilder<double>(
              stream: user != null
                  ? _firestoreService.walletBalanceStream(user.uid)
                  : Stream.value(0.0),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const CircularProgressIndicator();
                }
                return Text(
                  '${snapshot.data?.toStringAsFixed(2) ?? '0.00'}',
                  style: Theme.of(context).textTheme.bodyLarge,
                );
              },
            ),
            const SizedBox(height: 32),
            // KYC Status Banner
            if (user != null)
              StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const SizedBox.shrink();
                  final userData = snapshot.data?.data() as Map<String, dynamic>?;
                  final kycStatus = userData?['kycStatus'] as String? ?? 'not_submitted';
                  final rejectionReason = userData?['kycRejectionReason'] as String?;

                  Color bannerColor;
                  String statusText;
                  IconData statusIcon;

                  if (kycStatus == 'approved') {
                    bannerColor = Colors.green.shade50;
                    statusText = 'KYC Verified';
                    statusIcon = Icons.check_circle;
                  } else if (kycStatus == 'pending') {
                    bannerColor = Colors.orange.shade50;
                    statusText = 'KYC Under Review';
                    statusIcon = Icons.pending;
                  } else if (kycStatus == 'rejected') {
                    bannerColor = Colors.red.shade50;
                    statusText = 'KYC Rejected';
                    statusIcon = Icons.error;
                  } else {
                    bannerColor = Colors.blue.shade50;
                    statusText = 'KYC Not Submitted';
                    statusIcon = Icons.info;
                  }

                  return Card(
                    color: bannerColor,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(statusIcon, color: bannerColor == Colors.green.shade50
                                  ? Colors.green
                                  : bannerColor == Colors.red.shade50
                                      ? Colors.red
                                      : Colors.orange),
                              const SizedBox(width: 8),
                              Text(
                                statusText,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          if (rejectionReason != null) ...[
                            const SizedBox(height: 8),
                            Text('Reason: $rejectionReason'),
                          ],
                          if (kycStatus != 'approved') ...[
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () {
                                  Navigator.of(context).pushNamed('/kyc');
                                },
                                child: const Text('Complete Verification'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pushNamed('/explore');
                },
                icon: const Icon(Icons.explore),
                label: const Text('Explore Auctions'),
              ),
            ),
            const SizedBox(height: 16),
            if (user != null)
              StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const SizedBox.shrink();
                  final userData = snapshot.data?.data() as Map<String, dynamic>?;
                  final kycStatus = userData?['kycStatus'] as String? ?? 'not_submitted';
                  final isApproved = kycStatus == 'approved';

                  return SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: isApproved
                          ? () {
                              Navigator.of(context).pushNamed('/sellCreateAuction');
                            }
                          : () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'KYC verification required to sell items. Please complete verification first.',
                                  ),
                                ),
                              );
                              Navigator.of(context).pushNamed('/kyc');
                            },
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('Sell Item'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isApproved ? null : Colors.grey,
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pushNamed('/sellerMyAuctions');
                },
                icon: const Icon(Icons.list),
                label: const Text('My Auctions'),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pushNamed('/myWins');
                },
                icon: const Icon(Icons.emoji_events),
                label: const Text('My Wins'),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pushNamed('/wallet');
                },
                icon: const Icon(Icons.account_balance_wallet),
                label: const Text('Wallet'),
              ),
            ),
            // Show Admin Panel only if user is admin
            if (user != null)
              StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SizedBox.shrink();
                  }
                  final userData = snapshot.data?.data() as Map<String, dynamic>?;
                  final role = userData?['role'] as String?;
                  final isAdmin = role == 'admin';
                  
                  if (!isAdmin) {
                    return const SizedBox.shrink();
                  }
                  
                  return Column(
                    children: [
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(context).pushNamed('/adminPanel');
                          },
                          icon: const Icon(Icons.admin_panel_settings),
                          label: const Text('Admin Panel'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            const Spacer(),
            Center(
              child: ElevatedButton(
                onPressed: () => _signOut(context),
                child: const Text('Sign out'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
