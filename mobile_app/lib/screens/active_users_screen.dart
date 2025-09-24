// mobile_app/lib/screens/active_users_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_management_provider.dart';
import '../providers/auth_provider.dart'; // To get current user id/roles
import '../models/user.dart'; // For User model
import '../utils/string_extensions.dart'; // For toTitleCase()
import '../widgets/home_button.dart';

class ActiveUsersScreen extends StatefulWidget {
  const ActiveUsersScreen({super.key});

  @override
  State<ActiveUsersScreen> createState() => _ActiveUsersScreenState();
}

class _ActiveUsersScreenState extends State<ActiveUsersScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<UserManagementProvider>(context, listen: false).fetchActiveUsersData();
    });
  }

  Future<void> _forceLogoutUser(int userId, String fullName) async {
    final userManagementProvider = Provider.of<UserManagementProvider>(context, listen: false);
    bool confirm = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Force Logout'),
          content: Text('Are you sure you want to force logout "$fullName"? They will be signed out on their next action.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            ElevatedButton(
              child: const Text('Force Logout'),
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            ),
          ],
        );
      },
    ) ?? false;

    if (confirm) {
      try {
        await userManagementProvider.forceLogoutUser(userId, fullName);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('User "$fullName" will be logged out.')),
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
    final int currentUserId = authProvider.user?.id ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Active Users'),
        backgroundColor: Colors.green[800],
        actions: [
          HomeButton(),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => userManagementProvider.fetchActiveUsersData(),
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

          if (userManagement.activeUsers.isEmpty) {
            return const Center(child: Text('No users active recently.'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(8.0),
            itemCount: userManagement.activeUsers.length,
            itemBuilder: (context, index) {
              final user = userManagement.activeUsers[index];
              final bool isCurrentUser = user.id == currentUserId;
              final bool canForceLogout = !isCurrentUser && user.id != 1; // Cannot logout self or root admin

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4.0),
                elevation: 2,
                child: ListTile(
                  title: Text('${user.fullName} (${user.username})', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Roles: ${user.roles.map((r) => r.toTitleCase()).join(', ')}'),
                      Text('Last Seen: ${user.formattedLastSeen}'),
                      if (user.forceLogoutRequested)
                        const Padding(
                          padding: EdgeInsets.only(top: 4.0),
                          child: Chip(
                            label: Text('Logout Pending'),
                            backgroundColor: Colors.orange,
                            labelStyle: TextStyle(color: Colors.white),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                    ],
                  ),
                  trailing: canForceLogout
                      ? ElevatedButton.icon(
                          icon: const Icon(Icons.logout, size: 18),
                          label: const Text('Force Logout'),
                          onPressed: () => _forceLogoutUser(user.id, user.fullName),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                        )
                      : (isCurrentUser
                          ? const Text('Your Account', style: TextStyle(color: Colors.grey))
                          : const SizedBox.shrink()), // Or show nothing
                ),
              );
            },
          );
        },
      ),
    );
  }
}