import 'package:flutter/material.dart';

class CampusOnboardingScreen extends StatelessWidget {
  final bool manageMode;
  const CampusOnboardingScreen({super.key, this.manageMode = false});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('Campus selection removed.')));
  }
}
