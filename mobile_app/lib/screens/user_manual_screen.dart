// mobile_app/lib/screens/user_manual_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/announcement_provider.dart'; // It also holds user manual data
import '../models/user_manual_section.dart';
import '../utils/string_extensions.dart'; // For toTitleCase()
import 'package:flutter_html/flutter_html.dart'; // For rendering HTML content
import '../widgets/home_button.dart';

class UserManualScreen extends StatefulWidget {
  const UserManualScreen({super.key});

  @override
  State<UserManualScreen> createState() => _UserManualScreenState();
}

class _UserManualScreenState extends State<UserManualScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AnnouncementProvider>(context, listen: false).fetchUserManualContent();
    });
  }

  @override
  Widget build(BuildContext context) {
    final announcementProvider = Provider.of<AnnouncementProvider>(context);
    final List<UserManualSection> manualSections = announcementProvider.userManualSections;

    return Scaffold(
      appBar: AppBar(
        title: const Text('User Manual'),
        backgroundColor: Colors.green[800],
        actions: [
          HomeButton(),      
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => announcementProvider.fetchUserManualContent(),
          ),
        ],
      ),
      body: Consumer<AnnouncementProvider>(
        builder: (context, announcements, child) {
          if (announcements.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (announcements.errorMessage != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Error: ${announcements.errorMessage}',
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (manualSections.isEmpty) {
            return const Center(child: Text('No user manual content available for your roles.'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(8.0),
            itemCount: manualSections.length,
            itemBuilder: (context, index) {
              final section = manualSections[index];
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4.0),
                elevation: 2,
                child: ExpansionTile(
                  title: Text(section.title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Html(
                        data: section.content, // Render HTML content
                        style: {
                          "body": Style(fontSize: FontSize.medium),
                          "p": Style(margin: Margins(bottom: Margin(8, Unit.px))),
                          "h1": Style(fontSize: FontSize.xLarge, fontWeight: FontWeight.bold),
                          "h2": Style(fontSize: FontSize.large, fontWeight: FontWeight.bold),
                          "h3": Style(fontSize: FontSize.medium, fontWeight: FontWeight.bold),
                          "ul": Style(padding: HtmlPaddings.only(left:20)),
                          "li": Style(margin: Margins(bottom: Margin(4, Unit.px))),
                          "strong": Style(fontWeight: FontWeight.bold),
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}