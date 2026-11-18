package com.plix.plix

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
import android.os.PowerManager

class DownloadForegroundService : Service() {
    companion object {
        const val CHANNEL_ID = "plix_downloads_channel"
        const val NOTIFICATION_ID = 90210
        const val COMPLETE_NOTIFICATION_ID = 90211
        const val ACTION_START = "ACTION_START"
        const val ACTION_UPDATE = "ACTION_UPDATE"
        const val ACTION_STOP = "ACTION_STOP"
        const val ACTION_COMPLETE = "ACTION_COMPLETE"
        const val EXTRA_TITLE = "EXTRA_TITLE"
        const val EXTRA_TEXT = "EXTRA_TEXT"
        const val EXTRA_PROGRESS = "EXTRA_PROGRESS"
        const val EXTRA_INDETERMINATE = "EXTRA_INDETERMINATE"
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        acquireWakeLock()
    }

    private fun getIconRes(): Int {
        return applicationInfo.icon.takeIf { it != 0 } ?: R.mipmap.ic_launcher
    }

    private fun getOpenAppIntent(): PendingIntent {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        return PendingIntent.getActivity(this, 0, launchIntent, flags)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        createNotificationChannel()
        val action = intent?.action ?: ACTION_START
        when (action) {
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_COMPLETE -> {
                val title = intent?.getStringExtra(EXTRA_TITLE) ?: "Download Complete"
                val text = intent?.getStringExtra(EXTRA_TEXT) ?: "Download finished. Tap to dismiss."
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                } else {
                    @Suppress("DEPRECATION")
                    stopForeground(true)
                }
                val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                val completeNotification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    Notification.Builder(this, CHANNEL_ID)
                        .setContentTitle(title)
                        .setContentText(text)
                        .setSmallIcon(getIconRes())
                        .setContentIntent(getOpenAppIntent())
                        .setOngoing(false)
                        .setAutoCancel(true)
                        .build()
                } else {
                    @Suppress("DEPRECATION")
                    Notification.Builder(this)
                        .setContentTitle(title)
                        .setContentText(text)
                        .setSmallIcon(getIconRes())
                        .setContentIntent(getOpenAppIntent())
                        .setOngoing(false)
                        .setAutoCancel(true)
                        .build()
                }
                manager?.notify(COMPLETE_NOTIFICATION_ID, completeNotification)
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_START, ACTION_UPDATE -> {
                val title = intent?.getStringExtra(EXTRA_TITLE) ?: "Plix Download"
                val text = intent?.getStringExtra(EXTRA_TEXT) ?: "Downloading content in background..."
                val progress = intent?.getIntExtra(EXTRA_PROGRESS, -1) ?: -1
                val indeterminate = intent?.getBooleanExtra(EXTRA_INDETERMINATE, false) ?: false
                val notification = buildNotification(title, text, progress, indeterminate)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    startForeground(
                        NOTIFICATION_ID,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                    )
                } else {
                    startForeground(NOTIFICATION_ID, notification)
                }
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        releaseWakeLock()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        super.onDestroy()
    }

    private fun acquireWakeLock() {
        if (wakeLock == null) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
            wakeLock = powerManager?.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "plix:DownloadWakeLock"
            )?.apply {
                setReferenceCounted(false)
                acquire(24 * 60 * 60 * 1000L) // 24 hr max safeguard
            }
        }
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (_: Exception) {}
        wakeLock = null
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Downloads",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Shows progress for media downloads"
                setShowBadge(true)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            manager?.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(
        title: String,
        text: String,
        progress: Int = -1,
        indeterminate: Boolean = false
    ): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        builder.setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(getIconRes())
            .setContentIntent(getOpenAppIntent())
            .setOngoing(true)
            .setOnlyAlertOnce(true)

        if (progress >= 0 || indeterminate) {
            builder.setProgress(100, if (indeterminate) 0 else progress.coerceIn(0, 100), indeterminate)
        }

        return builder.build()
    }
}
