import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/brand_model.dart';
import '../models/category_model.dart';
import '../services/brand_service.dart';
import '../theme/app_theme.dart';
import '../widgets/admin_layout.dart';
import '../widgets/unified_app_bar.dart';

/// Admin: CRUD for brands collection. Web-optimized with table layout.
class AdminBrandsPage extends StatefulWidget {
  const AdminBrandsPage({super.key});

  @override
  State<AdminBrandsPage> createState() => _AdminBrandsPageState();
}

class _AdminBrandsPageState extends State<AdminBrandsPage> {
  final BrandService _brandService = BrandService();
  final _nameController = TextEditingController();
  final _categoryController = TextEditingController();

  String _categoryFilter = 'all';
  String _sortBy = 'name';
  bool _showInactive = false;
  Brand? _editingBrand;
  bool _showForm = false;
  bool _saving = false;

  static const List<String> _categories = [
    'watches',
    'bags',
    'fashion',
    'jewelry',
    'accessories',
    'collectibles',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  void _startCreate() {
    _editingBrand = null;
    _nameController.clear();
    _categoryController.text = _categoryFilter == 'all' ? 'watches' : _categoryFilter;
    if (!isWide(context)) {
      _showFormDialog();
    } else {
      setState(() => _showForm = true);
    }
  }

  void _startEdit(Brand brand) {
    _editingBrand = brand;
    _nameController.text = brand.name;
    _categoryController.text = brand.category;
    if (!isWide(context)) {
      _showFormDialog();
    } else {
      setState(() => _showForm = true);
    }
  }

  bool isWide(BuildContext context) => MediaQuery.of(context).size.width > 600;

  void _showFormDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final nameCtrl = TextEditingController(text: _nameController.text);
        final catCtrl = TextEditingController(text: _categoryController.text);
        String cat = catCtrl.text.isEmpty ? 'watches' : catCtrl.text;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: Text(_editingBrand != null ? 'Edit brand' : 'New brand'),
              content: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Name'),
                      autofocus: true,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: cat,
                      decoration: const InputDecoration(labelText: 'Category'),
                      items: _categories
                          .map((c) => DropdownMenuItem(value: c, child: Text(categoryGroupDisplayName(c))))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          catCtrl.text = v;
                          setModalState(() => cat = v);
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    final category = catCtrl.text.trim();
                    if (name.isEmpty || category.isEmpty) return;
                    Navigator.pop(ctx);
                    _nameController.text = name;
                    _categoryController.text = category;
                    await _saveFromControllers();
                  },
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _saveFromControllers() async {
    final name = _nameController.text.trim();
    final category = _categoryController.text.trim();
    if (name.isEmpty || category.isEmpty) return;
    setState(() => _saving = true);
    try {
      if (_editingBrand != null) {
        await _brandService.updateBrand(_editingBrand!.id, name: name, category: category);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Brand updated'), backgroundColor: AppTheme.primaryBlue),
        );
      } else {
        await _brandService.createBrand(name: name, category: category, isActive: true);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Brand created'), backgroundColor: AppTheme.primaryBlue),
        );
      }
      setState(() {
        _editingBrand = null;
        _showForm = false;
        _nameController.clear();
        _categoryController.clear();
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.error),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    await _saveFromControllers();
  }

  Future<void> _deactivate(Brand brand) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deactivate brand'),
        content: Text(
          'Deactivate "${brand.name}"? It will no longer appear in listing dropdowns.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await _brandService.deleteBrand(brand.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Brand deactivated'),
            backgroundColor: AppTheme.primaryBlue,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: const UnifiedAppBar(title: 'Brands'),
      body: Padding(
        padding: const EdgeInsets.all(kAdminContentPadding),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: isWide ? 2 : 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _categoryFilter,
                          decoration: const InputDecoration(
                            labelText: 'Category',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          items: [
                            const DropdownMenuItem(value: 'all', child: Text('All categories')),
                            ..._categories.map((c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(categoryGroupDisplayName(c)),
                                )),
                          ],
                          onChanged: (v) => setState(() => _categoryFilter = v ?? 'all'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 160,
                        child: DropdownButtonFormField<String>(
                          value: _sortBy,
                          decoration: const InputDecoration(
                            labelText: 'Sort',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'name', child: Text('Name')),
                            DropdownMenuItem(value: 'category', child: Text('Category')),
                          ],
                          onChanged: (v) => setState(() => _sortBy = v ?? 'name'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: _showInactive,
                            onChanged: (v) => setState(() => _showInactive = v ?? false),
                          ),
                          const Text('Show inactive'),
                        ],
                      ),
                      const Spacer(),
                      ElevatedButton.icon(
                        onPressed: _startCreate,
                        style: kAdminPrimaryButtonStyle,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add brand'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: _brandService.streamAllBrands(),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return AdminErrorState(
                            message: snapshot.error.toString(),
                            onRetry: () => setState(() {}),
                          );
                        }
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        var docs = snapshot.data?.docs ?? [];
                        var brands = docs.map((d) => Brand.fromDoc(d)).toList();
                        if (!_showInactive) {
                          brands = brands.where((b) => b.isActive).toList();
                        }
                        if (_categoryFilter != 'all') {
                          brands = brands.where((b) => b.category == _categoryFilter).toList();
                        }
                        brands.sort((a, b) {
                          if (_sortBy == 'category') {
                            final c = a.category.compareTo(b.category);
                            return c != 0 ? c : a.name.compareTo(b.name);
                          }
                          return a.name.compareTo(b.name);
                        });
                        if (brands.isEmpty) {
                          return AdminEmptyState(
                            icon: Icons.branding_watermark_outlined,
                            title: 'No brands',
                            subtitle: _categoryFilter == 'all'
                                ? 'Add brands to allow sellers to select them when listing.'
                                : 'No brands in this category.',
                          );
                        }
                        return ListView.builder(
                          itemCount: brands.length,
                          itemBuilder: (context, index) {
                            final b = brands[index];
                            return AdminCard(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          b.name,
                                          style: Theme.of(context).textTheme.titleSmall,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            Chip(
                                              label: Text(
                                                categoryGroupDisplayName(b.category),
                                                style: Theme.of(context).textTheme.labelSmall,
                                              ),
                                              padding: EdgeInsets.zero,
                                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                            ),
                                            if (!b.isActive) ...[
                                              const SizedBox(width: 8),
                                              Chip(
                                                label: const Text('Inactive'),
                                                backgroundColor: AppTheme.warning.withValues(alpha: 0.2),
                                                padding: EdgeInsets.zero,
                                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () => _startEdit(b),
                                    child: const Text('Edit'),
                                  ),
                                  if (b.isActive)
                                    TextButton(
                                      onPressed: () => _deactivate(b),
                                      style: TextButton.styleFrom(
                                        foregroundColor: AppTheme.error,
                                      ),
                                      child: const Text('Deactivate'),
                                    ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            if (_showForm && isWide) ...[
              const SizedBox(width: 24),
              SizedBox(
                width: 320,
                child: AdminCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _editingBrand != null ? 'Edit brand' : 'New brand',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(labelText: 'Name'),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _categoryController.text.isEmpty ? 'watches' : _categoryController.text,
                        decoration: const InputDecoration(labelText: 'Category'),
                        items: _categories
                            .map((c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(categoryGroupDisplayName(c)),
                                ))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) {
                            _categoryController.text = v;
                            setState(() {});
                          }
                        },
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _saving
                                  ? null
                                  : () {
                                      setState(() {
                                        _editingBrand = null;
                                        _showForm = false;
                                        _nameController.clear();
                                        _categoryController.clear();
                                      });
                                    },
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _saving ? null : _save,
                              style: kAdminPrimaryButtonStyle,
                              child: _saving
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Text('Save'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
