// mobile_app/lib/screens/add_announcement_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/announcement_provider.dart';
import '../providers/auth_provider.dart'; // To get current user roles
import '../models/role_item.dart';
import '../utils/string_extensions.dart'; // For toTitleCase()
import '../widgets/home_button.dart';

class AddAnnouncementScreen extends StatefulWidget {
  const AddAnnouncementScreen({super.key});

  @override
  State<AddAnnouncementScreen> createState() => _AddAnnouncementScreenState();
}

class _AddAnnouncementScreenState extends State<AddAnnouncementScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _messageController = TextEditingController();
  String? _selectedCategory = 'General';
  List<String> _selectedTargetRoleNames = [];
  String? _selectedActionLinkView = 'none';

  final List<String> _categories = ['General', 'Late Arrival', 'Urgent'];
  final List<Map<String, String>> _actionableScheduleViews = [
    {'value': 'none', 'label': '(No Direct Link)'},
    {'value': 'personal', 'label': 'My Schedule'},
    {'value': 'boh', 'label': 'Back of House Schedule'},
    {'value': 'foh', 'label': 'Front of House Schedule'},
    {'value': 'managers', 'label': 'Managers Schedule'},
    {'value': 'bartenders_only', 'label': 'Bartenders Only Schedule'},
    {'value': 'waiters_only', 'label': 'Waiters Only Schedule'},
    {'value': 'skullers_only', 'label': 'Skullers Only Schedule'},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AnnouncementProvider>(context, listen: false).fetchAllRoles();
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (_formKey.currentState!.validate()) {
      final announcementProvider = Provider.of<AnnouncementProvider>(context, listen: false);
      try {
        await announcementProvider.addAnnouncement(
          title: _titleController.text,
          message: _messageController.text,
          category: _selectedCategory ?? 'General',
          targetRoleNames: _selectedTargetRoleNames.isEmpty ? null : _selectedTargetRoleNames,
          actionLinkView: _selectedActionLinkView == 'none' ? null : _selectedActionLinkView,
        );
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Announcement posted successfully!')),
        );
        Navigator.of(context).pop(); // Go back to manage announcements
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString().replaceFirst('Exception: ', '')}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final announcementProvider = Provider.of<AnnouncementProvider>(context);
    final authProvider = Provider.of<AuthProvider>(context);

    // Filter roles for posting: System Admin can target all, others cannot target System Admin
    final List<RoleItem> assignableRoles = authProvider.user?.roles.contains('system_admin') == true
        ? announcementProvider.allRoles
        : announcementProvider.allRoles.where((role) => role.name != 'system_admin').toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Post New Announcement'),
        backgroundColor: Colors.green[800],
        actions: const [ // <--- ADD IT HERE
        HomeButton(), // Your new Home button
        // ... (other existing actions like refresh, add, etc.)
      ],
      ),
      body: Consumer<AnnouncementProvider>(
        builder: (context, announcements, child) {
          if (announcements.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Title
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a title.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Message
                  TextFormField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                      labelText: 'Message',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 5,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a message.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Category Dropdown
                  DropdownButtonFormField<String>(
                    value: _selectedCategory,
                    decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
                    items: _categories.map((category) => DropdownMenuItem(
                      value: category,
                      child: Text(category),
                    )).toList(),
                    onChanged: (String? newValue) {
                      setState(() {
                        _selectedCategory = newValue;
                      });
                    },
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please select a category.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Target Roles (Multi-select Checkboxes)
                  Text('Target Specific Roles (Optional)', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  ...assignableRoles.map((role) {
                    return CheckboxListTile(
                      title: Text(role.formattedName),
                      value: _selectedTargetRoleNames.contains(role.name),
                      onChanged: (bool? newValue) {
                        setState(() {
                          if (newValue == true) {
                            _selectedTargetRoleNames.add(role.name);
                          } else {
                            _selectedTargetRoleNames.remove(role.name);
                          }
                        });
                      },
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                    );
                  }).toList(),
                  const SizedBox(height: 16),

                  // Actionable Schedule Link Dropdown
                  DropdownButtonFormField<String>(
                    value: _selectedActionLinkView,
                    decoration: const InputDecoration(labelText: 'Make Actionable (Link to Schedule)', border: OutlineInputBorder()),
                    items: _actionableScheduleViews.map((view) => DropdownMenuItem(
                      value: view['value'],
                      child: Text(view['label']!),
                    )).toList(),
                    onChanged: (String? newValue) {
                      setState(() {
                        _selectedActionLinkView = newValue;
                      });
                    },
                  ),
                  const SizedBox(height: 32),

                  // Submit Button
                  ElevatedButton(
                    onPressed: announcements.isLoading ? null : _submitForm,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                    child: announcements.isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Post Announcement'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}