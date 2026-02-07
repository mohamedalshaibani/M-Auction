import 'package:cloud_firestore/cloud_firestore.dart';

/// Global number formatting for prices, balances, and bids.
/// Use [formatMoney] for AED amounts: thousand separators + 2 decimals (e.g. 12,500.00).

/// Formats a number as money: thousand separators and 2 decimal places (e.g. 12,500.00).
String formatMoney(num value) {
  final n = value.toDouble();
  final s = n.toStringAsFixed(2);
  final parts = s.split('.');
  final intPart = parts[0];
  final isNegative = intPart.startsWith('-');
  final digits = isNegative ? intPart.substring(1) : intPart;
  final buffer = StringBuffer();
  if (isNegative) buffer.write('-');
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return '${buffer}.${parts[1]}';
}

/// Compact remaining-time badge. Consistent across app.
/// - If remaining >= 24h: "Xd Xh Xm" (e.g. 2d 05h 12m)
/// - If remaining < 24h: "Xh Xm Xs" (e.g. 12h 07m 34s)
String formatTimeLeftCompact(dynamic endsAt) {
  if (endsAt == null) return '—';
  final endDate = endsAt is DateTime ? endsAt : (endsAt as Timestamp).toDate();
  final now = DateTime.now();
  final diff = endDate.difference(now);
  if (diff.isNegative) return 'Ended';
  final days = diff.inDays;
  final hours = diff.inHours % 24;
  final minutes = diff.inMinutes % 60;
  final seconds = diff.inSeconds % 60;
  if (days > 0) return '${days}d ${hours}h ${minutes}m';
  // Under 24h: show hours, minutes, seconds
  if (hours > 0) return '${hours}h ${minutes}m ${seconds}s';
  if (minutes > 0) return '${minutes}m ${seconds}s';
  if (seconds > 0) return '${seconds}s';
  return 'Ending soon';
}

/// Relative time string (e.g. "2 min ago", "1 hour ago").
String relativeTime(DateTime dateTime) {
  final now = DateTime.now();
  final diff = now.difference(dateTime);
  if (diff.inDays > 0) return '${diff.inDays}d ago';
  if (diff.inHours > 0) return '${diff.inHours}h ago';
  if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
  if (diff.inSeconds > 0) return '${diff.inSeconds}s ago';
  return 'Just now';
}

/// True only when auction is ACTIVE and not yet ended by time.
/// Use to hide ENDED / ended-by-time auctions from public lists (Home, Explore, Categories).
bool isAuctionOpenForPublicBrowsing(Map<String, dynamic> data) {
  final state = data['state'] as String? ?? '';
  if (state != 'ACTIVE') return false;
  final endsAt = data['endsAt'];
  if (endsAt == null) return true;
  final endDate = endsAt is DateTime ? endsAt : (endsAt as Timestamp).toDate();
  return endDate.isAfter(DateTime.now());
}
