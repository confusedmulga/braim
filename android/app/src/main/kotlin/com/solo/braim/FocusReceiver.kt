package com.solo.braim

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import java.io.File

/// The focus timer's notification button and its end-of-session alarm, on a
/// receiver only this app can reach (exported="false").
///
/// The button used to go through androidx's MediaButtonReceiver, which throws
/// (and so crashes the app) when no media service is declared — and none is.
/// The alarm ends Do Not Disturb when the session is over even if Android has
/// frozen or killed the app meanwhile: the timer's own ticker only runs while
/// the app does, so without it the phone could stay muted for hours.
class FocusReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_TOGGLE = "com.solo.braim.FOCUS_TOGGLE"
        private const val ACTION_END = "com.solo.braim.FOCUS_END"
        private const val EXTRA_FILTER = "filter"
        private const val EXTRA_MARKER = "marker"
        private const val TOGGLE_REQUEST = 1
        private const val END_REQUEST = 2

        private const val FLAGS =
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE

        fun togglePendingIntent(context: Context): PendingIntent =
            PendingIntent.getBroadcast(
                context,
                TOGGLE_REQUEST,
                Intent(context, FocusReceiver::class.java).setAction(ACTION_TOGGLE),
                FLAGS,
            )

        private fun endPendingIntent(
            context: Context,
            filter: Int,
            marker: String,
        ): PendingIntent =
            PendingIntent.getBroadcast(
                context,
                END_REQUEST,
                Intent(context, FocusReceiver::class.java)
                    .setAction(ACTION_END)
                    .putExtra(EXTRA_FILTER, filter)
                    .putExtra(EXTRA_MARKER, marker),
                FLAGS,
            )

        /// Arms the end-of-session alarm for [atMs]: it puts back [filter]
        /// (none when -1), deletes the Dart side's DND [marker] file and
        /// clears the notification. Exact when Android allows exact alarms.
        fun scheduleEnd(context: Context, atMs: Long, filter: Int, marker: String) {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val pi = endPendingIntent(context, filter, marker)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                !am.canScheduleExactAlarms()
            ) {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMs, pi)
            } else {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMs, pi)
            }
        }

        fun cancelEnd(context: Context) {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            // Extras don't take part in matching: this finds the armed one.
            am.cancel(endPendingIntent(context, -1, ""))
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_TOGGLE -> FocusMedia.current?.toggle()
            ACTION_END -> {
                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
                    as NotificationManager
                val filter = intent.getIntExtra(EXTRA_FILTER, -1)
                if (filter > 0 && nm.isNotificationPolicyAccessGranted) {
                    nm.setInterruptionFilter(filter)
                }
                intent.getStringExtra(EXTRA_MARKER)?.let {
                    if (it.isNotEmpty()) File(it).delete()
                }
                val media = FocusMedia.current
                if (media != null) media.hide() else nm.cancel(FocusMedia.NOTIF_ID)
            }
        }
    }
}
