package me.windless.niulife

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import java.time.DayOfWeek
import java.time.ZonedDateTime

/**
 * 完整課表: Monday to Friday across (the weekend only when it has classes),
 * one row per hour down. A course fills the hours it covers in its own
 * colour, its name in the first and its room in the second; the class under
 * way is drawn in the accent colour. Built from resources, so it follows the
 * system's light or dark mode.
 */
class WeekWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) =
        ScheduleWidget.refresh(context)
    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) =
        ScheduleWidget.refresh(context)

    companion object {
        internal fun draw(c: Context, manager: AppWidgetManager, snapshot: Snapshot?, now: ZonedDateTime) {
            val ids = manager.ids(c, WeekWidget::class.java)
            if (ids.isEmpty()) return
            val views = build(c, snapshot, now)
            for (id in ids) manager.updateAppWidget(id, views)
        }

        internal fun build(c: Context, snapshot: Snapshot?, now: ZonedDateTime): RemoteViews {
            val views = RemoteViews(c.packageName, R.layout.week_widget)
            views.setOnClickPendingIntent(R.id.week_root, openApp(c, "schedule", 16))
            views.removeAllViews(R.id.week_days)
            views.removeAllViews(R.id.week_grid)
            val today = now.toLocalDate()
            val minute = now.hour * 60 + now.minute
            val monday = today.with(DayOfWeek.MONDAY)
            // At the weekend, with nothing left this week, show the coming one.
            val weekendFree = today.dayOfWeek >= DayOfWeek.SATURDAY &&
                snapshot != null && (today.dayOfWeek.value..7).all { snapshot.on(monday.plusDays(it - 1L)).isEmpty() }
            val start = if (weekendFree) monday.plusDays(7) else monday
            views.setTextViewText(R.id.week_title, if (weekendFree) "下週課表" else "本週課表")
            val days = (0L..6L).map { start.plusDays(it) }.map { it to (snapshot?.on(it).orEmpty()) }
                .filterIndexed { i, (_, blocks) -> i < 5 || blocks.isNotEmpty() }
            val end = days.last().first
            views.setTextViewText(R.id.week_range,
                "${start.monthValue}/${start.dayOfMonth} – ${end.monthValue}/${end.dayOfMonth}")
            val all = days.flatMap { it.second }
            if (snapshot == null || all.isEmpty()) {
                views.setViewVisibility(R.id.week_days, View.GONE)
                views.setViewVisibility(R.id.week_grid, View.GONE)
                views.setViewVisibility(R.id.week_empty, View.VISIBLE)
                views.setTextViewText(R.id.week_empty_title, if (snapshot == null) "尚未同步課表" else "這週沒有課")
                views.setTextViewText(R.id.week_empty_detail, if (snapshot == null) "開啟 App 同步一次課表" else "")
                return views
            }
            views.setViewVisibility(R.id.week_days, View.VISIBLE)
            views.setViewVisibility(R.id.week_grid, View.VISIBLE)
            views.setViewVisibility(R.id.week_empty, View.GONE)
            views.addView(R.id.week_days, RemoteViews(c.packageName, R.layout.week_widget_gutter))
            for ((date, _) in days) {
                val day = RemoteViews(c.packageName,
                    if (date == today) R.layout.week_widget_day_today else R.layout.week_widget_day)
                day.setTextViewText(R.id.day, "${weekday(date)} ${date.dayOfMonth}")
                views.addView(R.id.week_days, day)
            }
            val first = all.minOf { it.startMinute } / 60
            val last = (all.maxOf { it.endMinute } - 1) / 60
            for (hour in first..last) {
                val row = RemoteViews(c.packageName, R.layout.week_widget_row)
                val gutter = RemoteViews(c.packageName, R.layout.week_widget_gutter)
                gutter.setTextViewText(R.id.gutter, "$hour")
                row.addView(R.id.row, gutter)
                for ((date, blocks) in days) {
                    // A class starting in this hour wins over one only running into it.
                    val covering = blocks.filter { it.startMinute < (hour + 1) * 60 && it.endMinute > hour * 60 }
                    val block = covering.firstOrNull { it.startMinute / 60 == hour } ?: covering.firstOrNull()
                    val now = block != null && date == today && block.startMinute <= minute && minute < block.endMinute
                    val cell = RemoteViews(c.packageName,
                        if (now) R.layout.week_widget_cell_now else R.layout.week_widget_cell)
                    if (block != null) {
                        if (now) cell.setInt(R.id.cell, "setBackgroundResource", R.drawable.widget_lesson_now)
                        else cell.setLessonTile(R.id.cell, block, c)
                        cell.setTextViewText(R.id.cell, when (hour - block.startMinute / 60) {
                            0 -> block.title
                            1 -> block.room
                            else -> ""
                        })
                    }
                    row.addView(R.id.row, cell)
                }
                views.addView(R.id.week_grid, row)
            }
            return views
        }
    }
}
