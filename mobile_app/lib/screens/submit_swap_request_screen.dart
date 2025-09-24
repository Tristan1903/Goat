// mobile_app/lib/screens/submit_swap_request_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/schedule.dart'; // For ScheduleItem
import '../models/staff_member.dart';
import '../providers/schedule_provider.dart';
import '../providers/auth_provider.dart';
import 'package:intl/intl.dart';
import '../widgets/home_button.dart';

class SubmitSwapRequestScreen extends StatefulWidget {
  final ScheduleItem shiftToSwap;

  const SubmitSwapRequestScreen({super.key, required this.shiftToSwap});

  @override
  State<SubmitSwapRequestScreen> createState() => _SubmitSwapRequestScreenState();
}

class _SubmitSwapRequestScreenState extends State<SubmitSwapRequestScreen> {
  StaffMember? _selectedCover;
  List<StaffMember> _eligibleCovers = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _filterEligibleCovers();
    });
  }

  // Filter eligible staff for this specific swap (matching role, no conflicts)
  void _filterEligibleCovers() {
    final scheduleProvider = Provider.of<ScheduleProvider>(context, listen: false);
    final currentUser = Provider.of<AuthProvider>(context, listen: false).user; // Current user to get roles

    if (currentUser == null || scheduleProvider.staffForSwaps.isEmpty) {
      setState(() {
        _eligibleCovers = [];
      });
      return;
    }

    final requesterRoles = currentUser.roles; // The roles of the person requesting the swap
    final requestedShiftDate = widget.shiftToSwap.shiftDate;
    final requestedShiftType = widget.shiftToSwap.shiftType;
    final String requestedShiftDayName = DateFormat('EEEE').format(requestedShiftDate);

    // This logic needs to mirror the backend's `manage_swaps` filtering
    // for `all_potential_cover_staff` and `conflict` checks.
    // Since the `AuthApi.getStaffForSwaps` only returns basic staff data,
    // we need to rely on the backend for conflict checking or pre-filter here.
    // For now, let's just match roles and rely on backend for full conflict.

    List<StaffMember> tempEligible = [];
    for (var staff in scheduleProvider.staffForSwaps) {
      // 1. Exclude the requester themselves (current logged-in user)
      if (staff.id == currentUser.id) continue;

      // 2. Check for role matching
      final covererRoles = staff.roles;
      if (covererRoles == null || !covererRoles.any((role) => requesterRoles.contains(role))) {
        continue; // No matching role
      }

      // 3. (More complex): Check for shift conflicts.
      // The backend API `api/staff-for-swaps` in your app.py *does not* return schedule data for each staff.
      // So the full conflict check must happen on the backend in the `submit_new_swap_request` route,
      // or we need a new API that returns staff with their schedule conflicts already calculated for a given shift.
      // For now, we filter by role match here and let the backend handle the final conflict validation.
      tempEligible.add(staff);
    }
    setState(() {
      _eligibleCovers = tempEligible;
    });
  }

  Future<void> _submitSwapRequest() async {
    if (_selectedCover == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a potential cover.')),
      );
      return;
    }

    final scheduleProvider = Provider.of<ScheduleProvider>(context, listen: false);
    try {
      await scheduleProvider.submitNewSwapRequest(
        requesterScheduleId: widget.shiftToSwap.id!,
        desiredCoverId: _selectedCover!.id,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shift swap request submitted. A manager will be notified.')),
      );
      Navigator.of(context).pop(); // Go back to My Schedule
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error submitting request: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheduleProvider = Provider.of<ScheduleProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Request Shift Swap'),
        backgroundColor: Colors.green[800],
        actions: const [
        HomeButton(),
      ],
      ),
      body: scheduleProvider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Requesting swap for:',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 8.0),
                    child: ListTile(
                      title: Text('${widget.shiftToSwap.shiftType} ${widget.shiftToSwap.formattedTimeDisplay}'),
                      subtitle: Text('on ${widget.shiftToSwap.formattedDate}'),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Suggest a potential cover:',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<StaffMember>(
                    value: _selectedCover,
                    hint: const Text('Select Staff Member'),
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: _eligibleCovers.map((staff) {
                      return DropdownMenuItem(
                        value: staff,
                        child: Text(staff.fullName),
                      );
                    }).toList(),
                    onChanged: (StaffMember? newValue) {
                      setState(() {
                        _selectedCover = newValue;
                      });
                    },
                    validator: (value) {
                      if (value == null) {
                        return 'Please select a cover.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 30),
                  ElevatedButton(
                    onPressed: scheduleProvider.isLoading ? null : () {
                      if (_selectedCover == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please select a potential cover.')),
                        );
                        return; // IMPORTANT: return here if _selectedCover is null
                      }
                      _submitSwapRequest(); // Only call if _selectedCover is NOT null
                    },
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                    child: scheduleProvider.isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Submit Swap Request'),
                  ),
                ],
              ),
            ),
    );
  }
}