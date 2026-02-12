import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../utils/search_normalize.dart';
import '../widgets/admin_layout.dart';
import '../widgets/unified_app_bar.dart';

/// Admin-only: search users by phone/email and assign role (user / admin / super_admin).
/// Shows last 100 users by default; filters live as you type (partial phone, partial email).
class AdminAdminsPage extends StatefulWidget {
  const AdminAdminsPage({super.key});

  @override
  State<AdminAdminsPage> createState() => _AdminAdminsPageState();
}

class _AdminAdminsPageState extends State<AdminAdminsPage> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  static const int _initialLimit = 100;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Filter [docs] by normalized [query]: partial phone (digits) or partial email/name.
  List<QueryDocumentSnapshot> _filter(
    List<QueryDocumentSnapshot> docs,
    String query,
  ) {
    final q = query.trim();
    if (q.isEmpty) return docs;

    final qLower = q.toLowerCase();
    final qDigits = digitsOnlyFromPhone(q);

    return docs.where((d) {
      final data = d.data() as Map<String, dynamic>;
      final phone = data['phoneNumber'] as String? ?? '';
      final phoneDigits = data['phoneDigits'] as String? ?? digitsOnlyFromPhone(phone);
      final email = data['email'] as String? ?? '';
      final emailLower = data['emailLower'] as String? ?? emailToLower(email);
      final displayName = (data['displayName'] as String? ?? '').toLowerCase();

      if (isEmailSearch(q)) {
        return emailLower.contains(qLower) || displayName.contains(qLower);
      }
      if (qDigits.isEmpty) return true;
      return phoneDigits.contains(qDigits);
    }).toList();
  }

  Future<void> _setRole(String uid, String newRole) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'role': newRole,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Role set to $newRole')),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: const UnifiedAppBar(title: 'Admin roles'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(kAdminContentPadding),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocus,
              decoration: const InputDecoration(
                hintText: 'Phone or email (partial match)',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .orderBy('createdAt', descending: true)
                  .limit(_initialLimit)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      snapshot.error.toString(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppTheme.error,
                      ),
                    ),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final allDocs = snapshot.data?.docs ?? <QueryDocumentSnapshot>[];
                final query = _searchController.text.trim();
                final filtered = _filter(allDocs, query);

                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      query.isEmpty
                          ? 'No users yet'
                          : 'No users match "$query"',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: kAdminContentPadding,
                    vertical: kAdminCardSpacing,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final doc = filtered[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final uid = doc.id;
                    final displayName =
                        data['displayName'] as String? ?? '—';
                    final phone = data['phoneNumber'] as String? ?? '—';
                    final email = data['email'] as String? ?? '—';
                    final role = data['role'] as String? ?? 'user';

                    return AdminCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Phone: $phone',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          Text(
                            'Email: $email',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          Text(
                            'ID: ${uid.length > 16 ? '${uid.substring(0, 16)}...' : uid}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppTheme.textTertiary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                'Role: ',
                                style: theme.textTheme.labelLarge,
                              ),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: role == 'super_admin'
                                      ? 'super_admin'
                                      : role == 'admin'
                                          ? 'admin'
                                          : 'user',
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'user',
                                      child: Text('User'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'admin',
                                      child: Text('Admin'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'super_admin',
                                      child: Text('Super admin'),
                                    ),
                                  ],
                                  onChanged: (String? newRole) {
                                    if (newRole != null && newRole != role) {
                                      _setRole(uid, newRole);
                                    }
                                  },
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
            ),
          ),
        ],
      ),
    );
  }
}
