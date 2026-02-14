import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auction_service.dart';
import '../services/admin_settings_service.dart';
import '../services/brand_service.dart';
import '../services/listing_eligibility_service.dart';
import '../models/category_model.dart';
import '../models/brand_model.dart';
import '../widgets/auction_image_uploader.dart';
import '../widgets/brand_picker.dart';
import '../theme/app_theme.dart';
import '../widgets/unified_app_bar.dart';
import 'listing_flow_gate_page.dart';

class SellCreateAuctionPage extends StatefulWidget {
  const SellCreateAuctionPage({super.key});

  @override
  State<SellCreateAuctionPage> createState() => _SellCreateAuctionPageState();
}

class _SellCreateAuctionPageState extends State<SellCreateAuctionPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _itemIdentifierController = TextEditingController();
  final _startPriceController = TextEditingController();
  final _reservePriceController = TextEditingController();

  static const List<String> _conditionOptions = ['New', 'Like New', 'Good', 'Fair', 'Used'];
  String? _selectedCondition;

  List<CategoryGroup> _categoryGroups = defaultTopLevelCategories;
  List<Subcategory> _subcategories = defaultSubcategories.where((s) => s.parentId == 'bags').toList();
  String _selectedCategoryGroupId = 'bags';
  String? _selectedSubcategoryId;
  String? _selectedBrandId;
  int? _selectedDurationDays;
  String? _auctionId;

  List<Brand> _brands = [];
  List<int> _durationOptions = [];
  bool _isLoading = false;
  String? _error;

  final AuctionService _auctionService = AuctionService();
  final AdminSettingsService _adminSettings = AdminSettingsService();
  final BrandService _brandService = BrandService();
  final ListingEligibilityService _eligibility = ListingEligibilityService();

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkGate();
  }

  Future<void> _checkGate() async {
    final result = await _eligibility.checkEligibility();
    if (!mounted) return;
    if (!result.canProceed) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const ListingFlowGatePage()),
      );
    }
  }

  Future<void> _loadSettings() async {
    try {
      final durations = await _adminSettings.getDurationOptions();
      final groups = await _adminSettings.getTopLevelCategories();
      final subs = await _adminSettings.getSubcategories('bags');
      final brands = await _brandService.getBrands(category: 'bags');
      if (mounted) {
        setState(() {
          _durationOptions = durations;
          _categoryGroups = groups;
          _subcategories = subs;
          _selectedSubcategoryId = subs.isNotEmpty ? subs.first.id : null;
          _brands = brands;
          _selectedBrandId = brands.isNotEmpty ? brands.first.id : null;
          _selectedDurationDays = durations.isNotEmpty ? durations.first : null;
          _selectedCondition = _conditionOptions.first;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Error loading settings: $e');
    }
  }

  Future<void> _onCategoryGroupChanged(String groupId) async {
    final subs = await _adminSettings.getSubcategories(groupId);
    final brands = await _brandService.getBrands(category: groupId);
    if (!mounted) return;
    setState(() {
      _selectedCategoryGroupId = groupId;
      _subcategories = subs;
      _selectedSubcategoryId = subs.isNotEmpty ? subs.first.id : null;
      _brands = brands;
      _selectedBrandId = brands.isNotEmpty ? brands.first.id : null;
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _itemIdentifierController.dispose();
    _startPriceController.dispose();
    _reservePriceController.dispose();
    super.dispose();
  }

  Future<void> _submitForApproval() async {
    if (_auctionId == null) {
      setState(() => _error = 'Please create draft first');
      return;
    }
    setState(() => _isLoading = true);
    setState(() => _error = null);
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

    final effectiveSubId = _subcategories.length == 1
        ? _subcategories.first.id
        : _selectedSubcategoryId;
    if (effectiveSubId == null || _selectedDurationDays == null) {
      setState(() => _error = 'Please select category and duration');
      return;
    }
    if (_selectedBrandId == null || _selectedBrandId!.isEmpty) {
      setState(() => _error = 'Please select a brand');
      return;
    }
    final idx = _brands.indexWhere((b) => b.id == _selectedBrandId);
    final brandName = idx >= 0 ? _brands[idx].name : _selectedBrandId!;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final startPrice = double.parse(_startPriceController.text);
      final reserveText = _reservePriceController.text.trim();
      final reservePrice = reserveText.isEmpty ? null : double.tryParse(reserveText);
      if (reserveText.isNotEmpty && (reservePrice == null || reservePrice < 0)) {
        setState(() => _error = 'Please enter a valid reserve price');
        _isLoading = false;
        return;
      }
      if (reservePrice != null && reservePrice > startPrice) {
        setState(() => _error = 'Reserve price cannot exceed start price');
        _isLoading = false;
        return;
      }

      final auctionId = await _auctionService.createDraftAuction(
        sellerId: user.uid,
        categoryGroup: _selectedCategoryGroupId,
        subcategory: effectiveSubId,
        brandId: _selectedBrandId!,
        brand: brandName,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        condition: _selectedCondition ?? _conditionOptions.first,
        itemIdentifier: _itemIdentifierController.text.trim(),
        startPrice: startPrice,
        reservePrice: reservePrice,
        durationDays: _selectedDurationDays!,
      );

      await Future.delayed(const Duration(milliseconds: 500));

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
    return Scaffold(
      appBar: const UnifiedAppBar(title: 'Create Auction'),
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
            if (_subcategories.length >= 2) ...[
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
            ],
            const SizedBox(height: 16),
            if (_brands.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No brands configured for this category. Ask an admin to add brands.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                ),
              )
            else
              BrandPicker(
                brands: _brands,
                selectedBrandId: _selectedBrandId,
                onChanged: (value) => setState(() => _selectedBrandId = value),
                allowAll: false,
                label: 'Brand',
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
            DropdownButtonFormField<String>(
              value: _selectedCondition ?? _conditionOptions.first,
              decoration: const InputDecoration(labelText: 'Condition'),
              items: _conditionOptions
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (value) => setState(() => _selectedCondition = value),
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
            TextFormField(
              controller: _reservePriceController,
              decoration: const InputDecoration(
                labelText: 'Reserve Price (Minimum Selling Price)',
                hintText: 'Optional',
              ),
              keyboardType: TextInputType.number,
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 12, right: 12),
              child: Text(
                'If bids do not reach the reserve price, the app will automatically reject all bids and the auction will not be sold.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
              ),
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
                onPressed: _isLoading || _brands.isEmpty ? null : _submit,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create Draft'),
              )
            else
              StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('auctions')
                    .doc(_auctionId)
                    .snapshots(),
                builder: (context, snapshot) {
                  bool hasAtLeastOneImage = false;
                  if (snapshot.hasData &&
                      snapshot.data!.exists &&
                      snapshot.data!.data() != null) {
                    final data = snapshot.data!.data() as Map<String, dynamic>?;
                    final images = data?['images'] as List<dynamic>?;
                    if (images != null && images.isNotEmpty) {
                      hasAtLeastOneImage = images.any((img) {
                        if (img is! Map<String, dynamic>) return false;
                        final url = img['url'] as String?;
                        return url != null && url.isNotEmpty;
                      });
                    }
                  }
                  final canSubmit = hasAtLeastOneImage && !_isLoading;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!hasAtLeastOneImage) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            'Add at least one image before submitting for approval.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppTheme.textSecondary,
                                ),
                          ),
                        ),
                      ],
                      ElevatedButton(
                        onPressed: canSubmit ? _submitForApproval : null,
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Submit for Approval'),
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
