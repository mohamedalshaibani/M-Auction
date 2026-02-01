import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/admin_settings_service.dart';
import '../services/auction_service.dart';
import '../theme/app_theme.dart';
import '../widgets/auction_image_uploader.dart';

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
  final _conditionController = TextEditingController();
  final _itemIdentifierController = TextEditingController();
  final _startPriceController = TextEditingController();

  String _selectedCategory = 'bags';
  String? _selectedBrand;
  int? _selectedDurationDays;

  List<String> _bagBrands = [];
  List<String> _watchBrands = [];
  List<int> _durationOptions = [];
  bool _isLoading = false;
  bool _isSubmitting = false;
  String? _error;
  bool _isLoadingData = true;

  final AdminSettingsService _adminSettings = AdminSettingsService();
  final AuctionService _auctionService = AuctionService();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      // Load settings
      final bagBrands = await _adminSettings.getWhitelistBags();
      final watchBrands = await _adminSettings.getWhitelistWatches();
      final durations = await _adminSettings.getDurationOptions();

      // Load auction data
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
      
      // Verify it's a draft
      if (state != 'DRAFT' && state != 'PENDING_APPROVAL') {
        setState(() {
          _error = 'Only draft auctions can be edited';
          _isLoadingData = false;
        });
        return;
      }

      // Verify ownership
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

      setState(() {
        _bagBrands = bagBrands;
        _watchBrands = watchBrands;
        _durationOptions = durations;
        _selectedCategory = data['category'] as String? ?? 'bags';
        _selectedBrand = data['brand'] as String?;
        _selectedDurationDays = data['durationDays'] as int?;
        _titleController.text = data['title'] as String? ?? '';
        _descriptionController.text = data['description'] as String? ?? '';
        _conditionController.text = data['condition'] as String? ?? '';
        _itemIdentifierController.text = data['itemIdentifier'] as String? ?? '';
        _startPriceController.text = (data['startPrice'] as num?)?.toString() ?? '';
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
    _conditionController.dispose();
    _itemIdentifierController.dispose();
    _startPriceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _error = 'User not logged in');
      return;
    }

    if (_selectedBrand == null || _selectedDurationDays == null) {
      setState(() => _error = 'Please select brand and duration');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final startPrice = double.parse(_startPriceController.text);

      // Update auction
      await FirebaseFirestore.instance
          .collection('auctions')
          .doc(widget.auctionId)
          .update({
        'category': _selectedCategory,
        'brand': _selectedBrand!,
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'condition': _conditionController.text.trim(),
        'itemIdentifier': _itemIdentifierController.text.trim(),
        'startPrice': startPrice,
        'currentPrice': startPrice, // Update current price too
        'durationDays': _selectedDurationDays!,
        'updatedAt': FieldValue.serverTimestamp(),
      });

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
      
      setState(() {
        _error = 'Error updating auction: $e';
      });
    } finally {
      // Always reset loading state
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _submitForApproval() async {
    // First save current changes
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() => _error = 'User not logged in');
      }
      return;
    }

    if (_selectedBrand == null || _selectedDurationDays == null) {
      if (mounted) {
        setState(() => _error = 'Please select brand and duration');
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isSubmitting = true;
        _error = null;
      });
    }

    try {
      final startPrice = double.parse(_startPriceController.text);

      // First, update auction with current changes
      await FirebaseFirestore.instance
          .collection('auctions')
          .doc(widget.auctionId)
          .update({
        'category': _selectedCategory,
        'brand': _selectedBrand!,
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'condition': _conditionController.text.trim(),
        'itemIdentifier': _itemIdentifierController.text.trim(),
        'startPrice': startPrice,
        'currentPrice': startPrice,
        'durationDays': _selectedDurationDays!,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Then submit for approval (which validates)
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
      // Always reset submitting state, regardless of success or error
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingData) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Auction')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null && _bagBrands.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Auction')),
        body: Center(child: Text(_error!)),
      );
    }

    final availableBrands =
        _selectedCategory == 'bags' ? _bagBrands : _watchBrands;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Auction'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<String>(
              value: _selectedCategory,
              decoration: const InputDecoration(labelText: 'Category'),
              items: const [
                DropdownMenuItem(value: 'bags', child: Text('Bags')),
                DropdownMenuItem(value: 'watches', child: Text('Watches')),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedCategory = value ?? 'bags';
                  _selectedBrand = availableBrands.isNotEmpty
                      ? availableBrands.first
                      : null;
                });
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedBrand,
              decoration: const InputDecoration(labelText: 'Brand'),
              items: availableBrands
                  .map((brand) => DropdownMenuItem(
                        value: brand,
                        child: Text(brand),
                      ))
                  .toList(),
              onChanged: (value) {
                setState(() => _selectedBrand = value);
              },
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
            // Image uploader
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
                    onPressed: _isLoading || _isSubmitting ? null : _save,
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
                    onPressed: _isLoading || _isSubmitting ? null : _submitForApproval,
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
