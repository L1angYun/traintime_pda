package io.github.benderblog.traintime_pda.liveupdate

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject

/// Schedules the alarms which start, refresh and finish the Live Update of a
/// class. It works while the app is not running, the alarms carry everything
/// the receiver needs.
object CourseLiveUpdateScheduler {
    const val ACTION_START: String =
        "io.github.benderblog.traintime_pda.liveupdate.START"
    const val ACTION_UPDATE: String =
        "io.github.benderblog.traintime_pda.liveupdate.UPDATE"
    const val ACTION_STOP: String =
        "io.github.benderblog.traintime_pda.liveupdate.STOP"

    /// Three alarms per class: its start, its middle and its end.
    private const val ALARMS_PER_EVENT = 3

    /// Keeps the amount of pending alarms sane.
    private const val MAX_EVENTS = 240

    private const val PREFERENCES = "course_live_update"
    private const val KEY_EVENTS = "events"
    private const val KEY_EVENT_COUNT = "event_count"

    /// Replaces the whole schedule with [events].
    fun schedule(context: Context, events: List<CourseLiveUpdateEvent>) {
        cancelAll(context)

        val now = System.currentTimeMillis()
        val planned = events
            .filter { it.endMillis > now }
            .sortedBy { it.startMillis }
            .take(MAX_EVENTS)

        var index = 0
        for (event in planned) {
            val offset = index * ALARMS_PER_EVENT
            if (event.startMillis > now) {
                setAlarm(context, event, ACTION_START, event.startMillis, offset)
            } else {
                // The class is already going on, show it right away: the user
                // has just opened the app in the middle of it.
                CourseLiveUpdateManager.show(context, event, now)
            }
            val middle = event.startMillis + event.durationMillis / 2
            if (middle > now) {
                setAlarm(context, event, ACTION_UPDATE, middle, offset + 1)
            }
            setAlarm(context, event, ACTION_STOP, event.endMillis, offset + 2)
            index++
        }

        log("scheduled $index classes")
        store(context, planned)
    }

    /// Drops everything, the ongoing notification included.
    fun cancelAll(context: Context) {
        val count = loadCount(context)
        for (index in 0 until count * ALARMS_PER_EVENT) {
            val action = when (index % ALARMS_PER_EVENT) {
                0 -> ACTION_START
                1 -> ACTION_UPDATE
                else -> ACTION_STOP
            }
            val alarmManager = context.getSystemService(AlarmManager::class.java)
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                index,
                Intent(context, CourseLiveUpdateReceiver::class.java).setAction(action),
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
            )
            if (pendingIntent != null) {
                alarmManager?.cancel(pendingIntent)
                pendingIntent.cancel()
            }
        }
        store(context, emptyList())
    }

    /// Puts the stored schedule back in place, e.g. after a reboot.
    fun restore(context: Context) {
        val events = load(context)
        if (events.isEmpty()) {
            return
        }
        log("restoring ${events.size} classes")
        schedule(context, events)
    }

    private fun setAlarm(
        context: Context,
        event: CourseLiveUpdateEvent,
        action: String,
        atMillis: Long,
        requestCode: Int,
    ) {
        val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            requestCode,
            event.writeTo(
                Intent(context, CourseLiveUpdateReceiver::class.java).setAction(action),
            ),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val exact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            alarmManager.canScheduleExactAlarms()
        try {
            if (exact) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    atMillis,
                    pendingIntent,
                )
            } else {
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    atMillis,
                    pendingIntent,
                )
            }
        } catch (e: SecurityException) {
            log("exact alarm refused, falling back: ${e.message}")
            alarmManager.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                atMillis,
                pendingIntent,
            )
        }
    }

    private fun store(context: Context, events: List<CourseLiveUpdateEvent>) {
        val array = JSONArray()
        events.forEach { array.put(it.toJson()) }
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_EVENTS, array.toString())
            .putInt(KEY_EVENT_COUNT, events.size)
            .apply()
    }

    private fun load(context: Context): List<CourseLiveUpdateEvent> {
        val raw = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .getString(KEY_EVENTS, null) ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).mapNotNull { index ->
                val entry = array.optJSONObject(index) ?: return@mapNotNull null
                CourseLiveUpdateEvent.fromJson(entry)
            }
        } catch (e: Exception) {
            log("unable to read the stored schedule: ${e.message}")
            emptyList()
        }
    }

    private fun loadCount(context: Context): Int =
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .getInt(KEY_EVENT_COUNT, 0)

    private fun log(message: String) {
        android.util.Log.i("CourseLiveUpdate", message)
    }
}
