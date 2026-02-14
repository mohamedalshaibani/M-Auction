import 'package:cloud_firestore/cloud_firestore.dart';

/// Brand from Firestore brands collection. Replaces legacy watchBrands/whitelist.
class Brand {
  final String id;
  final String name;
  final String category;
  final bool isActive;
  final DateTime? createdAt;
  final String? createdBy;

  const Brand({
    required this.id,
    required this.name,
    required this.category,
    this.isActive = true,
    this.createdAt,
    this.createdBy,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'category': category,
        'isActive': isActive,
        if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
        if (createdBy != null && createdBy!.isNotEmpty) 'createdBy': createdBy,
      };

  static Brand fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final ts = data['createdAt'] as Timestamp?;
    return Brand(
      id: doc.id,
      name: data['name'] as String? ?? '',
      category: data['category'] as String? ?? 'other',
      isActive: data['isActive'] as bool? ?? true,
      createdAt: ts?.toDate(),
      createdBy: data['createdBy'] as String?,
    );
  }

  static Brand fromMap(String id, Map<String, dynamic> data) {
    final ts = data['createdAt'] as Timestamp?;
    return Brand(
      id: id,
      name: data['name'] as String? ?? '',
      category: data['category'] as String? ?? 'other',
      isActive: data['isActive'] as bool? ?? true,
      createdAt: ts?.toDate(),
      createdBy: data['createdBy'] as String?,
    );
  }
}
