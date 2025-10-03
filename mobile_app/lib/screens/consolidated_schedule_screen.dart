// mobile_app/lib/screens/consolidated_schedule_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/schedule_provider.dart';
import '../models/schedule.dart'; // ScheduleItem, ShiftDefinitions
import '../models/shift_management.dart'; // <--- NEW IMPORT: For SchedulerUser, StaffingStatus
import '../utils/string_extensions.dart'; // For toTitleCase()
import '../widgets/home_button.dart';

class ConsolidatedScheduleScreen extends StatefulWidget {
  final String initialViewType; // e.g., 'boh', 'foh', 'managers', 'bartenders_only'

  const ConsolidatedScheduleScreen({
    super.key,
    required this.initialViewType,
  });

  @override
  State<ConsolidatedScheduleScreen> createState() => _ConsolidatedScheduleScreenState();
}

class _ConsolidatedScheduleScreenState extends State<ConsolidatedScheduleScreen> {
  String _displayRoleNameForRules = 'manager';

  Map<String, List<SchedulerUser>> _groupedUsers = {};
  List<String> _sortedRoleGroups = [];

  final List<Map<String, String>> _viewTypes = [
    {'value': 'boh', 'label': 'Back of House (BOH)'},
    {'value': 'foh', 'label': 'Front of House (FOH)'},
    {'value': 'managers', 'label': 'Managers'},
    {'value': 'bartenders_only', 'label': 'Bartenders Only'},
    {'value': 'waiters_only', 'label': 'Waiters Only'},
    {'value': 'skullers_only', 'label': 'Skullers Only'},
  ];


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeConsolidatedScheduleData(widget.initialViewType, 0); // Current week
      Provider.of<ScheduleProvider>(context, listen: false).fetchShiftDefinitions();
    });
  }

  Future<void> _initializeConsolidatedScheduleData(String viewType, int weekOffset) async {
    final scheduleProvider = Provider.of<ScheduleProvider>(context, listen: false);
    await scheduleProvider.fetchConsolidatedSchedule(viewType, weekOffset);
    _updateDisplayRoleNameForRules(viewType);

    if (scheduleProvider.usersInCategory.isNotEmpty) {
      _groupUsersByRole(scheduleProvider.usersInCategory);
    }
    setState(() {});
  }

  void _updateDisplayRoleNameForRules(String viewType) {
    setState(() {
      if (viewType == 'boh' || viewType == 'bartenders_only') _displayRoleNameForRules = 'bartender';
      else if (viewType == 'foh' || viewType == 'waiters_only') _displayRoleNameForRules = 'waiter';
      else if (viewType == 'skullers_only') _displayRoleNameForRules = 'skullers';
      else if (viewType == 'managers') _displayRoleNameForRules = 'manager';
      else _displayRoleNameForRules = 'manager';
    });
  }

  Future<void> _changeWeek(int offset) async {
    final scheduleProvider = Provider.of<ScheduleProvider>(context, listen: false);
    await _initializeConsolidatedScheduleData(
        scheduleProvider.currentConsolidatedViewType, scheduleProvider.currentConsolidatedWeekOffset + offset);
  }

  Future<void> _changeViewType(String newViewType) async {
    await _initializeConsolidatedScheduleData(newViewType, 0);
  }

  Future<void> _showShiftRulesModal() async {
    final scheduleProvider = Provider.of<ScheduleProvider>(context, listen: false);
    final shiftDefinitions = scheduleProvider.shiftDefinitions;

    if (shiftDefinitions == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shift definitions not loaded yet.')),
      );
      return;
    }

    final roleShiftDefs = shiftDefinitions.roleShiftDefinitions[_displayRoleNameForRules] ?? shiftDefinitions.roleShiftDefinitions['manager'];
    if (roleShiftDefs == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No shift rules found for role: $_displayRoleNameForRules.')),
      );
      return;
    }

    List<Widget> shiftRuleWidgets = [];
    final weekDays = ['Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

    for (var dayName in weekDays) {
      final daySpecificDefs = roleShiftDefs[dayName] ?? roleShiftDefs['default'];
      if (daySpecificDefs != null) {
        shiftRuleWidgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Text(
              '${dayName}:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        );
        daySpecificDefs.forEach((shiftType, times) {
          shiftRuleWidgets.add(
            Padding(
              padding: const EdgeInsets.only(left: 8.0, bottom: 2.0),
              child: Text('- $shiftType: ${times['start']} - ${times['end']}'),
            ),
          );
        });
      }
    }

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Shift Assignment Rules for ${_displayRoleNameForRules.toTitleCase()}s'),
          content: SingleChildScrollView(
            child: ListBody(
              children: [
                const Text('General Guidelines:', style: TextStyle(fontWeight: FontWeight.bold)),
                const Text('- All leave requests to be done by WEDNESDAY THE WEEK PRIOR.'),
                const Text('- In case of absence, contact management 24 HOURS prior.'),
                const Text('- Roster is subject to change. Staff will be informed.'),
                const Divider(),
                const Text('Defined Shift Times:', style: TextStyle(fontWeight: FontWeight.bold)),
                ...shiftRuleWidgets,
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Close'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _groupUsersByRole(List<SchedulerUser> users) {
    _groupedUsers.clear(); // Clear previous groups
    _sortedRoleGroups.clear(); // Clear previous order

    // Define a consistent order of priority for display groups
    // 'Hostess' has highest priority if user has multiple roles
    // 'Managers' includes manager, general_manager, system_admin
    // Then standard staff roles
    final List<String> roleGroupOrder = [
      'Managers', // Includes manager, general_manager, system_admin
      'Hostess',
      'Bartenders',
      'Waiters',
      'Skullers',
    ];

    for (var user in users) {
      String primaryGroup = 'Other Staff'; // Default fallback

      // Priority 1: Hostess
      if (user.roles.contains('hostess')) {
        primaryGroup = 'Hostess';
      }
      // Priority 2: Managers (Manager, General Manager, System Admin)
      else if (user.roles.any((role) => ['manager', 'general_manager', 'system_admin'].contains(role))) {
        primaryGroup = 'Managers';
      }
      // Priority 3: Specific staff roles
      else if (user.roles.contains('bartender')) {
        primaryGroup = 'Bartenders';
      } else if (user.roles.contains('waiter')) {
        primaryGroup = 'Waiters';
      } else if (user.roles.contains('skullers')) {
        primaryGroup = 'Skullers';
      }
      
      _groupedUsers.putIfAbsent(primaryGroup, () => []).add(user);
    }

    // Sort the group keys based on predefined order, then alphabetically for any others
    _sortedRoleGroups = _groupedUsers.keys.toList();
    _sortedRoleGroups.sort((a, b) {
      final int indexA = roleGroupOrder.indexOf(a);
      final int indexB = roleGroupOrder.indexOf(b);

      if (indexA != -1 && indexB != -1) {
        return indexA.compareTo(indexB);
      } else if (indexA != -1) {
        return -1; // A comes first
      } else if (indexB != -1) {
        return 1; // B comes first
      } else {
        return a.compareTo(b); // Alphabetical for unlisted groups
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheduleProvider = Provider.of<ScheduleProvider>(context);
    final consolidatedData = scheduleProvider.consolidatedScheduleData;
    final String currentViewType = scheduleProvider.currentConsolidatedViewType;

    String weekLabel;
    if (scheduleProvider.currentConsolidatedWeekOffset == 0) {
      weekLabel = 'Current Week';
    } else if (scheduleProvider.currentConsolidatedWeekOffset == 1) {
      weekLabel = 'Next Week';
    } else if (scheduleProvider.currentConsolidatedWeekOffset == -1) {
      weekLabel = 'Previous Week';
    } else {
      weekLabel = 'Week Offset ${scheduleProvider.currentConsolidatedWeekOffset}';
    }

    if (consolidatedData.isEmpty || scheduleProvider.shiftDefinitions == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Consolidated Schedule'), backgroundColor: Colors.green[800]),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    
    final String consolidatedLabel = consolidatedData['consolidated_label'] as String;
    final DateTime weekStart = DateTime.parse(consolidatedData['week_start'] as String);
    final List<DateTime> weekDates = (consolidatedData['week_dates'] as List<dynamic>).map((e) => DateTime.parse(e as String)).toList();
    final List<DateTime> displayDates = (consolidatedData['display_dates'] as List<dynamic>).map((e) => DateTime.parse(e as String)).toList();
    final List<SchedulerUser> usersInCategory = scheduleProvider.usersInCategory;

    _groupUsersByRole(usersInCategory);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background, // Should be dark blue-grey from global theme
      appBar: AppBar(
        title: Text(consolidatedLabel),
        backgroundColor: Theme.of(context).colorScheme.primary, // Primary color (bright blue)
        actions: [        
        HomeButton(),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'View Shift Rules',
            onPressed: _showShiftRulesModal,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Schedule',
            onPressed: () => _initializeConsolidatedScheduleData(currentViewType, scheduleProvider.currentConsolidatedWeekOffset),
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

          if (usersInCategory.isEmpty) {
            return Center(child: Text('No users found for $consolidatedLabel.'));
          }

          return Column(
            children: [
              // View Type Selector
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: DropdownButtonFormField<String>(
                  value: currentViewType,
                  decoration: InputDecoration(
                    labelText: 'View Type',
                    labelStyle: TextStyle(color: Theme.of(context).colorScheme.onBackground), // White label
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Theme.of(context).colorScheme.primary), // Use primary for border
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Theme.of(context).colorScheme.secondary, width: 2), // Secondary for focused
                    ),// Label text color
                  ),
                  dropdownColor: Theme.of(context).colorScheme.background, // Dropdown menu background color
                  style: TextStyle(color: Theme.of(context).colorScheme.onBackground), // Dropdown item text color
                  items: _viewTypes.map((type) {
                    return DropdownMenuItem(
                      value: type['value'],
                      child: Text(type['label']!, style: TextStyle(color: Theme.of(context).colorScheme.onBackground)), // Dropdown item text color
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    if (newValue != null && newValue != currentViewType) {
                      _changeViewType(newValue);
                    }
                  },
                ),
              ),
              const Divider(color: Colors.white70),

              // Consolidated Schedule Table (User-by-Day Grid)
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(8.0),
                  itemCount: _sortedRoleGroups.length,
                  itemBuilder: (context, groupIndex) {
                    final String groupName = _sortedRoleGroups[groupIndex];
                    final List<SchedulerUser> usersInGroup = _groupedUsers[groupName]!;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Group Header (e.g., "Bartenders")
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
                          margin: const EdgeInsets.only(bottom: 8.0),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.background, // Dark background
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          child: Text(
                            groupName,
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onBackground, // White text
                            ),
                          ),
                        ),
                        // DataTable for users within this group
                        Card( // <--- THIS CARD WRAPS THE DATATABLE FOR THE GROUP
                          margin: EdgeInsets.zero, // Remove card margins so background shows
                          color: Color.fromRGBO(64, 170, 136, 1), // Match the dark background
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)), // Rounded corners for the card
                          child: Padding(
                            padding: const EdgeInsets.all(0.0), // No padding inside card
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 16),
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 16.0), // Adjust this value as needed
                                  child: DataTable(
                                    columnSpacing: 12,
                                    headingRowHeight: 60,
                                    dataRowMinHeight: 60,
                                    dataRowMaxHeight: 80,
                                    dividerThickness: 1,
                                    horizontalMargin: 0,
                                    headingRowColor: MaterialStateProperty.resolveWith<Color>((Set<MaterialState> states) {
                                      return Theme.of(context).colorScheme.background;
                                    }),

                                  columns: [
                                    DataColumn(
                                      label: SizedBox(
                                        width: 120,
                                        child:                                         
                                        Text('Staff', 
                                          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onBackground)
                                          ),
                                      ),
                                    ),
                                    ...displayDates.map((day) {
                                      return DataColumn(
                                        label: SizedBox(
                                          width: 120,
                                          child: Text(DateFormat('EEE, MMM d').format(day), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white), textAlign: TextAlign.center), // White text for day headers
                                        ),
                                      );
                                    }).toList(),
                                  ],
                                  rows: usersInGroup.map((user) {
                                    return DataRow(
                                      color: MaterialStateProperty.resolveWith<Color>((Set<MaterialState> states) {
                                        return Color.fromRGBO(64, 170, 136, 1);
                                      }),
                                      cells: [
                                        DataCell(
                                          SizedBox(
                                            width: 120,
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(user.fullName, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold, color: Color.fromRGBO(65, 65, 65, 1))), // Bright blue text
                                                Text(user.roles.map((r) => r.toTitleCase()).join(', '), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7))), // Grey text
                                              ],
                                            ),
                                          ),
                                        ),
                                        ...displayDates.map((day) {
                                          final List<ScheduleItem> shiftsOnDay = schedule.getConsolidatedShiftsForUserAndDate(user.id, day);
                                          final String dayName = DateFormat('EEEE').format(day);

                                          return DataCell(
                                            SizedBox(
                                              width: 120,
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  if (shiftsOnDay.isEmpty)
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                      decoration: BoxDecoration(
                                                        color: Colors.red.withOpacity(0.1),
                                                        borderRadius: BorderRadius.circular(4),
                                                        border: Border.all(color: Colors.red.withOpacity(0.3)),
                                                      ),
                                                      child: Text(
                                                        'OFF',
                                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.red.shade400),
                                                      ),
                                                    )
                                                  else
                                                    ...shiftsOnDay.map((shift) {
                                                      final String timeDisplay = schedule.getFormattedShiftTimeDisplay(
                                                        _displayRoleNameForRules,
                                                        dayName,
                                                        shift.shiftType,
                                                        customStart: shift.startTimeStr,
                                                        customEnd: shift.endTimeStr,
                                                      );
                                                      return Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                        decoration: BoxDecoration(
                                                          color: Colors.green.withOpacity(0.1),
                                                          borderRadius: BorderRadius.circular(4),
                                                          border: Border.all(color: Colors.green.withOpacity(0.3)),
                                                        ),
                                                        child: Text(
                                                          '${shift.shiftType} $timeDisplay',
                                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.green.shade400),
                                                          overflow: TextOverflow.ellipsis,
                                                          maxLines: 2,
                                                        ),
                                                      );
                                                    }).toList(),
                                                  // TODO: Add on-leave indicator here if needed (from ScheduleItem)
                                                ],
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                      ],
                                    );
                                  }).toList(),
                              ),
                            ),
                          ),
                        ),
                      )// const SizedBox(height: 20), // Spacing between groups, outside the Card
                    )],
                    );
                  },
                ),
              ),
            ]
          );
        }
      )
    );
  }
}