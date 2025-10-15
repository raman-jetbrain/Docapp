import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// --- DATA MODEL ---
class CalendarEvent {
  final String title;
  final DateTime date;
  final Color color;

  CalendarEvent({
    required this.title,
    required this.date,
    this.color = const Color(0xFF2196F3),
  });
}

/// --- MOCK DATA ---
final List<CalendarEvent> events = [
  CalendarEvent(
    title: 'Team Meeting',
    date: DateTime(2024, 9, 6),
    color: Colors.blue,
  ),
  CalendarEvent(
    title: 'Doctor Appointment',
    date: DateTime(2024, 9, 12),
    color: Colors.red,
  ),
  CalendarEvent(
    title: 'Birthday Party',
    date: DateTime(2024, 9, 25),
    color: Colors.green,
  ),
  CalendarEvent(
    title: 'Flight to Tokyo',
    date: DateTime(2024, 9, 18),
    color: Colors.amber,
  ),
];

/// --- MAIN FUNCTION ---
void main() {
  runApp(const CalendarApp());
}

/// --- ROOT APP ---
class CalendarApp extends StatelessWidget {
  const CalendarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Table Calendar Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const CalendarPage(),
    );
  }
}

/// --- PAGE WIDGET ---
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime _focusedMonth = DateTime.now();

  List<DateTime?> _generateMonthDays(int year, int month) {
    final firstDay = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final startWeekday = firstDay.weekday; // Monday=1 .. Sunday=7
    // Fill cells to start on Monday and finish Sunday
    final totalCells = ((startWeekday - 1) + daysInMonth + 6) ~/ 7 * 7;

    return List<DateTime?>.generate(totalCells, (index) {
      final dayNumber = index - (startWeekday - 2);
      if (dayNumber < 1 || dayNumber > daysInMonth) return null;
      return DateTime(year, month, dayNumber);
    });
  }

  void _goToNextMonth() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1);
    });
  }

  void _goToPreviousMonth() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final monthDays = _generateMonthDays(_focusedMonth.year, _focusedMonth.month);
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: Text(DateFormat.yMMMM().format(_focusedMonth)),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        actions: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios, size: 18),
            onPressed: _goToPreviousMonth,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios, size: 18),
            onPressed: _goToNextMonth,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildWeekdayHeader(),
          Expanded(
            child: GridView.builder(
              itemCount: monthDays.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1,
              ),
              itemBuilder: (context, index) {
                final date = monthDays[index];
                final dayEvents = events.where((e) =>
                    date != null &&
                    e.date.year == date.year &&
                    e.date.month == date.month &&
                    e.date.day == date.day);
                final isToday = date != null &&
                    date.day == now.day &&
                    date.month == now.month &&
                    date.year == now.year;

                return DateCell(
                  date: date,
                  events: dayEvents.toList(),
                  isToday: isToday,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekdayHeader() {
    final weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Container(
      color: Colors.grey.shade200,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: weekdayLabels
            .map(
              (label) => Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

/// --- DATE CELL WIDGET ---
class DateCell extends StatelessWidget {
  final DateTime? date;
  final List<CalendarEvent> events;
  final bool isToday;

  const DateCell({
    super.key,
    this.date,
    required this.events,
    this.isToday = false,
  });

  @override
  Widget build(BuildContext context) {
    if (date == null) {
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
        ),
      );
    }

    return GestureDetector(
      onTap: events.isEmpty
          ? null
          : () => showModalBottomSheet(
                context: context,
                builder: (context) => _eventDetailsSheet(context),
              ),
      child: Container(
        margin: const EdgeInsets.all(1),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          color: isToday
              ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // day number with optional "today" highlight circle
            Align(
              alignment: Alignment.topLeft,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isToday
                      ? Theme.of(context).colorScheme.primary.withOpacity(0.3)
                      : Colors.transparent,
                ),
                child: Text(
                  '${date!.day}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isToday
                        ? Theme.of(context).colorScheme.primary
                        : Colors.black,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            ...events.map((e) => Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(vertical: 1, horizontal: 2),
                  margin: const EdgeInsets.only(bottom: 2),
                  decoration: BoxDecoration(
                    color: e.color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    e.title,
                    style: const TextStyle(
                      fontSize: 9,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _eventDetailsSheet(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat.yMMMMd().format(date!),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          for (final e in events)
            ListTile(
              leading: CircleAvatar(backgroundColor: e.color),
              title: Text(e.title),
              subtitle:
                  Text(DateFormat.jm().format(e.date)), // just the time portion
            ),
        ],
      ),
    );
  }
}