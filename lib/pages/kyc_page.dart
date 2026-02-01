import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import '../services/kyc_service.dart';
import '../theme/app_theme.dart';
import 'dart:html' if (dart.library.io) '../web_stubs.dart' as html;

class KycPage extends StatefulWidget {
  const KycPage({super.key});

  @override
  State<KycPage> createState() => _KycPageState();
}

class _KycPageState extends State<KycPage> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _nationalityController = TextEditingController();
  final _dobController = TextEditingController();
  final _idNumberController = TextEditingController();
  final _proofNoteController = TextEditingController();

  String _selectedIdType = 'EmiratesID';
  String _selectedProofType = 'receipt';

  Uint8List? _idFrontBytes;
  Uint8List? _idBackBytes;
  Uint8List? _selfieBytes;
  Uint8List? _proofBytes;

  String? _idFrontFileName;
  String? _idBackFileName;
  String? _selfieFileName;
  String? _proofFileName;

  bool _isSubmitting = false;
  String? _error;

  final KycService _kycService = KycService();

  @override
  void dispose() {
    _fullNameController.dispose();
    _nationalityController.dispose();
    _dobController.dispose();
    _idNumberController.dispose();
    _proofNoteController.dispose();
    super.dispose();
  }

  Future<void> _pickFile(String type) async {
    if (kIsWeb) {
      final input = html.FileUploadInputElement()..accept = 'image/*';
      input.click();

      input.onChange.listen((e) {
        final files = input.files;
        if (files == null || files.isEmpty) return;

        final file = files[0];
        final reader = html.FileReader();

        reader.onLoadEnd.listen((e) {
          final bytes = reader.result as Uint8List?;
          if (bytes != null) {
            setState(() {
              switch (type) {
                case 'idFront':
                  _idFrontBytes = bytes;
                  _idFrontFileName = 'id_front.jpg';
                  break;
              case 'idBack':
                _idBackBytes = bytes;
                _idBackFileName = 'id_back.jpg';
                break;
              case 'selfie':
                _selfieBytes = bytes;
                _selfieFileName = 'selfie.jpg';
                break;
              case 'proof':
                _proofBytes = bytes;
                _proofFileName = 'proof.jpg';
                break;
            }
          });
        }
      });

      reader.readAsArrayBuffer(file);
    });
    } else {
      // Mobile platform - use image_picker
      final ImagePicker picker = ImagePicker();
      final XFile? file = await picker.pickImage(source: ImageSource.gallery);
      
      if (file != null) {
        final bytes = await file.readAsBytes();
        setState(() {
          switch (type) {
            case 'idFront':
              _idFrontBytes = bytes;
              _idFrontFileName = file.name;
              break;
            case 'idBack':
              _idBackBytes = bytes;
              _idBackFileName = file.name;
              break;
            case 'selfie':
              _selfieBytes = bytes;
              _selfieFileName = file.name;
              break;
            case 'proof':
              _proofBytes = bytes;
              _proofFileName = file.name;
              break;
          }
        });
      }
    }
  }

  Future<void> _submitKyc() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _error = 'No user logged in');
      return;
    }

    if (_idFrontBytes == null || _selfieBytes == null || _proofBytes == null) {
      setState(() => _error = 'Please upload all required files');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      // Verify auth state before upload
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null || currentUser.uid != user.uid) {
        throw Exception('Authentication error: Please sign in again');
      }
      
      // Wait a brief moment to ensure auth token is fresh
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Upload files
      final idFrontUrl = await _kycService.uploadFileFromBytes(
        uid: user.uid,
        fileName: _idFrontFileName!,
        bytes: _idFrontBytes!,
        contentType: 'image/jpeg',
      );

      String? idBackUrl;
      if (_idBackBytes != null) {
        idBackUrl = await _kycService.uploadFileFromBytes(
          uid: user.uid,
          fileName: _idBackFileName!,
          bytes: _idBackBytes!,
          contentType: 'image/jpeg',
        );
      }

      final selfieUrl = await _kycService.uploadFileFromBytes(
        uid: user.uid,
        fileName: _selfieFileName!,
        bytes: _selfieBytes!,
        contentType: 'image/jpeg',
      );

      final proofUrl = await _kycService.uploadFileFromBytes(
        uid: user.uid,
        fileName: _proofFileName!,
        bytes: _proofBytes!,
        contentType: 'image/jpeg',
      );

      // Submit KYC request
      await _kycService.submitKycRequest(
        uid: user.uid,
        fullName: _fullNameController.text.trim(),
        nationality: _nationalityController.text.trim(),
        dob: _dobController.text.trim(),
        idType: _selectedIdType,
        idNumber: _idNumberController.text.trim(),
        idFrontUrl: idFrontUrl,
        idBackUrl: idBackUrl,
        selfieUrl: selfieUrl,
        proofType: _selectedProofType,
        proofUrl: proofUrl,
        proofNote: _proofNoteController.text.trim().isEmpty
            ? null
            : _proofNoteController.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('KYC request submitted successfully')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() {
        _error = 'Error submitting KYC: $e';
        _isSubmitting = false;
      });
    }
  }

  Widget _buildFilePicker(String label, String type, Uint8List? bytes, String? fileName, bool required) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label + (required ? ' *' : ''),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _isSubmitting ? null : () => _pickFile(type),
              icon: const Icon(Icons.upload_file),
              label: Text(fileName ?? 'Choose File'),
            ),
            if (bytes != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'File selected: ${fileName ?? 'Unknown'}',
                  style: const TextStyle(color: Colors.green),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'KYC Verification',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Identity Information',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _fullNameController,
                decoration: const InputDecoration(
                  labelText: 'Full Name *',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Full name is required';
                  }
                  return null;
                },
                enabled: !_isSubmitting,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nationalityController,
                decoration: const InputDecoration(
                  labelText: 'Nationality *',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Nationality is required';
                  }
                  return null;
                },
                enabled: !_isSubmitting,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _dobController,
                decoration: const InputDecoration(
                  labelText: 'Date of Birth (YYYY-MM-DD) *',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Date of birth is required';
                  }
                  return null;
                },
                enabled: !_isSubmitting,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedIdType,
                decoration: const InputDecoration(
                  labelText: 'ID Type *',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'EmiratesID', child: Text('Emirates ID')),
                  DropdownMenuItem(value: 'Passport', child: Text('Passport')),
                ],
                onChanged: _isSubmitting
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _selectedIdType = value);
                        }
                      },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _idNumberController,
                decoration: const InputDecoration(
                  labelText: 'ID Number *',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'ID number is required';
                  }
                  return null;
                },
                enabled: !_isSubmitting,
              ),
              const SizedBox(height: 24),
              _buildFilePicker('ID Front Photo *', 'idFront', _idFrontBytes, _idFrontFileName, true),
              const SizedBox(height: 16),
              _buildFilePicker('ID Back Photo', 'idBack', _idBackBytes, _idBackFileName, false),
              const SizedBox(height: 16),
              _buildFilePicker('Selfie Photo *', 'selfie', _selfieBytes, _selfieFileName, true),
              const SizedBox(height: 24),
              const Text(
                'Product Proof',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedProofType,
                decoration: const InputDecoration(
                  labelText: 'Proof Type *',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'receipt', child: Text('Receipt')),
                  DropdownMenuItem(value: 'serial', child: Text('Serial Number')),
                  DropdownMenuItem(value: 'authCard', child: Text('Authentication Card')),
                ],
                onChanged: _isSubmitting
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _selectedProofType = value);
                        }
                      },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _proofNoteController,
                decoration: const InputDecoration(
                  labelText: 'Proof Note (Optional)',
                  border: OutlineInputBorder(),
                  hintText: 'Additional notes about the proof',
                ),
                maxLines: 3,
                enabled: !_isSubmitting,
              ),
              const SizedBox(height: 16),
              _buildFilePicker('Proof Photo *', 'proof', _proofBytes, _proofFileName, true),
              const SizedBox(height: 24),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ElevatedButton(
                onPressed: _isSubmitting ? null : _submitKyc,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Submit KYC Request'),
              ),
              const SizedBox(height: 16),
              StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(FirebaseAuth.instance.currentUser?.uid ?? '')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const SizedBox.shrink();
                  final userData = snapshot.data?.data() as Map<String, dynamic>?;
                  final kycStatus = userData?['kycStatus'] as String?;
                  final rejectionReason = userData?['kycRejectionReason'] as String?;

                  if (kycStatus == 'rejected' && rejectionReason != null) {
                    return Card(
                      color: Colors.red.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Previous Request Rejected',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text('Reason: $rejectionReason'),
                            const SizedBox(height: 8),
                            const Text(
                              'You can resubmit with corrected information.',
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
