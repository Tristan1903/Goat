// mobile_app/lib/screens/submit_availability_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/schedule_provider.dart';
import '../models/schedule.dart'; // For ShiftDefinitions, not directly used here but good context
import '../widgets/home_button.dart';

class SubmitAvailabilityScreen extends StatefulWidget {
  const SubmitAvailabilityScreen({super.key});

  @override
  State<SubmitAvailabilityScreen> createState() => _SubmitAvailabilityScreenState();
}

class _SubmitAvailabilityScreenState extends State<SubmitAvailabilityScreen> {
  // Store the state of checkboxes: { 'date_iso': { 'shift_type': bool } }
  final Map<String, Map<String, bool>> _selectedAvailability = {};

  // Track start/end of the submission window
  DateTime? _submissionWindowStart;
  DateTime? _submissionWindowEnd;
  String _nextWeekStartDate = ''; // ISO string for the start of the next week

  // Shift types available for staff to submit (Day, Night, Double)
  final List<String> _staffSubmissionShiftTypes = ['Day', 'Night', 'Double'];

  // Timer for the countdown display
  Duration _timeToWindowChange = Duration.zero;
  // Unique key to rebuild TweenAnimationBuilder if duration changes
  // This helps restart the timer correctly.
  int? _timerKey; 

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeAvailabilityData();
    });
  }

  // --- Initialize Availability Data and Window Status ---
  Future<void> _initializeAvailabilityData() async {
    final scheduleProvider = Provider.of<ScheduleProvider>(context, listen: false);
    await Future.wait([
      scheduleProvider.fetchAvailabilityWindowStatus(),
      scheduleProvider.fetchMyAvailability(),
    ]);

    setState(() {
      _submissionWindowStart = DateTime.parse(scheduleProvider.availabilityWindowStatus['start_time_utc'] as String).toUtc();
      _submissionWindowEnd = DateTime.parse(scheduleProvider.availabilityWindowStatus['end_time_utc'] as String).toUtc();
      _nextWeekStartDate = scheduleProvider.availabilityWindowStatus['next_week_start_date'] as String;

      final myAvailability = scheduleProvider.myAvailability;

      // --- MODIFIED: Use availabilitySubmissionWeekDates for initialization ---
      for (var day in scheduleProvider.availabilitySubmissionWeekDates) {
        final dateStr = day.toIso8601String().substring(0, 10);
        _selectedAvailability.putIfAbsent(dateStr, () => {});
        for (var shiftType in _staffSubmissionShiftTypes) {
          _selectedAvailability[dateStr]![shiftType] = false;
        }
        
        final List<String> submittedShiftsForDay = myAvailability[dateStr] ?? [];
        for (var submittedShiftType in submittedShiftsForDay) {
          if (submittedShiftType == 'Double') {
            _selectedAvailability[dateStr]!['Day'] = true;
            _selectedAvailability[dateStr]!['Night'] = true;
            _selectedAvailability[dateStr]!['Double'] = true;
          } else {
            if (_staffSubmissionShiftTypes.contains(submittedShiftType)) {
              _selectedAvailability[dateStr]![submittedShiftType] = true;
            }
          }
        }
      }
      // --- END MODIFIED ---
      _updateTimerDuration();
    });
  }

  // --- Checkbox Changed Logic ---
  void _onCheckboxChanged(String dateStr, String shiftType, bool? newValue) {
    setState(() {
      _selectedAvailability.putIfAbsent(dateStr, () => {});
      _selectedAvailability[dateStr]![shiftType] = newValue ?? false;

      // Ensure Day/Night/Double checkboxes reflect consolidation logic
      final bool isDayChecked = _selectedAvailability[dateStr]!['Day'] ?? false;
      final bool isNightChecked = _selectedAvailability[dateStr]!['Night'] ?? false;

      if (shiftType == 'Double') {
        // If Double is checked/unchecked, update Day and Night to match
        _selectedAvailability[dateStr]!['Day'] = newValue ?? false;
        _selectedAvailability[dateStr]!['Night'] = newValue ?? false;
      } else {
        // If Day/Night is changed, update Double based on both
        _selectedAvailability[dateStr]!['Double'] = isDayChecked && isNightChecked;
      }
    });
  }

  // --- Submit Availability ---
  Future<void> _submitAvailability() async {
    final List<String> shiftsToSubmit = [];
    _selectedAvailability.forEach((dateStr, typesMap) {
      // Only send Day and Night. Backend will consolidate into Double.
      // This ensures we don't send conflicting "Day", "Night", and "Double".
      if (typesMap['Day'] == true) {
        shiftsToSubmit.add('${dateStr}_Day');
      }
      if (typesMap['Night'] == true) {
        shiftsToSubmit.add('${dateStr}_Night');
      }
    });

    final scheduleProvider = Provider.of<ScheduleProvider>(context, listen: false);
    try {
      await scheduleProvider.submitMyAvailability(shiftsToSubmit);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Availability submitted successfully!')),
      );
      Navigator.of(context).pop(); // Go back
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error submitting availability: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
  }

  // --- Countdown Timer Logic (Replicated from web) ---
  String _formatDuration(Duration duration) {
    if (duration.isNegative) return "00:00:00";
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final days = duration.inDays;
    final hours = twoDigits(duration.inHours.remainder(24));
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return days > 0 ? "${days}d $hours:$minutes:$seconds" : "$hours:$minutes:$seconds";
  }

  // Updates the internal timer duration and forces a rebuild of the TweenAnimationBuilder
  void _updateTimerDuration() {
    if (_submissionWindowStart == null || _submissionWindowEnd == null) {
      _timeToWindowChange = Duration.zero;
      _timerKey = 0; // Reset key
      return;
    }

    final now = DateTime.now().toUtc(); // Use UTC for consistent comparison

    if (now.isBefore(_submissionWindowStart!)) {
      _timeToWindowChange = _submissionWindowStart!.difference(now);
    } else if (now.isAfter(_submissionWindowStart!) && now.isBefore(_submissionWindowEnd!)) {
      _timeToWindowChange = _submissionWindowEnd!.difference(now);
    } else {
      _timeToWindowChange = Duration.zero; // Window is closed
    }
    // Update key to ensure TweenAnimationBuilder restarts when duration changes
    // A simple hash code of the duration works as a unique key for the widget.
    _timerKey = _timeToWindowChange.inSeconds.hashCode; 
  }


  @override
  Widget build(BuildContext context) {
    // --- CRITICAL FIX: Add initial null check for crucial DateTime objects ---
    // This ensures the UI doesn't try to build until these are initialized from API.
    if (_submissionWindowStart == null || _submissionWindowEnd == null || _nextWeekStartDate.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Submit Availability'), backgroundColor: Colors.green[800]),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    // --- END CRITICAL FIX ---

    final scheduleProvider = Provider.of<ScheduleProvider>(context);
    final bool isWindowOpen = scheduleProvider.availabilityWindowStatus['is_open'] ?? false;
    
    String timerMessage;
    Color timerColor;
    final now = DateTime.now().toUtc();

    if (now.isBefore(_submissionWindowStart!)) {
      timerMessage = "Submission window opens in: ";
      timerColor = Colors.orange; // Warning
    } else if (now.isAfter(_submissionWindowStart!) && now.isBefore(_submissionWindowEnd!)) {
      timerMessage = "Submission window closes in: ";
      timerColor = Colors.green; // Success
    } else {
      timerMessage = "Submission window is closed.";
      timerColor = Colors.red; // Danger
    }
    

    // Filter week dates to only show Tuesday-Sunday (as per web UI and schedule logic)
    final List<DateTime> displayWeekDates = scheduleProvider.availabilitySubmissionWeekDates
      .where((date) => date.weekday != DateTime.monday) // Exclude Monday
      .toList();
    
    print('DEBUG (SubmitAvailabilityScreen): scheduleProvider.myScheduleWeekDates (from Provider): ${scheduleProvider.myScheduleWeekDates}'); // <--- ADD THIS
    print('DEBUG (SubmitAvailabilityScreen): displayWeekDates (filtered Tue-Sun): $displayWeekDates');


    return Scaffold(
      appBar: AppBar(
        title: Text('Submit Availability for Week Starting ${DateFormat('MMM d, yyyy').format(DateTime.parse(_nextWeekStartDate))}'),
        backgroundColor: Colors.green[800],
        actions: const [
        HomeButton(),
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
          
          return Column(
            children: [
              // --- Submission Window Timer ---
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12.0),
                margin: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: timerColor.withOpacity(0.1),
                  border: Border.all(color: timerColor),
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Column(
                  children: [
                    Text(
                      'Submission window for week starting ${DateFormat('MMM d, yyyy').format(DateTime.parse(_nextWeekStartDate))}',
                      style: Theme.of(context).textTheme.titleSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    // Use a unique key to force TweenAnimationBuilder to restart when duration changes
                    TweenAnimationBuilder<Duration>(
                      key: ValueKey(_timerKey), // <--- Use the new key
                      duration: _timeToWindowChange, // <--- Use the state variable
                      tween: Tween(begin: _timeToWindowChange, end: Duration.zero),
                      onEnd: () {
                        // Refresh status when timer ends
                        scheduleProvider.fetchAvailabilityWindowStatus();
                        _updateTimerDuration(); // Recalculate timer and force rebuild
                      },
                      builder: (BuildContext context, Duration value, Widget? child) {
                        return Text(
                          '$timerMessage ${_formatDuration(value)}',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: timerColor,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const Divider(),

              // --- Availability Table ---
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width),
                    child: DataTable(
                      headingRowHeight: 80,
                      columnSpacing: 12,
                      columns: [
                        const DataColumn(label: Text('Shift Type', style: TextStyle(fontWeight: FontWeight.bold))),
                        // --- CRITICAL: Use displayWeekDates here ---
                        ...displayWeekDates.map((day) => DataColumn(
                          label: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(DateFormat('EEE').format(day), style: const TextStyle(fontWeight: FontWeight.bold)),
                              Text(DateFormat('MMM d').format(day), style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                        )),
                        // --- END CRITICAL ---
                      ],
                      rows: _staffSubmissionShiftTypes.map((shiftType) {
                        return DataRow(
                          cells: [
                            DataCell(Text(shiftType, style: const TextStyle(fontWeight: FontWeight.bold))),
                            // --- CRITICAL: Use displayWeekDates here ---
                            ...displayWeekDates.map((day) {
                              final dateStr = day.toIso8601String().substring(0, 10);
                              final bool isSelected = _selectedAvailability[dateStr]?[shiftType] ?? false;
                              
                              final DateTime todayUtcMidnight = DateTime.now().toUtc().copyWith(
                                hour: 0, minute: 0, second: 0, millisecond: 0, microsecond: 0);
                              final bool isDayInPast = day.isBefore(todayUtcMidnight);

                              final bool isDisabled = !isWindowOpen || isDayInPast;

                              return DataCell(
                                Center(
                                  child: Checkbox(
                                    value: isSelected,
                                    onChanged: isDisabled ? null : (newValue) {
                                      _onCheckboxChanged(dateStr, shiftType, newValue);
                                    },
                                    activeColor: Colors.green[800],
                                    checkColor: Colors.white,
                                  ),
                                ),
                              );
                            }).toList(),
                            // --- END CRITICAL FIX ---
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
              // --- Submit Button ---
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: ElevatedButton(
                  onPressed: isWindowOpen && !schedule.isLoading ? _submitAvailability : null,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                  child: schedule.isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Submit Availability'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}