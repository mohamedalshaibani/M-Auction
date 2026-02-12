import 'package:cloud_firestore/cloud_firestore.dart';

/// Canonical field names for support_threads/{uid}.
/// Use these everywhere; accept legacy lastMessageFromUserAt only when reading.
const String kLastUserMessageAt = 'lastUserMessageAt';
const String kLastAdminMessageAt = 'lastAdminMessageAt';
const String kLastUserReadAt = 'lastUserReadAt';
const String kLastAdminReadAt = 'lastAdminReadAt';

/// Legacy field (migrated to lastUserMessageAt) - only for read fallback.
const String kLegacyLastMessageFromUserAt = 'lastMessageFromUserAt';

/// Thread status: 'open' or 'closed'.
const String kStatus = 'status';
const String kStatusOpen = 'open';
const String kStatusClosed = 'closed';
const String kClosedAt = 'closedAt';

/// User ID field for multi-ticket support (enables querying tickets by user).
const String kUserId = 'userId';

/// Extract user uid from ticketId. Legacy: threadId == uid. New: uid_T{timestamp}.
String getUserUidFromTicketId(String ticketId) {
  const suffix = '_T';
  final idx = ticketId.indexOf(suffix);
  if (idx >= 0) return ticketId.substring(0, idx);
  return ticketId;
}

/// Generate a new ticket ID for a user (format: uid_T{timestamp}).
String newTicketId(String uid) => '${uid}_T${DateTime.now().millisecondsSinceEpoch}';

/// True if the thread is closed (admin resolved the issue).
bool isThreadClosed(Map<String, dynamic>? data) {
  if (data == null) return false;
  final status = data[kStatus] as String?;
  final closedAt = data[kClosedAt];
  return status == kStatusClosed || closedAt != null;
}

/// Safe extraction of Timestamp from Firestore map value.
/// Handles null, Timestamp, and Map (from different Firestore encodings).
Timestamp? parseTimestamp(Object? v) {
  if (v == null) return null;
  if (v is Timestamp) return v;
  if (v is Map) {
    final sec = v['seconds'] ?? v['_seconds'];
    final nano = v['nanoseconds'] ?? v['_nanoseconds'] ?? 0;
    if (sec != null) {
      return Timestamp(
        (sec is int) ? sec : (sec as num).toInt(),
        (nano is int) ? nano : (nano as num).toInt(),
      );
    }
  }
  return null;
}

/// Admin has unread = last user message is newer than last admin read.
/// Closed threads are never unread.
/// Accepts legacy lastMessageFromUserAt for backward compat.
bool adminHasUnread(Map<String, dynamic>? data) {
  if (data == null || isThreadClosed(data)) return false;
  final lastUser = parseTimestamp(data[kLastUserMessageAt] ?? data[kLegacyLastMessageFromUserAt]);
  if (lastUser == null) return false;
  final lastRead = parseTimestamp(data[kLastAdminReadAt]);
  return lastRead == null || lastUser.compareTo(lastRead) > 0;
}

/// User has unread = last admin message is newer than last user read.
bool userHasUnread(Map<String, dynamic>? data) {
  if (data == null) return false;
  final lastAdmin = parseTimestamp(data[kLastAdminMessageAt]);
  if (lastAdmin == null) return false;
  final lastRead = parseTimestamp(data[kLastUserReadAt]);
  return lastRead == null || lastAdmin.compareTo(lastRead) > 0;
}

/// Timestamp for sorting threads (newest first).
/// Uses lastUserMessageAt ?? lastMessageFromUserAt ?? updatedAt.
Timestamp? getSortTimestamp(Map<String, dynamic>? data) {
  if (data == null) return null;
  return parseTimestamp(
    data[kLastUserMessageAt] ?? data[kLegacyLastMessageFromUserAt] ?? data['updatedAt'],
  );
}
