// mobile_app/lib/screens/daily_shifts_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/schedule_provider.dart';
import '../models/shift_management.dart'; // For CategorizedDailyShifts and DailyShiftEntry
import '../widgets/home_button.dart';

class DailyShiftsScreen extends StatefulWidget {
  const DailyShiftsScreen({super.key});

  @override
  State<DailyShiftsScreen> createState() => _DailyShiftsScreenState();
}

class _DailyShiftsScreenState extends State<DailyShiftsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ScheduleProvider>(context, listen: false).fetchShiftsTodayData();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheduleProvider = Provider.of<ScheduleProvider>(context);
    final CategorizedDailyShifts? dailyShifts = scheduleProvider.dailyShiftsToday;

    return Scaffold(
      appBar: AppBar(
        title: Text('Today\'s Schedule (${DateFormat('EEE, MMM d').format(dailyShifts?.todayDate ?? DateTime.now())})'),
        backgroundColor: Colors.green[800],
        actions: [
          HomeButton(),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => scheduleProvider.fetchShiftsTodayData(),
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

          if (dailyShifts == null || dailyShifts.shiftsByRoleCategorized.isEmpty) {
            return const Center(child: Text('No shifts scheduled for today.'));
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: dailyShifts.sortedRoleCategories.map((category) {
                final List<DailyShiftEntry> shiftsForCategory = dailyShifts.shiftsByRoleCategorized[category] ?? [];
                if (shiftsForCategory.isEmpty) return const SizedBox.shrink(); // Hide empty categories

                return Padding(
                  padding: const EdgeInsets.only(bottom: 20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const Divider(),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: shiftsForCategory.length,
                        itemBuilder: (context, index) {
                          final shift = shiftsForCategory[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4.0),
                            elevation: 1,
                            child: ListTile(
                              title: Text(shift.userName, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${shift.assignedShift} ${shift.timeDisplay}'),
                                  Text('Role(s): ${shift.roles.join(', ')}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          );
        },
      ),
    );
  }
}