package com.ecopulse.ecopulse

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "ecopulse/alerts"
    private val alarmChannelId = "alarms"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "init" -> {
                    ensureChannel()
                    requestNotificationPermission()
                    result.success(null)
                }
                "show" -> {
                    val id = call.argument<Int>("id") ?: 0
                    val title = call.argument<String>("title") ?: "EcoPulse"
                    val body = call.argument<String>("body") ?: ""
                    ensureChannel()
                    val launch = Intent(this, MainActivity::class.java).apply {
                        flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                        putExtra("open_alarms", true)
                        putExtra("alarm_id", id)
                    }
                    val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
                    val pending = PendingIntent.getActivity(this, id, launch, flags)
                    val notification = NotificationCompat.Builder(this, alarmChannelId)
                        .setSmallIcon(R.mipmap.ic_launcher)
                        .setContentTitle(title)
                        .setContentText(body)
                        .setPriority(NotificationCompat.PRIORITY_HIGH)
                        .setAutoCancel(true)
                        .setOnlyAlertOnce(true)
                        .setContentIntent(pending)
                        .build()
                    NotificationManagerCompat.from(this).notify(id, notification)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    // Android 13+ bildirim iznini çalışma anında ister; aksi halde alarm bildirimi sessizce düşer.
    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return
        }
        val granted = ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        if (!granted) {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
        }
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(alarmChannelId, "Alarmlar", NotificationManager.IMPORTANCE_HIGH)
        channel.description = "Yönetici anomali bildirimleri"
        manager.createNotificationChannel(channel)
    }
}
