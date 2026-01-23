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
  final Map<String, String> _uploadStatus = {}; // imageId -> status
  final Map<String, double> _uploadProgress = {}; // imageId -> progress

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

      setState(() {
        _selectedFiles.addAll(validFiles);
      });

      // Auto-upload valid files
      for (var file in validFiles) {
        _uploadImage(file);
      }
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

  Future<void> _uploadImage(XFile file) async {
    final imageId = '${DateTime.now().millisecondsSinceEpoch}_${file.name.hashCode}';
    
    setState(() {
      _uploadStatus[imageId] = 'uploading';
      _uploadProgress[imageId] = 0.0;
    });

    try {
      final contentType = await _getContentType(file);
      final fileObj = File(file.path);
      
      // Upload to Storage
      await _imageService.uploadImage(
        auctionId: widget.auctionId,
        imageId: imageId,
        file: fileObj,
        contentType: contentType,
      );

      // Add metadata to Firestore
      final currentImages = await _getCurrentImages();
      final isPrimary = currentImages.isEmpty; // First image is primary
      
      await _imageService.addImageMetadata(
        auctionId: widget.auctionId,
        imageId: imageId,
        path: 'auctions/${widget.auctionId}/original/$imageId.jpg',
        order: currentImages.length,
        isPrimary: isPrimary,
      );

      setState(() {
        _uploadStatus[imageId] = 'processing';
        _uploadProgress[imageId] = 1.0;
        _selectedFiles.removeWhere((f) => f.path == file.path);
      });

      // Wait for watermark processing (poll Firestore for url)
      _waitForWatermark(imageId);
    } catch (e) {
      setState(() {
        _uploadStatus[imageId] = 'error';
        _selectedFiles.removeWhere((f) => f.path == file.path);
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<List<Map<String, dynamic>>> _getCurrentImages() async {
    final doc = await FirebaseFirestore.instance
        .collection('auctions')
        .doc(widget.auctionId)
        .get();
    
    if (!doc.exists) return [];
    final data = doc.data()!;
    return List<Map<String, dynamic>>.from(data['images'] as List? ?? []);
  }

  Future<void> _waitForWatermark(String imageId) async {
    // Poll Firestore until watermark URL appears
    int attempts = 0;
    const maxAttempts = 30; // 30 seconds max wait
    
    while (attempts < maxAttempts) {
      await Future.delayed(const Duration(seconds: 1));
      
      final images = await _getCurrentImages();
      final image = images.firstWhere(
        (img) => img['id'] == imageId,
        orElse: () => <String, dynamic>{},
      );
      
      final url = image['url'] as String? ?? '';
      if (url.isNotEmpty) {
        setState(() {
          _uploadStatus[imageId] = 'complete';
        });
        return;
      }
      
      attempts++;
    }
    
    // Timeout - still show as processing
    setState(() {
      _uploadStatus[imageId] = 'processing';
    });
  }

  Future<void> _setPrimary(String imageId) async {
    try {
      await _imageService.updateImageMetadata(
        auctionId: widget.auctionId,
        imageId: imageId,
        isPrimary: true,
      );
    } catch (e) {
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
    try {
      await _imageService.deleteImage(
        auctionId: widget.auctionId,
        imageId: imageId,
      );
    } catch (e) {
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
