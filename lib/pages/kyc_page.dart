import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import '../services/kyc_service.dart';
import '../theme/app_theme.dart';
import '../utils/countries.dart';
import '../widgets/unified_app_bar.dart';
import 'dart:html' if (dart.library.io) '../web_stubs.dart' as html;

class KycPage extends StatefulWidget {
  const KycPage({super.key, this.returnAuctionId});

  final String? returnAuctionId;

  @override
  State<KycPage> createState() => _KycPageState();
}

class _KycPageState extends State<KycPage> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _dobController = TextEditingController();
  final _idNumberController = TextEditingController();

  int _step = 0; // 0 = identity, 1 = ID photos + submit
  CountryEntry? _selectedCountry;

  String _selectedIdType = 'EmiratesID';

  Uint8List? _idFrontBytes;
  Uint8List? _idBackBytes;
  String? _idFrontFileName;
  String? _idBackFileName;

  bool _isSubmitting = false;
  String? _error;

  final KycService _kycService = KycService();

  static const double _spacing = 10.0;
  static const double _sectionGap = 14.0;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _dobController.dispose();
    _idNumberController.dispose();
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
              if (type == 'idFront') {
                _idFrontBytes = bytes;
                _idFrontFileName = 'id_front.jpg';
              } else {
                _idBackBytes = bytes;
                _idBackFileName = 'id_back.jpg';
              }
            });
          }
        });
        reader.readAsArrayBuffer(file);
      });
    } else {
      final picker = ImagePicker();
      final file = await picker.pickImage(source: ImageSource.gallery);
      if (file != null) {
        final bytes = await file.readAsBytes();
        setState(() {
          if (type == 'idFront') {
            _idFrontBytes = bytes;
            _idFrontFileName = file.name;
          } else {
            _idBackBytes = bytes;
            _idBackFileName = file.name;
          }
        });
      }
    }
  }

  void _nextStep() {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCountry == null) {
      setState(() => _error = 'Please select your nationality');
      return;
    }
    setState(() {
      _error = null;
      _step = 1;
    });
  }

  Future<void> _submitKyc() async {
    if (_idFrontBytes == null) {
      setState(() => _error = 'Please upload ID front photo');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _error = 'No user logged in');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null || currentUser.uid != user.uid) {
        throw Exception('Authentication error: Please sign in again');
      }
      await Future.delayed(const Duration(milliseconds: 100));

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

      await _kycService.submitKycRequest(
        uid: user.uid,
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        nationalityCode: _selectedCountry!.code,
        nationalityName: _selectedCountry!.name,
        dob: _dobController.text.trim(),
        idType: _selectedIdType,
        idNumber: _idNumberController.text.trim(),
        idFrontUrl: idFrontUrl,
        idBackUrl: idBackUrl,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('KYC request submitted successfully')),
        );
        if (widget.returnAuctionId != null) {
          Navigator.of(context).popUntil((r) => r.isFirst);
          Navigator.of(context).pushNamed('/auctionDetail?auctionId=${widget.returnAuctionId}');
        } else {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      setState(() {
        _error = 'Error submitting KYC: $e';
        _isSubmitting = false;
      });
    }
  }

  Widget _buildFilePicker(String label, String type, Uint8List? bytes, String? fileName, bool required) {
    return Padding(
      padding: const EdgeInsets.only(bottom: _spacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label + (required ? ' *' : ''),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
          ),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: _isSubmitting ? null : () => _pickFile(type),
            icon: const Icon(Icons.upload_file, size: 20),
            label: Text(fileName ?? 'Choose photo'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          if (bytes != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Selected',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.success),
              ),
            ),
        ],
      ),
    );
  }

  void _showCountryPicker() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _CountryPickerSheet(
        selected: _selectedCountry,
        onSelect: (c) {
          setState(() => _selectedCountry = c);
          Navigator.of(ctx).pop();
        },
      ),
    );
  }

  void _onCancel() {
    if (widget.returnAuctionId != null) {
      Navigator.of(context).popUntil(
          (Route<dynamic> r) => r.settings.name?.startsWith('/auctionDetail') == true);
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: UnifiedAppBar(
        title: 'KYC Verification',
        leading: widget.returnAuctionId != null
            ? IconButton(icon: const Icon(Icons.close), onPressed: _onCancel)
            : null,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Privacy notice
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.primaryBlue.withValues(alpha: 0.2)),
                ),
                child: Text(
                  'Privacy notice: Your identity details are kept confidential and are used only for verification, trust, and fraud prevention. We do not display your ID information publicly.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textPrimary,
                        height: 1.4,
                      ),
                ),
              ),
              const SizedBox(height: _sectionGap),

              if (_step == 0) ...[
                Text(
                  'Step 1: Identity',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                ),
                const SizedBox(height: _spacing),
                TextFormField(
                  controller: _firstNameController,
                  decoration: const InputDecoration(
                    labelText: 'First Name *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  enabled: !_isSubmitting,
                ),
                const SizedBox(height: _spacing),
                TextFormField(
                  controller: _lastNameController,
                  decoration: const InputDecoration(
                    labelText: 'Last Name *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  enabled: !_isSubmitting,
                ),
                const SizedBox(height: _spacing),
                InkWell(
                  onTap: _isSubmitting ? null : _showCountryPicker,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Nationality *',
                      border: const OutlineInputBorder(),
                      suffixIcon: const Icon(Icons.arrow_drop_down),
                    ),
                    child: Text(
                      _selectedCountry?.name ?? 'Select country',
                      style: TextStyle(
                        color: _selectedCountry != null ? AppTheme.textPrimary : AppTheme.textTertiary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: _spacing),
                TextFormField(
                  controller: _dobController,
                  decoration: const InputDecoration(
                    labelText: 'Date of Birth (YYYY-MM-DD) *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  enabled: !_isSubmitting,
                ),
                const SizedBox(height: _spacing),
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
                  onChanged: _isSubmitting ? null : (v) => v != null ? setState(() => _selectedIdType = v) : null,
                ),
                const SizedBox(height: _spacing),
                TextFormField(
                  controller: _idNumberController,
                  decoration: const InputDecoration(
                    labelText: 'ID Number *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  enabled: !_isSubmitting,
                ),
                if (_error != null) ...[
                  const SizedBox(height: _spacing),
                  Text(
                    _error!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.error),
                  ),
                ],
                const SizedBox(height: _sectionGap),
                FilledButton(
                  onPressed: _nextStep,
                  child: const Text('Next – ID photos'),
                ),
              ] else ...[
                Text(
                  'Step 2: ID photos',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Clear photo, all corners visible.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                ),
                const SizedBox(height: _spacing),
                _buildFilePicker('ID Front Photo *', 'idFront', _idFrontBytes, _idFrontFileName, true),
                _buildFilePicker('ID Back Photo', 'idBack', _idBackBytes, _idBackFileName, false),
                const SizedBox(height: _sectionGap),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: _spacing),
                    child: Text(
                      _error!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.error),
                    ),
                  ),
                FilledButton(
                  onPressed: _isSubmitting ? null : _submitKyc,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Submit KYC Request'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _isSubmitting ? null : () => setState(() => _step = 0),
                  child: const Text('Back'),
                ),
              ],

              const SizedBox(height: _sectionGap),
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
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.error.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Previous request rejected',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.error,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            rejectionReason,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textPrimary),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'You can resubmit with corrected information.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
                          ),
                        ],
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

class _CountryPickerSheet extends StatefulWidget {
  const _CountryPickerSheet({this.selected, required this.onSelect});

  final CountryEntry? selected;
  final void Function(CountryEntry) onSelect;

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() => _query = _searchController.text.trim().toLowerCase()));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<CountryEntry> get _filtered {
    if (_query.isEmpty) return kCountries;
    return kCountries.where((c) => c.name.toLowerCase().contains(_query)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Text(
            'Select nationality',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Type to search...',
                prefixIcon: const Icon(Icons.search, size: 22),
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              autofocus: true,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 320,
            child: ListView.builder(
              itemCount: _filtered.length,
              itemBuilder: (context, index) {
                final c = _filtered[index];
                final isSelected = widget.selected?.code == c.code;
                return ListTile(
                  dense: true,
                  title: Text(c.name),
                  trailing: isSelected ? const Icon(Icons.check, color: AppTheme.primaryBlue, size: 22) : null,
                  onTap: () => widget.onSelect(c),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
