import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/brand_model.dart';

/// Brand CRUD. Brands collection: brands/{brandId} with name, category, isActive, createdAt, createdBy.
class BrandService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get active brands, optionally filtered by category.
  Future<List<Brand>> getBrands({String? category, bool activeOnly = true}) async {
    Query<Map<String, dynamic>> query = _firestore.collection('brands');
    if (category != null && category.isNotEmpty) {
      query = query.where('category', isEqualTo: category);
    }
    if (activeOnly) {
      query = query.where('isActive', isEqualTo: true);
    }
    query = query.orderBy('name');
    final snapshot = await query.get();
    return snapshot.docs.map((d) => Brand.fromDoc(d)).toList();
  }

  /// Stream active brands by category.
  Stream<List<Brand>> streamBrandsByCategory(String category) {
    return _firestore
        .collection('brands')
        .where('category', isEqualTo: category)
        .where('isActive', isEqualTo: true)
        .orderBy('name')
        .snapshots()
        .map((s) => s.docs.map((d) => Brand.fromDoc(d)).toList());
  }

  /// Get brand by id (for display).
  Future<Brand?> getBrand(String brandId) async {
    final doc = await _firestore.collection('brands').doc(brandId).get();
    if (!doc.exists) return null;
    return Brand.fromDoc(doc);
  }

  /// Resolve display name from brandId. Returns brandId if not found.
  Future<String> getBrandName(String brandId) async {
    final b = await getBrand(brandId);
    return b?.name ?? brandId;
  }

  /// Admin: create brand.
  Future<String> createBrand({
    required String name,
    required String category,
    bool isActive = true,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final ref = _firestore.collection('brands').doc();
    await ref.set({
      'name': name.trim(),
      'category': category,
      'isActive': isActive,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': user?.uid,
    });
    return ref.id;
  }

  /// Admin: update brand.
  Future<void> updateBrand(
    String brandId, {
    String? name,
    String? category,
    bool? isActive,
  }) async {
    final updates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (name != null) updates['name'] = name.trim();
    if (category != null) updates['category'] = category;
    if (isActive != null) updates['isActive'] = isActive;
    await _firestore.collection('brands').doc(brandId).update(updates);
  }

  /// Admin: delete brand (or soft-deactivate).
  Future<void> deleteBrand(String brandId) async {
    await _firestore.collection('brands').doc(brandId).update({
      'isActive': false,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Admin: stream all brands (for management, includes inactive).
  Stream<QuerySnapshot> streamAllBrands() {
    return _firestore.collection('brands').orderBy('name').snapshots();
  }
}
