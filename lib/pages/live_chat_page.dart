import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../utils/support_unread.dart';
import '../utils/format.dart';
import '../widgets/unified_app_bar.dart';

/// Live Chat: direct conversation between customer and all admins (multi-admin).
/// Data: support_threads/{threadId} (userId, status, createdAt, updatedAt) + messages subcollection.
/// - No previous conversations: opens directly to new chat (ready to type).
/// - Has previous conversations: opens Chat History list; tap thread or "Start New Conversation".
class LiveChatPage extends StatefulWidget {
  const LiveChatPage({super.key});

  @override
  State<LiveChatPage> createState() => _LiveChatPageState();
}

class _LiveChatPageState extends State<LiveChatPage> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  bool _isSending = false;
  bool _hasMarkedRead = false;
  bool _hasScrolledToUnread = false;
  Timestamp? _lastUserReadAtBeforeOpen;

  /// User has at least one thread. If false, we show direct chat (no history screen).
  bool _hasHistory = false;
  /// Currently viewed thread. null = history screen or new chat (no threads yet).
  String? _currentTicketId;
  bool _hasLoadedInitial = false;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _hasLoadedInitial = true);
      return;
    }
    var hasHistory = false;
    try {
      // Query threads that have userId (new format + migrated legacy).
      var query = await FirebaseFirestore.instance
          .collection('support_threads')
          .where(kUserId, isEqualTo: user.uid)
          .orderBy('updatedAt', descending: true)
          .get();

      // Legacy: thread doc id was the user's uid and may lack userId. Ensure it appears in the query.
      final legacyRef = FirebaseFirestore.instance.collection('support_threads').doc(user.uid);
      final legacySnap = await legacyRef.get();
      if (legacySnap.exists) {
        final data = legacySnap.data();
        if (data == null || data[kUserId] != user.uid) {
          await legacyRef.set({kUserId: user.uid, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
        }
        if (query.docs.isEmpty) {
          query = await FirebaseFirestore.instance
              .collection('support_threads')
              .where(kUserId, isEqualTo: user.uid)
              .orderBy('updatedAt', descending: true)
              .get();
        }
      }
      hasHistory = query.docs.isNotEmpty || legacySnap.exists;
    } catch (_) {
      // Query may fail (e.g. index not deployed). Still check legacy doc so we show history when user has a thread.
      try {
        final legacySnap = await FirebaseFirestore.instance
            .collection('support_threads')
            .doc(user.uid)
            .get();
        if (legacySnap.exists) {
          final data = legacySnap.data();
          if (data == null || data[kUserId] != user.uid) {
            await FirebaseFirestore.instance
                .collection('support_threads')
                .doc(user.uid)
                .set({kUserId: user.uid, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
          }
          hasHistory = true;
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _hasHistory = hasHistory;
        _hasLoadedInitial = true;
      });
    }
  }

  Future<void> _loadAndMarkRead(String ticketId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _hasMarkedRead) return;
    _hasMarkedRead = true;
    try {
      final threadRef = FirebaseFirestore.instance
          .collection('support_threads')
          .doc(ticketId);
      final threadDoc = await threadRef.get();
      final data = threadDoc.data();
      if (data != null) {
        _lastUserReadAtBeforeOpen = parseTimestamp(data[kLastUserReadAt]);
      }
      await threadRef.set(
        {
          kUserId: user.uid,
          kLastUserReadAt: FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      if (mounted) setState(() {});
    } catch (_) {}
  }

  void _openThread(String threadId) {
    setState(() {
      _currentTicketId = threadId;
      _hasMarkedRead = false;
      _hasScrolledToUnread = false;
    });
    _loadAndMarkRead(threadId);
  }

  void _goBackToHistory() {
    setState(() => _currentTicketId = null);
  }

  Future<void> _startNewConversation() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final ref = await FirebaseFirestore.instance.collection('support_threads').add({
        kUserId: user.uid,
        kStatus: kStatusOpen,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (kDebugMode) {
        // ignore: avoid_print
        print('[LiveChat] Thread created: ${ref.id}');
      }
      if (mounted) _openThread(ref.id);
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[LiveChat] Start new conversation failed: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start: $e'), backgroundColor: AppTheme.error),
        );
      }
    }
  }

  int _findFirstUnreadIndex(List<QueryDocumentSnapshot> docs) {
    if (_lastUserReadAtBeforeOpen == null) {
      for (var i = 0; i < docs.length; i++) {
        final data = docs[i].data() as Map<String, dynamic>;
        final role = data['senderRole'] as String? ?? data['role'] as String? ?? 'user';
        if (role == 'admin' || role == 'super_admin') return i;
      }
      return -1;
    }
    for (var i = 0; i < docs.length; i++) {
      final data = docs[i].data() as Map<String, dynamic>;
      final role = data['senderRole'] as String? ?? data['role'] as String? ?? 'user';
      if (role == 'admin' || role == 'super_admin') {
        final createdAt = data['createdAt'] as Timestamp?;
        if (createdAt != null && createdAt.compareTo(_lastUserReadAtBeforeOpen!) > 0) {
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

  Future<void> _sendMessage() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    String? ticketId = _currentTicketId;
    if (ticketId == null) {
      // First-time user: create new thread with unique ID on first send
      try {
        final ref = await FirebaseFirestore.instance.collection('support_threads').add({
          kUserId: user.uid,
          kStatus: kStatusOpen,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        ticketId = ref.id;
        if (kDebugMode) {
          // ignore: avoid_print
          print('[LiveChat] First thread created: $ticketId');
        }
        if (mounted) {
          setState(() {
            _currentTicketId = ticketId;
            _hasHistory = true;
          });
          _loadAndMarkRead(ticketId);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to create conversation: $e'), backgroundColor: AppTheme.error),
          );
        }
        return;
      }
    }

    final threadDoc = await FirebaseFirestore.instance
        .collection('support_threads')
        .doc(ticketId)
        .get();
    if (isThreadClosed(threadDoc.data())) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[LiveChat] Cannot send: thread $ticketId is closed');
      }
      return;
    }

    setState(() => _isSending = true);
    try {
      final threadRef =
          FirebaseFirestore.instance.collection('support_threads').doc(ticketId);
      final now = FieldValue.serverTimestamp();
      await threadRef.set(
        {
          kUserId: user.uid,
          'updatedAt': now,
          'lastUserMessageAt': now,
        },
        SetOptions(merge: true),
      );
      await threadRef.collection('messages').add({
        'senderUid': user.uid,
        'senderRole': 'user',
        'text': text,
        'createdAt': now,
      });
      await threadRef.set(
        {'updatedAt': now, 'lastUserMessageAt': now},
        SetOptions(merge: true),
      );
      if (kDebugMode) {
        // ignore: avoid_print
        print('[LiveChat] Message sent to thread $ticketId, updatedAt set');
      }
      _textController.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
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
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: const UnifiedAppBar(title: 'Live Chat'),
        body: const Center(child: Text('Please sign in to use Live Chat')),
      );
    }

    if (!_hasLoadedInitial) {
      return Scaffold(
        appBar: const UnifiedAppBar(title: 'Live Chat'),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // Has history and not viewing a thread → show Chat History screen
    if (_hasHistory && _currentTicketId == null) {
      return _buildHistoryScreen(context);
    }

    // Direct chat (no history) or viewing a thread
    return _buildThreadView(context);
  }

  /// Chat History screen: list of past threads + "Start New Conversation".
  Widget _buildHistoryScreen(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: const UnifiedAppBar(title: 'Live Chat'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _startNewConversation,
                icon: const Icon(Icons.add_comment, size: 20),
                label: const Text('Start New Conversation'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Chat History',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('support_threads')
                  .where(kUserId, isEqualTo: FirebaseAuth.instance.currentUser!.uid)
                  .orderBy('updatedAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _buildHistoryFallback(context);
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(child: Text('No conversations yet'));
                }
                return _buildThreadList(context, docs);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// One-time load when stream fails (e.g. missing index). Ensures user can still see threads and start new.
  Widget _buildHistoryFallback(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Center(child: Text('Sign in to see history'));
    return FutureBuilder<List<DocumentSnapshot>>(
      future: _loadThreadsFallback(uid),
      builder: (context, futureSnap) {
        if (futureSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (futureSnap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Unable to load history',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.error),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You can still start a new conversation above.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }
        final docs = futureSnap.data ?? [];
        if (docs.isEmpty) {
          return const Center(child: Text('No conversations yet'));
        }
        return _buildThreadList(context, docs);
      },
    );
  }

  Future<List<DocumentSnapshot>> _loadThreadsFallback(String uid) async {
    try {
      final query = await FirebaseFirestore.instance
          .collection('support_threads')
          .where(kUserId, isEqualTo: uid)
          .orderBy('updatedAt', descending: true)
          .get();
      if (query.docs.isNotEmpty) return query.docs;
    } catch (_) {}
    final legacySnap = await FirebaseFirestore.instance.collection('support_threads').doc(uid).get();
    if (legacySnap.exists) return [legacySnap];
    return [];
  }

  Widget _buildThreadList(BuildContext context, List<DocumentSnapshot> docs) {
    return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>?;
                    final closed = isThreadClosed(data);
                    final updatedAt = data?['updatedAt'] as Timestamp?;
                    final hasUnread = userHasUnread(data);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(
                          closed ? Icons.chat_bubble_outline : Icons.chat_bubble,
                          color: closed ? AppTheme.textTertiary : AppTheme.primaryBlue,
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                closed ? 'Closed conversation' : 'Conversation',
                                style: const TextStyle(fontWeight: FontWeight.w500),
                              ),
                            ),
                            if (closed)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.backgroundGrey,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Closed',
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                        color: AppTheme.textSecondary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              )
                            else if (hasUnread)
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: AppTheme.error,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                        subtitle: updatedAt != null
                            ? Text(
                                'Updated ${relativeTime(updatedAt.toDate())}',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppTheme.textTertiary,
                                    ),
                              )
                            : null,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openThread(doc.id),
                      ),
                    );
                  },
                );
  }

  /// Thread view: messages + input (if open). Back button when user has history.
  Widget _buildThreadView(BuildContext context) {
    if (_currentTicketId == null) {
      // First-time user: no thread yet, show empty chat + input ready to create on send
      return Scaffold(
        backgroundColor: AppTheme.backgroundLight,
        appBar: const UnifiedAppBar(title: 'Live Chat'),
        body: Column(
          children: [
            Expanded(child: _buildEmptyChatPrompt(context)),
            _buildMessageInput(context),
          ],
        ),
      );
    }
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('support_threads')
          .doc(_currentTicketId)
          .snapshots(),
      builder: (context, threadSnap) {
        final threadData = threadSnap.data?.data() as Map<String, dynamic>?;
        final closed = isThreadClosed(threadData);
        return Scaffold(
          backgroundColor: AppTheme.backgroundLight,
          appBar: UnifiedAppBar(
            title: closed ? 'Live Chat (Closed)' : 'Live Chat',
            leading: _hasHistory
                ? IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: _goBackToHistory,
                  )
                : null,
          ),
          body: Column(
            children: [
              if (closed)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  color: AppTheme.backgroundGrey,
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline, size: 20, color: AppTheme.textSecondary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This conversation is closed. You can view the history but cannot send new messages.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('support_threads')
                            .doc(_currentTicketId)
                            .collection('messages')
                            .orderBy('createdAt', descending: false)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return Center(
                              child: Text(
                                'Unable to load chat',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppTheme.error,
                                    ),
                              ),
                            );
                          }
                          final docs = snapshot.data?.docs ?? [];
                          if (docs.isEmpty) {
                            return _buildEmptyChatPrompt(context);
                          }
                          final firstUnreadIndex = _findFirstUnreadIndex(docs);
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!_hasScrolledToUnread && mounted && _scrollController.hasClients) {
                              _hasScrolledToUnread = true;
                              if (firstUnreadIndex >= 0 && firstUnreadIndex < docs.length) {
                                final offset = firstUnreadIndex * 72.0;
                                _scrollController.animateTo(
                                  offset.clamp(0.0, _scrollController.position.maxScrollExtent),
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
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            itemCount: docs.length,
                            itemBuilder: (context, index) {
                              final doc = docs[index];
                              final data = doc.data() as Map<String, dynamic>;
                              final senderUid = data['senderUid'] as String? ?? data['senderId'] as String? ?? '';
                              final role = data['senderRole'] as String? ?? data['role'] as String? ?? 'user';
                              final text = data['text'] as String? ?? '';
                              final isUserMsg = role == 'user' || senderUid == FirebaseAuth.instance.currentUser!.uid;
                              return _ChatBubble(
                                text: text,
                                isUser: isUserMsg,
                                createdAt: data['createdAt'] as Timestamp?,
                              );
                            },
                          );
                        },
                      ),
              ),
              if (!closed) _buildMessageInput(context),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyChatPrompt(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline, size: 48, color: AppTheme.textTertiary),
            const SizedBox(height: 12),
            Text(
              'Start a conversation',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 4),
            Text(
              'Your messages are seen by our support team. We\'ll reply as soon as we can.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageInput(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _textController,
                  focusNode: _focusNode,
                  decoration: InputDecoration(
                    hintText: 'Type a message...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: AppTheme.backgroundGrey,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  maxLines: 3,
                  minLines: 1,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _isSending ? null : _sendMessage,
                icon: _isSending
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
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
