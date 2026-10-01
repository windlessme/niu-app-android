package me.windless.niulife

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import java.time.LocalDate

class ScheduleWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) = refresh(context)
    companion object {
        fun refresh(c: Context) {
            val manager = AppWidgetManager.getInstance(c)
            val today = LocalDate.now(scheduleZone)
            val snapshot = ScheduleStore.load(c)
            val blocks = snapshot?.on(today).orEmpty()
            val body = if (snapshot == null) "開啟 App 登入並同步課表" else if (blocks.isEmpty())
                "今天沒有課程" else blocks.joinToString("\n\n") {
                    "%02d:%02d–%02d:%02d  %s\n%s".format(it.startMinute / 60, it.startMinute % 60,
                        it.endMinute / 60, it.endMinute % 60, it.title, it.room)
                }
            val views = RemoteViews(c.packageName, R.layout.schedule_widget)
            views.setTextViewText(R.id.widget_title, "今日課表 · $today")
            views.setTextViewText(R.id.widget_body, body)
            val intent = Intent(c, MainActivity::class.java).setAction(Intent.ACTION_VIEW)
                .setData(Uri.parse("niulife://schedule"))
            views.setOnClickPendingIntent(R.id.widget_root, PendingIntent.getActivity(c, 10, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
            manager.updateAppWidget(ComponentName(c, ScheduleWidget::class.java), views)
        }
    }
}
