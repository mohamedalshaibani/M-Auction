import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../utils/support_unread.dart';
import '../widgets/unified_app_bar.dart';

/// Admin view of a single support thread. threadId = uid (legacy) or uid_T{timestamp}.
/// Admin can close the conversation; closed threads are read-only for the user.
class AdminSupportThreadPage extends StatefulWidget {
  const AdminSupportThreadPage({super.key, required this.threadId});

  final String threadId;

  @override
  State<AdminSupportThreadPage> createState() => _AdminSupportThreadPageState();
}

class _AdminSupportThreadPageState extends State<AdminSupportThreadPage> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  bool _isSending = false;
  bool _hasMarkedRead = false;
  bool _hasScrolledToUnread = false;
  Timestamp? _lastAdminReadAtBeforeOpen;

  @override
  void initState() {
    super.initState();
    _loadAndMarkAdminRead();
  }

  Future<void> _loadAndMarkAdminRead() async {
    if (_hasMarkedRead) return;
    _hasMarkedRead = true;
    try {
      final threadRef = FirebaseFirestore.instance
          .collection('support_threads')
          .doc(widget.threadId);
      final threadDoc = await threadRef.get();
      final data = threadDoc.data();
      if (data != null) {
        _lastAdminReadAtBeforeOpen = parseTimestamp(data[kLastAdminReadAt]);
      }
      await threadRef.set({
        'lastAdminReadAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) setState(() {});
    } catch (_) {}
  }

  int _findFirstUnreadIndex(List<QueryDocumentSnapshot> docs) {
    if (_lastAdminReadAtBeforeOpen == null) {
      for (var i = 0; i < docs.length; i++) {
        final data = docs[i].data() as Map<String, dynamic>;
        final role =
            data['senderRole'] as String? ?? data['role'] as String? ?? 'user';
        if (role == 'user') return i;
      }
      return -1;
    }
    for (var i = 0; i < docs.length; i++) {
      final data = docs[i].data() as Map<String, dynamic>;
      final role =
          data['senderRole'] as String? ?? data['role'] as String? ?? 'user';
      if (role == 'user') {
        final createdAt = data['createdAt'] as Timestamp?;
        if (createdAt != null &&
            createdAt.compareTo(_lastAdminReadAtBeforeOpen!) > 0) {
          return i;
        }
      }
    }
    return -1;
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _sendReply() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isSending = true);
    try {
      final threadRef = FirebaseFirestore.instance
          .collection('support_threads')
          .doc(widget.threadId);
      await threadRef.collection('messages').add({
        'senderUid': user.uid,
        'senderRole': 'admin',
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await threadRef.set({
        'updatedAt': FieldValue.serverTimestamp(),
        'lastAdminMessageAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _textController.clear();
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('support_threads')
          .doc(widget.threadId)
          .snapshots(),
      builder: (context, threadSnap) {
        final threadData = threadSnap.data?.data() as Map<String, dynamic>?;
        final closed = isThreadClosed(threadData);
        return Scaffold(
          backgroundColor: AppTheme.backgroundLight,
          appBar: UnifiedAppBar(
            title: closed ? 'Support thread (Closed)' : 'Support thread',
            actions: [
              if (!closed)
                TextButton.icon(
                  onPressed: _closeConversation,
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Close'),
                ),
            ],
          ),
          body: Column(
            children: [
              _UserIdentityCard(
                threadId: widget.threadId,
                userId: threadData?['userId'] as String? ?? getUserUidFromTicketId(widget.threadId),
              ),
              if (closed)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  color: AppTheme.backgroundGrey,
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 18,
                        color: AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This conversation is closed. No further messages can be sent by the user.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppTheme.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('support_threads')
                      .doc(widget.threadId)
                      .collection('messages')
                      .orderBy('createdAt', descending: false)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Unable to load chat',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppTheme.error),
                        ),
                      );
                    }
                    final docs = snapshot.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return Center(
                        child: Text(
                          'No messages yet',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: AppTheme.textTertiary),
                        ),
                      );
                    }
                    final firstUnreadIndex = _findFirstUnreadIndex(docs);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!_hasScrolledToUnread &&
                          mounted &&
                          _scrollController.hasClients) {
                        _hasScrolledToUnread = true;
                        if (firstUnreadIndex >= 0 &&
                            firstUnreadIndex < docs.length) {
                          final offset = firstUnreadIndex * 72.0;
                          _scrollController.animateTo(
                            offset.clamp(
                              0.0,
                              _scrollController.position.maxScrollExtent,
                            ),
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                          );
                        } else if (docs.isNotEmpty) {
                          _scrollController.animateTo(
                            _scrollController.position.maxScrollExtent,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                          );
                        }
                      }
                    });
                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final doc = docs[index];
                        final data = doc.data() as Map<String, dynamic>;
                        final role =
                            data['senderRole'] as String? ??
                            data['role'] as String? ??
                            'user';
                        final isAdmin = role == 'admin' || role == 'super_admin';
                        return _ChatBubble(
                          text: data['text'] as String? ?? '',
                          isUser: isAdmin,
                          createdAt: data['createdAt'] as Timestamp?,
                        );
                      },
                    );
                  },
                ),
              ),
              if (!closed)
                Material(
                  color: AppTheme.surface,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _textController,
                              focusNode: _focusNode,
                              decoration: InputDecoration(
                                hintText: 'Reply...',
                                filled: true,
                                fillColor: AppTheme.backgroundGrey,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 14,
                                ),
                              ),
                              maxLines: 3,
                              minLines: 1,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _sendReply(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            onPressed: _isSending ? null : _sendReply,
                            icon: _isSending
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.send),
                            style: IconButton.styleFrom(
                              backgroundColor: AppTheme.primaryBlue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _closeConversation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Close conversation?'),
        content: const Text(
          'This will mark the conversation as resolved. The user will not be able to send further messages.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await FirebaseFirestore.instance
          .collection('support_threads')
          .doc(widget.threadId)
          .set({
            kUserId: getUserUidFromTicketId(widget.threadId),
            kStatus: kStatusClosed,
            kClosedAt: FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Conversation closed'),
            backgroundColor: AppTheme.primaryBlue,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to close: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }
}

class _UserIdentityCard extends StatelessWidget {
  final String threadId;
  final String userId;

  const _UserIdentityCard({required this.threadId, required this.userId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<DocumentSnapshot?>>(
      future: Future.wait([
        FirebaseFirestore.instance.collection('users').doc(userId).get(),
        FirebaseFirestore.instance.collection('kycRequests').doc(userId).get(),
      ]),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final userDoc = snapshot.data![0];
        final kycDoc = snapshot.data![1];
        if (userDoc == null || !userDoc.exists) return const SizedBox.shrink();
        final data = userDoc.data() as Map<String, dynamic>? ?? {};
        final kycData = kycDoc?.data() as Map<String, dynamic>?;
        final displayName = data['displayName'] as String? ?? '—';
        final firstName = kycData?['firstName'] as String?;
        final lastName = kycData?['lastName'] as String?;
        final kycStatusValue = kycData?['status'] as String?;
        final kycName = (firstName != null && lastName != null &&
                (firstName.trim().isNotEmpty || lastName.trim().isNotEmpty))
            ? '${firstName.trim()} ${lastName.trim()}'.trim()
            : null;
        final name = (kycName != null && kycName.isNotEmpty && kycStatusValue == 'approved')
            ? kycName
            : displayName;
        final phoneNumber = data['phoneNumber'] as String? ?? '—';
        final email = data['email'] as String?;
        final kycStatus = data['kycStatus'] as String? ?? '—';
        final phoneVerified = data['phoneVerified'] as bool? ?? false;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          margin: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'User identity',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Name: $name',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.textPrimary,
                ),
              ),
              Text(
                'Phone: $phoneNumber',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
              if (email != null && email.isNotEmpty)
                Text(
                  'Email: $email',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              Text(
                'UID: $userId',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppTheme.textTertiary,
                ),
              ),
              Text(
                'Verified: ${phoneVerified ? "Phone ✓" : "—"} | KYC: $kycStatus',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final String text;
  final bool isUser;
  final Timestamp? createdAt;

  const _ChatBubble({required this.text, required this.isUser, this.createdAt});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        decoration: BoxDecoration(
          color: isUser ? AppTheme.primaryBlue : AppTheme.backgroundGrey,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isUser ? 14 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: isUser ? Colors.white : AppTheme.textPrimary,
                height: 1.4,
              ),
            ),
            if (createdAt != null) ...[
              const SizedBox(height: 4),
              Text(
                _formatTime(createdAt!.toDate()),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: isUser ? Colors.white70 : AppTheme.textTertiary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msg = DateTime(dateTime.year, dateTime.month, dateTime.day);
    if (msg == today) {
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
    return '${dateTime.day}/${dateTime.month} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}
