import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/admin_settings_service.dart';
import '../services/auction_service.dart';
import '../services/brand_service.dart';
import '../models/category_model.dart';
import '../models/brand_model.dart';
import '../theme/app_theme.dart';
import '../widgets/auction_image_uploader.dart';
import '../widgets/unified_app_bar.dart';
import '../widgets/brand_picker.dart';

class EditDraftAuctionPage extends StatefulWidget {
  final String auctionId;

  const EditDraftAuctionPage({super.key, required this.auctionId});

  @override
  State<EditDraftAuctionPage> createState() => _EditDraftAuctionPageState();
}

class _EditDraftAuctionPageState extends State<EditDraftAuctionPage> {
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

  List<Brand> _brands = [];
  List<int> _durationOptions = [];
  bool _isLoading = false;
  bool _isSubmitting = false;
  String? _error;
  bool _isLoadingData = true;

  final AdminSettingsService _adminSettings = AdminSettingsService();
  final AuctionService _auctionService = AuctionService();
  final BrandService _brandService = BrandService();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final durations = await _adminSettings.getDurationOptions();

      final auctionDoc = await FirebaseFirestore.instance
          .collection('auctions')
          .doc(widget.auctionId)
          .get();

      if (!auctionDoc.exists) {
        setState(() {
          _error = 'Auction not found';
          _isLoadingData = false;
        });
        return;
      }

      final data = auctionDoc.data()!;
      final state = data['state'] as String? ?? '';

      if (state != 'DRAFT' && state != 'PENDING_APPROVAL') {
        setState(() {
          _error = 'Only draft auctions can be edited';
          _isLoadingData = false;
        });
        return;
      }

      final user = FirebaseAuth.instance.currentUser;
      final sellerId = data['sellerId'] as String? ?? '';
      final ownerUid = data['ownerUid'] as String? ?? sellerId;

      if (user?.uid != ownerUid) {
        setState(() {
          _error = 'You are not authorized to edit this auction';
          _isLoadingData = false;
        });
        return;
      }

      final groupId = data['categoryGroup'] as String? ?? legacyCategoryToGroup(data['category'] as String?);
      final subId = data['subcategory'] as String? ?? data['category'] as String? ?? 'bags';
      final groups = await _adminSettings.getTopLevelCategories();
      final subs = await _adminSettings.getSubcategories(groupId);
      final brands = await _brandService.getBrands(category: groupId);

      if (!mounted) return;
      setState(() {
        _durationOptions = durations;
        _categoryGroups = groups;
        _selectedCategoryGroupId = groupId;
        _subcategories = subs;
        _selectedSubcategoryId = subs.length == 1
            ? subs.first.id
            : (subs.any((s) => s.id == subId) ? subId : (subs.isNotEmpty ? subs.first.id : null));
        _brands = brands;
        final bid = data['brandId'] as String?;
        if (bid != null && bid.isNotEmpty) {
          _selectedBrandId = brands.any((b) => b.id == bid) ? bid : (brands.isNotEmpty ? brands.first.id : null);
        } else {
          final bName = data['brand'] as String?;
          Brand? match;
        for (final b in brands) {
          if (b.name == bName) { match = b; break; }
        }
          _selectedBrandId = match?.id ?? (brands.isNotEmpty ? brands.first.id : null);
        }
        _selectedDurationDays = data['durationDays'] as int?;
        _titleController.text = data['title'] as String? ?? '';
        _descriptionController.text = data['description'] as String? ?? '';
        final cond = data['condition'] as String? ?? '';
        _selectedCondition = _conditionOptions.contains(cond) ? cond : _conditionOptions.first;
        _itemIdentifierController.text = data['itemIdentifier'] as String? ?? '';
        _startPriceController.text = (data['startPrice'] as num?)?.toString() ?? '';
        final rp = data['reservePrice'] as num?;
        _reservePriceController.text = rp != null ? rp.toString() : '';
        _isLoadingData = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error loading data: $e';
        _isLoadingData = false;
      });
    }
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

  Future<void> _save() async {
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

      final updateData = <String, dynamic>{
        'categoryGroup': _selectedCategoryGroupId,
        'subcategory': effectiveSubId,
        'category': effectiveSubId,
        'brandId': _selectedBrandId,
        'brand': brandName,
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'condition': _selectedCondition ?? _conditionOptions.first,
        'itemIdentifier': _itemIdentifierController.text.trim(),
        'startPrice': startPrice,
        'currentPrice': startPrice,
        'durationDays': _selectedDurationDays!,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (reservePrice != null) {
        updateData['reservePrice'] = reservePrice;
      } else {
        updateData['reservePrice'] = FieldValue.delete();
      }
      await FirebaseFirestore.instance
          .collection('auctions')
          .doc(widget.auctionId)
          .update(updateData);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Auction updated successfully'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Error updating auction: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitForApproval() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _error = 'User not logged in');
      return;
    }

    final effectiveSubIdForSubmit = _subcategories.length == 1
        ? _subcategories.first.id
        : _selectedSubcategoryId;
    if (effectiveSubIdForSubmit == null || _selectedDurationDays == null) {
      if (mounted) setState(() => _error = 'Please select category and duration');
      return;
    }
    if (_selectedBrandId == null || _selectedBrandId!.isEmpty) {
      if (mounted) setState(() => _error = 'Please select a brand');
      return;
    }
    final idx = _brands.indexWhere((b) => b.id == _selectedBrandId);
    final brandName = idx >= 0 ? _brands[idx].name : _selectedBrandId!;

    if (mounted) {
      setState(() {
        _isSubmitting = true;
        _error = null;
      });
    }

    try {
      final startPrice = double.parse(_startPriceController.text);
      final reserveText = _reservePriceController.text.trim();
      final reservePriceForSubmit = reserveText.isEmpty ? null : double.tryParse(reserveText);

      final updateData = <String, dynamic>{
        'categoryGroup': _selectedCategoryGroupId,
        'subcategory': effectiveSubIdForSubmit,
        'category': effectiveSubIdForSubmit,
        'brandId': _selectedBrandId,
        'brand': brandName,
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'condition': _selectedCondition ?? _conditionOptions.first,
        'itemIdentifier': _itemIdentifierController.text.trim(),
        'startPrice': startPrice,
        'currentPrice': startPrice,
        'durationDays': _selectedDurationDays!,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (reservePriceForSubmit != null) {
        updateData['reservePrice'] = reservePriceForSubmit;
      } else {
        updateData['reservePrice'] = FieldValue.delete();
      }
      await FirebaseFirestore.instance
          .collection('auctions')
          .doc(widget.auctionId)
          .update(updateData);

      await _auctionService.submitForApproval(widget.auctionId);

      if (!mounted) return;

      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Auction submitted for admin approval'),
          backgroundColor: AppTheme.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingData) {
      return Scaffold(
        appBar: const UnifiedAppBar(title: 'Edit Auction'),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null && _brands.isEmpty && _isLoadingData == false) {
      return Scaffold(
        appBar: const UnifiedAppBar(title: 'Edit Auction'),
        body: Center(child: Text(_error!)),
      );
    }

    return Scaffold(
      appBar: const UnifiedAppBar(title: 'Edit Auction'),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<String>(
              value: _selectedCategoryGroupId,
              decoration: const InputDecoration(labelText: 'Category'),
              items: _categoryGroups
                  .map((g) => DropdownMenuItem(value: g.id, child: Text(g.nameEn)))
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
                    .map((s) => DropdownMenuItem(value: s.id, child: Text(s.nameEn)))
                    .toList(),
                onChanged: (value) => setState(() => _selectedSubcategoryId = value),
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
            AuctionImageUploader(
              auctionId: widget.auctionId,
              isDraft: true,
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.error),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppTheme.error),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading || _isSubmitting || _brands.isEmpty ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.textSecondary,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save Changes'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading || _isSubmitting || _brands.isEmpty ? null : _submitForApproval,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryBlue,
                    ),
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.send),
                    label: Text(_isSubmitting ? 'Submitting...' : 'Submit'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
