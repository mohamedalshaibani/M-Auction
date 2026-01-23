import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auction_image_service.dart';
import '../theme/app_theme.dart';

class AuctionImageUploader extends StatefulWidget {
  final String auctionId;
  final bool isDraft;

  const AuctionImageUploader({
    super.key,
    required this.auctionId,
    this.isDraft = true,
  });

  @override
  State<AuctionImageUploader> createState() => _AuctionImageUploaderState();
}

class _AuctionImageUploaderState extends State<AuctionImageUploader> {
  final _imageService = AuctionImageService();
  final _picker = ImagePicker();
  final List<XFile> _selectedFiles = [];
  final List<XFile> _uploadQueue = []; // Queue for sequential uploads
  final Map<String, String> _uploadStatus = {}; // imageId -> status
  final Map<String, double> _uploadProgress = {}; // imageId -> progress
  bool _isUploading = false; // Track if upload is in progress
  static const int _maxConcurrentUploads = 1; // One at a time to avoid OOM / "Lost connection" on iOS

  @override
  void initState() {
    super.initState();
    _loadExistingImages();
  }

  Future<void> _loadExistingImages() async {
    // Load existing images from Firestore to show current state
    // This will be handled by StreamBuilder in parent
  }

  Future<void> _pickImages() async {
    try {
      final List<XFile> pickedFiles = await _picker.pickMultiImage();
      
      if (pickedFiles.isEmpty) return;

      // Check total count
      final currentCount = _selectedFiles.length;
      if (currentCount + pickedFiles.length > 6) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Maximum 6 images allowed'),
              backgroundColor: AppTheme.error,
            ),
          );
        }
        return;
      }

      // Validate each file
      final validFiles = <XFile>[];
      for (var file in pickedFiles) {
        final size = await file.length();
        final contentType = await _getContentType(file);
        
        if (!_imageService.validateImage(
          fileSizeBytes: size,
          contentType: contentType,
        )) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${file.name}: Invalid file (max 5MB, jpg/png/webp only)'),
                backgroundColor: AppTheme.error,
              ),
            );
          }
          continue;
        }
        
        validFiles.add(file);
      }

      if (mounted) {
        setState(() {
          _selectedFiles.addAll(validFiles);
          _uploadQueue.addAll(validFiles);
        });
      }

      // Start sequential uploads (max 2 concurrent)
      _processUploadQueue();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking images: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<String?> _getContentType(XFile file) async {
    final path = file.path.toLowerCase();
    final mimeType = file.mimeType;
    
    // Prefer mimeType from XFile if available
    if (mimeType != null && mimeType.startsWith('image/')) {
      return mimeType;
    }
    
    // Fallback to extension-based detection
    if (path.endsWith('.jpg') || path.endsWith('.jpeg')) {
      return 'image/jpeg';
    } else if (path.endsWith('.png')) {
      return 'image/png';
    } else if (path.endsWith('.webp')) {
      return 'image/webp';
    }
    return 'image/jpeg'; // Default
  }

  // Process upload queue sequentially (max 2 concurrent)
  Future<void> _processUploadQueue() async {
    if (_isUploading || _uploadQueue.isEmpty) return;
    
    _isUploading = true;
    debugPrint('[Upload] Starting upload queue processing. Queue size: ${_uploadQueue.length}');
    
    final activeUploads = <Future<void>>[];
    
    while (_uploadQueue.isNotEmpty || activeUploads.isNotEmpty) {
      // Start new uploads if we have capacity
      while (activeUploads.length < _maxConcurrentUploads && _uploadQueue.isNotEmpty) {
        if (!mounted) {
          debugPrint('[Upload] Widget disposed, stopping upload queue');
          _isUploading = false;
          return;
        }
        
        final file = _uploadQueue.removeAt(0);
        final f = _uploadImage(file);
        f.whenComplete(() {
          activeUploads.removeWhere((x) => x == f);
        });
        activeUploads.add(f);
        debugPrint('[Upload] Started upload for: ${file.name}');
      }
      
      // Wait for at least one upload to complete
      if (activeUploads.isNotEmpty) {
        await Future.any(activeUploads);
      }
    }
    
    _isUploading = false;
    debugPrint('[Upload] Upload queue processing complete');
  }

  Future<void> _uploadImage(XFile file) async {
    final imageId = '${DateTime.now().millisecondsSinceEpoch}_${file.name.hashCode}';
    
    debugPrint('[Upload] Starting upload for imageId: $imageId, file: ${file.name}');
    
    if (!mounted) {
      debugPrint('[Upload] Widget not mounted, aborting upload for: $imageId');
      return;
    }
    
    try {
      setState(() {
        _uploadStatus[imageId] = 'uploading';
        _uploadProgress[imageId] = 0.0;
      });
    } catch (e) {
      debugPrint('[Upload] Error in setState before upload: $e');
      return;
    }

    try {
      debugPrint('[Upload] Getting content type for: ${file.name}');
      final contentType = await _getContentType(file);
      final fileObj = File(file.path);
      
      // Verify file exists before upload
      if (!await fileObj.exists()) {
        throw Exception('File no longer exists. Please try again.');
      }
      
      debugPrint('[Upload] File exists, size: ${await fileObj.length()} bytes');
      
      // Upload to Storage with error handling
      String uploadedPath;
      try {
        debugPrint('[Upload] Calling uploadImage service for: $imageId');
        uploadedPath = await _imageService.uploadImage(
          auctionId: widget.auctionId,
          imageId: imageId,
          file: fileObj,
          contentType: contentType,
        );
        debugPrint('[Upload] Storage upload successful: $uploadedPath');
      } catch (uploadError, stackTrace) {
        // Prevent app crash - log and show user-friendly error
        debugPrint('[Upload] Storage upload error: $uploadError');
        debugPrint('[Upload] Stack trace: $stackTrace');
        throw Exception('Failed to upload image. Please check your connection and try again.');
      }

      if (!mounted) {
        debugPrint('[Upload] Widget disposed after upload, aborting metadata update');
        return;
      }

      // Add metadata to Firestore
      debugPrint('[Upload] Getting current images for metadata update');
      final currentImages = await _getCurrentImages();
      final isPrimary = currentImages.isEmpty; // First image is primary
      
      debugPrint('[Upload] Current images count: ${currentImages.length}, isPrimary: $isPrimary');
      
      try {
        debugPrint('[Upload] Adding image metadata to Firestore');
        await _imageService.addImageMetadata(
          auctionId: widget.auctionId,
          imageId: imageId,
          path: uploadedPath,
          order: currentImages.length,
          isPrimary: isPrimary,
        );
        debugPrint('[Upload] Image metadata added successfully');
      } catch (metadataError, stackTrace) {
        // Don't fail completely - image is uploaded, metadata can be retried
        debugPrint('[Upload] Metadata update error: $metadataError');
        debugPrint('[Upload] Stack trace: $stackTrace');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Image uploaded but metadata update failed. Please refresh.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        // Still continue to watermark wait
      }

      if (!mounted) {
        debugPrint('[Upload] Widget disposed after metadata update');
        return;
      }

      try {
        setState(() {
          _uploadStatus[imageId] = 'processing';
          _uploadProgress[imageId] = 1.0;
          _selectedFiles.removeWhere((f) => f.path == file.path);
        });
      } catch (e) {
        debugPrint('[Upload] Error in setState after metadata: $e');
      }

      // Wait for watermark processing (poll Firestore for url)
      debugPrint('[Upload] Starting watermark wait for: $imageId');
      await _waitForWatermark(imageId);
      debugPrint('[Upload] Watermark wait complete for: $imageId');
    } catch (e, stackTrace) {
      debugPrint('[Upload] Upload error for $imageId: $e');
      debugPrint('[Upload] Stack trace: $stackTrace');
      
      if (!mounted) {
        debugPrint('[Upload] Widget not mounted, cannot update error state');
        return;
      }
      
      try {
        setState(() {
          _uploadStatus[imageId] = 'error';
          _selectedFiles.removeWhere((f) => f.path == file.path);
        });
      } catch (setStateError) {
        debugPrint('[Upload] Error in setState for error case: $setStateError');
      }
      
      if (mounted) {
        // Show user-friendly error message
        final errorMessage = e.toString().replaceAll('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $errorMessage'),
            backgroundColor: AppTheme.error,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<List<Map<String, dynamic>>> _getCurrentImages() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('auctions')
          .doc(widget.auctionId)
          .get();
      
      if (!doc.exists) {
        debugPrint('[GetCurrentImages] Auction document does not exist: ${widget.auctionId}');
        return [];
      }
      
      final data = doc.data()!;
      final images = List<Map<String, dynamic>>.from(data['images'] as List? ?? []);
      debugPrint('[GetCurrentImages] Found ${images.length} images');
      return images;
    } catch (e, stackTrace) {
      debugPrint('[GetCurrentImages] Error getting current images: $e');
      debugPrint('[GetCurrentImages] Stack trace: $stackTrace');
      return [];
    }
  }

  Future<void> _waitForWatermark(String imageId) async {
    // Poll Firestore until watermark URL appears
    int attempts = 0;
    const maxAttempts = 30; // 30 seconds max wait
    
    debugPrint('[Watermark] Starting watermark wait for: $imageId');
    
    while (attempts < maxAttempts) {
      if (!mounted) {
        debugPrint('[Watermark] Widget disposed during watermark wait for: $imageId');
        return;
      }
      
      await Future.delayed(const Duration(seconds: 1));
      
      try {
        final images = await _getCurrentImages();
        final image = images.firstWhere(
          (img) => img['id'] == imageId,
          orElse: () => <String, dynamic>{},
        );
        
        final url = image['url'] as String? ?? '';
        if (url.isNotEmpty) {
          debugPrint('[Watermark] Watermark URL found for $imageId: $url');
          if (mounted) {
            try {
              setState(() {
                _uploadStatus[imageId] = 'complete';
              });
            } catch (e) {
              debugPrint('[Watermark] Error in setState when watermark found: $e');
            }
          }
          return;
        }
        
        attempts++;
        if (attempts % 5 == 0) {
          debugPrint('[Watermark] Still waiting for watermark URL, attempt $attempts/$maxAttempts');
        }
      } catch (e, stackTrace) {
        debugPrint('[Watermark] Error during watermark wait: $e');
        debugPrint('[Watermark] Stack trace: $stackTrace');
        // Continue waiting despite error
        attempts++;
      }
    }
    
    // Timeout - still show as processing
    debugPrint('[Watermark] Timeout waiting for watermark URL for: $imageId');
    if (mounted) {
      try {
        setState(() {
          _uploadStatus[imageId] = 'processing';
        });
      } catch (e) {
        debugPrint('[Watermark] Error in setState on timeout: $e');
      }
    }
  }

  Future<void> _setPrimary(String imageId) async {
    if (!mounted) return;
    
    try {
      debugPrint('[SetPrimary] Setting primary image: $imageId');
      await _imageService.updateImageMetadata(
        auctionId: widget.auctionId,
        imageId: imageId,
        isPrimary: true,
      );
      debugPrint('[SetPrimary] Successfully set primary image: $imageId');
    } catch (e, stackTrace) {
      debugPrint('[SetPrimary] Error setting primary: $e');
      debugPrint('[SetPrimary] Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _deleteImage(String imageId) async {
    if (!mounted) return;
    
    try {
      debugPrint('[Delete] Deleting image: $imageId');
      await _imageService.deleteImage(
        auctionId: widget.auctionId,
        imageId: imageId,
      );
      debugPrint('[Delete] Successfully deleted image: $imageId');
    } catch (e, stackTrace) {
      debugPrint('[Delete] Error deleting image: $e');
      debugPrint('[Delete] Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('auctions')
          .doc(widget.auctionId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final data = snapshot.data!.data() as Map<String, dynamic>?;
        final images = List<Map<String, dynamic>>.from(data?['images'] as List? ?? []);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Images (${images.length}/6)',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            
            // Image grid
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                // Existing images (sorted by order)
                ...(images..sort((a, b) {
                  final aOrder = a['order'] as int? ?? 0;
                  final bOrder = b['order'] as int? ?? 0;
                  return aOrder.compareTo(bOrder);
                })).map((img) {
                  final imageId = img['id'] as String;
                  final url = img['url'] as String? ?? '';
                  final isPrimary = img['isPrimary'] == true;
                  final isProcessing = url.isEmpty;
                  
                  return _ImageThumbnail(
                    imageId: imageId,
                    url: url,
                    isPrimary: isPrimary,
                    isProcessing: isProcessing,
                    onSetPrimary: () => _setPrimary(imageId),
                    onDelete: () => _deleteImage(imageId),
                  );
                }),
                
                // Upload button (if less than 6)
                if (images.length < 6)
                  _UploadButton(
                    onTap: _pickImages,
                    isUploading: _selectedFiles.isNotEmpty,
                  ),
              ],
            ),
            
            // Upload status for pending files
            if (_selectedFiles.isNotEmpty) ...[
              const SizedBox(height: 12),
              ..._selectedFiles.map((file) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Uploading ${file.name}...',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        );
      },
    );
  }
}

class _ImageThumbnail extends StatelessWidget {
  final String imageId;
  final String url;
  final bool isPrimary;
  final bool isProcessing;
  final VoidCallback onSetPrimary;
  final VoidCallback onDelete;

  const _ImageThumbnail({
    required this.imageId,
    required this.url,
    required this.isPrimary,
    required this.isProcessing,
    required this.onSetPrimary,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: AppTheme.backgroundGrey,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isPrimary ? AppTheme.primaryBlue : AppTheme.border,
              width: isPrimary ? 2 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: isProcessing
                ? const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : url.isNotEmpty
                    ? Image.network(
                        url,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const Icon(Icons.broken_image);
                        },
                      )
                    : const Icon(Icons.image),
          ),
        ),
        // Primary badge
        if (isPrimary)
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.star,
                size: 12,
                color: Colors.white,
              ),
            ),
          ),
        // Actions overlay (show on hover/long press)
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(14),
                bottomRight: Radius.circular(14),
              ),
              color: Colors.black.withValues(alpha: 0.6),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!isPrimary)
                  IconButton(
                    icon: const Icon(Icons.star_border, color: Colors.white, size: 20),
                    onPressed: onSetPrimary,
                    tooltip: 'Set as primary',
                  ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.white, size: 20),
                  onPressed: onDelete,
                  tooltip: 'Delete',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _UploadButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool isUploading;

  const _UploadButton({
    required this.onTap,
    this.isUploading = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: isUploading ? null : onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          color: AppTheme.backgroundGrey,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppTheme.border,
            width: 1,
          ),
        ),
        child: isUploading
            ? const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_photo_alternate, size: 32),
                  SizedBox(height: 4),
                  Text(
                    'Add Image',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
      ),
    );
  }
}
