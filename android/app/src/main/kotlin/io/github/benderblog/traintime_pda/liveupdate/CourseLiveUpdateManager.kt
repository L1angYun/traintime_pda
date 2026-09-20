package io.github.benderblog.traintime_pda.liveupdate

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.Typeface
import android.graphics.drawable.Icon
import android.os.Build
import android.provider.Settings
import androidx.annotation.RequiresApi
import io.github.benderblog.traintime_pda.MainActivity
import io.github.benderblog.traintime_pda.R

/// Posts the "a class is going on" notification.
///
/// Android 16 promotes ongoing progress notifications into Live Updates: a
/// chip in the status bar, on the lock screen and in the always-on display.
/// Devices which ship their own version of it (Xiaomi's "Super Island" for
/// instance) pick the very same notification up.
object CourseLiveUpdateManager {
    /// Live Updates are an Android 16 feature.
    private const val LIVE_UPDATE_API_LEVEL = 36

    private const val CHANNEL_ID = "course_live_update"

    /// Kept outside of the range the scheduled classes use.
    private const val PREVIEW_NOTIFICATION_ID = 2147483000

    /// The looks of the badge are chosen on the debug page, which writes them
    /// into the preferences shared with the Dart side.
    private const val FLUTTER_PREFERENCES = "FlutterSharedPreferences"
    private const val BADGE_STYLE_PREFERENCE = "liveUpdateBadgeStyle"
    private const val BADGE_STYLE_INITIAL = 0
    private const val BADGE_STYLE_SHORT = 1
    private const val BADGE_STYLE_NONE = 2

    val isSupported: Boolean
        get() = Build.VERSION.SDK_INT >= LIVE_UPDATE_API_LEVEL

    fun show(
        context: Context,
        event: CourseLiveUpdateEvent,
        now: Long = System.currentTimeMillis(),
    ) {
        if (Build.VERSION.SDK_INT < LIVE_UPDATE_API_LEVEL) {
            return
        }
        if (now >= event.endMillis) {
            cancel(context, event.id)
            return
        }

        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        ensureChannel(context, manager)
        manager.notify(event.id, build(context, event, now))
    }

    fun cancel(context: Context, id: Int) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        manager.cancel(id)
    }

    /// Shows a made up class right away, to try the island out without waiting
    /// for a real lesson. It is not part of the schedule, so it does not touch
    /// the pending alarms.
    fun showPreview(context: Context, event: CourseLiveUpdateEvent) {
        if (Build.VERSION.SDK_INT < LIVE_UPDATE_API_LEVEL) {
            return
        }

        show(
            context,
            event.copy(id = PREVIEW_NOTIFICATION_ID),
            System.currentTimeMillis(),
        )
    }

    fun stopPreview(context: Context) {
        cancel(context, PREVIEW_NOTIFICATION_ID)
    }

    private fun ensureChannel(context: Context, manager: NotificationManager) {
        if (manager.getNotificationChannel(CHANNEL_ID) != null) {
            return
        }

        val channel = NotificationChannel(
            CHANNEL_ID,
            "Ongoing class",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "Shows the class which is going on right now"
            setShowBadge(false)
            // A class going on is a status, it should never beep.
            setSound(null, null)
            enableVibration(false)
        }
        manager.createNotificationChannel(channel)
    }

    @RequiresApi(LIVE_UPDATE_API_LEVEL)
    private fun build(
        context: Context,
        event: CourseLiveUpdateEvent,
        now: Long,
    ): Notification {
        val total = event.periods.coerceAtLeast(1)
        val style = Notification.ProgressStyle()
            .setStyledByProgress(false)
            .setProgress(event.progressInPeriods(now))
            // One piece per class period, in the colour of the course card.
            .setProgressTrackerIcon(trackerDot(context, event))
            .setProgressSegments(
                (0 until total).map {
                    Notification.ProgressStyle.Segment(1).setColor(event.color)
                },
            )

        val builder = Notification.Builder(context, CHANNEL_ID)
            // The left icon is the app itself, the course is represented by the
            // badge on the right: showing the course twice, once on each side,
            // only makes the card look busy.
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentTitle(event.title)
            .setContentText(event.detailText)
            .setSubText(event.footnoteText(now))
            .setContentIntent(openAppIntent(context))
            .setCategory(Notification.CATEGORY_PROGRESS)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            // A live countdown to the end of the lesson, kept running by the
            // system itself; before the lesson starts it counts towards its
            // beginning instead.
            .setWhen(event.countdownTarget(now))
            .setUsesChronometer(true)
            .setChronometerCountDown(true)
            .setStyle(style)
            // What the collapsed island and the status bar chip show: only a
            // couple of characters fit there, so the short name is used.
            .setShortCriticalText(
                event.shortTitle.ifEmpty { event.title },
            )
            // This is the bit which asks the system to promote the notification
            // into a Live Update.
            .setRequestPromotedOngoing(true)
            // Note: setColorized(true) must *not* be used, a colorized
            // notification is not eligible for promotion.

        // The badge of the course is optional: it can be turned off, or made to
        // show two characters, from the debug page.
        val badgeCharacters = badgeCharacters(context)
        if (badgeCharacters > 0) {
            builder.setLargeIcon(courseBadge(context, event, badgeCharacters))
        }

        return builder.build()
    }

    /// How many characters the badge of the course shows, zero for no badge.
    ///
    /// The value is written by the debug page, so that the looks can be
    /// compared without building the app again.
    private fun badgeCharacters(context: Context): Int {
        val style = context
            .getSharedPreferences(FLUTTER_PREFERENCES, Context.MODE_PRIVATE)
            .getLong("flutter.$BADGE_STYLE_PREFERENCE", BADGE_STYLE_INITIAL.toLong())
            .toInt()

        return when (style) {
            BADGE_STYLE_SHORT -> 2
            BADGE_STYLE_NONE -> 0
            else -> 1
        }
    }

    /// The mark of the course: a circle in the colour of its card with the
    /// beginning of its name.
    ///
    /// It is the only place where the course is drawn inside the card; the left
    /// icon stays the app itself.
    private fun courseBadge(
        context: Context,
        event: CourseLiveUpdateEvent,
        characters: Int,
    ): Icon {
        val size = dp(context, 48)
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        val background = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = event.color }
        canvas.drawCircle(size / 2f, size / 2f, size / 2f, background)

        val label = (event.shortTitle.ifEmpty { event.title }).take(characters)
        if (label.isNotEmpty()) {
            drawLabel(canvas, label, size.toFloat(), Color.WHITE)
        }

        return Icon.createWithBitmap(bitmap)
    }

    /// The mark which travels along the progress bar: a plain dot, so that the
    /// badge of the course is not repeated inside the same card.
    private fun trackerDot(context: Context, event: CourseLiveUpdateEvent): Icon {
        val size = dp(context, 20)
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        val radius = size / 2.4f
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
            color = Color.WHITE
        }
        canvas.drawCircle(size / 2f, size / 2f, radius, paint)

        paint.style = Paint.Style.STROKE
        paint.strokeWidth = size / 9f
        paint.color = event.color
        canvas.drawCircle(size / 2f, size / 2f, radius, paint)

        return Icon.createWithBitmap(bitmap)
    }

    private fun dp(context: Context, value: Int): Int =
        (value * context.resources.displayMetrics.density).toInt()
            .coerceAtLeast(value * 2)

    /// Draws the text centred inside a square of [size].
    ///
    /// The font is the one of the system interface - MiSans on HyperOS, Roboto
    /// elsewhere - at its regular weight; a bold weight makes a single Chinese
    /// character look heavy. The ink of the glyphs is centred instead of the
    /// font box, which would put them a little off centre.
    private fun drawLabel(canvas: Canvas, label: String, size: Float, color: Int) {
        val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
            textAlign = Paint.Align.CENTER
            textSize = size * if (label.length > 1) 0.42f else 0.6f
            typeface = Typeface.DEFAULT
            isSubpixelText = true
            if (label.length > 1) {
                letterSpacing = -0.03f
            }
        }

        val ink = Rect()
        text.getTextBounds(label, 0, label.length, ink)
        canvas.drawText(
            label,
            size / 2f,
            size / 2f - (ink.top + ink.bottom) / 2f,
            text,
        )
    }

    /// Whether the notification of a class satisfies the rules the system
    /// applies before promoting it into a Live Update.
    fun hasPromotableCharacteristics(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < LIVE_UPDATE_API_LEVEL) {
            return false
        }

        val now = System.currentTimeMillis()
        val sample = CourseLiveUpdateEvent(
            id = PREVIEW_NOTIFICATION_ID,
            title = "Class",
            body = "",
            color = CourseLiveUpdateEvent.DEFAULT_COLOR,
            startMillis = now,
            endMillis = now + 60_000L,
        )
        return build(context, sample, now).hasPromotableCharacteristics()
    }

    /// Whether the system is showing one of our notifications as a Live Update
    /// right now.
    fun isPromoted(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < LIVE_UPDATE_API_LEVEL) {
            return false
        }

        val manager = context.getSystemService(NotificationManager::class.java)
            ?: return false
        return manager.activeNotifications.any { statusBarNotification ->
            (statusBarNotification.notification.flags and
                Notification.FLAG_PROMOTED_ONGOING) != 0
        }
    }

    /// Everything which decides whether the island shows up, for the debug
    /// page.
    fun diagnostics(context: Context): Map<String, Any?> {
        val manager = context.getSystemService(NotificationManager::class.java)
        ensureChannelIfPossible(context, manager)
        val channel = manager?.getNotificationChannel(CHANNEL_ID)

        return mapOf(
            "supported" to isSupported,
            "targetSdk" to context.applicationInfo.targetSdkVersion,
            "notificationsEnabled" to (manager?.areNotificationsEnabled() ?: false),
            "canPostPromoted" to canPostPromoted(manager),
            "promotableCharacteristics" to hasPromotableCharacteristics(context),
            "promoted" to isPromoted(context),
            "channelImportance" to (channel?.importance ?: -1),
        )
    }

    private fun canPostPromoted(manager: NotificationManager?): Boolean {
        if (Build.VERSION.SDK_INT < LIVE_UPDATE_API_LEVEL) {
            return false
        }
        return manager?.canPostPromotedNotifications() ?: false
    }

    private fun ensureChannelIfPossible(context: Context, manager: NotificationManager?) {
        if (manager != null) {
            ensureChannel(context, manager)
        }
    }

    /// Opens the notification settings of the app, where the user can turn the
    /// live updates on.
    fun openNotificationSettings(context: Context) {
        val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
            putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            context.startActivity(intent)
        } catch (e: ActivityNotFoundException) {
            android.util.Log.w("CourseLiveUpdate", "No notification settings: ${e.message}")
        }
    }

    private fun openAppIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
