import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' as firebase_core;
import 'package:flutter/foundation.dart' show debugPrint;

class AuctionImageService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Get Storage instance - use default instance (bucket is auto-configured from FirebaseOptions)
  // The bucket is automatically set from Firebase.initializeApp() options
  // For iOS, we need to ensure the bucket is properly configured
  FirebaseStorage get _storage {
    try {
      final instance = FirebaseStorage.instance;
      // Verify bucket is set
      final bucket = instance.app.options.storageBucket;
      if (bucket == null || bucket.isEmpty) {
        debugPrint('Warning: Storage bucket is not configured');
      } else {
        debugPrint('Storage bucket: $bucket');
      }
      return instance;
    } catch (e) {
      debugPrint('Error getting Storage instance: $e');
      rethrow;
    }
  }

  // Validate image file
  bool validateImage({
    required int fileSizeBytes,
    required String? contentType,
  }) {
    // Check file size (5MB max)
    if (fileSizeBytes > 5 * 1024 * 1024) {
      return false;
    }
    
    // Check content type
    if (contentType == null) return false;
    final allowedTypes = ['image/jpeg', 'image/jpg', 'image/png', 'image/webp'];
    return allowedTypes.contains(contentType.toLowerCase());
  }

  // Upload image to Storage (original path)
  Future<String> uploadImage({
    required String auctionId,
    required String imageId,
    required File file,
    String? contentType,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('User must be authenticated');
    }

    // Refresh auth token to ensure it's valid
    try {
      await user.getIdToken(true); // Force refresh
    } catch (e) {
      debugPrint('Warning: Could not refresh auth token: $e');
    }

    // Verify auction exists and user is owner
    final auctionDoc = await _firestore.collection('auctions').doc(auctionId).get();
    if (!auctionDoc.exists) {
      throw Exception('Auction not found. Please create the auction first.');
    }
    
    final auctionData = auctionDoc.data()!;
    final ownerUid = auctionData['ownerUid'] as String? ?? auctionData['sellerId'] as String?;
    if (ownerUid != user.uid) {
      throw Exception('You are not authorized to upload images for this auction');
    }

    // Verify file size
    final fileSize = await file.length();
    final detectedContentType = contentType ?? 'image/jpeg';
    
    if (!validateImage(
      fileSizeBytes: fileSize,
      contentType: detectedContentType,
    )) {
      throw Exception('Invalid image: size must be <= 5MB and format must be jpg/jpeg/png/webp');
    }

    // Determine file extension from content type
    String extension = 'jpg';
    if (detectedContentType.contains('png')) {
      extension = 'png';
    } else if (detectedContentType.contains('webp')) {
      extension = 'webp';
    }

    // Sanitize imageId to avoid path issues
    final sanitizedImageId = imageId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final path = 'auctions/$auctionId/original/$sanitizedImageId.$extension';
    
    try {
      debugPrint('Uploading to path: $path, size: $fileSize bytes, contentType: $detectedContentType');
      debugPrint('User UID: ${user.uid}, Auction ID: $auctionId');
      debugPrint('File path: ${file.path}');
      
      final ref = _storage.ref(path);
      
      final metadata = SettableMetadata(
        contentType: detectedContentType,
        customMetadata: {
          'uploadedBy': user.uid,
          'auctionId': auctionId,
        },
      );
      
      // Verify file exists and is readable
      if (!await file.exists()) {
        throw Exception('File does not exist: ${file.path}');
      }
      
      // Small delay to ensure Storage is ready (helps with -1017 errors)
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Read file as bytes and use putData instead of putFile
      // This can help avoid -1017 errors on iOS
      final fileBytes = await file.readAsBytes();
      debugPrint('File read as bytes: ${fileBytes.length} bytes');
      
      // Use uploadTask with proper error handling
      final uploadTask = ref.putData(fileBytes, metadata);
      
      // Wait for upload to complete with timeout
      final snapshot = await uploadTask.timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          throw Exception('Upload timeout after 60 seconds');
        },
      );
      
      debugPrint('Upload successful: $path, bytesTransferred: ${snapshot.bytesTransferred}');
      
      return path;
    } on firebase_core.FirebaseException catch (e) {
      debugPrint('Firebase Storage error: code=${e.code}, message=${e.message}');
      debugPrint('Error details: ${e.toString()}');
      throw Exception('Storage error (${e.code}): ${e.message ?? 'Unknown error'}');
    } catch (e, stackTrace) {
      debugPrint('Upload error: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }

  // Upload image from bytes (for web)
  Future<String> uploadImageFromBytes({
    required String auctionId,
    required String imageId,
    required Uint8List bytes,
    String? contentType,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('User must be authenticated');
    }

    // Verify file size
    if (!validateImage(
      fileSizeBytes: bytes.length,
      contentType: contentType ?? 'image/jpeg',
    )) {
      throw Exception('Invalid image: size must be <= 5MB and format must be jpg/jpeg/png/webp');
    }

    final path = 'auctions/$auctionId/original/$imageId.jpg';
    final ref = _storage.ref(path);
    
    final metadata = SettableMetadata(
      contentType: contentType ?? 'image/jpeg',
    );
    
    await ref.putData(bytes, metadata);
    return path;
  }

  // Add image metadata to Firestore
  Future<void> addImageMetadata({
    required String auctionId,
    required String imageId,
    required String path,
    required int order,
    required bool isPrimary,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('User must be authenticated');
    }

    final auctionRef = _firestore.collection('auctions').doc(auctionId);
    
    // Use transaction to ensure atomic update
    await _firestore.runTransaction((transaction) async {
      final auctionDoc = await transaction.get(auctionRef);
      if (!auctionDoc.exists) {
        throw Exception('Auction not found');
      }

      final data = auctionDoc.data()!;
      final ownerUid = data['ownerUid'] as String? ?? data['sellerId'] as String?;
      
      // Verify ownership
      if (ownerUid != user.uid) {
        throw Exception('Only auction owner can add images');
      }

      final images = List<Map<String, dynamic>>.from(data['images'] as List? ?? []);
      
      // Check max 6 images
      if (images.length >= 6) {
        throw Exception('Maximum 6 images allowed');
      }

      // If this is the first image, set as primary
      final willBePrimary = images.isEmpty || isPrimary;
      
      // If setting this as primary, unset others
      if (willBePrimary) {
        for (var img in images) {
          img['isPrimary'] = false;
        }
      }

      // Add new image
      images.add({
        'id': imageId,
        'path': path,
        'wmPath': '', // Will be set by Cloud Function
        'url': '', // Will be set by Cloud Function
        'isPrimary': willBePrimary,
        'order': order,
        'uploadedAt': FieldValue.serverTimestamp(),
      });

      transaction.update(auctionRef, {
        'images': images,
        'ownerUid': ownerUid, // Ensure ownerUid is set
      });
    });
  }

  // Update image metadata (set primary, reorder)
  Future<void> updateImageMetadata({
    required String auctionId,
    required String imageId,
    bool? isPrimary,
    int? order,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('User must be authenticated');
    }

    final auctionRef = _firestore.collection('auctions').doc(auctionId);
    
    await _firestore.runTransaction((transaction) async {
      final auctionDoc = await transaction.get(auctionRef);
      if (!auctionDoc.exists) {
        throw Exception('Auction not found');
      }

      final data = auctionDoc.data()!;
      final ownerUid = data['ownerUid'] as String? ?? data['sellerId'] as String?;
      
      if (ownerUid != user.uid) {
        throw Exception('Only auction owner can update images');
      }

      final images = List<Map<String, dynamic>>.from(data['images'] as List? ?? []);
      
      // Find and update image
      var found = false;
      for (var img in images) {
        if (img['id'] == imageId) {
          found = true;
          if (isPrimary != null) {
            // If setting as primary, unset others
            if (isPrimary) {
              for (var other in images) {
                if (other['id'] != imageId) {
                  other['isPrimary'] = false;
                }
              }
            }
            img['isPrimary'] = isPrimary;
          }
          if (order != null) {
            img['order'] = order;
          }
          break;
        }
      }

      if (!found) {
        throw Exception('Image not found');
      }

      // Ensure exactly one primary
      final primaryCount = images.where((img) => img['isPrimary'] == true).length;
      if (primaryCount != 1) {
        // Auto-fix: set first image as primary
        if (images.isNotEmpty) {
          for (var img in images) {
            img['isPrimary'] = false;
          }
          images[0]['isPrimary'] = true;
        }
      }

      transaction.update(auctionRef, {'images': images});
    });
  }

  // Delete image
  Future<void> deleteImage({
    required String auctionId,
    required String imageId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('User must be authenticated');
    }

    final auctionRef = _firestore.collection('auctions').doc(auctionId);
    
    await _firestore.runTransaction((transaction) async {
      final auctionDoc = await transaction.get(auctionRef);
      if (!auctionDoc.exists) {
        throw Exception('Auction not found');
      }

      final data = auctionDoc.data()!;
      final ownerUid = data['ownerUid'] as String? ?? data['sellerId'] as String?;
      
      if (ownerUid != user.uid) {
        throw Exception('Only auction owner can delete images');
      }

      final images = List<Map<String, dynamic>>.from(data['images'] as List? ?? []);
      final imageToDelete = images.firstWhere(
        (img) => img['id'] == imageId,
        orElse: () => throw Exception('Image not found'),
      );

      final wasPrimary = imageToDelete['isPrimary'] == true;
      final path = imageToDelete['path'] as String? ?? '';
      final wmPath = imageToDelete['wmPath'] as String? ?? '';

      // Remove from array
      images.removeWhere((img) => img['id'] == imageId);

      // If deleted was primary and there are remaining images, set first as primary
      if (wasPrimary && images.isNotEmpty) {
        images[0]['isPrimary'] = true;
      }

      transaction.update(auctionRef, {'images': images});

      // Delete from Storage (fire and forget - don't block on this)
      try {
        if (path.isNotEmpty) {
          await _storage.ref(path).delete();
        }
        if (wmPath.isNotEmpty) {
          await _storage.ref(wmPath).delete();
        }
      } catch (e) {
        // Log but don't fail transaction
        debugPrint('Error deleting storage files: $e');
      }
    });
  }

  // Reorder images
  Future<void> reorderImages({
    required String auctionId,
    required List<String> imageIds, // New order
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('User must be authenticated');
    }

    final auctionRef = _firestore.collection('auctions').doc(auctionId);
    
    await _firestore.runTransaction((transaction) async {
      final auctionDoc = await transaction.get(auctionRef);
      if (!auctionDoc.exists) {
        throw Exception('Auction not found');
      }

      final data = auctionDoc.data()!;
      final ownerUid = data['ownerUid'] as String? ?? data['sellerId'] as String?;
      
      if (ownerUid != user.uid) {
        throw Exception('Only auction owner can reorder images');
      }

      final images = List<Map<String, dynamic>>.from(data['images'] as List? ?? []);
      
      // Reorder based on imageIds list
      final reordered = <Map<String, dynamic>>[];
      for (var i = 0; i < imageIds.length; i++) {
        final img = images.firstWhere(
          (img) => img['id'] == imageIds[i],
          orElse: () => throw Exception('Image ${imageIds[i]} not found'),
        );
        img['order'] = i;
        reordered.add(img);
      }

      transaction.update(auctionRef, {'images': reordered});
    });
  }
}
