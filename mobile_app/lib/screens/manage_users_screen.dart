// mobile_app/lib/screens/manage_users_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_management_provider.dart';
import '../providers/auth_provider.dart'; // To get current user roles
import '../models/user.dart';
import '../models/role_item.dart';
import '../utils/string_extensions.dart'; // For toTitleCase()
import 'add_edit_user_screen.dart'; // We will create this next
import 'manage_suspension_screen.dart';
import '../widgets/home_button.dart';

class ManageUsersScreen extends StatefulWidget {
  const ManageUsersScreen({super.key});

  @override
  State<ManageUsersScreen> createState() => _ManageUsersScreenState();
}

class _ManageUsersScreenState extends State<ManageUsersScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchData();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    final userManagementProvider = Provider.of<UserManagementProvider>(context, listen: false);
    await userManagementProvider.fetchInitialUserManagementData();
  }

  Future<void> _reinstateUser(int userId, String fullName) async {
    final userManagementProvider = Provider.of<UserManagementProvider>(context, listen: false);
    bool confirm = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Reinstate'),
          content: Text('Are you sure you want to reinstate "$fullName"? Their suspension will be lifted.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            ElevatedButton(
              child: const Text('Reinstate'),
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            ),
          ],
        );
      },
    ) ?? false;

    if (confirm) {
      try {
        await userManagementProvider.reinstateUser(userId);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('User "$fullName" reinstated successfully!')),
        );
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString().replaceFirst('Exception: ', '')}')),
        );
      }
    }
  }

  Future<void> _deleteUser(int userId, String fullName) async {
    final userManagementProvider = Provider.of<UserManagementProvider>(context, listen: false);
    bool confirm = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Delete'),
          content: Text('Are you sure you want to delete user "$fullName"? This action cannot be undone.'),
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
        await userManagementProvider.deleteUser(userId, fullName);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('User "$fullName" deleted successfully!')),
        );
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
    final bool canAddEditSuspendReinstate = authProvider.user?.roles.any(
      (role) => ['manager', 'general_manager', 'system_admin'].contains(role),
    ) == true;
    final bool canDelete = authProvider.user?.roles.any(
      (role) => ['system_admin'].contains(role), // Only system admin can delete
    ) == true;
    final int currentUserId = authProvider.user?.id ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Users'),
        backgroundColor: Colors.green[800],
        actions: [
          HomeButton(),
          if (canAddEditSuspendReinstate)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add New User',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (ctx) => const AddEditUserScreen()),
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => userManagementProvider.fetchUsers(),
          ),
        ],
      ),
      body: Consumer<UserManagementProvider>(
        builder: (context, userManagement, child) {
          if (userManagement.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (userManagement.errorMessage != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Error: ${userManagement.errorMessage}',
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return Column(
            children: [
              // --- Filters Section ---
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: ExpansionTile(
                  title: const Text('Filter Users'),
                  leading: const Icon(Icons.filter_list),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          // Role Filter
                          DropdownButtonFormField<String>(
                            value: userManagement.selectedRoleFilter,
                            hint: const Text('Filter by Role'),
                            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                            items: [
                              const DropdownMenuItem(value: 'all', child: Text('All Roles')),
                              ...userManagement.allRoles.map((role) => DropdownMenuItem(
                                value: role.name,
                                child: Text(role.formattedName),
                              )),
                            ],
                            onChanged: (String? newValue) {
                              userManagement.setRoleFilter(newValue);
                            },
                          ),
                          const SizedBox(height: 10),
                          // Search Filter
                          TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              labelText: 'Search Name or Username',
                              prefixIcon: const Icon(Icons.search),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onChanged: (value) {
                              userManagement.setSearchQuery(value); // Triggers fetch on change
                            },
                            onSubmitted: (value) {
                              userManagement.setSearchQuery(value); // Also triggers on submit
                            },
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.filter_list_off),
                            label: const Text('Clear Filters'),
                            onPressed: () {
                              userManagement.clearFilters();
                              _searchController.clear();
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),

              // --- Users List ---
              Expanded(
                child: userManagement.users.isEmpty
                    ? const Center(child: Text('No users found matching your criteria.'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(8.0),
                        itemCount: userManagement.users.length,
                        itemBuilder: (context, index) {
                          final user = userManagement.users[index];
                          final bool isRootAdmin = user.id == 1;
                          final bool isCurrentUser = user.id == currentUserId;

                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4.0),
                            elevation: 2,
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(user.fullName, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                                  Text('Username: ${user.username}'),
                                  Text('Roles: ${user.roles.map((r) => r.toTitleCase()).join(', ')}'),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Chip(
                                        label: Text(user.isSuspended ? 'Suspended' : 'Active'),
                                        backgroundColor: user.isSuspended ? Colors.red.shade100 : Colors.green.shade100,
                                        labelStyle: TextStyle(color: user.isSuspended ? Colors.red.shade800 : Colors.green.shade800),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      if (user.isSuspended && user.suspensionEndDate != null)
                                        Chip(
                                          label: Text('Ends: ${user.formattedSuspensionEndDate}'),
                                          backgroundColor: Colors.orange.shade100,
                                          labelStyle: TextStyle(color: Colors.orange.shade800),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  // Actions
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: Wrap(
                                      spacing: 8.0,
                                      runSpacing: 4.0,
                                      children: [
                                        // Edit Button
                                        if (!isRootAdmin && canAddEditSuspendReinstate && !isCurrentUser) // Cannot edit root admin or self with basic manage role
                                          ElevatedButton.icon(
                                            icon: const Icon(Icons.edit, size: 18),
                                            label: const Text('Edit'),
                                            onPressed: () {
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (ctx) => AddEditUserScreen(user: user),
                                                ),
                                              );
                                            },
                                            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey),
                                          ),
                                        // Suspend/Reinstate Button
                                        if (!isRootAdmin && canAddEditSuspendReinstate && !isCurrentUser) // Cannot suspend root admin or self
                                          user.isSuspended
                                              ? ElevatedButton.icon(
                                                  icon: const Icon(Icons.undo, size: 18),
                                                  label: const Text('Reinstate'),
                                                  onPressed: () => _reinstateUser(user.id, user.fullName),
                                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                                                )
                                              : ElevatedButton.icon(
                                                  icon: const Icon(Icons.block, size: 18),
                                                  label: const Text('Suspend'),
                                                  onPressed: () {
                                                    Navigator.of(context).push(
                                                      MaterialPageRoute(builder: (ctx) => ManageSuspensionScreen(user: user)),
                                                    );
                                                  },
                                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                                                ),
                                        // Delete Button
                                        if (!isRootAdmin && canDelete && !isCurrentUser) // Only SA can delete, cannot delete root admin or self
                                          ElevatedButton.icon(
                                            icon: const Icon(Icons.delete, size: 18),
                                            label: const Text('Delete'),
                                            onPressed: () => _deleteUser(user.id, user.fullName),
                                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}