import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_theme.dart';
import '../services/ads_service.dart';
import '../widgets/unified_app_bar.dart';

/// Preferred ad size options (common IAB standards).
const List<Map<String, String>> kPreferredSizes = [
  {'value': '320×50', 'label': '320×50 (Mobile banner)'},
  {'value': '300×250', 'label': '300×250 (Medium rectangle)'},
  {'value': '728×90', 'label': '728×90 (Leaderboard)'},
  {'value': '300×600', 'label': '300×600 (Half page)'},
  {'value': 'custom', 'label': 'Custom (describe in message)'},
];

/// Page for partners to request advertising on the app.
class RequestAdPage extends StatefulWidget {
  const RequestAdPage({super.key});

  @override
  State<RequestAdPage> createState() => _RequestAdPageState();
}

class _RequestAdPageState extends State<RequestAdPage> {
  final _formKey = GlobalKey<FormState>();
  final _partnerNameController = TextEditingController();
  final _contactEmailController = TextEditingController();
  final _companyController = TextEditingController();
  final _messageController = TextEditingController();
  bool _submitting = false;
  XFile? _attachedImage;
  Uint8List? _attachedImageBytes;
  String? _preferredSize;
  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    _partnerNameController.dispose();
    _contactEmailController.dispose();
    _companyController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final XFile? file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (mounted) setState(() {
      _attachedImage = file;
      _attachedImageBytes = bytes;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _submitting) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please sign in to submit an ad request.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      String? imageUrl;
      if (_attachedImage != null && _attachedImageBytes != null) {
        final name = _attachedImage!.name;
        final fileName = name.isNotEmpty ? name : 'ad_${DateTime.now().millisecondsSinceEpoch}.jpg';
        imageUrl = await uploadAdRequestImage(
          uid: user.uid,
          fileName: fileName,
          bytes: _attachedImageBytes!,
        );
      }
      await submitAdRequest(
        partnerName: _partnerNameController.text.trim(),
        contactEmail: _contactEmailController.text.trim(),
        company: _companyController.text.trim().isEmpty
            ? null
            : _companyController.text.trim(),
        message: _messageController.text.trim().isEmpty
            ? null
            : _messageController.text.trim(),
        imageUrl: imageUrl,
        preferredSize: (_preferredSize != null && _preferredSize!.isNotEmpty && _preferredSize != 'custom')
            ? _preferredSize
            : null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Request submitted. We\'ll be in touch.'),
          backgroundColor: AppTheme.success,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const UnifiedAppBar(title: 'Request an Ad'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Partner with M Auction to reach our audience. Submit your details and we\'ll get back to you.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _partnerNameController,
                decoration: const InputDecoration(
                  labelText: 'Partner / Brand name *',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _contactEmailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Contact email *',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (!v.contains('@')) return 'Enter a valid email';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _companyController,
                decoration: const InputDecoration(
                  labelText: 'Company (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              // Preferred ad size
              DropdownButtonFormField<String>(
                value: _preferredSize,
                decoration: const InputDecoration(
                  labelText: 'Preferred ad size',
                  border: OutlineInputBorder(),
                ),
                hint: const Text('Select size (optional)'),
                items: kPreferredSizes.map((e) {
                  return DropdownMenuItem<String>(
                    value: e['value'],
                    child: Text(e['label']!),
                  );
                }).toList(),
                onChanged: (v) => setState(() => _preferredSize = v),
              ),
              const SizedBox(height: 16),
              // Attach photo
              Text(
                'Attach ad creative (optional)',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _submitting ? null : _pickImage,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(_attachedImage == null ? 'Attach photo' : 'Change photo'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              if (_attachedImage != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _attachedImageBytes != null
                          ? Image.memory(
                              _attachedImageBytes!,
                              width: 64,
                              height: 64,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(Icons.image, size: 64),
                            )
                          : const Icon(Icons.image, size: 64, color: AppTheme.textSecondary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _attachedImage!.name,
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() {
                        _attachedImage = null;
                        _attachedImageBytes = null;
                      }),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                controller: _messageController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Message (optional)',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _submitting
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Submit request'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
