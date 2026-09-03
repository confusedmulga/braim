import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/note.dart';

/// Schedules the local notifications behind note reminders. Everything is
/// best-effort: on a device without notification support (or a denied
/// permission) the calls simply no-op so the rest of the app is unaffected.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _tried = false;

  static const _channelId = 'braim_reminders';
  static const _journalChannelId = 'braim_journal';
  static const _taskChannelId = 'braim_daily';
  static const _focusChannelId = 'braim_focus';

  /// A fixed id for the one repeating daily-journal nudge.
  static const int _journalDailyId = 424242;

  /// The single focus-timer notification (updated in place across phases) and
  /// the payload that opens the timer when it's tapped.
  static const int _focusOngoingId = 900001;
  static const String focusPayload = 'focus';

  /// Brand accent tinting the small icon and app name in the notification.
  static const _accent = Color(0xFF3D6EF7);

  /// Called when a notification (or one of its action buttons) is tapped, with
  /// the payload and the action id. Wired up by the app so the focus
  /// notification can open the timer or toggle play/pause.
  static void Function(String? payload, String? actionId)? onSelect;

  Future<void> init() async {
    // Attempt the platform setup at most once; if it fails (e.g. no plugin in
    // a test), every later call quietly no-ops instead of retrying.
    if (_ready || _tried) return;
    _tried = true;
    try {
      tzdata.initializeTimeZones();
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      // Fall back to UTC; reminders still fire, just relative to UTC.
    }
    try {
      // Small (status-bar) icon must be a white-on-transparent silhouette;
      // the full-colour @mipmap/ic_launcher is invalid here and made
      // notifications render blank / drop on some devices.
      const android = AndroidInitializationSettings('ic_stat_braim');
      const settings = InitializationSettings(android: android);
      await _plugin.initialize(
        settings,
        onDidReceiveNotificationResponse: (response) =>
            onSelect?.call(response.payload, response.actionId),
      );
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  /// Asks for the notification permission (Android 13+). Returns false if it
  /// isn't granted; callers can surface that to the user.
  Future<bool> requestPermission() async {
    if (!_ready) await init();
    if (!_ready) return false;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android == null) return true;
      final granted = await android.requestNotificationsPermission() ?? true;
      // Also ask to schedule exact alarms so reminders fire on time rather than
      // in an inexact (Doze-deferred) window. Best-effort; ignored where the
      // OS auto-grants it (Android 13+ via USE_EXACT_ALARM).
      try {
        await android.requestExactAlarmsPermission();
      } catch (_) {}
      return granted;
    } catch (_) {
      return false;
    }
  }

  /// Exact firing when the OS allows it (a reminder app), else an inexact window.
  Future<AndroidScheduleMode> _scheduleMode() async {
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null &&
          (await android.canScheduleExactNotifications() ?? false)) {
        return AndroidScheduleMode.exactAllowWhileIdle;
      }
    } catch (_) {}
    return AndroidScheduleMode.inexactAllowWhileIdle;
  }

  /// A stable notification id for a note (fits a 32-bit int).
  static int idFor(String noteId) => noteId.hashCode & 0x7fffffff;

  /// Schedules (or reschedules) a reminder for [noteId] at [when]. A time in
  /// the past is ignored.
  Future<void> schedule({
    required String noteId,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    if (!_ready) await init();
    if (!_ready) return;
    if (when.isBefore(DateTime.now())) return;
    try {
      await _plugin.zonedSchedule(
        idFor(noteId),
        title,
        body,
        tz.TZDateTime.from(when, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'Reminders',
            channelDescription: 'Node reminders',
            importance: Importance.high,
            priority: Priority.high,
            icon: 'ic_stat_braim',
            color: _accent,
          ),
        ),
        androidScheduleMode: await _scheduleMode(),
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      debugPrint('reminder schedule failed: $e');
    }
  }

  Future<void> cancel(String noteId) async {
    if (!_ready) await init();
    if (!_ready) return;
    try {
      await _plugin.cancel(idFor(noteId));
    } catch (_) {}
  }

  /// Schedules the gentle nightly nudge to write a journal entry, repeating
  /// every day at [hour]:[minute]. Re-scheduling replaces the previous one.
  Future<void> scheduleDailyJournal({
    required int hour,
    required int minute,
    required String title,
    required String body,
  }) async {
    if (!_ready) await init();
    if (!_ready) return;
    try {
      final now = tz.TZDateTime.now(tz.local);
      var when =
          tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
      // If today's time has already passed, start from tomorrow.
      if (!when.isAfter(now)) when = when.add(const Duration(days: 1));
      await _plugin.zonedSchedule(
        _journalDailyId,
        title,
        body,
        when,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _journalChannelId,
            'Journal',
            channelDescription: 'Daily journal nudge',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            icon: 'ic_stat_braim',
            color: _accent,
          ),
        ),
        androidScheduleMode: await _scheduleMode(),
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        // Fire at the same clock time every day.
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      debugPrint('journal reminder schedule failed: $e');
    }
  }

  /// A gentle reminder for a task at [hour]:[minute]. With no [weekdays] it
  /// repeats daily; with weekdays (a reflex's consistency days, 1 = Mon … 7 =
  /// Sun) it repeats weekly on each of those days only. Keyed by thread id.
  /// Not an alarm — a normal-priority notification.
  Future<void> scheduleThreadReminder({
    required String threadId,
    required String title,
    required String body,
    required int hour,
    required int minute,
    Set<int> weekdays = const {},
  }) async {
    if (!_ready) await init();
    if (!_ready) return;
    // Clear any previous scheduling (daily or per-weekday) for this thread.
    await cancelThreadReminder(threadId);
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _taskChannelId,
        'Daily day',
        channelDescription: 'Daily task reminders',
        importance: Importance.high,
        priority: Priority.high,
        icon: 'ic_stat_braim',
        color: _accent,
      ),
    );
    final safeTitle = title.isEmpty ? 'Daily day' : title;
    final mode = await _scheduleMode();
    try {
      if (weekdays.isEmpty) {
        final now = tz.TZDateTime.now(tz.local);
        var when = tz.TZDateTime(
            tz.local, now.year, now.month, now.day, hour, minute);
        if (!when.isAfter(now)) when = when.add(const Duration(days: 1));
        await _plugin.zonedSchedule(
          idFor(threadId),
          safeTitle,
          body,
          when,
          details,
          androidScheduleMode: mode,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      } else {
        for (final w in weekdays) {
          if (w < 1 || w > 7) continue;
          await _plugin.zonedSchedule(
            idFor('$threadId#$w'),
            safeTitle,
            body,
            _nextWeekday(w, hour, minute),
            details,
            androidScheduleMode: mode,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            // Weekly on that weekday at that time.
            matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
          );
        }
      }
    } catch (e) {
      debugPrint('task reminder schedule failed: $e');
    }
  }

  /// The next occurrence of [weekday] (1 = Mon … 7 = Sun) at [hour]:[minute].
  tz.TZDateTime _nextWeekday(int weekday, int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var d = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    while (d.weekday != weekday || !d.isAfter(now)) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }

  /// Cancels a thread's reminder, whether it was scheduled daily or per-weekday.
  Future<void> cancelThreadReminder(String threadId) async {
    if (!_ready) await init();
    if (!_ready) return;
    try {
      await _plugin.cancel(idFor(threadId));
      for (var w = 1; w <= 7; w++) {
        await _plugin.cancel(idFor('$threadId#$w'));
      }
    } catch (_) {}
  }

  Future<void> cancelDailyJournal() async {
    if (!_ready) await init();
    if (!_ready) return;
    try {
      await _plugin.cancel(_journalDailyId);
    } catch (_) {}
  }

  AndroidNotificationDetails _focusDetails({
    DateTime? endsAt,
    required int progress,
    required int maxProgress,
    Color? color,
    required bool ongoing,
  }) =>
      AndroidNotificationDetails(
        _focusChannelId,
        'Focus timer',
        channelDescription: 'The running focus timer',
        importance: Importance.low,
        priority: Priority.low,
        ongoing: ongoing,
        autoCancel: !ongoing,
        onlyAlertOnce: true,
        playSound: false,
        enableVibration: false,
        // Tinted with the phase colour (green study / blue break).
        color: color,
        showProgress: maxProgress > 0,
        maxProgress: maxProgress,
        progress: progress.clamp(0, maxProgress),
        indeterminate: false,
        showWhen: endsAt != null,
        when: endsAt?.millisecondsSinceEpoch,
        usesChronometer: endsAt != null,
        chronometerCountDown: endsAt != null,
      );

  /// Shows (or updates in place — always the same id) the focus-timer
  /// notification: a silent, tappable shade entry with a progress bar that fills
  /// as time passes and a phase colour (dark for focus, green for the break).
  /// [endsAt] drives the live count-down; omit it for the paused state.
  Future<void> showFocusOngoing({
    required String title,
    required String body,
    DateTime? endsAt,
    int progress = 0,
    int maxProgress = 0,
    Color? color,
    bool ongoing = true,
  }) async {
    if (!_ready) await init();
    if (!_ready) return;
    try {
      await _plugin.show(
        _focusOngoingId,
        title,
        body,
        NotificationDetails(
            android: _focusDetails(
          endsAt: endsAt,
          progress: progress,
          maxProgress: maxProgress,
          color: color,
          ongoing: ongoing,
        )),
        payload: focusPayload,
      );
    } catch (e) {
      debugPrint('focus notification failed: $e');
    }
  }

  /// Schedules the next phase-change to update the SAME notification when it
  /// arrives (so a change lands even if the app is backgrounded — updating the
  /// existing entry, never spawning a new one). Best-effort / inexact.
  Future<void> scheduleFocusNext({
    required DateTime when,
    required String title,
    required String body,
    DateTime? endsAt,
    int maxProgress = 0,
    Color? color,
    bool ongoing = true,
  }) async {
    if (!_ready) await init();
    if (!_ready) return;
    if (!when.isAfter(DateTime.now())) return;
    try {
      await _plugin.zonedSchedule(
        _focusOngoingId,
        title,
        body,
        tz.TZDateTime.from(when, tz.local),
        NotificationDetails(
            android: _focusDetails(
          endsAt: endsAt,
          progress: 0,
          maxProgress: maxProgress,
          color: color,
          ongoing: ongoing,
        )),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: focusPayload,
      );
    } catch (e) {
      debugPrint('focus schedule failed: $e');
    }
  }

  /// Clears the focus notification and any pending scheduled update (same id).
  Future<void> cancelFocus() async {
    if (!_ready) await init();
    if (!_ready) return;
    try {
      await _plugin.cancel(_focusOngoingId);
    } catch (_) {}
  }

  /// Brings the scheduled notification in line with a note's reminder: schedule
  /// when it's set in the future, cancel otherwise.
  Future<void> syncNote(Note note) async {
    final at = note.reminderAt;
    if (at != null && at.isAfter(DateTime.now())) {
      final title = note.title.trim();
      var body = note.textPreview.trim().replaceAll('\n', ' ');
      if (body.length > 120) body = '${body.substring(0, 120)}…';
      await schedule(
        noteId: note.id,
        title: title.isEmpty ? 'Reminder' : title,
        body: body,
        when: at,
      );
    } else {
      await cancel(note.id);
    }
  }
}
