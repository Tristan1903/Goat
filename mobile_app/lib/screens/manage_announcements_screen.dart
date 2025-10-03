// mobile_app/lib/screens/manage_announcements_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart'; // For launching action links
import '../providers/announcement_provider.dart';
import '../providers/auth_provider.dart'; // To get current user roles
import '../models/announcement_item.dart';
import '../utils/string_extensions.dart'; // For toTitleCase()
import 'add_announcement_screen.dart'; // Add/Edit screen
import '../widgets/home_button.dart';

class ManageAnnouncementsScreen extends StatefulWidget {
  const ManageAnnouncementsScreen({super.key});

  @override
  State<ManageAnnouncementsScreen> createState() => _ManageAnnouncementsScreenState();
}

class _ManageAnnouncementsScreenState extends State<ManageAnnouncementsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AnnouncementProvider>(context, listen: false).fetchAnnouncements();
    });
  }

  // --- Delete Single Announcement ---
  Future<void> _deleteAnnouncement(int announcementId, String title) async {
    final announcementProvider = Provider.of<AnnouncementProvider>(context, listen: false);
    bool confirm = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Delete'),
          content: Text('Are you sure you want to delete announcement "$title"? This action cannot be undone.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            ElevatedButton(
              child: const Text('Delete'),
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            ),
          ],
        );
      },
    ) ?? false;

    if (confirm) {
      try {
        await announcementProvider.deleteAnnouncement(announcementId, title);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Announcement "$title" deleted successfully!')),
        );
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString().replaceFirst('Exception: ', '')}')),
        );
      }
    }
  }

  // --- Clear All Announcements ---
  Future<void> _clearAllAnnouncements() async {
    final announcementProvider = Provider.of<AnnouncementProvider>(context, listen: false);
    bool confirm = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Clear All'),
          content: const Text('Are you sure you want to clear ALL announcements? This action cannot be undone.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            ElevatedButton(
              child: const Text('Clear All'),
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            ),
          ],
        );
      },
    ) ?? false;

    if (confirm) {
      try {
        await announcementProvider.clearAllAnnouncements();
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All announcements cleared successfully!')),
        );
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString().replaceFirst('Exception: ', '')}')),
        );
      }
    }
  }

  // --- Launch Action Link ---
  Future<void> _launchActionLink(String url) async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication); // Open in external browser/tab
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not launch $url')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final announcementProvider = Provider.of<AnnouncementProvider>(context);
    final authProvider = Provider.of<AuthProvider>(context);

    // Permissions check: Who can post/clear/delete announcements?
    final bool canPostClearDelete = authProvider.user?.roles.any(
      (role) => ['manager', 'general_manager', 'system_admin'].contains(role),
    ) == true;
    final int currentUserId = authProvider.user?.id ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Announcements'),
        backgroundColor: Colors.green[800],
        actions: [
          HomeButton(),
          // Add New Announcement Button
          if (canPostClearDelete)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Post New Announcement',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (ctx) => const AddAnnouncementScreen()),
                );
              },
            ),
          // Clear All Announcements Button
          if (canPostClearDelete)
            IconButton(
              icon: const Icon(Icons.clear_all),
              tooltip: 'Clear All Announcements',
              onPressed: _clearAllAnnouncements,
            ),
          // Refresh Button
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => announcementProvider.fetchAnnouncements(),
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

          if (announcements.announcements.isEmpty) {
            return const Center(child: Text('No announcements have been posted yet.'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(8.0),
            itemCount: announcements.announcements.length,
            itemBuilder: (context, index) {
              final announcement = announcements.announcements[index];
              // A user can delete their own announcement, or a GM/System Admin can delete any.
              final bool canDeleteThis = (announcement.userId == currentUserId || authProvider.user?.roles.contains('system_admin') == true || authProvider.user?.roles.contains('general_manager') == true);

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4.0),
                elevation: 2,
                color: const Color.fromARGB(255, 82, 82, 82), // White background for the card
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              announcement.title,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Chip(
                            label: Text(announcement.category),
                            backgroundColor: Colors.grey.shade300, // Light grey for "General" category chip
                            labelStyle: TextStyle(color: Colors.grey.shade800),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(announcement.message),
                      const SizedBox(height: 8),
                      // Display Target Roles if any
                      if (announcement.targetRoles.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Text(
                            'Targeted: ${announcement.targetRoles.map((r) => r.toTitleCase()).join(', ')}',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Posted by: ${announcement.userFullName} on ${announcement.formattedTimestamp}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Action Link Button
                              if (announcement.actionLink != null)
                                IconButton(
                                  icon: const Icon(Icons.link, size: 20, color: Colors.blue),
                                  tooltip: 'View Action',
                                  onPressed: () => _launchActionLink(announcement.actionLink!),
                                ),
                              // Delete Button
                              if (canDeleteThis)
                                IconButton(
                                  icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                                  tooltip: 'Delete Announcement',
                                  onPressed: () => _deleteAnnouncement(announcement.id, announcement.title),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}