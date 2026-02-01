import 'package:flutter/material.dart';
import '../models/watch_brand.dart';
import '../theme/app_theme.dart';

/// A searchable picker for watch brands: search field as first row, then filtered list.
/// Use for create/edit auction (allowAll: false) or filters (allowAll: true).
class WatchBrandPicker extends StatelessWidget {
  final List<WatchBrand> brands;
  final String? selectedBrandId;
  final ValueChanged<String?> onChanged;
  final bool allowAll;
  final String label;

  const WatchBrandPicker({
    super.key,
    required this.brands,
    required this.selectedBrandId,
    required this.onChanged,
    this.allowAll = false,
    this.label = 'Brand',
  });

  String get _displayValue {
    if (selectedBrandId == null || selectedBrandId!.isEmpty) {
      return allowAll ? 'All brands' : 'Select brand';
    }
    for (final b in brands) {
      if (b.id == selectedBrandId) return b.name;
    }
    return selectedBrandId!;
  }

  void _openPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _WatchBrandPickerSheet(
        brands: brands,
        selectedBrandId: selectedBrandId,
        onChanged: onChanged,
        allowAll: allowAll,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: brands.isEmpty ? null : () => _openPicker(context),
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        child: Text(
          _displayValue,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}

class _WatchBrandPickerSheet extends StatefulWidget {
  final List<WatchBrand> brands;
  final String? selectedBrandId;
  final ValueChanged<String?> onChanged;
  final bool allowAll;

  const _WatchBrandPickerSheet({
    required this.brands,
    required this.selectedBrandId,
    required this.onChanged,
    required this.allowAll,
  });

  @override
  State<_WatchBrandPickerSheet> createState() => _WatchBrandPickerSheetState();
}

class _WatchBrandPickerSheetState extends State<_WatchBrandPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<WatchBrand> get _filtered {
    if (_query.isEmpty) return List.from(widget.brands);
    final q = _query.toLowerCase();
    return widget.brands.where((b) => b.name.toLowerCase().contains(q)).toList();
  }

  void _select(String? brandId) {
    widget.onChanged(brandId);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search brands...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                autofocus: true,
                textInputAction: TextInputAction.search,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: [
                  if (widget.allowAll)
                    ListTile(
                      title: const Text('All brands'),
                      selected: widget.selectedBrandId == null,
                      selectedTileColor: AppTheme.primaryBlue.withValues(alpha: 0.1),
                      onTap: () => _select(null),
                    ),
                  ...filtered.map((b) => ListTile(
                        title: Text(b.name),
                        selected: widget.selectedBrandId == b.id,
                        selectedTileColor: AppTheme.primaryBlue.withValues(alpha: 0.1),
                        onTap: () => _select(b.id),
                      )),
                  if (filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          'No brands match "$_query"',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
