import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/notification_service.dart';

/// After a reminder is switched on, says if it might not arrive on time:
/// notifications are off (it won't show at all), or exact alarms are off
/// (Android may hold it back a few minutes while the phone is idle), with a
/// button to the "Alarms & reminders" screen. Says nothing when all is set.
///
/// Call it with a mounted [context]; [notificationsAllowed] is what
/// [NotificationService.requestPermission] returned.
Future<void> showReminderHint(BuildContext context,
    {required bool notificationsAllowed}) async {
  final messenger = ScaffoldMessenger.of(context);
  final t = context.t;
  if (!notificationsAllowed) {
    messenger.showSnackBar(SnackBar(content: Text(t.notifPermNeeded)));
    return;
  }
  if (await NotificationService.instance.exactAlarmsAllowed()) return;
  messenger.showSnackBar(SnackBar(
    content: Text(t.reminderMayBeLate),
    duration: const Duration(seconds: 6),
    // A hint, not a question: it goes away on its own like the others.
    persist: false,
    action: SnackBarAction(
      label: t.reminderAllowExact,
      onPressed: () =>
          unawaited(NotificationService.instance.requestExactAlarms()),
    ),
  ));
}
