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

  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchShiftsForDate(_selectedDate); // Fetch for initial date
    });
  }

  Future<void> _fetchShiftsForDate(DateTime date) async {
    final scheduleProvider = Provider.of<ScheduleProvider>(context, listen: false);
    await scheduleProvider.fetchShiftsTodayData(date);
  }

  void _changeDay(int offset) {
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: offset));
    });
    _fetchShiftsForDate(_selectedDate); // Fetch new data
  }

  @override
  Widget build(BuildContext context) {
    final scheduleProvider = Provider.of<ScheduleProvider>(context);
    final CategorizedDailyShifts? dailyShifts = scheduleProvider.dailyShiftsToday;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      appBar: AppBar(
        title: Text('Today\'s Schedule (${DateFormat('EEE, MMM d').format(_selectedDate)})'), // <--- MODIFIED: Use _selectedDate
        backgroundColor: Theme.of(context).colorScheme.primary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => _fetchShiftsForDate(_selectedDate), // Refresh current day
            color: Theme.of(context).colorScheme.onPrimary,
          ),
          const HomeButton(), // Add Home button
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

          return Column(
            children: [
              // --- NEW: Day Navigation Row ---
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => _changeDay(-1), // Go to previous day
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          DateFormat('EEEE, MMM d, yyyy').format(_selectedDate), // Display full selected date
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.onBackground),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => _changeDay(1), // Go to next day
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white70), // White divider
              // --- END NEW ---

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: dailyShifts.sortedRoleCategories.map((category) {
                      final List<DailyShiftEntry> shiftsForCategory = dailyShifts.shiftsByRoleCategorized[category] ?? [];
                      if (shiftsForCategory.isEmpty) return const SizedBox.shrink();

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              category,
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onBackground), // White text
                            ),
                            const Divider(color: Colors.white70), // White divider
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
          ))]);
        },
      ),
    );
  }
}