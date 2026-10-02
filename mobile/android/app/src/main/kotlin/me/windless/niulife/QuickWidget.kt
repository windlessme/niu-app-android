package me.windless.niulife

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews

/** One row of shortcuts: attendance, timetable, M 園區 and the library pass. */
class QuickWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) = refresh(context)
    companion object {
        private val targets = listOf(
            R.id.quick_attendance to "attendance",
            R.id.quick_schedule to "schedule",
            R.id.quick_moodle to "moodle",
            R.id.quick_library to "library",
        )

        fun refresh(c: Context) {
            val views = RemoteViews(c.packageName, R.layout.quick_widget)
            for ((index, target) in targets.withIndex()) {
                val intent = Intent(c, MainActivity::class.java).setAction(Intent.ACTION_VIEW)
                    .setData(Uri.parse("niulife://${target.second}"))
                views.setOnClickPendingIntent(target.first, PendingIntent.getActivity(c, 20 + index, intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
            }
            AppWidgetManager.getInstance(c).updateAppWidget(ComponentName(c, QuickWidget::class.java), views)
        }
    }
}
