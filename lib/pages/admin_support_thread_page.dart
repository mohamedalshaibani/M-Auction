import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../widgets/unified_app_bar.dart';

/// Admin view of a single support thread. threadId is the user's uid.
class AdminSupportThreadPage extends StatefulWidget {
  final String threadId;

  const AdminSupportThreadPage({super.key, required this.threadId});

  @override
  State<AdminSupportThreadPage> createState() => _AdminSupportThreadPageState();
}

class _AdminSupportThreadPageState extends State<AdminSupportThreadPage> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isSending = false;
  bool _hasMarkedRead = false;

  @override
  void initState() {
    super.initState();
    _markAdminRead();
  }

  Future<void> _markAdminRead() async {
    if (_hasMarkedRead) return;
    _hasMarkedRead = true;
    try {
      await FirebaseFirestore.instance
          .collection('support_threads')
          .doc(widget.threadId)
          .set(
            {
              'lastAdminReadAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
    } catch (_) {}
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
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
      await threadRef.set(
        {
          'updatedAt': FieldValue.serverTimestamp(),
          'lastAdminMessageAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
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
          SnackBar(content: Text('Failed to send: $e'), backgroundColor: AppTheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: UnifiedAppBar(title: 'Support thread'),
      body: Column(
        children: [
          _UserIdentityCard(threadId: widget.threadId),
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
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.error),
                    ),
                  );
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(
                    child: Text(
                      'No messages yet',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.textTertiary),
                    ),
                  );
                }
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final role = data['senderRole'] as String? ?? data['role'] as String? ?? 'user';
                    final isAdmin = role == 'admin';
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
          Container(
            padding: const EdgeInsets.all(12),
            color: AppTheme.surface,
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      decoration: InputDecoration(
                        hintText: 'Reply...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: AppTheme.backgroundGrey,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      maxLines: 3,
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
                            child: CircularProgressIndicator(strokeWidth: 2),
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
        ],
      ),
    );
  }
}

class _UserIdentityCard extends StatelessWidget {
  final String threadId;

  const _UserIdentityCard({required this.threadId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(threadId).get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const SizedBox.shrink();
        }
        final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
        final displayName = data['displayName'] as String? ?? '—';
        final phoneNumber = data['phoneNumber'] as String? ?? '—';
        final email = data['email'] as String?;
        final kycStatus = data['kycStatus'] as String? ?? '—';
        final phoneVerified = data['phoneVerified'] as bool? ?? false;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
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
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              Text('Name: $displayName', style: Theme.of(context).textTheme.bodySmall),
              Text('Phone: $phoneNumber', style: Theme.of(context).textTheme.bodySmall),
              if (email != null && email.isNotEmpty)
                Text('Email: $email', style: Theme.of(context).textTheme.bodySmall),
              Text('UID: $threadId', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11, color: AppTheme.textTertiary)),
              Text(
                'Verified: ${phoneVerified ? "Phone ✓" : "—"} | KYC: $kycStatus',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        decoration: BoxDecoration(
          color: isUser ? AppTheme.primaryBlue : AppTheme.backgroundGrey,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
                      fontSize: 10,
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
