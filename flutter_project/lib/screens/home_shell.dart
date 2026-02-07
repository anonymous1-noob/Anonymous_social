import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'feed_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';
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

  Future<void> _openComposer() async {
    await showPostComposerSheet(
      context: context,
      categoryId: widget.categoryId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      FeedScreen(categoryId: widget.categoryId),
      const _ExplorePlaceholder(),
      // index 2 is the + action (no page)
      NotificationsScreen(),
      const ProfileScreen(), // ProfileScreen is now a const widget
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
          // When the profile tab is selected, invalidate the provider to force a refresh.
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

class _ExplorePlaceholder extends StatelessWidget {
  const _ExplorePlaceholder();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.search, size: 44),
                SizedBox(height: 12),
                Text('Explore coming soon', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
                SizedBox(height: 6),
                Text('Search and discover posts by categories and trends.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
