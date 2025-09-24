// mobile_app/lib/screens/submit_relinquish_shift_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/schedule.dart'; // For ScheduleItem
import '../providers/schedule_provider.dart';
import 'package:intl/intl.dart';
import '../widgets/home_button.dart';

class SubmitRelinquishShiftScreen extends StatefulWidget {
  final ScheduleItem shiftToRelinquish;

  const SubmitRelinquishShiftScreen({super.key, required this.shiftToRelinquish});

  @override
  State<SubmitRelinquishShiftScreen> createState() => _SubmitRelinquishShiftScreenState();
}

class _SubmitRelinquishShiftScreenState extends State<SubmitRelinquishShiftScreen> {
  final _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submitRelinquishRequest() async {
    final scheduleProvider = Provider.of<ScheduleProvider>(context, listen: false);
    try {
      await scheduleProvider.submitRelinquishShift(
        scheduleId: widget.shiftToRelinquish.id!,
        reason: _reasonController.text.isEmpty ? null : _reasonController.text,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shift relinquishment request submitted. Managers notified.')),
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
        title: const Text('Relinquish Shift'),
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
                    'Relinquishing shift:',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 8.0),
                    child: ListTile(
                      title: Text('${widget.shiftToRelinquish.shiftType} ${widget.shiftToRelinquish.formattedTimeDisplay}'),
                      subtitle: Text('on ${widget.shiftToRelinquish.formattedDate}'),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _reasonController,
                    decoration: const InputDecoration(
                      labelText: 'Reason for Relinquishing (Optional)',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 4,
                  ),
                  const SizedBox(height: 30),
                  ElevatedButton(
                    onPressed: scheduleProvider.isLoading ? null : _submitRelinquishRequest,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange[700], // Distinct color for relinquish
                      minimumSize: const Size.fromHeight(50),
                    ),
                    child: scheduleProvider.isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Submit Relinquish Request'),
                  ),
                ],
              ),
            ),
    );
  }
}