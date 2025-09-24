// mobile_app/lib/screens/add_edit_user_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_management_provider.dart';
import '../providers/auth_provider.dart';
import '../models/user.dart';
import '../models/role_item.dart';
import '../utils/string_extensions.dart'; // For toTitleCase()
import '../widgets/home_button.dart';

class AddEditUserScreen extends StatefulWidget {
  final User? user; // Null for add, non-null for edit

  const AddEditUserScreen({super.key, this.user});

  @override
  State<AddEditUserScreen> createState() => _AddEditUserScreenState();
}

class _AddEditUserScreenState extends State<AddEditUserScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController(); // Only for setting/changing password

  bool _isEditing = false;
  List<RoleItem> _allAvailableRoles = [];
  Set<String> _selectedRoleNames = {}; // Store selected role names
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    _fetchRolesAndPopulateForm();
  }

  Future<void> _fetchRolesAndPopulateForm() async {
    final userManagementProvider = Provider.of<UserManagementProvider>(context, listen: false);
    await userManagementProvider.fetchAllRoles();

    setState(() {
      _allAvailableRoles = userManagementProvider.allRoles;

      if (widget.user != null) {
        _isEditing = true;
        _fullNameController.text = widget.user!.fullName;
        _usernameController.text = widget.user!.username;
        _selectedRoleNames = Set<String>.from(widget.user!.roles); // Convert to Set
      }
    });
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (_formKey.currentState!.validate()) {
      if (_selectedRoleNames.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please assign at least one role.')));
        return;
      }

      final userManagementProvider = Provider.of<UserManagementProvider>(context, listen: false);
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      
      // Permission check for roles (managers can only assign specific roles)
      final bool isManagerOnly = authProvider.user?.roles.contains('manager') == true && !(authProvider.user?.roles.contains('system_admin') == true || authProvider.user?.roles.contains('general_manager') == true);
      if (isManagerOnly) {
        final allowedRoles = {'bartender', 'waiter', 'skullers'};
        if (!_selectedRoleNames.every((role) => allowedRoles.contains(role))) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Managers can only assign Bartender, Waiter, and Skullers roles.')));
          return;
        }
      }


      try {
        if (_isEditing) {
          await userManagementProvider.editUserDetails(
            widget.user!.id!,
            username: _usernameController.text,
            fullName: _fullNameController.text,
            password: _passwordController.text.isEmpty ? null : _passwordController.text,
            roles: _selectedRoleNames.toList(),
          );
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('User "${_fullNameController.text}" updated successfully!')),
          );
        } else {
          await userManagementProvider.addUser(
            username: _usernameController.text,
            fullName: _fullNameController.text,
            password: _passwordController.text, // Password is required for add
            roles: _selectedRoleNames.toList(),
          );
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('User "${_fullNameController.text}" created successfully!')),
          );
        }
        Navigator.of(context).pop(); // Go back to manage users list
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
    final userManagementProvider = Provider.of<UserManagementProvider>(context);
    final authProvider = Provider.of<AuthProvider>(context);

    // Permission checks
    final bool isManagerOnly = authProvider.user?.roles.contains('manager') == true && !(authProvider.user?.roles.contains('system_admin') == true || authProvider.user?.roles.contains('general_manager') == true);
    final bool isLimitedView = authProvider.user?.roles.contains('owners') == true && !(authProvider.user?.roles.contains('system_admin') == true || authProvider.user?.roles.contains('general_manager') == true);


    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit User' : 'Add New User'),
        backgroundColor: Colors.green[800],
        actions: const [
        HomeButton(),
      ],
      ),
      body: Consumer<UserManagementProvider>(
        builder: (context, userManagement, child) {
          if (userManagement.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Full Name
                  TextFormField(
                    controller: _fullNameController,
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                      border: OutlineInputBorder(),
                    ),
                    readOnly: isLimitedView,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter full name.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Username
                  TextFormField(
                    controller: _usernameController,
                    decoration: const InputDecoration(
                      labelText: 'Username (for login)',
                      border: OutlineInputBorder(),
                    ),
                    readOnly: isLimitedView,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter username.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Password (Required for add, optional for edit)
                  if (!_isEditing || !isLimitedView) // Password field visible for add, or edit if not limited view
                    Column(
                      children: [
                        TextFormField(
                          controller: _passwordController,
                          obscureText: !_showPassword,
                          decoration: InputDecoration(
                            labelText: _isEditing ? 'New Password (Optional)' : 'Password',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(_showPassword ? Icons.visibility : Icons.visibility_off),
                              onPressed: () {
                                setState(() {
                                  _showPassword = !_showPassword;
                                });
                              },
                            ),
                          ),
                          validator: (value) {
                            if (!_isEditing && (value == null || value.isEmpty)) {
                              return 'Password is required for new users.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),

                  // Assign Roles
                  if (!isLimitedView) // Roles can't be changed by limited owner
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Assign Roles', style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 8),
                        ..._allAvailableRoles.map((role) {
                          final bool isAllowedForManager = isManagerOnly
                              ? (role.name == 'bartender' || role.name == 'waiter' || role.name == 'skullers')
                              : true; // Managers can only assign specific roles
                          final bool isSystemAdmin = role.name == 'system_admin';
                          final bool isSelf = widget.user?.id == authProvider.user?.id; // Cannot edit own roles here

                          final bool isDisabled = isLimitedView || !isAllowedForManager || isSystemAdmin || isSelf;

                          return CheckboxListTile(
                            title: Text(role.formattedName),
                            value: _selectedRoleNames.contains(role.name),
                            onChanged: isDisabled
                                ? null // Disable if not allowed
                                : (bool? newValue) {
                                    setState(() {
                                      if (newValue == true) {
                                        _selectedRoleNames.add(role.name);
                                      } else {
                                        _selectedRoleNames.remove(role.name);
                                      }
                                    });
                                  },
                            controlAffinity: ListTileControlAffinity.leading,
                            dense: true,
                          );
                        }).toList(),
                        const SizedBox(height: 16),
                      ],
                    ),

                  // Submit Button
                  ElevatedButton(
                    onPressed: (userManagementProvider.isLoading || isLimitedView) ? null : _submitForm,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                    child: userManagementProvider.isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(_isEditing ? 'Update User' : 'Add User'),
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