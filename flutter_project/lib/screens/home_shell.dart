import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'feed_screen.dart';
import 'activity_screen.dart';
import 'profile_screen.dart';
import 'categories_screen.dart';
import '../widgets/post_composer_sheet.dart';
import '../providers/user_profile_provider.dart';

class HomeShell extends ConsumerStatefulWidget {
  final int categoryId;
  const HomeShell({super.key, required this.categoryId});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;
  late int _categoryId;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.categoryId;
  }

  Future<void> _openComposer() async {
    await showPostComposerSheet(
      context: context,
      categoryId: _categoryId == 0 ? 1 : _categoryId, // default preselect
    );
  }

  void _selectCategory(int id) {
    setState(() {
      _categoryId = id;
      _index = 0; // jump back to Home
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      FeedScreen(categoryId: _categoryId),
      CategoriesScreen(
        selectedCategoryId: _categoryId,
        onSelectCategory: _selectCategory,
      ),
      // index 2 is +
      const ActivityScreen(),
      const ProfileScreen(),
    ];

    Widget body;
    if (_index <= 1) {
      body = pages[_index];
    } else if (_index >= 3) {
      body = pages[_index - 1];
    } else {
      body = pages[0];
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) async {
          if (i == 2) {
            await _openComposer();
            return;
          }
          if (i == 4) {
            ref.invalidate(userProfileProvider);
          }
          if (mounted) setState(() => _index = i);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.search), label: 'Explore'),
          NavigationDestination(icon: Icon(Icons.add_box_outlined), selectedIcon: Icon(Icons.add_box), label: 'Create'),
          NavigationDestination(icon: Icon(Icons.favorite_border), selectedIcon: Icon(Icons.favorite), label: 'Activity'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
