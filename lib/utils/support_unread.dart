import 'package:cloud_firestore/cloud_firestore.dart';

/// Canonical field names for support_threads/{uid}.
/// Use these everywhere; accept legacy lastMessageFromUserAt only when reading.
const String kLastUserMessageAt = 'lastUserMessageAt';
const String kLastAdminMessageAt = 'lastAdminMessageAt';
const String kLastUserReadAt = 'lastUserReadAt';
const String kLastAdminReadAt = 'lastAdminReadAt';

/// Legacy field (migrated to lastUserMessageAt) - only for read fallback.
const String kLegacyLastMessageFromUserAt = 'lastMessageFromUserAt';

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
/// Accepts legacy lastMessageFromUserAt for backward compat.
bool adminHasUnread(Map<String, dynamic>? data) {
  if (data == null) return false;
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
