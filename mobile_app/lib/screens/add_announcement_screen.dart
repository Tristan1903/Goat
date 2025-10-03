// mobile_app/lib/screens/add_announcement_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/announcement_provider.dart';
import '../providers/auth_provider.dart'; // To get current user roles
import '../models/role_item.dart';
import '../utils/string_extensions.dart'; // For toTitleCase()
import '../widgets/home_button.dart';
import 'package:google_fonts/google_fonts.dart';

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
                    decoration: InputDecoration(
                      labelText: 'Title',
                      labelStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface), // Dark text on white input field
                      filled: true,
                      fillColor: Colors.white, // White background for input field
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Theme.of(context).colorScheme.primary.withOpacity(0.5)), // Subtle primary border
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Theme.of(context).colorScheme.secondary, width: 2), // Secondary accent for focus
                      ),
                    ),
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface), // Dark text in input
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
                    decoration: InputDecoration(
                      labelText: 'Message',
                      labelStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Theme.of(context).colorScheme.primary.withOpacity(0.5)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Theme.of(context).colorScheme.secondary, width: 2),
                      ),
                    ),
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
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
                    decoration: InputDecoration(
                      labelText: 'Category',
                      labelStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Theme.of(context).colorScheme.primary.withOpacity(0.5)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Theme.of(context).colorScheme.secondary, width: 2),
                      ),
                    ),
                    dropdownColor: Colors.white, // Dropdown menu background color
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface), // Selected item text color
                    iconEnabledColor: Theme.of(context).colorScheme.secondary, // Dropdown arrow color
                    items: _categories.map((category) => DropdownMenuItem(
                      value: category,
                      child: Text(category, style: TextStyle(color: Theme.of(context).colorScheme.onSurface)), // Item text color in menu
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
                  Text('Target Specific Roles (Optional)', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.onBackground)), // White text label
                  const SizedBox(height: 8),
                  // --- MODIFIED: CheckboxListTile styling ---
                  ...assignableRoles.map((role) {
                    return CheckboxListTile(
                      title: Text(role.formattedName, style: TextStyle(color: Theme.of(context).colorScheme.onBackground)), // White text for role name
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
                      checkColor: Colors.white, // White checkmark
                      activeColor: Theme.of(context).colorScheme.secondary, // Bright blue when checked
                      tileColor: Theme.of(context).colorScheme.background.withOpacity(0.1), // Subtle background for list tile
                    );
                  }).toList(),
                  // --- END MODIFIED ---
                  const SizedBox(height: 16),

                  // Actionable Schedule Link Dropdown
                  DropdownButtonFormField<String>(
                    value: _selectedActionLinkView,
                    decoration: InputDecoration(
                      labelText: 'Make Actionable (Link to Schedule)',
                      labelStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Theme.of(context).colorScheme.primary.withOpacity(0.5)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Theme.of(context).colorScheme.secondary, width: 2),
                      ),
                    ),
                    dropdownColor: Colors.white,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                    iconEnabledColor: Theme.of(context).colorScheme.secondary,
                    items: _actionableScheduleViews.map((view) => DropdownMenuItem(
                      value: view['value'],
                      child: Text(view['label']!, style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
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
                      // --- MODIFIED: Button color ---
                      backgroundColor: Theme.of(context).colorScheme.secondary, // Bright blue submit button
                      foregroundColor: Colors.white, // White text
                      // --- END MODIFIED ---
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      textStyle: GoogleFonts.nunito(fontWeight: FontWeight.bold, fontSize: 18),
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