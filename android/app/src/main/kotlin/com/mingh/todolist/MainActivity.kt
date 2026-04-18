package com.mingh.todolist

import android.app.Activity
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
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
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.app.ActivityCompat
import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

private const val TAG = "TodoAlarm"
private const val METHOD_CHANNEL = "com.mingh.todolist/alarm"
private val PENDING_FILE_LOCK = Any() // 文件写入锁

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Allow showing on lock screen
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
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
                    val todoId = call.argument<String>("todoId") ?: ""
                    val vibMode = call.argument<String>("vibrationMode") ?: "continuous"
                    AlarmHelper.set(this, ms, msg, id, vibMode, todoId)
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
                "checkAccessibility" -> {
                    result.success(AlarmKeepAliveService.isEnabled(this))
                }
                "openAccessibilitySettings" -> {
                    startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    })
                    result.success(true)
                }
                "dismissNotification" -> {
                    val todoId = call.argument<String>("todoId") ?: ""
                    if (todoId.isNotEmpty()) {
                        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                        val advNames = listOf("atTime", "min15", "hour1", "day1", "morning7")
                        for (adv in advNames) {
                            val nid = AlarmRescheduleHelper.stableHash("${todoId}_$adv")
                            nm.cancel(nid)
                        }
                        // 取消 snooze 闹钟通知
                        nm.cancel(AlarmRescheduleHelper.stableHash("${todoId}_snooze"))
                        stopService(Intent(this, AlarmForegroundService::class.java))
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}

object AlarmHelper {
    fun set(context: Context, triggerAtMillis: Long, message: String, id: Int, vibrationMode: String = "continuous", todoId: String = "") {
        if (triggerAtMillis <= System.currentTimeMillis()) return
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, AlarmReceiver::class.java).apply {
            action = "com.mingh.todolist.ALARM_$id"
            putExtra("message", message)
            putExtra("id", id)
            putExtra("vibrationMode", vibrationMode)
            putExtra("todoId", todoId)
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
        val todoId = intent.getStringExtra("todoId") ?: ""
        Log.e(TAG, "AlarmReceiver 触发! id=$id")

        val serviceIntent = Intent(context, AlarmForegroundService::class.java).apply {
            putExtra("message", message)
            putExtra("id", id)
            putExtra("vibrationMode", vibrationMode)
            putExtra("todoId", todoId)
        }
        try {
            context.startForegroundService(serviceIntent)
        } catch (e: Exception) {
            Log.e(TAG, "启动前台 Service 失败: $e")
            AlarmForegroundService.executeAlarm(context.applicationContext, message, id, vibrationMode, todoId)
        }
    }
}

class AlarmForegroundService : Service() {
    private var handler: Handler? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(NotificationChannel("todo_fg_service", "提醒服务", NotificationManager.IMPORTANCE_LOW).apply {
            setSound(null, null); enableVibration(false)
        })
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val message = intent?.getStringExtra("message") ?: "任务提醒"
        val id = intent?.getIntExtra("id", 0) ?: 0
        val vibrationMode = intent?.getStringExtra("vibrationMode") ?: "continuous"
        val todoId = intent?.getStringExtra("todoId") ?: ""

        try {
            startForeground(0x7FFF0001, Notification.Builder(this, "todo_fg_service")
                .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                .setContentTitle("提醒中...").build())
        } catch (e: Exception) {
            Log.e(TAG, "startForeground 失败: $e"); stopSelf(); return START_NOT_STICKY
        }

        executeAlarm(this, message, id, vibrationMode, todoId)

        // 取消旧的 handler 回调，重新注册
        handler?.removeCallbacksAndMessages(null)
        val h = Handler(Looper.getMainLooper())
        handler = h

        // 每 5 秒检查任务是否已被另一端完成
        val checkRunnable = object : Runnable {
            override fun run() {
                if (todoId.isNotEmpty()) {
                    try {
                        val file = java.io.File(filesDir.parentFile, "app_flutter/todos.json")
                        if (file.exists()) {
                            val json = org.json.JSONObject(file.readText())
                            val todos = json.optJSONArray("todos")
                            if (todos != null) {
                                for (i in 0 until todos.length()) {
                                    val t = todos.getJSONObject(i)
                                    if (t.optString("id") == todoId && t.optBoolean("completed", false)) {
                                        Log.d(TAG, "任务已被另一端完成，自动停止提醒")
                                        stopSelf()
                                        return
                                    }
                                }
                            }
                        }
                    } catch (_: Exception) { /* 读取失败跳过本轮 */ }
                }
                h.postDelayed(this, 5000)
            }
        }
        h.postDelayed(checkRunnable, 5000)
        h.postDelayed({ stopSelf() }, 300000)
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        handler?.removeCallbacksAndMessages(null)
        ReminderAlert.forceStop()
        sendBroadcast(Intent("com.mingh.todolist.DISMISS_ALARM").apply { setPackage(packageName) })
        super.onDestroy()
    }

    companion object {
        fun executeAlarm(context: Context, message: String, id: Int, vibrationMode: String = "continuous", todoId: String = "") {
            var wakeLock: PowerManager.WakeLock? = null
            try {
                val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
                // 亮屏（锁屏时也能点亮）
                @Suppress("DEPRECATION")
                pm.newWakeLock(PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP, "todolist:screen")
                    .acquire(10000)
                wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "todolist:alarm")
                wakeLock.acquire(310000)
            } catch (e: Exception) { Log.e(TAG, "WakeLock 失败: $e"); wakeLock = null }

            ReminderAlert.startVibration(context, wakeLock, vibrationMode == "continuous")
            ReminderAlert.startRingtone(context)

            val overlayShown = try {
                val alarmIntent = Intent(context, AlarmActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_ANIMATION)
                    putExtra("message", message)
                    putExtra("id", id)
                    putExtra("vibrationMode", vibrationMode)
                    putExtra("todoId", todoId)
                }
                context.startActivity(alarmIntent)
                true
            } catch (e: Exception) { Log.e(TAG, "启动 AlarmActivity 失败: $e"); false }
            if (!overlayShown) {
                Handler(Looper.getMainLooper()).postDelayed({ ReminderAlert.stop() }, 60000)
            }

            try {
                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                val prefs = context.getSharedPreferences("channel_prefs", Context.MODE_PRIVATE)
                if (prefs.getInt("todo_force_alarm_ver", 0) < 2) {
                    nm.deleteNotificationChannel("todo_force_alarm")
                    nm.createNotificationChannel(NotificationChannel("todo_force_alarm", "任务提醒", NotificationManager.IMPORTANCE_HIGH).apply {
                        enableVibration(true); vibrationPattern = longArrayOf(0, 800, 300, 800, 300, 800, 300, 1200)
                    })
                    prefs.edit().putInt("todo_force_alarm_ver", 2).apply()
                }
                // Intent to open AlarmActivity (for fullScreenIntent and notification tap)
                val openIntent = Intent(context, AlarmActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    putExtra("message", message)
                    putExtra("id", id)
                    putExtra("vibrationMode", vibrationMode)
                    putExtra("todoId", todoId)
                }
                val openPi = PendingIntent.getActivity(context, id, openIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

                nm.notify(id, Notification.Builder(context, "todo_force_alarm")
                    .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                    .setContentTitle("任务已到期").setContentText(message)
                    .setContentIntent(openPi)
                    .setFullScreenIntent(openPi, true)
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
    private var activeCount = 0 // 活跃闹钟计数

    private val autoStopRunnable = Runnable { forceStop() }
    private val repeatRunnable = object : Runnable {
        override fun run() {
            if (!isRunning) return
            doVibrate(); handler.postDelayed(this, 5500)
        }
    }

    fun startVibration(context: Context, wakeLock: PowerManager.WakeLock? = null, repeat: Boolean = true) {
        activeCount++
        if (isRunning) return // 已在震动中，不重复启动
        isRunning = true; ReminderAlert.wakeLock = wakeLock
        if (!repeat) handler.postDelayed(autoStopRunnable, 60000)
        try {
            vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
            } else {
                @Suppress("DEPRECATION") context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            doVibrate()
            if (repeat) handler.postDelayed(repeatRunnable, 5500)
        } catch (e: Exception) { Log.e(TAG, "startVibration 失败: $e") }

        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.currentInterruptionFilter != NotificationManager.INTERRUPTION_FILTER_ALL) {
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                if (!prefs.getBoolean("flutter.vibrate_in_dnd", true)) {
                    vibrator?.cancel(); handler.removeCallbacks(repeatRunnable)
                }
            }
        } catch (_: Exception) {}
    }

    fun startRingtone(context: Context) {
        try {
            val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (audio.ringerMode == AudioManager.RINGER_MODE_NORMAL &&
                nm.currentInterruptionFilter == NotificationManager.INTERRUPTION_FILTER_ALL) {
                ringtone = RingtoneManager.getRingtone(context, RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM))
                ringtone?.audioAttributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
                ringtone?.play()
                if (Build.VERSION.SDK_INT >= 28) ringtone?.isLooping = true
            }
        } catch (e: Exception) { Log.e(TAG, "铃声失败: $e") }
    }

    private fun doVibrate() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(VibrationEffect.createWaveform(PATTERN, -1))
            } else {
                @Suppress("DEPRECATION") vibrator?.vibrate(PATTERN, -1)
            }
        } catch (e: Exception) { Log.e(TAG, "doVibrate 失败: $e") }
    }

    fun stop() {
        activeCount = (activeCount - 1).coerceAtLeast(0)
        if (activeCount > 0) return // 还有其他活跃闹钟，不停止
        forceStop()
    }

    fun forceStop() {
        activeCount = 0; isRunning = false
        handler.removeCallbacks(autoStopRunnable); handler.removeCallbacks(repeatRunnable)
        try { vibrator?.cancel() } catch (_: Exception) {}; vibrator = null
        try { ringtone?.stop() } catch (_: Exception) {}; ringtone = null
        try { wakeLock?.let { if (it.isHeld) it.release() } } catch (_: Exception) {}; wakeLock = null
    }
}

class AlarmActivity : Activity() {
    private var checkHandler: Handler? = null
    private val dismissReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) { finish() }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
        window.addFlags(
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
            @Suppress("DEPRECATION") WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
            @Suppress("DEPRECATION") WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
        )
        // 导航栏适配：直接加固定底部安全边距
        window.navigationBarColor = Color.parseColor("#2C2C2E")
        // 窗口背景设为纯黑，防止透出后面的 MainActivity
        window.setBackgroundDrawableResource(android.R.color.black)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(dismissReceiver, IntentFilter("com.mingh.todolist.DISMISS_ALARM"),
                Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(dismissReceiver, IntentFilter("com.mingh.todolist.DISMISS_ALARM"))
        }

        val message = intent.getStringExtra("message") ?: "任务提醒"
        val id = intent.getIntExtra("id", 0)
        val vibrationMode = intent.getStringExtra("vibrationMode") ?: "continuous"
        val todoId = intent.getStringExtra("todoId") ?: ""
        val ctx = this

        val splitRegex = Regex("[：:] ?")
        val parts = message.split(splitRegex, limit = 2)
        val title = if (parts.size > 1) parts[1] else message
        val timeLabel = if (parts.size > 1) parts[0] else "提醒"

        val outer = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.BOTTOM
            setBackgroundColor(Color.parseColor("#80000000"))
            val h = dp(ctx, 12f).toInt()
            setPadding(h, 0, h, 0)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.MATCH_PARENT)
        }

        val card = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#2C2C2E"))
                val r = dp(ctx, 16f)
                cornerRadii = floatArrayOf(r, r, r, r, r, r, r, r)
            }
            setPadding(dp(ctx, 20f).toInt(), dp(ctx, 16f).toInt(), dp(ctx, 20f).toInt(), dp(ctx, 20f).toInt())
        }

        // 顶部行
        val topRow = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        topRow.addView(TextView(ctx).apply {
            text = timeLabel; setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f); setTextColor(Color.parseColor("#E8913A"))
        })
        topRow.addView(View(ctx).apply { layoutParams = LinearLayout.LayoutParams(0, 0, 1f) })
        topRow.addView(TextView(ctx).apply {
            text = "✕"; setTextSize(TypedValue.COMPLEX_UNIT_SP, 20f); setTextColor(Color.parseColor("#666666"))
            setPadding(dp(ctx, 12f).toInt(), dp(ctx, 4f).toInt(), 0, dp(ctx, 4f).toInt())
            setOnClickListener { ReminderAlert.stop(); dismissWithAnimation() }
        })
        card.addView(topRow)

        card.addView(TextView(ctx).apply {
            text = title; setTextSize(TypedValue.COMPLEX_UNIT_SP, 20f); setTextColor(Color.WHITE)
            setPadding(0, dp(ctx, 8f).toInt(), 0, 0)
        })

        card.addView(View(ctx).apply {
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(ctx, 20f).toInt())
        })

        val btnContainer = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL }
        val mainBtns = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL }

        mainBtns.addView(ReminderOverlay.makeBtn(ctx, "稍后提醒", Color.parseColor("#3A3A3C"), Color.parseColor("#999999"), Color.parseColor("#555555")) {
            btnContainer.removeAllViews()
            val opts = listOf("5分" to 5L, "15分" to 15L, "30分" to 30L, "1时" to 60L)
            val optRow = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL }
            for ((i, pair) in opts.withIndex()) {
                val (label, mins) = pair
                if (i > 0) optRow.addView(View(ctx).apply { layoutParams = LinearLayout.LayoutParams(dp(ctx, 4f).toInt(), 0) })
                optRow.addView(ReminderOverlay.makeBtn(ctx, label, Color.parseColor("#3A3A3C"), Color.parseColor("#E8913A"), Color.parseColor("#555555"), compact = true) {
                    ReminderAlert.stop()
                    val snoozeTime = System.currentTimeMillis() + mins * 60000
                    AlarmHelper.set(ctx, snoozeTime, message, if (todoId.isNotEmpty()) AlarmRescheduleHelper.stableHash("${todoId}_snooze") else id + 100000, vibrationMode, todoId)
                    if (todoId.isNotEmpty()) {
                        synchronized(PENDING_FILE_LOCK) { try { java.io.File(ctx.filesDir.parentFile, "app_flutter/pending_snooze.txt").appendText("$todoId|$snoozeTime\n") } catch (_: Exception) {} }
                    }
                    dismissWithAnimation()
                })
            }
            // 取消按钮：恢复原始按钮
            optRow.addView(View(ctx).apply { layoutParams = LinearLayout.LayoutParams(dp(ctx, 4f).toInt(), 0) })
            optRow.addView(ReminderOverlay.makeBtn(ctx, "取消", Color.parseColor("#3A3A3C"), Color.parseColor("#666666"), Color.parseColor("#555555"), compact = true) {
                btnContainer.removeAllViews()
                btnContainer.addView(mainBtns)
            })
            btnContainer.addView(optRow)
        })
        mainBtns.addView(View(ctx).apply { layoutParams = LinearLayout.LayoutParams(dp(ctx, 12f).toInt(), 0) })
        mainBtns.addView(ReminderOverlay.makeBtn(ctx, "完成", Color.parseColor("#4A3A28"), Color.parseColor("#E8913A"), 0) {
            if (todoId.isNotEmpty()) {
                synchronized(PENDING_FILE_LOCK) { try { java.io.File(ctx.filesDir.parentFile, "app_flutter/pending_complete.txt").appendText("$todoId\n") } catch (_: Exception) {} }
            }
            ReminderAlert.stop(); dismissWithAnimation()
        })
        btnContainer.addView(mainBtns)
        card.addView(btnContainer)
        outer.addView(card)

        // 点击半透明背景不做任何操作（防误触）
        outer.setOnClickListener { /* 不操作 */ }

        setContentView(outer)

        // 动态获取导航栏真实高度并设置底部 padding
        outer.post {
            val h = dp(ctx, 12f).toInt()
            var navH = 0
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                window.decorView.rootWindowInsets?.let {
                    navH = it.getInsets(android.view.WindowInsets.Type.navigationBars()).bottom
                }
            }
            // fallback: 资源值
            if (navH == 0) {
                val resId = resources.getIdentifier("navigation_bar_height", "dimen", "android")
                if (resId > 0) navH = resources.getDimensionPixelSize(resId)
            }
            // 最终 fallback: 48dp
            if (navH == 0) navH = dp(ctx, 48f).toInt()
            outer.setPadding(h, 0, h, navH + dp(ctx, 8f).toInt())
            // 入场动画（padding 设好后再启动，避免跳动）
            outer.alpha = 0f; outer.translationY = dp(ctx, 60f)
            outer.animate().alpha(1f).translationY(0f).setDuration(250).start()
        }
        contentView = outer

        // 每 5 秒检查任务是否已被另一端完成
        if (todoId.isNotEmpty()) {
            val h = Handler(Looper.getMainLooper())
            checkHandler = h
            val checkRunnable = object : Runnable {
                override fun run() {
                    try {
                        val f = java.io.File(ctx.filesDir.parentFile, "app_flutter/todos.json")
                        if (f.exists()) {
                            val json = org.json.JSONObject(f.readText())
                            val todos = json.optJSONArray("todos")
                            if (todos != null) {
                                for (i in 0 until todos.length()) {
                                    val t = todos.getJSONObject(i)
                                    if (t.optString("id") == todoId && t.optBoolean("completed", false)) {
                                        ReminderAlert.stop(); finish(); return
                                    }
                                }
                            }
                        }
                    } catch (_: Exception) { /* 读取失败跳过本轮 */ }
                    h.postDelayed(this, 5000)
                }
            }
            h.postDelayed(checkRunnable, 5000)
        }
    }

    override fun onDestroy() {
        checkHandler?.removeCallbacksAndMessages(null)
        try { unregisterReceiver(dismissReceiver) } catch (_: Exception) { /* 已注销 */ }
        super.onDestroy()
    }

    private var contentView: View? = null
    private var isDismissing = false

    private fun dismissWithAnimation() {
        if (isDismissing) return
        isDismissing = true
        contentView?.animate()
            ?.alpha(0f)
            ?.translationY(dp(this, 200f))
            ?.setDuration(400)
            ?.withEndAction { finish() }
            ?.start()
            ?: finish()
    }

    private fun dp(ctx: Context, v: Float) = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, ctx.resources.displayMetrics)
}

object ReminderOverlay {
    private var overlayView: View? = null
    private var windowManager: WindowManager? = null

    fun show(context: Context, message: String, id: Int, vibrationMode: String = "continuous", todoId: String = ""): Boolean {
        if (!Settings.canDrawOverlays(context)) return false
        dismiss(context)
        val ctx = context.applicationContext
        val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager

        var navBarH = 0
        val navResId = ctx.resources.getIdentifier("navigation_bar_height", "dimen", "android")
        if (navResId > 0) navBarH = ctx.resources.getDimensionPixelSize(navResId)

        val splitRegex = Regex("[：:] ?")
        val parts = message.split(splitRegex, limit = 2)
        val title = if (parts.size > 1) parts[1] else message
        val timeLabel = if (parts.size > 1) parts[0] else "提醒"

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
            PixelFormat.TRANSLUCENT
        ).apply { gravity = Gravity.BOTTOM }

        val r = dp(ctx, 16f)
        val outer = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            val h = dp(ctx, 12f).toInt()
            setPadding(h, 0, h, navBarH)
        }

        val card = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#2C2C2E"))
                cornerRadii = floatArrayOf(r, r, r, r, r, r, r, r)
            }
            setPadding(dp(ctx, 24f).toInt(), dp(ctx, 20f).toInt(), dp(ctx, 24f).toInt(), dp(ctx, 24f).toInt())
        }

        // 顶部：橙色时间 + ✕
        val topRow = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        topRow.addView(TextView(ctx).apply {
            text = timeLabel; setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f); setTextColor(Color.parseColor("#E8913A"))
        })
        topRow.addView(View(ctx).apply { layoutParams = LinearLayout.LayoutParams(0, 0, 1f) })
        topRow.addView(TextView(ctx).apply {
            text = "✕"; setTextSize(TypedValue.COMPLEX_UNIT_SP, 20f); setTextColor(Color.parseColor("#666666"))
            setPadding(dp(ctx, 12f).toInt(), dp(ctx, 4f).toInt(), 0, dp(ctx, 4f).toInt())
            background = rippleBg(ctx)
            setOnClickListener { ReminderAlert.stop(); animateDismiss(ctx) }
        })
        card.addView(topRow)

        // 标题（无行数限制，自动换行扩展）
        card.addView(TextView(ctx).apply {
            text = title; setTextSize(TypedValue.COMPLEX_UNIT_SP, 20f); setTextColor(Color.WHITE)
            setPadding(0, dp(ctx, 12f).toInt(), 0, 0)
        })

        // 间距
        card.addView(View(ctx).apply {
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(ctx, 32f).toInt())
        })

        // 按钮容器
        val btnContainer = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL }

        val mainBtns = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL }
        // 稍后提醒 → 点击后切换为时间选项
        mainBtns.addView(makeBtn(ctx, "稍后提醒", Color.parseColor("#3A3A3C"), Color.parseColor("#999999"), Color.parseColor("#555555")) {
            btnContainer.removeAllViews()
            val opts = listOf("5分" to 5L, "15分" to 15L, "30分" to 30L, "1时" to 60L)
            val optRow = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL }
            for ((i, pair) in opts.withIndex()) {
                val (label, mins) = pair
                if (i > 0) optRow.addView(View(ctx).apply { layoutParams = LinearLayout.LayoutParams(dp(ctx, 4f).toInt(), 0) })
                optRow.addView(makeBtn(ctx, label, Color.parseColor("#3A3A3C"), Color.parseColor("#E8913A"), Color.parseColor("#555555"), compact = true) {
                    ReminderAlert.stop()
                    val snoozeTime = System.currentTimeMillis() + mins * 60000
                    AlarmHelper.set(ctx, snoozeTime, message, if (todoId.isNotEmpty()) AlarmRescheduleHelper.stableHash("${todoId}_snooze") else id + 100000, vibrationMode, todoId)
                    if (todoId.isNotEmpty()) {
                        synchronized(PENDING_FILE_LOCK) { try { java.io.File(ctx.filesDir.parentFile, "app_flutter/pending_snooze.txt").appendText("$todoId|$snoozeTime\n") } catch (_: Exception) {} }
                    }
                    animateDismiss(ctx)
                })
            }
            optRow.addView(View(ctx).apply { layoutParams = LinearLayout.LayoutParams(dp(ctx, 4f).toInt(), 0) })
            optRow.addView(makeBtn(ctx, "取消", Color.parseColor("#3A3A3C"), Color.parseColor("#666666"), Color.parseColor("#555555"), compact = true) {
                btnContainer.removeAllViews()
                btnContainer.addView(mainBtns)
            })
            btnContainer.addView(optRow)
        })
        mainBtns.addView(View(ctx).apply { layoutParams = LinearLayout.LayoutParams(dp(ctx, 12f).toInt(), 0) })
        // 完成 → 写 pending 到 SharedPreferences
        mainBtns.addView(makeBtn(ctx, "完成", Color.parseColor("#4A3A28"), Color.parseColor("#E8913A"), 0) {
            if (todoId.isNotEmpty()) {
                synchronized(PENDING_FILE_LOCK) { try { java.io.File(ctx.filesDir.parentFile, "app_flutter/pending_complete.txt").appendText("$todoId\n") } catch (_: Exception) {} }
            }
            ReminderAlert.stop(); animateDismiss(ctx)
        })
        btnContainer.addView(mainBtns)
        card.addView(btnContainer)
        outer.addView(card)

        // 入场动画
        outer.alpha = 0f; outer.translationY = dp(ctx, 60f)
        overlayView = outer; windowManager = wm
        wm.addView(outer, params)
        outer.animate().alpha(1f).translationY(0f).setDuration(250).start()
        return true
    }

    private fun animateDismiss(ctx: Context) {
        val v = overlayView ?: return
        v.animate().alpha(0f).translationY(dp(ctx, 60f)).setDuration(200).withEndAction { dismiss(ctx) }.start()
    }

    fun dismiss(context: Context) {
        overlayView?.let { v -> windowManager?.let { wm -> try { wm.removeView(v) } catch (_: Exception) {} } }
        overlayView = null; windowManager = null
    }

    fun makeBtn(ctx: Context, text: String, bgColor: Int, textColor: Int, strokeColor: Int, compact: Boolean = false, onClick: () -> Unit): Button {
        val r = dp(ctx, 12f)
        val bg = GradientDrawable().apply {
            setColor(bgColor); cornerRadius = r
            if (strokeColor != 0) setStroke(dp(ctx, 1f).toInt().coerceAtLeast(1), strokeColor)
        }
        val fontSize = if (compact) 13f else 16f
        val hPad = if (compact) dp(ctx, 6f).toInt() else dp(ctx, 16f).toInt()
        val vPad = if (compact) dp(ctx, 10f).toInt() else dp(ctx, 14f).toInt()
        return Button(ctx).apply {
            this.text = text; setTextSize(TypedValue.COMPLEX_UNIT_SP, fontSize); setTextColor(textColor)
            isAllCaps = false; stateListAnimator = null; maxLines = 1
            background = android.graphics.drawable.RippleDrawable(
                android.content.res.ColorStateList.valueOf(Color.parseColor("#22FFFFFF")),
                bg, GradientDrawable().apply { setColor(Color.WHITE); cornerRadius = r })
            setPadding(hPad, vPad, hPad, vPad)
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
            setOnClickListener { onClick() }
        }
    }

    private fun rippleBg(ctx: Context) = android.graphics.drawable.RippleDrawable(
        android.content.res.ColorStateList.valueOf(Color.parseColor("#33FFFFFF")),
        null, GradientDrawable().apply { setColor(Color.WHITE); cornerRadius = dp(ctx, 16f) })

    private fun dp(ctx: Context, v: Float) = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, ctx.resources.displayMetrics)
}

/// 开机后重新注册闹钟
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            Log.d(TAG, "开机完成，重新注册闹钟")
            AlarmRescheduleHelper.rescheduleFromLocal(context)
        }
    }
}

/// 无障碍服务：force-stop 后系统会自动重启此服务，用于恢复闹钟
class AlarmKeepAliveService : AccessibilityService() {
    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.d(TAG, "无障碍服务已连接，重新注册闹钟")
        AlarmRescheduleHelper.rescheduleFromLocal(this)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}
    override fun onInterrupt() {}

    companion object {
        fun isEnabled(context: Context): Boolean {
            val am = context.getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
            return am.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
                .any { it.resolveInfo.serviceInfo.packageName == context.packageName }
        }
    }
}

/// 从本地 JSON 文件读取 todo 列表并重新注册闹钟
object AlarmRescheduleHelper {
    // FNV-1a 确定性哈希（跨语言一致）
    fun stableHash(s: String): Int {
        var h = 0x811c9dc5.toInt()
        for (b in s.toByteArray(Charsets.UTF_8)) {
            h = h xor (b.toInt() and 0xFF)
            h = (h.toLong() * 0x01000193 and 0xFFFFFFFFL).toInt()
        }
        return h and 0x7FFFFFFF
    }

    fun rescheduleFromLocal(context: Context) {
        try {
            val file = java.io.File(context.filesDir.parentFile, "app_flutter/todos.json")
            if (!file.exists()) return
            val json = org.json.JSONObject(file.readText())
            val todos = json.optJSONArray("todos") ?: return
            val now = System.currentTimeMillis()

            for (i in 0 until todos.length()) {
                try {
                val t = todos.getJSONObject(i)
                if (!t.optBoolean("remind", false)) continue
                if (t.optBoolean("completed", false)) continue
                val dlStr = t.optString("deadline", "")
                if (dlStr.isEmpty() || dlStr == "null") continue

                val dl = try { java.time.Instant.parse(dlStr).toEpochMilli() } catch (_: Exception) {
                    try { java.time.LocalDateTime.parse(dlStr).atZone(java.time.ZoneId.systemDefault()).toInstant().toEpochMilli() } catch (_: Exception) { continue }
                }

                val todoId = t.optString("id", "")
                val vibMode = t.optString("vibrationMode", "continuous")
                val title = t.optString("title", "任务提醒")
                val advances = t.optJSONArray("reminderAdvances")

                if (advances != null) {
                    for (j in 0 until advances.length()) {
                        val advName = advances.optString(j, "atTime")
                        val offset = when (advName) {
                            "atTime" -> 0L
                            "min15" -> 15 * 60000L
                            "hour1" -> 3600000L
                            "day1" -> 86400000L
                            "morning7" -> -1L // 特殊处理
                            else -> 0L
                        }
                        val triggerAt = if (offset == -1L) {
                            // 当天早上 7 点
                            val cal = java.util.Calendar.getInstance().apply { timeInMillis = dl }
                            cal.set(java.util.Calendar.HOUR_OF_DAY, 7)
                            cal.set(java.util.Calendar.MINUTE, 0)
                            cal.set(java.util.Calendar.SECOND, 0)
                            cal.timeInMillis
                        } else {
                            dl - offset
                        }
                        if (triggerAt <= now) continue

                        val advLabel = when (advName) {
                            "atTime" -> "到期时"
                            "min15" -> "15分钟前"
                            "hour1" -> "1小时前"
                            "day1" -> "1天前"
                            "morning7" -> "当天7点"
                            else -> advName
                        }
                        val id = stableHash("${todoId}_$advName")
                        val msg = "$advLabel: $title"
                        AlarmHelper.set(context, triggerAt, msg, id, vibMode, todoId)
                    }
                }
                } catch (e: Exception) { Log.w(TAG, "单条 todo 闹钟注册失败: $e") }
            }
            Log.d(TAG, "闹钟重新注册完成")
        } catch (e: Exception) {
            Log.e(TAG, "闹钟重新注册失败: $e")
        }
    }
}
