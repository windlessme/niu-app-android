package me.windless.niulife

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import java.time.LocalDate
import java.time.ZonedDateTime

internal fun clock(minute: Int) = "%02d:%02d".format(minute / 60, minute % 60)

private fun open(c: Context, target: String, request: Int): PendingIntent = PendingIntent.getActivity(
    c, request, Intent(c, MainActivity::class.java).setAction(Intent.ACTION_VIEW)
        .setData(Uri.parse("niulife://$target")),
    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

private val weekdays = listOf("一", "二", "三", "四", "五", "六", "日")

/** Today's classes, with the attendance scanner and library pass a tap away. */
class ScheduleWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) = refresh(context)
    companion object {
        /** Redraws every timetable widget and wakes again at the next class change. */
        fun refresh(c: Context) {
            val manager = AppWidgetManager.getInstance(c)
            val now = ZonedDateTime.now(scheduleZone)
            val today = now.toLocalDate()
            val snapshot = ScheduleStore.load(c)
            val blocks = snapshot?.on(today).orEmpty()
            val minute = now.hour * 60 + now.minute
            val body = when {
                snapshot == null -> "開啟 App 同步一次課表"
                blocks.isEmpty() -> "今天沒有課"
                else -> blocks.joinToString("\n\n") {
                    val mark = if (it.startMinute <= minute && minute < it.endMinute) "上課中  " else ""
                    "${clock(it.startMinute)}–${clock(it.endMinute)}  $mark${it.title}" +
                        if (it.room.isNotBlank()) "\n${it.room}" else ""
                }
            }
            val views = RemoteViews(c.packageName, R.layout.schedule_widget)
            views.setTextViewText(R.id.widget_title,
                "今日課表 · ${today.monthValue}/${today.dayOfMonth} 週${weekdays[today.dayOfWeek.value - 1]}")
            views.setTextViewText(R.id.widget_body, body)
            views.setOnClickPendingIntent(R.id.widget_root, open(c, "schedule", 10))
            views.setOnClickPendingIntent(R.id.widget_attendance, open(c, "attendance", 13))
            views.setOnClickPendingIntent(R.id.widget_library, open(c, "library", 14))
            manager.updateAppWidget(ComponentName(c, ScheduleWidget::class.java), views)
            NextClassWidget.draw(c, manager, snapshot, now)
            scheduleUpdate(c, snapshot, now)
        }

        private fun pending(c: Context) = PendingIntent.getBroadcast(c, 103,
            Intent(c, WidgetClockReceiver::class.java).setAction("me.windless.niulife.WIDGET_CLOCK"),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        /** Next start or end of a class today, else just after midnight. */
        private fun scheduleUpdate(c: Context, snapshot: Snapshot?, now: ZonedDateTime) {
            val manager = AppWidgetManager.getInstance(c)
            val alarms = c.getSystemService(AlarmManager::class.java)
            val shown = manager.getAppWidgetIds(ComponentName(c, ScheduleWidget::class.java)).isNotEmpty() ||
                manager.getAppWidgetIds(ComponentName(c, NextClassWidget::class.java)).isNotEmpty()
            if (snapshot == null || !shown) {
                alarms.cancel(pending(c))
                return
            }
            val today = now.toLocalDate()
            val minute = now.hour * 60 + now.minute
            val change = snapshot.on(today).flatMap { listOf(it.startMinute, it.endMinute) }
                .filter { it > minute }.minOrNull()
            val at = if (change != null) today.atStartOfDay(scheduleZone).plusMinutes(change.toLong())
                else today.plusDays(1).atStartOfDay(scheduleZone)
            alarms.wakeBy(at.toInstant().toEpochMilli() + 1000, pending(c), now.toInstant().toEpochMilli())
        }
    }
}

/** The class under way or the next one, for a small widget. */
class NextClassWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) =
        ScheduleWidget.refresh(context)
    companion object {
        internal fun draw(c: Context, manager: AppWidgetManager, snapshot: Snapshot?, now: ZonedDateTime) {
            val today = now.toLocalDate()
            val minute = now.hour * 60 + now.minute
            val (label, title, detail) = when (snapshot) {
                null -> Triple("課表", "尚未同步", "開啟 App 同步一次課表")
                else -> describe(snapshot, today, minute)
            }
            val views = RemoteViews(c.packageName, R.layout.next_class_widget)
            views.setTextViewText(R.id.next_label, label)
            views.setTextViewText(R.id.next_title, title)
            views.setTextViewText(R.id.next_detail, detail)
            views.setOnClickPendingIntent(R.id.next_root, open(c, "schedule", 15))
            manager.updateAppWidget(ComponentName(c, NextClassWidget::class.java), views)
        }

        private fun describe(snapshot: Snapshot, today: LocalDate, minute: Int): Triple<String, String, String> {
            val blocks = snapshot.on(today)
            blocks.firstOrNull { it.startMinute <= minute && minute < it.endMinute }?.let {
                return Triple("上課中 · ${clock(it.endMinute)} 下課", it.title, it.room)
            }
            blocks.firstOrNull { it.startMinute > minute }?.let {
                return Triple("下一堂 · ${clock(it.startMinute)}", it.title,
                    listOf("${clock(it.startMinute)}–${clock(it.endMinute)}", it.room).filter(String::isNotBlank)
                        .joinToString(" · "))
            }
            for (ahead in 1L..7L) {
                val date = today.plusDays(ahead)
                val first = snapshot.on(date).firstOrNull() ?: continue
                val day = if (ahead == 1L) "明天" else "週${weekdays[date.dayOfWeek.value - 1]}"
                return Triple("$day ${clock(first.startMinute)}", first.title,
                    listOf("${clock(first.startMinute)}–${clock(first.endMinute)}", first.room)
                        .filter(String::isNotBlank).joinToString(" · "))
            }
            return Triple("課表", "近期沒有課", "")
        }
    }
}

class WidgetClockReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) { ScheduleWidget.refresh(context) }
}
