import 'package:flutter/material.dart';

import 'feed_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';
import '../widgets/post_composer_sheet.dart';

/// Instagram-like app shell:
/// - Bottom navigation is primary.
/// - Center (+) opens a modal composer sheet (does not switch tabs).
/// - Comments open as a modal sheet from the feed (see FeedScreen).
class HomeShell extends StatefulWidget {
  final int categoryId;
  const HomeShell({super.key, required this.categoryId});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  Future<void> _openComposer() async {
    await showPostComposerSheet(
      context: context,
      categoryId: widget.categoryId,
    );

    if (!mounted) return;

    // Optional: If you later want a "Posted ✅" snackbar only on success,
    // update showPostComposerSheet to Navigator.pop(true) on success and
    // return Future<bool?>. For now it's Future<void>, so we don't show it here.
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      FeedScreen(categoryId: widget.categoryId),
      const _ExplorePlaceholder(),
      // index 2 is the + action (no page)
      NotificationsScreen(),
      ProfileScreen(),
    ];

    // Map bottom-nav index -> page index.
    // 0 -> feed
    // 1 -> explore
    // 2 -> composer action
    // 3 -> notifications
    // 4 -> profile
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
            return; // don't change selected tab
          }
          if (mounted) setState(() => _index = i);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.search),
            selectedIcon: Icon(Icons.search),
            label: 'Explore',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_box_outlined),
            selectedIcon: Icon(Icons.add_box),
            label: 'Create',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_border),
            selectedIcon: Icon(Icons.favorite),
            label: 'Activity',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
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
                Text(
                  'Explore coming soon',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 6),
                Text(
                  'Search and discover posts by categories and trends.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
