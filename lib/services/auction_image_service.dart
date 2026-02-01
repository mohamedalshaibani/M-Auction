import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' as firebase_core;
import 'package:flutter/foundation.dart' show debugPrint;

class AuctionImageService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Future<void> _addImageMetadataMutex = Future<void>.value();

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
    debugPrint('[AuctionImageService] Starting upload for imageId: $imageId');
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('[AuctionImageService] User not authenticated');
        throw Exception('User must be authenticated');
      }

      debugPrint('[AuctionImageService] User authenticated: ${user.uid}');

      // Refresh auth token to ensure it's valid
      try {
        debugPrint('[AuctionImageService] Refreshing auth token');
        await user.getIdToken(true); // Force refresh
        debugPrint('[AuctionImageService] Auth token refreshed successfully');
      } catch (e) {
        debugPrint('[AuctionImageService] Warning: Could not refresh auth token: $e');
        // Continue anyway - token might still be valid
      }

      // Verify auction exists and user is owner
      debugPrint('[AuctionImageService] Verifying auction: $auctionId');
      final auctionDoc = await _firestore.collection('auctions').doc(auctionId).get();
      if (!auctionDoc.exists) {
        debugPrint('[AuctionImageService] Auction not found: $auctionId');
        throw Exception('Auction not found. Please create the auction first.');
      }
      
      final auctionData = auctionDoc.data()!;
      final ownerUid = auctionData['ownerUid'] as String? ?? auctionData['sellerId'] as String?;
      if (ownerUid != user.uid) {
        debugPrint('[AuctionImageService] Authorization failed. Owner: $ownerUid, User: ${user.uid}');
        throw Exception('You are not authorized to upload images for this auction');
      }
      
      debugPrint('[AuctionImageService] Authorization verified');

      // Verify file size
      debugPrint('[AuctionImageService] Checking file size');
      final fileSize = await file.length();
      final detectedContentType = contentType ?? 'image/jpeg';
      
      debugPrint('[AuctionImageService] File size: $fileSize bytes, contentType: $detectedContentType');
      
      if (!validateImage(
        fileSizeBytes: fileSize,
        contentType: detectedContentType,
      )) {
        debugPrint('[AuctionImageService] Image validation failed');
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
      
      debugPrint('[AuctionImageService] Uploading to path: $path');
      debugPrint('[AuctionImageService] User UID: ${user.uid}, Auction ID: $auctionId');
      debugPrint('[AuctionImageService] File path: ${file.path}');
      
      final ref = _storage.ref(path);
      
      final metadata = SettableMetadata(
        contentType: detectedContentType,
        customMetadata: {
          'uploadedBy': user.uid,
          'auctionId': auctionId,
          'imageId': imageId,
        },
      );
      
      // Verify file exists and is readable
      if (!await file.exists()) {
        debugPrint('[AuctionImageService] File does not exist: ${file.path}');
        throw Exception('File does not exist: ${file.path}');
      }
      
      // Small delay to ensure Storage is ready (helps with -1017 errors)
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Try putFile first (stream from disk, avoids OOM). On iOS, putFile can fail with
      // -1017; fall back to putData so uploads still succeed.
      debugPrint('[AuctionImageService] Starting Storage upload (putFile)...');
      try {
        final uploadTask = ref.putFile(file, metadata);
        final snapshot = await uploadTask.timeout(
          const Duration(seconds: 60),
          onTimeout: () {
            debugPrint('[AuctionImageService] Upload timeout after 60 seconds');
            throw Exception('Upload timeout after 60 seconds');
          },
        );
        debugPrint('[AuctionImageService] Upload successful (putFile): $path, bytesTransferred: ${snapshot.bytesTransferred}');
        return path;
      } on firebase_core.FirebaseException catch (e, stackTrace) {
        debugPrint('[AuctionImageService] putFile failed: code=${e.code}, message=${e.message}. Retrying with putData...');
        debugPrint('[AuctionImageService] Stack trace: $stackTrace');
        final fileBytes = await file.readAsBytes();
        debugPrint('[AuctionImageService] File read as bytes: ${fileBytes.length} bytes');
        final uploadTask = ref.putData(fileBytes, metadata);
        final snapshot = await uploadTask.timeout(
          const Duration(seconds: 60),
          onTimeout: () {
            debugPrint('[AuctionImageService] putData upload timeout after 60 seconds');
            throw Exception('Upload timeout after 60 seconds');
          },
        );
        debugPrint('[AuctionImageService] Upload successful (putData fallback): $path, bytesTransferred: ${snapshot.bytesTransferred}');
        return path;
      }
    } on firebase_core.FirebaseException catch (e, stackTrace) {
      debugPrint('[AuctionImageService] Firebase Storage error: code=${e.code}, message=${e.message}');
      debugPrint('[AuctionImageService] Error details: ${e.toString()}');
      debugPrint('[AuctionImageService] Stack trace: $stackTrace');
      throw Exception('Storage error (${e.code}): ${e.message ?? 'Unknown error'}');
    } catch (e, stackTrace) {
      debugPrint('[AuctionImageService] Upload error: $e');
      debugPrint('[AuctionImageService] Stack trace: $stackTrace');
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

  /// Returns a long-lived download URL for a Storage path.
  Future<String> getDownloadUrlForPath(String path) async {
    final ref = _storage.ref(path);
    return ref.getDownloadURL();
  }

  /// Upload invoice image (ownership verification). Stored separately; never shown in listing.
  Future<void> uploadInvoiceImage({
    required String auctionId,
    required File file,
    String? contentType,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('User must be authenticated');

    final auctionRef = _firestore.collection('auctions').doc(auctionId);
    final auctionDoc = await auctionRef.get();
    if (!auctionDoc.exists) throw Exception('Auction not found');
    final auctionData = auctionDoc.data()!;
    final ownerUid = auctionData['ownerUid'] as String? ?? auctionData['sellerId'] as String?;
    if (ownerUid != user.uid) throw Exception('Only auction owner can upload invoice image');

    final fileSize = await file.length();
    final detectedContentType = contentType ?? 'image/jpeg';
    if (!validateImage(fileSizeBytes: fileSize, contentType: detectedContentType)) {
      throw Exception('Invalid image: size <= 5MB, jpg/png/webp only');
    }

    String extension = 'jpg';
    if (detectedContentType.contains('png')) extension = 'png';
    else if (detectedContentType.contains('webp')) extension = 'webp';
    final storagePath = 'auctions/$auctionId/invoice/invoice.$extension';
    final ref = _storage.ref(storagePath);

    final metadata = SettableMetadata(
      contentType: detectedContentType,
      customMetadata: {'uploadedBy': user.uid, 'auctionId': auctionId},
    );
    await ref.putFile(file, metadata);
    final url = await ref.getDownloadURL();

    await auctionRef.update({
      'invoiceImagePath': storagePath,
      'invoiceImageUrl': url,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Remove invoice image from auction (and delete from Storage if desired).
  Future<void> deleteInvoiceImage(String auctionId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('User must be authenticated');

    final auctionRef = _firestore.collection('auctions').doc(auctionId);
    final auctionDoc = await auctionRef.get();
    if (!auctionDoc.exists) return;
    final auctionData = auctionDoc.data()!;
    final ownerUid = auctionData['ownerUid'] as String? ?? auctionData['sellerId'] as String?;
    if (ownerUid != user.uid) throw Exception('Only auction owner can delete invoice image');

    final path = auctionData['invoiceImagePath'] as String?;
    if (path != null && path.isNotEmpty) {
      try {
        await _storage.ref(path).delete();
      } catch (_) {}
    }
    await auctionRef.update({
      'invoiceImagePath': FieldValue.delete(),
      'invoiceImageUrl': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Add image metadata via direct Firestore update (no Cloud Function).
  // NOTE: This is now primarily called by the Storage trigger, not the widget.
  // Keeps url when provided (upload-only flow) so images display without watermark.
  Future<void> addImageMetadata({
    required String auctionId,
    required String imageId,
    required String path,
    required int order,
    required bool isPrimary,
    String? url,
  }) async {
    debugPrint('[AuctionImageService] Adding image metadata for: $imageId');

    final prev = _addImageMetadataMutex;
    final completer = Completer<void>();
    _addImageMetadataMutex = completer.future;

    try {
      await prev;
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('[AuctionImageService] User not authenticated for metadata update');
        throw Exception('User must be authenticated');
      }

      final auctionRef = _firestore.collection('auctions').doc(auctionId);

      debugPrint('[AuctionImageService] Fetching auction doc for metadata update');
      final auctionDoc = await auctionRef.get();
      if (!auctionDoc.exists) {
        debugPrint('[AuctionImageService] Auction not found: $auctionId');
        throw Exception('Auction not found');
      }

      final data = auctionDoc.data()!;
      final ownerUid = data['ownerUid'] as String? ?? data['sellerId'] as String?;

      if (ownerUid != user.uid) {
        debugPrint('[AuctionImageService] Ownership verification failed. Owner: $ownerUid, User: ${user.uid}');
        throw Exception('Only auction owner can add images');
      }

      final images = List<Map<String, dynamic>>.from(data['images'] as List? ?? []);

      debugPrint('[AuctionImageService] Current images count: ${images.length}');

      if (images.length >= 6) {
        debugPrint('[AuctionImageService] Maximum 6 images already reached');
        throw Exception('Maximum 6 images allowed');
      }

      final willBePrimary = images.isEmpty || isPrimary;
      debugPrint('[AuctionImageService] Will be primary: $willBePrimary');

      if (willBePrimary) {
        for (var img in images) {
          img['isPrimary'] = false;
        }
      }

      images.add({
        'id': imageId,
        'path': path,
        'wmPath': '',
        'url': url ?? '',
        'isPrimary': willBePrimary,
        'order': order,
        'uploadedAt': FieldValue.serverTimestamp(),
      });

      debugPrint('[AuctionImageService] Updating Firestore with ${images.length} images');
      await auctionRef.update({
        'images': images,
        'ownerUid': ownerUid,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      debugPrint('[AuctionImageService] Image metadata added successfully');
    } catch (e, stackTrace) {
      debugPrint('[AuctionImageService] Error adding image metadata: $e');
      debugPrint('[AuctionImageService] Stack trace: $stackTrace');
      rethrow;
    } finally {
      completer.complete();
    }
  }

  // Update image metadata (set primary, reorder)
  Future<void> updateImageMetadata({
    required String auctionId,
    required String imageId,
    bool? isPrimary,
    int? order,
  }) async {
    debugPrint('[AuctionImageService] Updating image metadata for: $imageId');
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('[AuctionImageService] User not authenticated for metadata update');
        throw Exception('User must be authenticated');
      }

      final auctionRef = _firestore.collection('auctions').doc(auctionId);
      
      await _firestore.runTransaction((transaction) async {
        final auctionDoc = await transaction.get(auctionRef);
        if (!auctionDoc.exists) {
          debugPrint('[AuctionImageService] Auction not found: $auctionId');
          throw Exception('Auction not found');
        }

        final data = auctionDoc.data()!;
        final ownerUid = data['ownerUid'] as String? ?? data['sellerId'] as String?;
        
        if (ownerUid != user.uid) {
          debugPrint('[AuctionImageService] Ownership verification failed');
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
              debugPrint('[AuctionImageService] Set primary: $isPrimary');
            }
            if (order != null) {
              img['order'] = order;
              debugPrint('[AuctionImageService] Set order: $order');
            }
            break;
          }
        }

        if (!found) {
          debugPrint('[AuctionImageService] Image not found: $imageId');
          throw Exception('Image not found');
        }

        // Ensure exactly one primary
        final primaryCount = images.where((img) => img['isPrimary'] == true).length;
        if (primaryCount != 1) {
          debugPrint('[AuctionImageService] Primary count is $primaryCount, auto-fixing...');
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
      
      debugPrint('[AuctionImageService] Image metadata updated successfully');
    } catch (e, stackTrace) {
      debugPrint('[AuctionImageService] Error updating image metadata: $e');
      debugPrint('[AuctionImageService] Stack trace: $stackTrace');
      rethrow;
    }
  }

  // Delete image
  Future<void> deleteImage({
    required String auctionId,
    required String imageId,
  }) async {
    debugPrint('[AuctionImageService] Deleting image: $imageId');
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('[AuctionImageService] User not authenticated for delete');
        throw Exception('User must be authenticated');
      }

      final auctionRef = _firestore.collection('auctions').doc(auctionId);
      
      await _firestore.runTransaction((transaction) async {
        final auctionDoc = await transaction.get(auctionRef);
        if (!auctionDoc.exists) {
          debugPrint('[AuctionImageService] Auction not found: $auctionId');
          throw Exception('Auction not found');
        }

        final data = auctionDoc.data()!;
        final ownerUid = data['ownerUid'] as String? ?? data['sellerId'] as String?;
        
        if (ownerUid != user.uid) {
          debugPrint('[AuctionImageService] Ownership verification failed for delete');
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

        debugPrint('[AuctionImageService] Image to delete - wasPrimary: $wasPrimary, path: $path');

        // Remove from array
        images.removeWhere((img) => img['id'] == imageId);

        // If deleted was primary and there are remaining images, set first as primary
        if (wasPrimary && images.isNotEmpty) {
          images[0]['isPrimary'] = true;
          debugPrint('[AuctionImageService] Set first remaining image as primary');
        }

        transaction.update(auctionRef, {'images': images});

        // Delete from Storage (fire and forget - don't block on this)
        try {
          if (path.isNotEmpty) {
            debugPrint('[AuctionImageService] Deleting storage file: $path');
            await _storage.ref(path).delete();
          }
          if (wmPath.isNotEmpty) {
            debugPrint('[AuctionImageService] Deleting watermark storage file: $wmPath');
            await _storage.ref(wmPath).delete();
          }
        } catch (e, stackTrace) {
          // Log but don't fail transaction
          debugPrint('[AuctionImageService] Error deleting storage files: $e');
          debugPrint('[AuctionImageService] Stack trace: $stackTrace');
        }
      });
      
      debugPrint('[AuctionImageService] Image deleted successfully');
    } catch (e, stackTrace) {
      debugPrint('[AuctionImageService] Error deleting image: $e');
      debugPrint('[AuctionImageService] Stack trace: $stackTrace');
      rethrow;
    }
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
