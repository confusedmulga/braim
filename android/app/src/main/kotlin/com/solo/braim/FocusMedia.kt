package com.solo.braim

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.os.Build
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import androidx.core.app.NotificationCompat
import androidx.media.app.NotificationCompat.MediaStyle
import androidx.media.session.MediaButtonReceiver

/// A real MediaSession-backed notification for the Pomodoro focus timer. Because
/// it carries a PlaybackState with position + duration, Android renders the
/// system media UI — including the Android 13 "squiggly" seek-bar that wiggles
/// while playing and goes straight when paused — and routes the transport button
/// back to the timer.
class FocusMedia(private val context: Context) {
    private var session: MediaSessionCompat? = null

    /// Invoked ("play" / "pause") when the notification's transport button is
    /// tapped, so Flutter can toggle the timer.
    var onAction: ((String) -> Unit)? = null

    companion object {
        private const val CHANNEL_ID = "braim_focus"
        private const val NOTIF_ID = 900001
    }

    private fun notificationManager(): NotificationManager =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = notificationManager()
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                val ch = NotificationChannel(
                    CHANNEL_ID, "Focus timer", NotificationManager.IMPORTANCE_LOW
                )
                ch.description = "The running focus timer"
                ch.setSound(null, null)
                ch.enableVibration(false)
                ch.setShowBadge(false)
                nm.createNotificationChannel(ch)
            }
        }
    }

    private fun ensureSession(): MediaSessionCompat {
        session?.let { return it }
        val s = MediaSessionCompat(context, "braim_focus")
        s.setCallback(object : MediaSessionCompat.Callback() {
            override fun onPlay() {
                onAction?.invoke("play")
            }

            override fun onPause() {
                onAction?.invoke("pause")
            }
        })
        s.isActive = true
        session = s
        return s
    }

    fun show(
        title: String,
        text: String,
        elapsedMs: Long,
        durationMs: Long,
        playing: Boolean,
        color: Int,
    ) {
        ensureChannel()
        val s = ensureSession()

        s.setMetadata(
            MediaMetadataCompat.Builder()
                .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
                .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, text)
                .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, durationMs)
                .build()
        )
        s.setPlaybackState(
            PlaybackStateCompat.Builder()
                .setActions(
                    PlaybackStateCompat.ACTION_PLAY or
                        PlaybackStateCompat.ACTION_PAUSE or
                        PlaybackStateCompat.ACTION_PLAY_PAUSE
                )
                .setState(
                    if (playing) PlaybackStateCompat.STATE_PLAYING
                    else PlaybackStateCompat.STATE_PAUSED,
                    elapsedMs,
                    if (playing) 1f else 0f,
                )
                .build()
        )

        val piFlags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val contentPi = PendingIntent.getActivity(context, 0, launch, piFlags)

        val toggle = NotificationCompat.Action(
            if (playing) R.drawable.ic_pomo_pause else R.drawable.ic_pomo_play,
            if (playing) "Pause" else "Play",
            MediaButtonReceiver.buildMediaButtonPendingIntent(
                context, PlaybackStateCompat.ACTION_PLAY_PAUSE
            )
        )

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(contentPi)
            .setColor(color)
            .setColorized(true)
            .setOngoing(playing)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .addAction(toggle)
            .setStyle(
                MediaStyle()
                    .setMediaSession(s.sessionToken)
                    .setShowActionsInCompactView(0)
            )

        notificationManager().notify(NOTIF_ID, builder.build())
    }

    fun hide() {
        notificationManager().cancel(NOTIF_ID)
        session?.let {
            it.isActive = false
            it.release()
        }
        session = null
    }
}
