/// Helpers for normalized search (phone digits only, email lowercase).
/// Used by admin user search and when writing user docs for future querying.

/// Returns digits only from [phone] (e.g. "+971 55 888 8324" → "971558888324").
/// Use for prefix/partial phone matching and storing phoneDigits on user docs.
String digitsOnlyFromPhone(String? phone) {
  if (phone == null || phone.isEmpty) return '';
  return phone.replaceAll(RegExp(r'[^\d]'), '');
}

/// Returns [email] trimmed and lowercased, or empty string if null/empty.
String emailToLower(String? email) {
  if (email == null || email.trim().isEmpty) return '';
  return email.trim().toLowerCase();
}

/// True if [query] looks like an email search (contains @ or only letters/numbers/dots).
bool isEmailSearch(String query) {
  final t = query.trim();
  if (t.isEmpty) return false;
  if (t.contains('@')) return true;
  // If it has letters (and maybe digits/dots), treat as email/name search
  return t.contains(RegExp(r'[a-zA-Z]'));
}
