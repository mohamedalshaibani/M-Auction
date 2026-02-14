import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../utils/search_normalize.dart';
import '../widgets/admin_layout.dart';
import '../widgets/unified_app_bar.dart';

/// Admin-only: search users by phone/email and assign role (user / admin / super_admin).
/// Paginated list with debounced search, role filter, sort, and compact rows.
class AdminAdminsPage extends StatefulWidget {
  const AdminAdminsPage({super.key});

  @override
  State<AdminAdminsPage> createState() => _AdminAdminsPageState();
}

class _AdminAdminsPageState extends State<AdminAdminsPage> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  static const int _pageSize = 20;
  List<QueryDocumentSnapshot> _users = [];
  DocumentSnapshot? _lastDoc;
  bool _hasMore = true;
  bool _loading = false;
  String? _roleFilter;
  String _sortBy = 'recent';
  String _searchQuery = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _fetchUsers(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() => _searchQuery = _searchController.text.trim());
      }
    });
  }

  Future<void> _fetchUsers({required bool reset}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      if (reset) {
        _users = [];
        _lastDoc = null;
        _hasMore = true;
      }
    });

    try {
      Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection('users');
      if (_roleFilter != null && _roleFilter!.isNotEmpty) {
        query = query.where('role', isEqualTo: _roleFilter);
      }
      if (_sortBy == 'name') {
        query = query.orderBy('displayName', descending: false);
      } else {
        query = query.orderBy('createdAt', descending: true);
      }
      query = query.limit(_pageSize);
      if (!reset && _lastDoc != null) {
        query = query.startAfterDocument(_lastDoc!);
      }

      final snapshot = await query.get();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _users = reset ? snapshot.docs : [..._users, ...snapshot.docs];
        _lastDoc = snapshot.docs.isEmpty ? null : snapshot.docs.last;
        _hasMore = snapshot.docs.length == _pageSize;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.error),
      );
    }
  }

  List<QueryDocumentSnapshot> _filter(
    List<QueryDocumentSnapshot> docs,
    String query,
  ) {
    final q = query.trim();
    if (q.isEmpty) return docs;

    final qLower = q.toLowerCase();
    final qDigits = digitsOnlyFromPhone(q);

    return docs.where((d) {
      final data = d.data() as Map<String, dynamic>?;
      if (data == null) return false;
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
          SnackBar(
            content: Text('Role set to $newRole'),
            backgroundColor: AppTheme.primaryBlue,
          ),
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

  void _applyFiltersAndRefetch() {
    _fetchUsers(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filter(_users, _searchQuery);

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: const UnifiedAppBar(title: 'Admin roles'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(kAdminContentPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  decoration: const InputDecoration(
                    hintText: 'Phone or email (partial match)',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _roleFilter ?? 'all',
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('All roles')),
                          DropdownMenuItem(value: 'user', child: Text('User')),
                          DropdownMenuItem(value: 'admin', child: Text('Admin')),
                          DropdownMenuItem(value: 'super_admin', child: Text('Super admin')),
                        ],
                        onChanged: (v) {
                          setState(() {
                            _roleFilter = v == 'all' ? null : v;
                            _applyFiltersAndRefetch();
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _sortBy,
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'recent', child: Text('Recent')),
                          DropdownMenuItem(value: 'name', child: Text('Name')),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setState(() {
                              _sortBy = v;
                              _applyFiltersAndRefetch();
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading && _users.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? Center(
                        child: Text(
                          _searchQuery.isEmpty
                              ? 'No users yet'
                              : 'No users match "$_searchQuery"',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: kAdminContentPadding,
                          vertical: kAdminCardSpacing,
                        ),
                        itemCount: filtered.length + (_hasMore && _searchQuery.isEmpty ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == filtered.length) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Center(
                                child: TextButton.icon(
                                  onPressed: _loading ? null : () => _fetchUsers(reset: false),
                                  icon: _loading
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Icon(Icons.expand_more_rounded),
                                  label: Text(_loading ? 'Loading...' : 'Load more'),
                                ),
                              ),
                            );
                          }
                          final doc = filtered[index];
                          final data = doc.data() as Map<String, dynamic>;
                          final uid = doc.id;
                          final displayName = data['displayName'] as String? ?? '—';
                          final phone = data['phoneNumber'] as String? ?? '';
                          final email = data['email'] as String? ?? '';
                          final role = data['role'] as String? ?? 'user';
                          final parts = [
                            if (phone.isNotEmpty) phone,
                            if (email.isNotEmpty) email,
                          ];
                          final subtitle = parts.isEmpty ? '—' : parts.join(' • ');

                          return AdminCard(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        displayName,
                                        style: theme.textTheme.titleSmall,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        subtitle,
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: AppTheme.textSecondary,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                SizedBox(
                                  width: 120,
                                  child: DropdownButtonFormField<String>(
                                    value: role == 'super_admin'
                                        ? 'super_admin'
                                        : role == 'admin'
                                            ? 'admin'
                                            : 'user',
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      contentPadding:
                                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    ),
                                    items: const [
                                      DropdownMenuItem(value: 'user', child: Text('User')),
                                      DropdownMenuItem(value: 'admin', child: Text('Admin')),
                                      DropdownMenuItem(
                                          value: 'super_admin', child: Text('Super admin')),
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
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
