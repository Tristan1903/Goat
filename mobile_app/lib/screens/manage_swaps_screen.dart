// mobile_app/lib/screens/manage_swaps_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/schedule_provider.dart';
import '../models/shift_management.dart';
import '../models/staff_member.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/home_button.dart';

class ManageSwapsScreen extends StatefulWidget {
  const ManageSwapsScreen({super.key});

  @override
  State<ManageSwapsScreen> createState() => _ManageSwapsScreenState();
}

class _ManageSwapsScreenState extends State<ManageSwapsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchSwapsData(0); // Fetch for current week
    });
  }

  Future<void> _fetchSwapsData(int weekOffset) async {
    final scheduleProvider = Provider.of<ScheduleProvider>(
      context,
      listen: false,
    );
    await scheduleProvider.fetchManageSwapsData(weekOffset);
  }

  Future<void> _updateSwapStatus(
    int swapId,
    String action, {
    int? covererId,
  }) async {
    final scheduleProvider = Provider.of<ScheduleProvider>(
      context,
      listen: false,
    );
    try {
      await scheduleProvider.updateSwapStatus(
        swapId,
        action,
        covererId: covererId,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Swap request ${action.toLowerCase()}ed successfully!'),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheduleProvider = Provider.of<ScheduleProvider>(context);
    final List<PendingSwap> pendingSwaps = scheduleProvider.pendingSwaps;
    final List<SwapHistoryItem> swapHistory = scheduleProvider.swapHistory;

    String weekLabel;
    if (scheduleProvider.manageSwapsWeekOffset == 0) {
      weekLabel = 'Current Week';
    } else if (scheduleProvider.manageSwapsWeekOffset == 1) {
      weekLabel = 'Next Week';
    } else if (scheduleProvider.manageSwapsWeekOffset == -1) {
      weekLabel = 'Previous Week';
    } else {
      weekLabel = 'Week Offset ${scheduleProvider.manageSwapsWeekOffset}';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Shift Swaps'),
        backgroundColor: Colors.green[800],
        actions: [
          HomeButton(),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () =>
                _fetchSwapsData(scheduleProvider.manageSwapsWeekOffset),
          ),
        ],
      ),
      body: Consumer<ScheduleProvider>(
        builder: (context, schedule, child) {
          if (schedule.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (schedule.errorMessage != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Error: ${schedule.errorMessage}',
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Week Navigation
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: () => _fetchSwapsData(
                          scheduleProvider.manageSwapsWeekOffset - 1,
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            weekLabel,
                            style: Theme.of(context).textTheme.titleMedium,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: () => _fetchSwapsData(
                          scheduleProvider.manageSwapsWeekOffset + 1,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(),

                // Pending Requests
                Text(
                  'Pending Requests',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                if (pendingSwaps.isEmpty)
                  const Text(
                    'No pending shift swap requests.',
                    style: TextStyle(fontStyle: FontStyle.italic),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: pendingSwaps.length,
                    itemBuilder: (context, index) {
                      final swap = pendingSwaps[index];
                      StaffMember?
                      selectedCover; // To hold dropdown selection locally

                      // Pre-select suggested cover if present and eligible
                      if (swap.covererId != null &&
                          swap.eligibleCovers.any(
                            (s) => s.id == swap.covererId,
                          )) {
                        selectedCover = swap.eligibleCovers.firstWhere(
                          (s) => s.id == swap.covererId,
                        );
                      }

                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 8.0),
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Requester: ${swap.requesterFullName}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Shift: ${swap.assignedShift} on ${swap.formattedShiftDate}',
                              ),
                              if (swap.covererFullName != null)
                                Text(
                                  'Suggested Cover: ${swap.covererFullName}',
                                  style: const TextStyle(
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              const SizedBox(height: 10),
                              DropdownButtonFormField<StaffMember>(
                                value: selectedCover,
                                hint: const Text(
                                  'Select Staff Member to Approve',
                                ),
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: swap.eligibleCovers.map((staff) {
                                  return DropdownMenuItem(
                                    value: staff,
                                    child: Text(
                                      staff.fullName,
                                      style: GoogleFonts.openSans(
                                        color: Colors.white,
                                      ),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (StaffMember? newValue) {
                                  // Update local state for dropdown
                                  if (newValue != null) {
                                    selectedCover = newValue;
                                  }
                                },
                              ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.check, size: 18),
                                    label: const Text('Approve'),
                                    onPressed: () {
                                      if (selectedCover == null) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Please select a cover to approve the swap.',
                                            ),
                                          ),
                                        );
                                      } else {
                                        _updateSwapStatus(
                                          swap.id,
                                          'Approve',
                                          covererId: selectedCover!.id,
                                        );
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.close, size: 18),
                                    label: const Text('Deny'),
                                    onPressed: () =>
                                        _updateSwapStatus(swap.id, 'Deny'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 30),

                // Swap History
                Text(
                  'Swap History',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                if (swapHistory.isEmpty)
                  const Text(
                    'No past swap requests found.',
                    style: TextStyle(fontStyle: FontStyle.italic),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: swapHistory.length,
                    itemBuilder: (context, index) {
                      final history = swapHistory[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4.0),
                        elevation: 1,
                        child: ListTile(
                          leading: Icon(
                            Icons.swap_horiz,
                            color: history.statusColor,
                          ),
                          title: Text(
                            '${history.requesterFullName} swapped ${history.assignedShift} on ${history.formattedShiftDate}',
                          ),
                          subtitle: Text(
                            'Covered by: ${history.covererFullName ?? 'N/A'}',
                          ),
                          trailing: Chip(
                            label: Text(history.status),
                            backgroundColor: history.statusColor.withOpacity(
                              0.2,
                            ),
                            labelStyle: TextStyle(color: history.statusColor),
                            visualDensity: VisualDensity.compact,
                          ),
                          onTap: () {
                            // Optionally show more details in a dialog
                          },
                        ),
                      );
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
