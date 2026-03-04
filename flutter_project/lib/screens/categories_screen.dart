import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/category_provider.dart';

class CategoriesScreen extends ConsumerStatefulWidget {
  final int selectedCategoryId;
  final ValueChanged<int> onSelectCategory;

  const CategoriesScreen({
    super.key,
    required this.selectedCategoryId,
    required this.onSelectCategory,
  });

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final query = _searchController.text.trim().toLowerCase();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8FA),
      appBar: AppBar(
        title: const Text('Explore'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search categories…',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(() => _searchController.clear()),
                          ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: categoriesAsync.when(
                    data: (cats) {
                      final filtered = cats.where((c) {
                        final name = (c['name'] ?? '').toString().toLowerCase();
                        return query.isEmpty || name.contains(query);
                      }).toList();

                      if (filtered.isEmpty) {
                        return const Center(child: Text('No categories found'));
                      }

                      return ListView.separated(
                        itemCount: filtered.length + 1,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            final selected = widget.selectedCategoryId == 0;
                            return ListTile(
                              leading: const Icon(Icons.public),
                              title: const Text('All posts'),
                              trailing: selected ? const Icon(Icons.check) : const Icon(Icons.chevron_right),
                              onTap: () => widget.onSelectCategory(0),
                            );
                          }

                          final cat = filtered[index - 1];
                          final id = cat['id'] as int?;
                          final name = (cat['name'] ?? '').toString();
                          if (id == null) return const SizedBox.shrink();

                          final selected = widget.selectedCategoryId == id;

                          return ListTile(
                            leading: const Icon(Icons.tag),
                            title: Text(name),
                            subtitle: const Text('Tap to view posts in this category'),
                            trailing: selected ? const Icon(Icons.check) : const Icon(Icons.chevron_right),
                            onTap: () => widget.onSelectCategory(id),
                          );
                        },
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(
                      child: Text(
                        'Failed to load categories\n$e',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
