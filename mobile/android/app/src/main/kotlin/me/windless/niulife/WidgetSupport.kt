package me.windless.niulife

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import java.time.LocalDate

internal fun clock(minute: Int) = "%02d:%02d".format(minute / 60, minute % 60)

internal val weekdays = listOf("一", "二", "三", "四", "五", "六", "日")

internal fun weekday(date: LocalDate) = weekdays[date.dayOfWeek.value - 1]

/** Opens a page of the app, e.g. `schedule`, through its `niulife://` link. */
internal fun openApp(c: Context, target: String, request: Int): PendingIntent = PendingIntent.getActivity(
    c, request, Intent(c, MainActivity::class.java).setAction(Intent.ACTION_VIEW)
        .setData(Uri.parse("niulife://$target")),
    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

internal fun AppWidgetManager.ids(c: Context, provider: Class<*>): IntArray =
    getAppWidgetIds(ComponentName(c, provider))

/** The widget's height in dp as placed on the home screen, in portrait. */
internal fun AppWidgetManager.heightDp(id: Int, fallback: Int): Int =
    getAppWidgetOptions(id).getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT).takeIf { it > 0 } ?: fallback

private val lessonTiles = intArrayOf(
    R.drawable.widget_lesson_0, R.drawable.widget_lesson_1, R.drawable.widget_lesson_2, R.drawable.widget_lesson_3,
    R.drawable.widget_lesson_4, R.drawable.widget_lesson_5, R.drawable.widget_lesson_6, R.drawable.widget_lesson_7)
private val lessonBars = intArrayOf(
    R.drawable.widget_bar_0, R.drawable.widget_bar_1, R.drawable.widget_bar_2, R.drawable.widget_bar_3,
    R.drawable.widget_bar_4, R.drawable.widget_bar_5, R.drawable.widget_bar_6, R.drawable.widget_bar_7)

/** Same hash and palette as the app's week view (`lessonHue`), so a course keeps its colour. */
private fun lessonIndex(name: String): Int {
    var hash = 0
    for (ch in name) hash = (hash * 31 + ch.code) and 0x7fffffff
    return hash % lessonTiles.size
}

internal fun lessonTile(name: String) = lessonTiles[lessonIndex(name)]
internal fun lessonBar(name: String) = lessonBars[lessonIndex(name)]
