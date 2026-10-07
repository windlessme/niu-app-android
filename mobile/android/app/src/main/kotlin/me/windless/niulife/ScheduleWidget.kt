package me.windless.niulife

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import java.time.LocalDate
import java.time.ZonedDateTime

/** Today's classes as rows, with the attendance scanner and library pass when there is room. */
class ScheduleWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) = refresh(context)
    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) =
        refresh(context)

    companion object {
        /** Redraws every timetable and calendar widget and wakes again at the next change. */
        fun refresh(c: Context) {
            val manager = AppWidgetManager.getInstance(c)
            val now = ZonedDateTime.now(scheduleZone)
            val snapshot = ScheduleStore.load(c)
            for (id in manager.ids(c, ScheduleWidget::class.java)) {
                manager.updateAppWidget(id, draw(c, snapshot, now, manager.heightDp(id, 180)))
            }
            NextClassWidget.draw(c, manager, snapshot, now)
            WeekWidget.draw(c, manager, snapshot, now)
            CalendarWidget.draw(c, manager, now.toLocalDate())
            scheduleUpdate(c, manager, snapshot, now)
        }

        internal fun draw(c: Context, snapshot: Snapshot?, now: ZonedDateTime, heightDp: Int): RemoteViews {
            val today = now.toLocalDate()
            val minute = now.hour * 60 + now.minute
            val views = RemoteViews(c.packageName, R.layout.schedule_widget)
            views.setOnClickPendingIntent(R.id.widget_root, openApp(c, "schedule", 10))
            views.setOnClickPendingIntent(R.id.widget_attendance, openApp(c, "attendance", 13))
            views.setOnClickPendingIntent(R.id.widget_library, openApp(c, "library", 14))
            val actions = heightDp >= 230
            views.setViewVisibility(R.id.widget_actions, if (actions) View.VISIBLE else View.GONE)
            val blocks = snapshot?.on(today).orEmpty()
            val date = "${today.monthValue}/${today.dayOfMonth} 週${weekday(today)}"
            views.setTextViewText(R.id.widget_subtitle, if (blocks.isEmpty()) date else "$date · ${blocks.size} 堂課")
            views.removeAllViews(R.id.widget_rows)
            if (snapshot == null || blocks.isEmpty()) {
                views.setViewVisibility(R.id.widget_rows, View.GONE)
                views.setViewVisibility(R.id.widget_more, View.GONE)
                views.setViewVisibility(R.id.widget_status, View.GONE)
                views.setViewVisibility(R.id.widget_empty, View.VISIBLE)
                views.setTextViewText(R.id.widget_empty_title, if (snapshot == null) "尚未同步課表" else "今天沒有課")
                views.setTextViewText(R.id.widget_empty_detail,
                    if (snapshot == null) "開啟 App 同步一次課表"
                    else nextDay(snapshot, today)?.let { (day, block) -> "$day ${clock(block.startMinute)} ${block.title}" }
                        ?: "近期沒有課")
                return views
            }
            views.setViewVisibility(R.id.widget_rows, View.VISIBLE)
            views.setViewVisibility(R.id.widget_empty, View.GONE)
            val current = blocks.firstOrNull { it.startMinute <= minute && minute < it.endMinute }
            val next = blocks.firstOrNull { it.startMinute > minute }
            views.setViewVisibility(R.id.widget_status, View.VISIBLE)
            views.setTextViewText(R.id.widget_status, when {
                current != null -> "${clock(current.endMinute)} 下課"
                next != null -> "下一堂 ${clock(next.startMinute)}"
                else -> "今天的課結束了"
            })
            // Rows of about 44dp; finished classes give way first when they don't all fit.
            val room = heightDp - 26 - 40 - 8 - (if (actions) 44 else 0) - 16
            val capacity = maxOf(1, room / 44)
            val shown = blocks.toMutableList()
            while (shown.size > capacity && shown.first().endMinute <= minute) shown.removeAt(0)
            val visible = shown.take(capacity)
            for (block in visible) {
                val ended = block.endMinute <= minute
                val row = RemoteViews(c.packageName, R.layout.schedule_widget_row)
                row.setTextViewText(R.id.row_start, clock(block.startMinute))
                row.setTextViewText(R.id.row_end, clock(block.endMinute))
                row.setTextViewText(R.id.row_title, block.title)
                row.setTextViewText(R.id.row_detail,
                    listOf(block.room, block.teacher).filter(String::isNotBlank).joinToString(" · "))
                if (ended) row.setImageViewResource(R.id.row_bar, R.drawable.widget_bar_muted)
                else row.setLessonBar(R.id.row_bar, block, c)
                row.setViewVisibility(R.id.row_badge, if (block === current) View.VISIBLE else View.GONE)
                row.setViewVisibility(R.id.row_next, if (block === next && current == null) View.VISIBLE else View.GONE)
                if (ended) row.setFloat(R.id.row_root, "setAlpha", 0.5f)
                views.addView(R.id.widget_rows, row)
            }
            val hidden = blocks.size - visible.size
            views.setViewVisibility(R.id.widget_more, if (hidden > 0) View.VISIBLE else View.GONE)
            if (hidden > 0) views.setTextViewText(R.id.widget_more, "還有 $hidden 堂 · ${clock(blocks.last().endMinute)} 下課")
            return views
        }

        /** The first day after [today], within a week, that has classes. */
        internal fun nextDay(snapshot: Snapshot, today: LocalDate): Pair<String, Block>? {
            for (ahead in 1L..7L) {
                val date = today.plusDays(ahead)
                val first = snapshot.on(date).firstOrNull() ?: continue
                return (if (ahead == 1L) "明天" else "週${weekday(date)}") to first
            }
            return null
        }

        private fun pending(c: Context) = PendingIntent.getBroadcast(c, 103,
            Intent(c, WidgetClockReceiver::class.java).setAction("me.windless.niulife.WIDGET_CLOCK"),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        /** Next start or end of a class today, else just after midnight. */
        private fun scheduleUpdate(c: Context, manager: AppWidgetManager, snapshot: Snapshot?, now: ZonedDateTime) {
            val alarms = c.getSystemService(AlarmManager::class.java)
            val timetable = listOf(ScheduleWidget::class.java, NextClassWidget::class.java, WeekWidget::class.java)
                .any { manager.ids(c, it).isNotEmpty() }
            val calendar = manager.ids(c, CalendarWidget::class.java).isNotEmpty()
            if (!calendar && (snapshot == null || !timetable)) {
                alarms.cancel(pending(c))
                return
            }
            val today = now.toLocalDate()
            val minute = now.hour * 60 + now.minute
            val change = if (snapshot == null || !timetable) null
                else snapshot.on(today).flatMap { listOf(it.startMinute, it.endMinute) }.filter { it > minute }.minOrNull()
            val at = if (change != null) today.atStartOfDay(scheduleZone).plusMinutes(change.toLong())
                else today.plusDays(1).atStartOfDay(scheduleZone)
            alarms.wakeBy(at.toInstant().toEpochMilli() + 1000, pending(c), now.toInstant().toEpochMilli())
        }
    }
}

/** The class under way or the next one, and what follows it, for a small widget. */
class NextClassWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) =
        ScheduleWidget.refresh(context)
    companion object {
        internal fun draw(c: Context, manager: AppWidgetManager, snapshot: Snapshot?, now: ZonedDateTime) {
            val today = now.toLocalDate()
            val minute = now.hour * 60 + now.minute
            val next = when (snapshot) {
                null -> Next("課表", "尚未同步", "開啟 App 同步一次課表", null)
                else -> describe(snapshot, today, minute)
            }
            val views = RemoteViews(c.packageName, R.layout.next_class_widget)
            views.setTextViewText(R.id.next_label, next.label)
            views.setTextViewText(R.id.next_title, next.title)
            views.setTextViewText(R.id.next_detail, next.detail)
            views.setViewVisibility(R.id.next_after, if (next.after == null) View.GONE else View.VISIBLE)
            views.setTextViewText(R.id.next_after, next.after ?: "")
            views.setOnClickPendingIntent(R.id.next_root, openApp(c, "schedule", 15))
            for (id in manager.ids(c, NextClassWidget::class.java)) manager.updateAppWidget(id, views)
        }

        private data class Next(val label: String, val title: String, val detail: String, val after: String?)

        private fun span(block: Block) = listOf("${clock(block.startMinute)}–${clock(block.endMinute)}", block.room)
            .filter(String::isNotBlank).joinToString(" · ")

        private fun describe(snapshot: Snapshot, today: LocalDate, minute: Int): Next {
            val blocks = snapshot.on(today)
            fun after(block: Block) = blocks.firstOrNull { it.startMinute >= block.endMinute }
                ?.let { "接著 ${clock(it.startMinute)} ${it.title}" }
            blocks.firstOrNull { it.startMinute <= minute && minute < it.endMinute }?.let {
                return Next("上課中 · ${clock(it.endMinute)} 下課", it.title, it.room, after(it))
            }
            blocks.firstOrNull { it.startMinute > minute }?.let {
                return Next("下一堂 · ${clock(it.startMinute)}", it.title, span(it), after(it))
            }
            ScheduleWidget.nextDay(snapshot, today)?.let { (day, block) ->
                return Next("$day ${clock(block.startMinute)}", block.title, span(block), null)
            }
            return Next("課表", "近期沒有課", "", null)
        }
    }
}

class WidgetClockReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) { ScheduleWidget.refresh(context) }
}
