package me.windless.niulife

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import java.time.LocalDate
import java.time.temporal.ChronoUnit

internal data class CalendarItem(val title: String, val start: LocalDate, val end: LocalDate)

/**
 * The academic calendar the app last loaded, kept on the device so the widget
 * works offline. It is the school's public calendar, not account data, so it
 * stays after sign-out.
 */
internal object CalendarWidgetStore {
    private fun prefs(c: Context) = c.getSharedPreferences("calendar_widget_v1", Context.MODE_PRIVATE)

    fun save(c: Context, events: List<Map<*, *>>) {
        val array = JSONArray()
        for (event in events.take(200)) {
            val item = CalendarItem("${event["title"]}".trim(), LocalDate.parse("${event["start"]}"),
                LocalDate.parse("${event["end"]}"))
            require(item.title.isNotEmpty() && !item.end.isBefore(item.start))
            array.put(org.json.JSONObject().put("title", item.title).put("start", "${item.start}")
                .put("end", "${item.end}"))
        }
        check(prefs(c).edit().putString("events", array.toString()).commit())
        ScheduleWidget.refresh(c)
    }

    fun load(c: Context): List<CalendarItem>? = runCatching {
        val array = JSONArray(prefs(c).getString("events", null) ?: return null)
        (0 until array.length()).map {
            val e = array.getJSONObject(it)
            CalendarItem(e.getString("title"), LocalDate.parse(e.getString("start")), LocalDate.parse(e.getString("end")))
        }
    }.getOrNull()
}

/** What is on today, then the dates that come next. */
class CalendarWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) =
        ScheduleWidget.refresh(context)
    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) =
        ScheduleWidget.refresh(context)

    companion object {
        internal fun draw(c: Context, manager: AppWidgetManager, today: LocalDate) {
            val ids = manager.ids(c, CalendarWidget::class.java)
            if (ids.isEmpty()) return
            val events = CalendarWidgetStore.load(c)
            for (id in ids) manager.updateAppWidget(id, build(c, events, today, manager.heightDp(id, 110)))
        }

        /** Events under way (those starting today first), then upcoming ones by date. */
        internal fun visible(events: List<CalendarItem>, today: LocalDate): List<CalendarItem> {
            val active = events.filter { !it.start.isAfter(today) && !it.end.isBefore(today) }
                .sortedWith(compareBy<CalendarItem> { it.start != today }.thenBy { it.start })
            val upcoming = events.filter { it.start.isAfter(today) }.sortedBy { it.start }
            return active + upcoming
        }

        /** 學年度 runs from August: 2026-10 is 115. */
        internal fun academicYear(date: LocalDate) = date.year - 1911 - if (date.monthValue < 8) 1 else 0

        private fun short(date: LocalDate) = "${date.monthValue}/${date.dayOfMonth}"

        internal fun detail(event: CalendarItem, today: LocalDate): String {
            if (!event.start.isAfter(today)) {
                return if (event.end == today) "今天" else "進行中 · 至 ${short(event.end)}"
            }
            val days = ChronoUnit.DAYS.between(today, event.start)
            val range = if (event.end == event.start) "${short(event.start)}（週${weekday(event.start)}）"
                else "${short(event.start)} – ${short(event.end)}"
            return when (days) {
                1L -> "明天 · $range"
                else -> "$days 天後 · $range"
            }
        }

        internal fun build(c: Context, events: List<CalendarItem>?, today: LocalDate, heightDp: Int): RemoteViews {
            val views = RemoteViews(c.packageName, R.layout.calendar_widget)
            views.setOnClickPendingIntent(R.id.calendar_root, openApp(c, "calendar", 17))
            views.setTextViewText(R.id.calendar_year, "${academicYear(today)} 學年度")
            views.removeAllViews(R.id.calendar_rows)
            val shown = events?.let { visible(it, today) }.orEmpty()
            if (shown.isEmpty()) {
                views.setViewVisibility(R.id.calendar_rows, View.GONE)
                views.setViewVisibility(R.id.calendar_empty, View.VISIBLE)
                views.setTextViewText(R.id.calendar_empty_title, if (events == null) "尚未取得行事曆" else "目前沒有後續事件")
                views.setTextViewText(R.id.calendar_empty_detail,
                    if (events == null) "開啟 App 更新一次" else "開啟 App 查看完整行事曆")
                return views
            }
            views.setViewVisibility(R.id.calendar_rows, View.VISIBLE)
            views.setViewVisibility(R.id.calendar_empty, View.GONE)
            val capacity = maxOf(1, (heightDp - 26 - 26 - 8) / 50)
            for (event in shown.take(capacity)) {
                val row = RemoteViews(c.packageName, R.layout.calendar_widget_row)
                // An event already under way shows today's date on its tile.
                val tile = if (event.start.isAfter(today)) event.start else today
                row.setTextViewText(R.id.event_month, "${tile.monthValue}月")
                row.setTextViewText(R.id.event_day, "${tile.dayOfMonth}")
                row.setTextViewText(R.id.event_title, event.title)
                row.setTextViewText(R.id.event_detail, detail(event, today))
                views.addView(R.id.calendar_rows, row)
            }
            return views
        }
    }
}
