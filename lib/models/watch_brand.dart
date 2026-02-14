/// Resolve display name from auction data.
/// Prefers denormalized brand name; falls back to brandId for legacy data.
String effectiveBrandDisplay(Map<String, dynamic> data) {
  final brand = data['brand'] as String?;
  if (brand != null && brand.trim().isNotEmpty) return brand.trim();
  final brandId = data['brandId'] as String?;
  if (brandId == null || brandId.isEmpty) return '—';
  return brandId;
}
