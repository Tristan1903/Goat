// mobile_app/lib/widgets/home_button.dart
import 'package:flutter/material.dart';

class HomeButton extends StatelessWidget {
  const HomeButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.home, color: Colors.white), // Assuming white icons on AppBar
      tooltip: 'Go to Home',
      onPressed: () {
        // This pops all routes until the first route (HomeScreen) is reached.
        Navigator.of(context).popUntil((route) => route.isFirst);
      },
    );
  }
}