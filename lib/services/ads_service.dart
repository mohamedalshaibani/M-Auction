import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// Partner ad / banner for home page. One banner per partner (dedupe by partnerId).
class PartnerAd {
  final String id;
  final String partnerId;
  final String partnerName;
  final String imageUrl;
  final String? linkUrl;
  final int order;
  final bool active;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  const PartnerAd({
    required this.id,
    required this.partnerId,
    required this.partnerName,
    required this.imageUrl,
    this.linkUrl,
    this.order = 0,
    this.active = true,
    this.createdAt,
    this.expiresAt,
  });

  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);

  static PartnerAd fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    final ts = d['createdAt'] as Timestamp?;
    final expTs = d['expiresAt'] as Timestamp?;
    return PartnerAd(
      id: doc.id,
      partnerId: d['partnerId'] as String? ?? doc.id,
      partnerName: d['partnerName'] as String? ?? 'Partner',
      imageUrl: d['imageUrl'] as String? ?? '',
      linkUrl: d['linkUrl'] as String?,
      order: (d['order'] as num?)?.toInt() ?? 0,
      active: d['active'] as bool? ?? true,
      createdAt: ts?.toDate(),
      expiresAt: expTs?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'partnerId': partnerId,
        'partnerName': partnerName,
        'imageUrl': imageUrl,
        if (linkUrl != null && linkUrl!.isNotEmpty) 'linkUrl': linkUrl,
        'order': order,
        'active': active,
        'createdAt': createdAt != null
            ? Timestamp.fromDate(createdAt!)
            : FieldValue.serverTimestamp(),
      };
}

/// Stream of active ads, one per partner (dedupe by partnerId, keep highest order).
Stream<List<PartnerAd>> streamPartnerAdsOnePerPartner() {
  return FirebaseFirestore.instance
      .collection('ads')
      .where('active', isEqualTo: true)
      .snapshots()
      .map((snapshot) {
    final list = snapshot.docs
        .map((d) => PartnerAd.fromDoc(d))
        .where((a) => a.imageUrl.isNotEmpty && !a.isExpired)
        .toList();
    list.sort((a, b) => b.order.compareTo(a.order));
    final seen = <String>{};
    final onePerPartner = <PartnerAd>[];
    for (final ad in list) {
      if (seen.contains(ad.partnerId)) continue;
      seen.add(ad.partnerId);
      onePerPartner.add(ad);
    }
    return onePerPartner;
  });
}

/// Admin: stream all ads (for management).
Stream<QuerySnapshot> streamAllAds() {
  return FirebaseFirestore.instance.collection('ads').snapshots();
}

/// Admin: create ad. [durationDays] = days from now until ad expires (0 = no expiry).
Future<void> createAd({
  required String partnerId,
  required String partnerName,
  required String imageUrl,
  String? linkUrl,
  int order = 0,
  int durationDays = 0,
}) async {
  final now = DateTime.now();
  final data = <String, dynamic>{
    'partnerId': partnerId,
    'partnerName': partnerName,
    'imageUrl': imageUrl,
    if (linkUrl != null && linkUrl.isNotEmpty) 'linkUrl': linkUrl,
    'order': order,
    'active': true,
    'createdAt': FieldValue.serverTimestamp(),
  };
  if (durationDays > 0) {
    data['expiresAt'] = Timestamp.fromDate(
      now.add(Duration(days: durationDays)),
    );
  }
  await FirebaseFirestore.instance.collection('ads').add(data);
}

/// Admin: update ad.
Future<void> updateAd(
  String adId, {
  String? partnerId,
  String? partnerName,
  String? imageUrl,
  String? linkUrl,
  int? order,
  bool? active,
  DateTime? expiresAt,
}) async {
  final ref = FirebaseFirestore.instance.collection('ads').doc(adId);
  final updates = <String, dynamic>{};
  if (partnerId != null) updates['partnerId'] = partnerId;
  if (partnerName != null) updates['partnerName'] = partnerName;
  if (imageUrl != null) updates['imageUrl'] = imageUrl;
  if (linkUrl != null) updates['linkUrl'] = linkUrl;
  if (order != null) updates['order'] = order;
  if (active != null) updates['active'] = active;
  if (expiresAt != null) {
    updates['expiresAt'] = Timestamp.fromDate(expiresAt);
  }
  updates['updatedAt'] = FieldValue.serverTimestamp();
  await ref.update(updates);
}

/// Admin: delete ad.
Future<void> deleteAd(String adId) async {
  await FirebaseFirestore.instance.collection('ads').doc(adId).delete();
}

/// Upload ad request attachment to Storage. Path: adRequests/{uid}/{fileName}
Future<String> uploadAdRequestImage({
  required String uid,
  required String fileName,
  required Uint8List bytes,
  String contentType = 'image/jpeg',
}) async {
  final ref = FirebaseStorage.instance.ref('adRequests/$uid/$fileName');
  final metadata = SettableMetadata(contentType: contentType);
  await ref.putData(bytes, metadata);
  return ref.getDownloadURL();
}

/// Submit ad request (partners). Requires authenticated user.
Future<void> submitAdRequest({
  required String partnerName,
  required String contactEmail,
  String? company,
  String? message,
  String? imageUrl,
  String? preferredSize,
}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    throw Exception(
      'You must be signed in to submit an ad request. Please sign in and try again.',
    );
  }
  await FirebaseFirestore.instance.collection('adRequests').add({
    'partnerName': partnerName,
    'contactEmail': contactEmail,
    if (company != null && company.isNotEmpty) 'company': company,
    if (message != null && message.isNotEmpty) 'message': message,
    if (imageUrl != null && imageUrl.isNotEmpty) 'imageUrl': imageUrl,
    if (preferredSize != null && preferredSize.isNotEmpty) 'preferredSize': preferredSize,
    'uid': user.uid,
    'status': 'pending',
    'createdAt': FieldValue.serverTimestamp(),
  });
}
