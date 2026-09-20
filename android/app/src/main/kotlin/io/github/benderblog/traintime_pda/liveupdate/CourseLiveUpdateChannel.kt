package io.github.benderblog.traintime_pda.liveupdate

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Bridge between the Dart side and the Live Update implementation.
object CourseLiveUpdateChannel {
    private const val CHANNEL = "xdyou/course_live_update"

    fun register(engine: FlutterEngine, context: Context) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isSupported" -> result.success(CourseLiveUpdateManager.isSupported)

                    "schedule" -> {
                        val events = parseEvents(call.argument<Any?>("events"))
                        CourseLiveUpdateScheduler.schedule(context, events)
                        result.success(events.size)
                    }

                    "cancelAll" -> {
                        CourseLiveUpdateScheduler.cancelAll(context)
                        result.success(null)
                    }

                    "showPreview" -> {
                        val event = (call.argument<Any?>("event") as? Map<*, *>)
                            ?.let { CourseLiveUpdateEvent.fromMap(it) }
                        if (event != null) {
                            CourseLiveUpdateManager.showPreview(context, event)
                        }
                        result.success(
                            event != null && CourseLiveUpdateManager.isSupported,
                        )
                    }

                    "stopPreview" -> {
                        CourseLiveUpdateManager.stopPreview(context)
                        result.success(null)
                    }

                    "diagnostics" -> result.success(CourseLiveUpdateManager.diagnostics(context))

                    "openNotificationSettings" -> {
                        CourseLiveUpdateManager.openNotificationSettings(context)
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun parseEvents(raw: Any?): List<CourseLiveUpdateEvent> {
        val entries = raw as? List<*> ?: return emptyList()
        return entries.mapNotNull { entry ->
            (entry as? Map<*, *>)?.let { CourseLiveUpdateEvent.fromMap(it) }
        }
    }
}
