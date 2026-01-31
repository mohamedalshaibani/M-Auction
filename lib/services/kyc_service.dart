import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../firebase_options.dart';

class KycService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Get Storage instance with explicit bucket for web compatibility
  FirebaseStorage get _storage {
    if (kIsWeb) {
      // For web, explicitly use the bucket from firebase_options
      final bucket = DefaultFirebaseOptions.currentPlatform.storageBucket;
      if (bucket != null) {
        return FirebaseStorage.instanceFor(bucket: bucket);
      }
    }
    return FirebaseStorage.instance;
  }

  // Upload file to Storage
  Future<String> uploadFile({
    required String uid,
    required String fileName,
    required File file,
  }) async {
    // Verify user is authenticated
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('User must be authenticated to upload files');
    }
    
    if (user.uid != uid) {
      throw Exception('User ID mismatch: cannot upload for different user');
    }
    
    // Ensure path matches storage rules: kyc/{uid}/...
    final ref = _storage.ref('kyc/$uid/$fileName');
    
    // Set metadata with content type
    final metadata = SettableMetadata(
      contentType: 'image/jpeg',
    );
    
    // Upload with metadata
    await ref.putFile(file, metadata);
    return await ref.getDownloadURL();
  }

  // For web: upload from Uint8List/Blob
  Future<String> uploadFileFromBytes({
    required String uid,
    required String fileName,
    required Uint8List bytes,
    String? contentType,
  }) async {
    // Verify user is authenticated
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('User must be authenticated to upload files');
    }
    
    if (user.uid != uid) {
      throw Exception('User ID mismatch: cannot upload for different user');
    }
    
    // Ensure path matches storage rules: kyc/{uid}/...
    final ref = _storage.ref('kyc/$uid/$fileName');
    
    // Set metadata with content type
    final metadata = SettableMetadata(
      contentType: contentType ?? 'image/jpeg',
    );
    
    // Upload with metadata
    await ref.putData(bytes, metadata);
    return await ref.getDownloadURL();
  }

  // Submit KYC request
  Future<void> submitKycRequest({
    required String uid,
    required String fullName,
    required String nationality,
    required String dob,
    required String idType,
    required String idNumber,
    required String idFrontUrl,
    String? idBackUrl,
    required String selfieUrl,
    required String proofType,
    required String proofUrl,
    String? proofNote,
  }) async {
    final batch = _firestore.batch();

    // Create/update KYC request
    final kycRequestRef = _firestore.collection('kycRequests').doc(uid);
    batch.set(kycRequestRef, {
      'userId': uid,
      'fullName': fullName,
      'nationality': nationality,
      'dob': dob,
      'idType': idType,
      'idNumber': idNumber,
      'idFrontUrl': idFrontUrl,
      if (idBackUrl != null) 'idBackUrl': idBackUrl,
      'selfieUrl': selfieUrl,
      'proofType': proofType,
      'proofUrl': proofUrl,
      if (proofNote != null) 'proofNote': proofNote,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Update user KYC status
    final userRef = _firestore.collection('users').doc(uid);
    batch.update(userRef, {
      'kycStatus': 'pending',
      'kycSubmittedAt': FieldValue.serverTimestamp(),
      'kycRejectionReason': FieldValue.delete(),
    });

    await batch.commit();
  }

  // Get KYC request
  Future<DocumentSnapshot> getKycRequest(String uid) async {
    return await _firestore.collection('kycRequests').doc(uid).get();
  }

  // Stream KYC request
  Stream<DocumentSnapshot> streamKycRequest(String uid) {
    return _firestore.collection('kycRequests').doc(uid).snapshots();
  }

  // Admin approve KYC
  Future<void> approveKyc(String uid, String reviewedBy) async {
    final batch = _firestore.batch();

    final kycRequestRef = _firestore.collection('kycRequests').doc(uid);
    batch.update(kycRequestRef, {
      'status': 'approved',
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewedBy': reviewedBy,
      'rejectionReason': FieldValue.delete(),
    });

    final userRef = _firestore.collection('users').doc(uid);
    batch.update(userRef, {
      'kycStatus': 'approved',
      'kycRejectionReason': FieldValue.delete(),
    });

    await batch.commit();
  }

  // Admin reject KYC
  Future<void> rejectKyc(String uid, String rejectionReason, String reviewedBy) async {
    final batch = _firestore.batch();

    final kycRequestRef = _firestore.collection('kycRequests').doc(uid);
    batch.update(kycRequestRef, {
      'status': 'rejected',
      'rejectionReason': rejectionReason,
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewedBy': reviewedBy,
    });

    final userRef = _firestore.collection('users').doc(uid);
    batch.update(userRef, {
      'kycStatus': 'rejected',
      'kycRejectionReason': rejectionReason,
    });

    await batch.commit();
  }

  // Stream pending KYC requests (for admin)
  Stream<QuerySnapshot> streamPendingKycRequests() {
    return _firestore
        .collection('kycRequests')
        .where('status', isEqualTo: 'pending')
        .snapshots();
  }
}
