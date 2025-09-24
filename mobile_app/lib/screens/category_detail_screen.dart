// mobile_app/lib/screens/category_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart'; // For launching web links
import '../models/navigation_item.dart';
import '../providers/auth_provider.dart';
import '../utils/string_extensions.dart'; // For toTitleCase()
import '../widgets/home_button.dart';

class CategoryDetailScreen extends StatelessWidget {
  final AppNavigationCategory category;

  const CategoryDetailScreen({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final List<String> currentUserRoles = authProvider.user?.roles ?? [];

    // Filter sub-screens based on current user's roles
    final List<AppScreenItem> accessibleSubScreens = category.subScreens
        .where((item) => item.requiredRoles.isEmpty || currentUserRoles.any((r) => item.requiredRoles.contains(r)))
        .toList();

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background, // Use background color
      appBar: AppBar(
        title: Text(category.title, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white)),
        backgroundColor: category.backgroundColor, // App bar color matches category
        foregroundColor: category.textColor,
        iconTheme: IconThemeData(color: category.textColor),
        actions: const [
        HomeButton(),
      ],
      ),
      body: accessibleSubScreens.isEmpty
          ? Center(
              child: Text(
                'No items available in this category for your role.',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16.0),
              itemCount: accessibleSubScreens.length,
              itemBuilder: (context, index) {
                final item = accessibleSubScreens[index];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 8.0),
                  elevation: 4,
                  color: Color.fromRGBO(203, 234, 166, 1), // White background for the card/list item
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)), // Use theme's card color
                  child: ListTile(
                    leading: Icon(item.icon, color: Color.fromRGBO(117, 112, 131, 1)), // Bright blue icon
                    title: Text(item.title, style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Color.fromRGBO(117, 112, 131, 1), // Bright blue text
                      fontWeight: FontWeight.w600, // Make text slightly bolder
                    )),
                    trailing: item.webLinkPath != null ? Icon(Icons.open_in_new, color: Color.fromRGBO(117, 112, 131, 1)) : null, // Bright blue icon
                    onTap: () async {
                      if (item.webLinkPath != null) {
                        final String baseUrl = item.webLinkBaseUrl ?? 'http://localhost:5000'; // Fallback
                        final Uri url = Uri.parse('$baseUrl${item.webLinkPath}');
                        if (await canLaunchUrl(url)) {
                          await launchUrl(url, mode: LaunchMode.externalApplication);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Could not launch ${item.webLinkPath!}')),
                          );
                        }
                      } else {
                        Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => item.targetScreen));
                      }
                    },
                  ),
                );
              },
            ),
    );
  }
}