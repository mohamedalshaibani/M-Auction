import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auction_service.dart';
import '../services/admin_settings_service.dart';
import '../models/category_model.dart';
import '../widgets/auction_image_uploader.dart';
import '../theme/app_theme.dart';

class SellCreateAuctionPage extends StatefulWidget {
  const SellCreateAuctionPage({super.key});

  @override
  State<SellCreateAuctionPage> createState() => _SellCreateAuctionPageState();
}

class _SellCreateAuctionPageState extends State<SellCreateAuctionPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _conditionController = TextEditingController();
  final _itemIdentifierController = TextEditingController();
  final _startPriceController = TextEditingController();
  final _brandTextController = TextEditingController();

  List<CategoryGroup> _categoryGroups = defaultTopLevelCategories;
  List<Subcategory> _subcategories = defaultSubcategories.where((s) => s.parentId == 'bags').toList();
  String _selectedCategoryGroupId = 'bags';
  String? _selectedSubcategoryId;
  String? _selectedBrand;
  int? _selectedDurationDays;
  String? _auctionId; // Store auctionId for image upload

  List<String> _bagBrands = [];
  List<String> _watchBrands = [];
  List<int> _durationOptions = [];
  bool _isLoading = false;
  String? _error;

  final AuctionService _auctionService = AuctionService();
  final AdminSettingsService _adminSettings = AdminSettingsService();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final bagBrands = await _adminSettings.getWhitelistBags();
      final watchBrands = await _adminSettings.getWhitelistWatches();
      final durations = await _adminSettings.getDurationOptions();
      final groups = await _adminSettings.getTopLevelCategories();
      final subs = await _adminSettings.getSubcategories('bags');
      if (mounted) {
        setState(() {
          _bagBrands = bagBrands;
          _watchBrands = watchBrands;
          _durationOptions = durations;
          _categoryGroups = groups;
          _subcategories = subs;
          _selectedSubcategoryId = subs.isNotEmpty ? subs.first.id : null;
          _selectedBrand = _bagBrands.isNotEmpty ? _bagBrands.first : null;
          _selectedDurationDays = _durationOptions.isNotEmpty ? _durationOptions.first : null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Error loading settings: $e');
    }
  }

  Future<void> _onCategoryGroupChanged(String groupId) async {
    final subs = await _adminSettings.getSubcategories(groupId);
    if (!mounted) return;
    setState(() {
      _selectedCategoryGroupId = groupId;
      _subcategories = subs;
      _selectedSubcategoryId = subs.isNotEmpty ? subs.first.id : null;
      if (groupId == 'bags') {
        _selectedBrand = _bagBrands.isNotEmpty ? _bagBrands.first : null;
        _brandTextController.clear();
      } else if (groupId == 'watches') {
        _selectedBrand = _watchBrands.isNotEmpty ? _watchBrands.first : null;
        _brandTextController.clear();
      } else {
        _selectedBrand = null;
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _conditionController.dispose();
    _itemIdentifierController.dispose();
    _startPriceController.dispose();
    _brandTextController.dispose();
    super.dispose();
  }

  Future<void> _submitForApproval() async {
    if (_auctionId == null) {
      setState(() => _error = 'Please create draft first');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await _auctionService.submitForApproval(_auctionId!);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Auction submitted for approval')),
        );
      }
    } catch (e) {
      setState(() {
        _error = 'Error submitting: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _error = 'User not logged in');
      return;
    }

    // Check KYC status
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final userData = userDoc.data();
    final kycStatus = userData?['kycStatus'] as String? ?? 'not_submitted';
    
    if (kycStatus != 'approved') {
      setState(() {
        _error = 'KYC verification required to sell items. Please complete verification first.';
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('KYC verification required. Please complete verification first.'),
            action: SnackBarAction(
              label: 'Go to KYC',
              onPressed: () {
                Navigator.of(context).pushNamed('/kyc');
              },
            ),
          ),
        );
        // Small delay to show message, then navigate
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            Navigator.of(context).pushNamed('/kyc');
          }
        });
      }
      return;
    }

    if (_selectedSubcategoryId == null || _selectedDurationDays == null) {
      setState(() => _error = 'Please select category and duration');
      return;
    }
    final brand = _selectedCategoryGroupId == 'bags' || _selectedCategoryGroupId == 'watches'
        ? (_selectedBrand ?? '')
        : _brandTextController.text.trim();
    if (brand.isEmpty) {
      setState(() => _error = 'Please select or enter brand');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final startPrice = double.parse(_startPriceController.text);

      // Create draft auction first (needed for image upload)
      final auctionId = await _auctionService.createDraftAuction(
        sellerId: user.uid,
        categoryGroup: _selectedCategoryGroupId,
        subcategory: _selectedSubcategoryId!,
        brand: brand,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        condition: _conditionController.text.trim(),
        itemIdentifier: _itemIdentifierController.text.trim(),
        startPrice: startPrice,
        durationDays: _selectedDurationDays!,
      );

      // Wait for Firestore to propagate before allowing uploads
      await Future.delayed(const Duration(milliseconds: 500));

      // Verify auction exists before showing upload UI
      final verifyDoc = await FirebaseFirestore.instance
          .collection('auctions')
          .doc(auctionId)
          .get();

      if (!verifyDoc.exists) {
        throw Exception('Failed to create auction. Please try again.');
      }

      setState(() {
        _auctionId = auctionId;
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Draft created! Add images, then submit for approval.'),
            duration: Duration(seconds: 3),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _error = 'Error creating auction: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final useBrandDropdown = _selectedCategoryGroupId == 'bags' || _selectedCategoryGroupId == 'watches';
    final availableBrands = _selectedCategoryGroupId == 'bags' ? _bagBrands : _watchBrands;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Auction'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<String>(
              value: _selectedCategoryGroupId,
              decoration: const InputDecoration(labelText: 'Category'),
              items: _categoryGroups
                  .map((g) => DropdownMenuItem(
                        value: g.id,
                        child: Text(g.nameEn),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) _onCategoryGroupChanged(value);
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedSubcategoryId,
              decoration: const InputDecoration(labelText: 'Subcategory'),
              items: _subcategories
                  .map((s) => DropdownMenuItem(
                        value: s.id,
                        child: Text(s.nameEn),
                      ))
                  .toList(),
              onChanged: (value) {
                setState(() => _selectedSubcategoryId = value);
              },
            ),
            const SizedBox(height: 16),
            if (useBrandDropdown)
              DropdownButtonFormField<String>(
                value: _selectedBrand,
                decoration: const InputDecoration(labelText: 'Brand'),
                items: availableBrands
                    .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                    .toList(),
                onChanged: (value) => setState(() => _selectedBrand = value),
              )
            else
              TextFormField(
                controller: _brandTextController,
                decoration: const InputDecoration(labelText: 'Brand (optional)'),
              ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Title'),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a title';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Description'),
              maxLines: 3,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a description';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _conditionController,
              decoration: const InputDecoration(labelText: 'Condition'),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter condition';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _itemIdentifierController,
              decoration: const InputDecoration(labelText: 'Item Identifier'),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter item identifier';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _startPriceController,
              decoration: const InputDecoration(labelText: 'Start Price'),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter start price';
                }
                final price = double.tryParse(value);
                if (price == null || price <= 0) {
                  return 'Please enter a valid price';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              value: _selectedDurationDays,
              decoration: const InputDecoration(labelText: 'Duration (days)'),
              items: _durationOptions
                  .map((days) => DropdownMenuItem(
                        value: days,
                        child: Text('$days days'),
                      ))
                  .toList(),
              onChanged: (value) {
                setState(() => _selectedDurationDays = value);
              },
            ),
            const SizedBox(height: 24),
            // Image uploader (create draft first if needed)
            if (_auctionId != null)
              AuctionImageUploader(
                auctionId: _auctionId!,
                isDraft: true,
              )
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Images',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Create draft auction first to upload images',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
            ],
            const SizedBox(height: 24),
            if (_auctionId == null)
              ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create Draft'),
              )
            else
              ElevatedButton(
                onPressed: _isLoading ? null : _submitForApproval,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Submit for Approval'),
              ),
          ],
        ),
      ),
    );
  }
}
