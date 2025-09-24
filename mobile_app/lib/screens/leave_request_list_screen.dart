// mobile_app/lib/screens/leave_request_list_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/leave_request.dart';
import '../providers/leave_provider.dart';
import '../providers/auth_provider.dart'; // To get current user roles
import 'submit_leave_request_screen.dart'; // We will create this next
import '../widgets/home_button.dart';

class LeaveRequestListScreen extends StatefulWidget {
  const LeaveRequestListScreen({super.key});

  @override
  State<LeaveRequestListScreen> createState() => _LeaveRequestListScreenState();
}

class _LeaveRequestListScreenState extends State<LeaveRequestListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<LeaveProvider>(context, listen: false).fetchLeaveRequests();
    });
  }

  // --- Helper to open document URL ---
  Future<void> _openDocument(String? url) async {
    if (url == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No document URL available.')),
      );
      return;
    }
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not launch $url')),
      );
    }
  }

  // --- Update Leave Request Status (Manager Action) ---
  Future<void> _updateStatus(int requestId, String status) async {
    final leaveProvider = Provider.of<LeaveProvider>(context, listen: false);
    try {
      await leaveProvider.updateLeaveRequestStatus(requestId, status);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Request $status successfully.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final bool isManagerOrAdmin = authProvider.user?.roles.any(
      (role) => ['manager', 'general_manager', 'system_admin'].contains(role),
    ) == true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Leave Requests'),
        backgroundColor: Colors.green[800],
        actions: [
          HomeButton(),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (ctx) => const SubmitLeaveRequestScreen(),
                ),
              );
            },
            tooltip: 'Submit New Leave Request',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => Provider.of<LeaveProvider>(context, listen: false).fetchLeaveRequests(),
            tooltip: 'Refresh Requests',
          ),
        ],
      ),
      body: Consumer<LeaveProvider>(
        builder: (context, leaveProvider, child) {
          if (leaveProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (leaveProvider.errorMessage != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Error: ${leaveProvider.errorMessage}',
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (leaveProvider.leaveRequests.isEmpty) {
            return const Center(
              child: Text(
                'No leave requests found.',
                textAlign: TextAlign.center,
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(8.0),
            itemCount: leaveProvider.leaveRequests.length,
            itemBuilder: (context, index) {
              final request = leaveProvider.leaveRequests[index];
              Color statusColor;
              switch (request.status) {
                case 'Approved':
                  statusColor = Colors.green;
                  break;
                case 'Denied':
                  statusColor = Colors.red;
                  break;
                default:
                  statusColor = Colors.orange; // Pending
              }

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4.0),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request.userFullName, // Show name for managers/admins
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 5),
                      Text('Dates: ${request.formattedDateRange}'),
                      Text('Reason: ${request.reason}'),
                      Row(
                        children: [
                          Text('Status: '),
                          Chip(
                            label: Text(request.status),
                            backgroundColor: statusColor.withOpacity(0.2),
                            labelStyle: TextStyle(color: statusColor),
                          ),
                          const Spacer(),
                          Text('Submitted: ${request.formattedSubmittedDate}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                      if (request.documentPath != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            icon: const Icon(Icons.attach_file, size: 18),
                            label: const Text('View Document'),
                            onPressed: () => _openDocument(request.documentPath),
                          ),
                        ),
                      // Manager/Admin actions
                      if (isManagerOrAdmin && request.status == 'Pending')
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            ElevatedButton.icon(
                              icon: const Icon(Icons.check, size: 18),
                              label: const Text('Approve'),
                              onPressed: () => _updateStatus(request.id, 'Approved'),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.close, size: 18),
                              label: const Text('Deny'),
                              onPressed: () => _updateStatus(request.id, 'Denied'),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
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