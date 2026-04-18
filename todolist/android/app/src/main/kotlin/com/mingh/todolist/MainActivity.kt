package com.mingh.todolist

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.IBinder
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.app.ActivityCompat
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

private const val TAG = "TodoAlarm"
private const val METHOD_CHANNEL = "com.mingh.todolist/alarm"

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= 33) {
            if (ActivityCompat.checkSelfPermission(this, "android.permission.POST_NOTIFICATIONS")
                != PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(this, arrayOf("android.permission.POST_NOTIFICATIONS"), 1001)
            }
        }
        if (!Settings.canDrawOverlays(this)) {
            startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setAlarm" -> {
                    val ms = (call.argument<Number>("triggerAtMillis"))?.toLong() ?: 0L
                    val msg = call.argument<String>("message") ?: "任务提醒"
                    val id = call.argument<Int>("id") ?: 0
                    val vibMode = call.argument<String>("vibrationMode") ?: "continuous"
                    AlarmHelper.set(this, ms, msg, id, vibMode)
                    result.success(true)
                }
                "cancelAlarm" -> {
                    AlarmHelper.cancel(this, call.argument<Int>("id") ?: 0)
                    result.success(true)
                }
                "testNotification" -> {
                    AlarmHelper.set(this, System.currentTimeMillis() + 5000, "测试：五秒后的强力提醒", 999)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}

object AlarmHelper {
    fun set(context: Context, triggerAtMillis: Long, message: String, id: Int, vibrationMode: String = "continuous") {
        if (triggerAtMillis <= System.currentTimeMillis()) return
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, AlarmReceiver::class.java).apply {
            action = "com.mingh.todolist.ALARM_$id"
            putExtra("message", message)
            putExtra("id", id)
            putExtra("vibrationMode", vibrationMode)
        }
        val pi = PendingIntent.getBroadcast(context, id, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        try {
            am.setAlarmClock(AlarmManager.AlarmClockInfo(triggerAtMillis, pi), pi)
        } catch (_: SecurityException) {
            am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pi)
        }
    }

    fun cancel(context: Context, id: Int) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, AlarmReceiver::class.java).apply { action = "com.mingh.todolist.ALARM_$id" }
        val pi = PendingIntent.getBroadcast(context, id, intent, PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE)
        pi?.let { am.cancel(it) }
    }
}

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val message = intent.getStringExtra("message") ?: "任务提醒"
        val id = intent.getIntExtra("id", 0)
        val vibrationMode = intent.getStringExtra("vibrationMode") ?: "continuous"
        Log.e(TAG, "AlarmReceiver 触发! id=$id, 启动前台 Service")

        val serviceIntent = Intent(context, AlarmForegroundService::class.java).apply {
            putExtra("message", message)
            putExtra("id", id)
            putExtra("vibrationMode", vibrationMode)
        }
        try {
            context.startForegroundService(serviceIntent)
        } catch (e: Exception) {
            Log.e(TAG, "启动前台 Service 失败，回退到直接执行: $e")
            // 回退：直接在 BroadcastReceiver 中执行（应用在前台时仍可工作）
            AlarmForegroundService.executeAlarm(context.applicationContext, message, id, vibrationMode)
        }
    }
}

class AlarmForegroundService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        // 创建前台通知渠道（静默，仅用于保活）
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(NotificationChannel("todo_fg_service", "提醒服务", NotificationManager.IMPORTANCE_LOW).apply {
            setSound(null, null)
            enableVibration(false)
        })
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val message = intent?.getStringExtra("message") ?: "任务提醒"
        val id = intent?.getIntExtra("id", 0) ?: 0
        val vibrationMode = intent?.getStringExtra("vibrationMode") ?: "continuous"

        // 立即进入前台，防止被系统杀掉
        try {
            startForeground(0x7FFF0001, Notification.Builder(this, "todo_fg_service")
                .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                .setContentTitle("提醒中...").build())
        } catch (e: Exception) {
            Log.e(TAG, "startForeground 失败: $e")
            stopSelf()
            return START_NOT_STICKY
        }

        executeAlarm(this, message, id, vibrationMode)

        // 62秒后自动停止 Service（ReminderAlert 60秒自动停止 + 2秒缓冲）
        Handler(Looper.getMainLooper()).postDelayed({ stopSelf() }, 62000)
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        ReminderAlert.stop()
        ReminderOverlay.dismiss(this)
        super.onDestroy()
        Log.e(TAG, "AlarmForegroundService 已销毁")
    }

    companion object {
        fun executeAlarm(context: Context, message: String, id: Int, vibrationMode: String = "continuous") {
            // 第一步：WakeLock
            var wakeLock: PowerManager.WakeLock? = null
            try {
                val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "todolist:alarm")
                wakeLock.acquire(65000)
                Log.e(TAG, "WakeLock 已获取")
            } catch (e: Exception) {
                Log.e(TAG, "获取 WakeLock 失败: $e")
                wakeLock = null
            }

            // 第二步：震动
            ReminderAlert.startVibration(context, wakeLock, vibrationMode == "continuous")

            // 第三步：铃声
            ReminderAlert.startRingtone(context)

            // 第四步：悬浮窗
            val overlayShown = ReminderOverlay.show(context, message, id, vibrationMode)
            if (!overlayShown) {
                Handler(Looper.getMainLooper()).postDelayed({ ReminderAlert.stop() }, 60000)
            }

            // 第五步：备用通知
            try {
                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                val prefs = context.getSharedPreferences("channel_prefs", Context.MODE_PRIVATE)
                val channelVer = 2
                if (prefs.getInt("todo_force_alarm_ver", 0) < channelVer) {
                    nm.deleteNotificationChannel("todo_force_alarm")
                    nm.createNotificationChannel(NotificationChannel("todo_force_alarm", "任务提醒", NotificationManager.IMPORTANCE_HIGH).apply {
                        enableVibration(true)
                        vibrationPattern = longArrayOf(0, 800, 300, 800, 300, 800, 300, 1200)
                    })
                    prefs.edit().putInt("todo_force_alarm_ver", channelVer).apply()
                }
                nm.notify(id, Notification.Builder(context, "todo_force_alarm")
                    .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                    .setContentTitle("任务已到期").setContentText(message)
                    .setCategory(Notification.CATEGORY_ALARM).setAutoCancel(true).build())
            } catch (e: Exception) { Log.e(TAG, "通知失败: $e") }
        }
    }
}

object ReminderAlert {
    private var vibrator: Vibrator? = null
    private var ringtone: Ringtone? = null
    private val handler = Handler(Looper.getMainLooper())
    private var isRunning = false
    private var wakeLock: PowerManager.WakeLock? = null
    private val PATTERN = longArrayOf(0, 800, 300, 800, 300, 800, 300, 1200)

    private val autoStopRunnable = Runnable { stop() }
    private val repeatRunnable = object : Runnable {
        override fun run() {
            if (!isRunning) return
            doVibrate()
            handler.postDelayed(this, 5500)
        }
    }

    /** 无条件强制震动，不检查任何模式 */
    fun startVibration(context: Context, wakeLock: PowerManager.WakeLock? = null, repeat: Boolean = true) {
        stop()
        isRunning = true
        ReminderAlert.wakeLock = wakeLock
        handler.postDelayed(autoStopRunnable, 60000)

        try {
            vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            Log.e(TAG, "Vibrator ok, hasVibrator=${vibrator?.hasVibrator()}, repeat=$repeat")
            doVibrate()
            if (repeat) {
                handler.postDelayed(repeatRunnable, 5500)
            }
        } catch (e: Exception) {
            Log.e(TAG, "startVibration 失败: $e")
        }

        // 事后检查：勿扰且开关关闭时才停止震动
        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val isDnd = nm.currentInterruptionFilter != NotificationManager.INTERRUPTION_FILTER_ALL
            if (isDnd) {
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                if (!prefs.getBoolean("flutter.vibrate_in_dnd", true)) {
                    vibrator?.cancel()
                    handler.removeCallbacks(repeatRunnable)
                    Log.e(TAG, "勿扰+开关关闭，停止震动")
                }
            }
        } catch (_: Exception) { /* 检测失败不影响震动 */ }
    }

    fun startRingtone(context: Context) {
        try {
            val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val isDnd = nm.currentInterruptionFilter != NotificationManager.INTERRUPTION_FILTER_ALL
            if (audio.ringerMode == AudioManager.RINGER_MODE_NORMAL && !isDnd) {
                ringtone = RingtoneManager.getRingtone(context, RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM))
                ringtone?.audioAttributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
                ringtone?.play()
                Log.e(TAG, "铃声已启动")
            }
        } catch (e: Exception) { Log.e(TAG, "铃声失败: $e") }
    }

    private fun doVibrate() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(VibrationEffect.createWaveform(PATTERN, -1))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(PATTERN, -1)
            }
        } catch (e: Exception) { Log.e(TAG, "doVibrate 失败: $e") }
    }

    fun stop() {
        isRunning = false
        handler.removeCallbacks(autoStopRunnable)
        handler.removeCallbacks(repeatRunnable)
        try { vibrator?.cancel() } catch (_: Exception) {}
        vibrator = null
        try { ringtone?.stop() } catch (_: Exception) {}
        ringtone = null
        try { wakeLock?.let { if (it.isHeld) it.release() } } catch (_: Exception) {}
        wakeLock = null
    }
}

object ReminderOverlay {
    private var overlayView: FlutterView? = null
    private var windowManager: WindowManager? = null
    private var engine: FlutterEngine? = null

    fun show(context: Context, message: String, id: Int, vibrationMode: String = "continuous"): Boolean {
        if (!Settings.canDrawOverlays(context)) return false
        dismiss(context)

        val appContext = context.applicationContext

        try {
            // 1. 确保 FlutterLoader 已初始化（release 模式下必须）
            val loader = FlutterInjector.instance().flutterLoader()
            if (!loader.initialized()) {
                loader.startInitialization(appContext)
                loader.ensureInitializationComplete(appContext, null)
            }
            Log.e(TAG, "FlutterLoader 已就绪, appBundlePath=${loader.findAppBundlePath()}")

            // 2. 创建独立 FlutterEngine
            val eng = FlutterEngine(appContext)
            engine = eng

            // 3. 注册 overlay MethodChannel
            val channel = MethodChannel(eng.dartExecutor.binaryMessenger, "com.mingh.todolist/overlay")
            val data = mapOf("message" to message, "id" to id, "vibrationMode" to vibrationMode)
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "ready" -> {
                        Log.e(TAG, "Dart overlay ready, 发送 setData")
                        channel.invokeMethod("setData", data)
                        result.success(null)
                    }
                    "dismiss" -> { ReminderAlert.stop(); dismiss(appContext); result.success(null) }
                    "snooze" -> {
                        ReminderAlert.stop(); dismiss(appContext)
                        AlarmHelper.set(appContext, System.currentTimeMillis() + 300000, message, id + 100000, vibrationMode)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

            // 4. 执行 Dart 入口
            Log.e(TAG, "启动 Dart entrypoint: overlayMain")
            eng.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "overlayMain")
            )

            // 4.5 定时重试发送 setData（防止 ready 信号丢失）
            val h = Handler(Looper.getMainLooper())
            var retries = 0
            val retryRunnable = object : Runnable {
                override fun run() {
                    if (engine == null || retries >= 10) return
                    retries++
                    Log.e(TAG, "重试发送 setData #$retries")
                    try { channel.invokeMethod("setData", data) } catch (_: Exception) {}
                    h.postDelayed(this, 500)
                }
            }
            h.postDelayed(retryRunnable, 1000)  // 1秒后开始重试

            // 5. 创建 FlutterView 并添加为悬浮窗
            val fv = FlutterView(appContext)
            fv.attachToFlutterEngine(eng)
            eng.lifecycleChannel.appIsResumed()

            val wm = appContext.getSystemService(Context.WINDOW_SERVICE) as WindowManager
            val dm = appContext.resources.displayMetrics
            val params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                dm.heightPixels / 3,
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                    or WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
                    or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
                PixelFormat.TRANSLUCENT
            ).apply { gravity = Gravity.BOTTOM }

            overlayView = fv
            windowManager = wm
            wm.addView(fv, params)
            Log.e(TAG, "Flutter 悬浮窗已添加")
            return true
        } catch (e: Exception) {
            Log.e(TAG, "Flutter 悬浮窗创建失败: $e")
            return false
        }
    }

    fun dismiss(context: Context) {
        overlayView?.let { v ->
            v.detachFromFlutterEngine()
            windowManager?.let { wm -> try { wm.removeView(v) } catch (_: Exception) {} }
        }
        engine?.destroy()
        overlayView = null
        windowManager = null
        engine = null
    }
}
