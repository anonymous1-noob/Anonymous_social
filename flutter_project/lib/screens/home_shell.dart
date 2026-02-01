import 'package:flutter/material.dart';

import 'feed_screen.dart';
import 'profile_screen.dart';
import 'create_post_screen.dart';

class HomeShell extends StatefulWidget {
  final int categoryId;
  const HomeShell({super.key, required this.categoryId});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  Future<void> _openComposer() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreatePostScreen(categoryId: widget.categoryId),
      ),
    );

    // If you want, you can show a toast after posting
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Posted ✅")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      FeedScreen(categoryId: widget.categoryId),
      ProfileScreen(),
    ];

    return Scaffold(
      body: pages[_index],

      // Instagram-like "+"
      floatingActionButton: FloatingActionButton(
        onPressed: _openComposer,
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,

      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: "Home",
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: "Profile",
          ),
        ],
      ),
    );
  }
}
