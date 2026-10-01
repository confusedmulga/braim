package com.solo.braim

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/// Keeps Braim's process alive while Braim Web is on, so the web server in the
/// Dart side keeps answering with the phone screen off. It holds no data and
/// runs no server: it only owns the persistent "Braim Web is on" notification.
/// The pairing code is never shown here, since notifications can appear on
/// the lock screen.
class BraimWebService : Service() {
    companion object {
        private const val CHANNEL_ID = "braim_web"
        private const val NOTIF_ID = 900002
        private const val ACTION_START = "com.solo.braim.web.START"
        private const val ACTION_TURN_OFF = "com.solo.braim.web.TURN_OFF"
        private const val EXTRA_URL = "url"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_TURN_OFF = "turnOff"
        private const val EXTRA_CHANNEL_NAME = "channelName"

        /// Set by MainActivity: hands the notification's Turn off to Dart,
        /// which stops the server and then this service.
        @Volatile
        var stopListener: (() -> Unit)? = null

        fun start(context: Context, url: String, title: String, turnOff: String,
                  channelName: String) {
            val intent = Intent(context, BraimWebService::class.java)
                .setAction(ACTION_START)
                .putExtra(EXTRA_URL, url)
                .putExtra(EXTRA_TITLE, title)
                .putExtra(EXTRA_TURN_OFF, turnOff)
                .putExtra(EXTRA_CHANNEL_NAME, channelName)
            ContextCompat.startForegroundService(context, intent)
        }

        /// Shows a new address in the running service's notification.
        fun update(context: Context, url: String, title: String, turnOff: String) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
                as NotificationManager
            nm.notify(NOTIF_ID, build(context, url, title, turnOff))
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, BraimWebService::class.java))
        }

        private fun ensureChannel(context: Context, name: String) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
                as NotificationManager
            val ch = NotificationChannel(CHANNEL_ID, name,
                NotificationManager.IMPORTANCE_LOW)
            ch.setSound(null, null)
            ch.enableVibration(false)
            ch.setShowBadge(false)
            nm.createNotificationChannel(ch) // also renames an existing one
        }

        private fun build(context: Context, url: String, title: String,
                          turnOff: String): Notification {
            val piFlags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            val contentPi = PendingIntent.getActivity(context, 0, launch, piFlags)
            val turnOffPi = PendingIntent.getService(
                context, 0,
                Intent(context, BraimWebService::class.java).setAction(ACTION_TURN_OFF),
                piFlags,
            )
            return NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_stat_braim)
                .setContentTitle(title)
                .setContentText(url)
                .setContentIntent(contentPi)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setSilent(true)
                .setShowWhen(false)
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
                .addAction(0, turnOff, turnOffPi)
                .build()
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_TURN_OFF) {
            val listener = stopListener
            if (listener != null) listener() else stopSelf()
            return START_NOT_STICKY
        }
        val url = intent?.getStringExtra(EXTRA_URL)
        if (intent?.action != ACTION_START || url == null) {
            // Never restarted on its own: without the Dart side there is no
            // server to keep alive.
            stopSelf()
            return START_NOT_STICKY
        }
        val title = intent.getStringExtra(EXTRA_TITLE) ?: "Braim Web"
        val turnOff = intent.getStringExtra(EXTRA_TURN_OFF) ?: "Turn off"
        ensureChannel(this, intent.getStringExtra(EXTRA_CHANNEL_NAME) ?: "Braim Web")
        val notification = build(this, url, title, turnOff)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIF_ID, notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        } else {
            startForeground(NOTIF_ID, notification)
        }
        return START_NOT_STICKY
    }
}
