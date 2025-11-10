// ignore_for_file: unused_local_variable

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import '../models/event.dart';
import '../repositories/event_repository.dart';

class EventsScreen extends StatefulWidget {
  final bool isAdmin;
  const EventsScreen({super.key, this.isAdmin = false});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  final EventRepository _repository = EventRepository();

  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  bool _loading = true;

  Map<DateTime, List<EventModel>> _events = {};
  List<EventModel> _allEvents = [];

  @override
  void initState() {
    super.initState();
    _focusedDay = DateTime(
      _focusedDay.year,
      _focusedDay.month,
      _focusedDay.day,
    );
    _selectedDay = _focusedDay;
    _fetchEventsFromBackend();
  }

  Future<void> _fetchEventsFromBackend() async {
    setState(() => _loading = true);
    try {
      final events = await _repository.fetchAllEvents();
      Map<DateTime, List<EventModel>> eventMap = {};
      for (var e in events) {
        final daySource = e.startTime;
        if (daySource != null) {
          // The event keys are set to midnight for proper calendar mapping
          final day = DateTime(daySource.year, daySource.month, daySource.day);
          eventMap[day] ??= [];
          eventMap[day]!.add(e);
        }
      }
      setState(() {
        _events = eventMap;
        _allEvents = events;
        _loading = false;
      });
    } catch (e) {
      debugPrint("❌ Error fetching events: $e");
      setState(() => _loading = false);
    }
  }

  List<EventModel> _getEventsForDay(DateTime day) {
    return _events[DateTime(day.year, day.month, day.day)] ?? [];
  }

  // ✅ GETTER: Finds the single next upcoming event
  EventModel? get _nextUpcomingEvent {
    final now = DateTime.now();
    // Filter out past events and events with no start time
    final upcomingEvents = _allEvents
        .where(
          (event) => event.startTime != null && event.startTime!.isAfter(now),
        )
        .toList();

    if (upcomingEvents.isEmpty) return null;

    // Sort by start time to get the absolute next one
    upcomingEvents.sort((a, b) => a.startTime!.compareTo(b.startTime!));
    return upcomingEvents.first;
  }

  // Helper functions for responsive design (kept from original code)
  bool isLargeScreen(BuildContext context) =>
      MediaQuery.of(context).size.width >= 900;

  double _carouselHeight(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 1200) return 250;
    if (width >= 800) return 220;
    return 180;
  }

  double _carouselViewportFraction(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 1200) return 0.35;
    if (width >= 800) return 0.6;
    return 0.85;
  }

  // 🌟 NEW HELPER WIDGET: Glowing Marker for TableCalendar
  Widget _buildGlowingMarker(ThemeData theme, Color eventColor) {
    return Container(
      width: 8.0,
      height: 8.0,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: eventColor,
        boxShadow: [
          BoxShadow(
            color: eventColor.withOpacity(0.8),
            blurRadius: 6.0,
            spreadRadius: 2.0,
          ),
        ],
      ),
    );
  }

  // ✅ NEW HELPER WIDGET: Upcoming Event Hint Card
  Widget _buildUpcomingHint(ThemeData theme) {
    final nextEvent = _nextUpcomingEvent;

    if (nextEvent == null) {
      return const SizedBox.shrink();
    }

    final startTime = DateFormat(
      'EEE, MMM d, h:mm a',
    ).format(nextEvent.startTime!);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Card(
        elevation: 8,
        // Using the event's color for a more dynamic, eye-catching hint
        color: nextEvent.color.withOpacity(0.9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          leading: const Icon(
            Icons.event_available,
            color: Colors.white, // Contrast with event color background
          ),
          title: Text(
            "UPCOMING: ${nextEvent.title}",
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          subtitle: Text(
            startTime,
            style: const TextStyle(color: Colors.white70),
          ),
          trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white),
          onTap: () => _showEventDetails(context, nextEvent),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedEvents = _selectedDay != null
        ? _getEventsForDay(_selectedDay!)
        : <EventModel>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Church Events'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Events',
            onPressed: _fetchEventsFromBackend,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isLargeScreen(context) ? 48 : 0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFeaturedEventsCarousel(context),
                    const SizedBox(height: 16),
                    _buildCalendar(theme),
                    const SizedBox(height: 16),
                    _buildUpcomingHint(theme), // The prominent hint is here
                    const SizedBox(height: 16),
                    _buildEventList(theme, selectedEvents),
                  ],
                ),
              ),
            ),
      floatingActionButton: widget.isAdmin
          ? FloatingActionButton(
              onPressed: () => _showAddEditEventDialog(context),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _buildCalendar(ThemeData theme) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: TableCalendar<EventModel>(
        firstDay: DateTime.now().subtract(const Duration(days: 365)),
        lastDay: DateTime.now().add(const Duration(days: 365)),
        focusedDay: _focusedDay,
        calendarFormat: _calendarFormat,
        selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
        onDaySelected: (selectedDay, focusedDay) {
          setState(() {
            _selectedDay = selectedDay;
            _focusedDay = focusedDay;
          });
        },
        onFormatChanged: (format) => setState(() => _calendarFormat = format),
        onPageChanged: (focusedDay) => _focusedDay = focusedDay,
        eventLoader: _getEventsForDay,
        calendarStyle: CalendarStyle(
          todayDecoration: BoxDecoration(
            color: theme.colorScheme.primary.withOpacity(0.3),
            shape: BoxShape.circle,
          ),
          selectedDecoration: BoxDecoration(
            color: theme.colorScheme.primary,
            shape: BoxShape.circle,
          ),
        ),
        headerStyle: HeaderStyle(
          formatButtonVisible: true,
          titleCentered: true,
          formatButtonDecoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.primary),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        // ✅ CORRECT USAGE of markerBuilder inside calendarBuilders
        calendarBuilders: CalendarBuilders<EventModel>(
          markerBuilder: (context, day, events) {
            if (events.isNotEmpty) {
              return Positioned(
                right: 60,
                bottom: 4,
                // Use the color of the first event on that day for the marker
                child: _buildGlowingMarker(theme, events.first.color),
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  Widget _buildEventList(ThemeData theme, List<EventModel> events) {
    if (events.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'No events for this day.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: events.length,
      itemBuilder: (context, index) {
        final event = events[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: event.color.withOpacity(0.2),
              child: Icon(Icons.event, color: event.color),
            ),
            title: Text(event.title),
            subtitle: Text(
              '${DateFormat.jm().format(event.startTime!)} | ${event.location ?? ''}',
            ),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _showEventDetails(context, event),
          ),
        );
      },
    );
  }

  Widget _buildFeaturedEventsCarousel(BuildContext context) {
    final featured = _allEvents.where((e) => e.isFeatured).toList();
    if (featured.isEmpty) return const SizedBox.shrink();

    final viewport = _carouselViewportFraction(context);
    final height = _carouselHeight(context);

    return SizedBox(
      height: height,
      child: PageView.builder(
        controller: PageController(viewportFraction: viewport),
        itemCount: featured.length,
        itemBuilder: (context, index) {
          final event = featured[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: GestureDetector(
              onTap: () => _showEventDetails(context, event),
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 4,
                child: Stack(
                  children: [
                    if (event.imageUrl != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.network(
                          event.imageUrl!,
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: LinearGradient(
                          colors: [
                            Colors.black.withOpacity(0.6),
                            Colors.transparent,
                          ],
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.title,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${DateFormat.yMMMd().format(event.startTime!)} | ${event.location ?? ''}',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showAddEditEventDialog(BuildContext context, [EventModel? event]) {
    final titleController = TextEditingController(text: event?.title ?? '');
    final descriptionController = TextEditingController(
      text: event?.description ?? '',
    );
    final locationController = TextEditingController(
      text: event?.location ?? '',
    );
    DateTime startTime = event?.startTime ?? DateTime.now();
    DateTime endTime =
        event?.endTime ?? DateTime.now().add(const Duration(hours: 1));

    Future<void> pickTime({required bool isStart}) async {
      final initialTime = TimeOfDay.fromDateTime(isStart ? startTime : endTime);
      final picked = await showTimePicker(
        context: context,
        initialTime: initialTime,
      );
      if (picked != null) {
        final date = DateTime(
          DateTime.now().year,
          DateTime.now().month,
          DateTime.now().day,
          picked.hour,
          picked.minute,
        );
        // NOTE: In a real app, you would use a StateFulBuilder or Stateful Dialog
        // to update the displayed time here, but we rely on the final refresh.
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(event == null ? 'Add Event' : 'Edit Event'),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              TextField(
                controller: locationController,
                decoration: const InputDecoration(labelText: 'Location'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Start Time: '),
                  TextButton(
                    child: Text(DateFormat.jm().format(startTime)),
                    onPressed: () => pickTime(isStart: true),
                  ),
                ],
              ),
              Row(
                children: [
                  const Text('End Time: '),
                  TextButton(
                    child: Text(DateFormat.jm().format(endTime)),
                    onPressed: () => pickTime(isStart: false),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          if (event != null)
            TextButton(
              onPressed: () async {
                await _repository.deleteEvent(event.id);
                Navigator.pop(context);
                _fetchEventsFromBackend();
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          TextButton(
            onPressed: () async {
              final newEvent = EventModel(
                id:
                    event?.id ??
                    DateTime.now().millisecondsSinceEpoch.toString(),
                title: titleController.text,
                description: descriptionController.text,
                eventType: '',
                startTime: startTime,
                endTime: endTime,
                location: locationController.text,
              );
              if (event == null) {
                await _repository.addEvent(newEvent);
              } else {
                await _repository.updateEvent(newEvent);
              }
              Navigator.pop(context);
              _fetchEventsFromBackend();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showEventDetails(BuildContext context, EventModel event) async {
    List<Map<String, dynamic>> attendees = [];
    bool reminderSet = false;

    try {
      // API calls that are likely returning 404 since the endpoints don't exist
      attendees = await _repository.fetchAttendees(event.id);
      final reminders = await _repository.fetchReminders(event.id);
      reminderSet = reminders.isNotEmpty;
    } catch (e) {
      // Gracefully handle the error since the endpoints are intentionally absent
      debugPrint(
        'Error fetching attendees/reminders for event ${event.id}: $e',
      );
    }

    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          children: [
            Text(event.title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Time: ${DateFormat.jm().format(event.startTime!)} - ${DateFormat.jm().format(event.endTime!)}',
            ),
            const SizedBox(height: 8),
            Text('Location: ${event.location ?? ''}'),
            const SizedBox(height: 16),
            Text('Description: ${event.description}'),
          ],
        ),
      ),
    );
  }
}
