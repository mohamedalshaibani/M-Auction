/// Category structure for auctions: top-level groups and subcategories.
/// Source of truth: Firestore adminSettings/main (categories + subcategories).
/// Fallback: default structure below for app-only or before Firestore is updated.

class CategoryGroup {
  final String id;
  final String nameAr;
  final String nameEn;
  final int order;

  const CategoryGroup({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.order,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'nameAr': nameAr,
        'nameEn': nameEn,
        'order': order,
      };

  static CategoryGroup fromMap(Map<String, dynamic> m) => CategoryGroup(
        id: m['id'] as String? ?? '',
        nameAr: m['nameAr'] as String? ?? m['id'] as String? ?? '',
        nameEn: m['nameEn'] as String? ?? m['id'] as String? ?? '',
        order: (m['order'] as num?)?.toInt() ?? 0,
      );
}

class Subcategory {
  final String id;
  final String parentId;
  final String nameAr;
  final String nameEn;
  final int order;

  const Subcategory({
    required this.id,
    required this.parentId,
    required this.nameAr,
    required this.nameEn,
    required this.order,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'parentId': parentId,
        'nameAr': nameAr,
        'nameEn': nameEn,
        'order': order,
      };

  static Subcategory fromMap(Map<String, dynamic> m) => Subcategory(
        id: m['id'] as String? ?? '',
        parentId: m['parentId'] as String? ?? '',
        nameAr: m['nameAr'] as String? ?? m['id'] as String? ?? '',
        nameEn: m['nameEn'] as String? ?? m['id'] as String? ?? '',
        order: (m['order'] as num?)?.toInt() ?? 0,
      );
}

/// Default top-level categories in display order (source of truth when Firestore not set).
/// 1) watches (ساعات) 2) bags (شنط) 3) fashion (فاشن) 4) jewelry (مجوهرات) 5) accessories (اكسسوارات) 6) collectibles (مقتنيات)
const List<CategoryGroup> defaultTopLevelCategories = [
  CategoryGroup(id: 'watches', nameAr: 'ساعات', nameEn: 'Watches', order: 1),
  CategoryGroup(id: 'bags', nameAr: 'شنط', nameEn: 'Bags', order: 2),
  CategoryGroup(id: 'fashion', nameAr: 'فاشن', nameEn: 'Fashion', order: 3),
  CategoryGroup(id: 'jewelry', nameAr: 'مجوهرات', nameEn: 'Jewelry', order: 4),
  CategoryGroup(id: 'accessories', nameAr: 'اكسسوارات', nameEn: 'Accessories', order: 5),
  CategoryGroup(id: 'collectibles', nameAr: 'مقتنيات', nameEn: 'Collectibles', order: 6),
];

/// Subcategories per parent (id, parentId, nameAr, nameEn, order).
const List<Subcategory> defaultSubcategories = [
  Subcategory(id: 'watches', parentId: 'watches', nameAr: 'ساعات', nameEn: 'Watches', order: 1),
  Subcategory(id: 'bags', parentId: 'bags', nameAr: 'شنط', nameEn: 'Bags', order: 1),
  Subcategory(id: 'clothing', parentId: 'fashion', nameAr: 'ملابس', nameEn: 'Clothing', order: 1),
  Subcategory(id: 'shoes', parentId: 'fashion', nameAr: 'أحذية', nameEn: 'Shoes', order: 2),
  Subcategory(id: 'caps', parentId: 'fashion', nameAr: 'قبعات', nameEn: 'Caps', order: 3),
  Subcategory(id: 'jewelry', parentId: 'jewelry', nameAr: 'مجوهرات', nameEn: 'Jewelry', order: 1),
  Subcategory(id: 'wallets', parentId: 'accessories', nameAr: 'محافظ', nameEn: 'Wallets', order: 1),
  Subcategory(id: 'eyewear', parentId: 'accessories', nameAr: 'نظارات', nameEn: 'Eyewear', order: 2),
  Subcategory(id: 'pens', parentId: 'accessories', nameAr: 'أقلام', nameEn: 'Pens', order: 3),
  Subcategory(id: 'travel_bags', parentId: 'collectibles', nameAr: 'حقائب سفر', nameEn: 'Travel Bags', order: 1),
  Subcategory(id: 'collectibles', parentId: 'collectibles', nameAr: 'مقتنيات', nameEn: 'Collectibles', order: 2),
];

/// Map legacy single-string category to top-level categoryGroup.
/// "art" is retired -> collectibles.
String legacyCategoryToGroup(String? legacyCategory) {
  if (legacyCategory == null || legacyCategory.isEmpty) return 'collectibles';
  final c = legacyCategory.toLowerCase().trim();
  if (c == 'art') return 'collectibles';
  if (c == 'bags') return 'bags';
  if (c == 'watches') return 'watches';
  if (c == 'jewelry' || c == 'jewellery') return 'jewelry';
  if (c == 'fashion' || c == 'clothing' || c == 'shoes' || c == 'caps') return 'fashion';
  if (c == 'accessories' || c == 'wallets' || c == 'eyewear' || c == 'pens') return 'accessories';
  if (c == 'collectibles' || c == 'travel_bags') return 'collectibles';
  return 'collectibles'; // default
}

/// Get effective categoryGroup from auction document (new field or legacy).
String effectiveCategoryGroup(Map<String, dynamic> data) {
  final group = data['categoryGroup'] as String?;
  if (group != null && group.isNotEmpty) return group;
  final legacy = data['category'] as String?;
  return legacyCategoryToGroup(legacy);
}

/// Normalized category group id for comparison (lowercase). Use when matching against seeded data.
String effectiveCategoryGroupNormalized(Map<String, dynamic> data) {
  return effectiveCategoryGroup(data).toLowerCase().trim();
}

/// Get effective subcategory from auction document (new field or legacy).
String effectiveSubcategory(Map<String, dynamic> data) {
  final sub = data['subcategory'] as String?;
  if (sub != null && sub.isNotEmpty) return sub;
  final legacy = data['category'] as String?;
  if (legacy == null || legacy.isEmpty) return 'collectibles';
  final c = legacy.toLowerCase().trim();
  if (c == 'art') return 'collectibles';
  return legacy;
}

/// Display name for a category group id (from defaults; no Firestore).
String categoryGroupDisplayName(String id) {
  if (id.isEmpty) return id;
  for (final g in defaultTopLevelCategories) {
    if (g.id == id) return g.nameEn;
  }
  return id;
}

/// Display name for a subcategory id (from defaults; no Firestore).
String subcategoryDisplayName(String id) {
  if (id.isEmpty) return id;
  for (final s in defaultSubcategories) {
    if (s.id == id) return s.nameEn;
  }
  return id;
}
