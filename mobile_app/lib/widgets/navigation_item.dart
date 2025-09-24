// mobile_app/lib/models/navigation_item.dart
import 'package:flutter/material.dart';

// Represents an actual screen/page to navigate to
class AppScreenItem {
  final String title;
  final IconData icon;
  final Widget targetScreen;
  final List<String> requiredRoles; // Roles needed to see this screen
  final String? webLinkPath; // Optional: if this item opens a web page
  final String? webLinkBaseUrl; // Optional: base URL for web link

  AppScreenItem({
    required this.title,
    required this.icon,
    required this.targetScreen,
    this.requiredRoles = const [],
    this.webLinkPath,
    this.webLinkBaseUrl,
  });
}

// Represents a top-level navigation category on the Home Screen
class AppNavigationCategory {
  final String title;
  final IconData icon;
  final Color backgroundColor;
  final Color textColor;
  final List<AppScreenItem> subScreens; // List of screens under this category

  AppNavigationCategory({
    required this.title,
    required this.icon,
    required this.backgroundColor,
    this.textColor = Colors.white,
    required this.subScreens,
  });
}