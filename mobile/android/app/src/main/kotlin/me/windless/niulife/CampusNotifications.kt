package me.windless.niulife

import android.app.*
import android.content.*
import android.net.Uri
import org.json.JSONArray
import org.json.JSONObject

/// One-shot reminders computed by Flutter (assignment deadlines, important
/// calendar dates). Each kind is replaced as a whole; one alarm steps toward
/// the earliest pending one.
internal object CampusNotifications {
    private const val requestCode = 101
    private const val lateLimit = 6 * 60 * 60 * 1000L
    private val channels = mapOf(
        "assignments" to ("assignments_v1" to "作業死線"),
        "calendar" to ("calendar_v1" to "重要日期"),
        "events" to ("events_v1" to "活動提醒"),
    )
    private val links = setOf("niulife://moodle", "niulife://calendar", "niulife://schedule", "niulife://events")

    private fun prefs(c: Context) = c.getSharedPreferences("notifications_v1", Context.MODE_PRIVATE)
    private fun pending(c: Context) = PendingIntent.getBroadcast(c, requestCode,
        Intent(c, CampusNotificationReceiver::class.java).setAction("me.windless.niulife.CAMPUS_NOTIFICATION"),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    private fun items(c: Context, kind: String): JSONArray =
        runCatching { JSONArray(prefs(c).getString(kind, "[]")) }.getOrDefault(JSONArray())
    private fun all(c: Context) = channels.keys.flatMap { kind ->
        items(c, kind).let { list -> (0 until list.length()).map { kind to list.getJSONObject(it) } }
    }

    fun replace(c: Context, kind: String, list: List<Map<*, *>>) {
        require(kind in channels && list.size <= 50)
        val stored = JSONArray()
        for (item in list) {
            val entry = JSONObject(item)
            require(entry.getString("id").isNotBlank() && entry.getString("title").isNotBlank() &&
                entry.getLong("at") > 0 && entry.optString("link") in links)
            entry.getString("body")
            stored.put(entry)
        }
        check(prefs(c).edit().putString(kind, stored.toString()).commit())
        reschedule(c)
    }

    fun clear(c: Context) {
        c.getSystemService(AlarmManager::class.java).cancel(pending(c))
        val manager = c.getSystemService(NotificationManager::class.java)
        for ((kind, item) in all(c)) manager.cancel(notificationId(kind, item))
        prefs(c).edit().clear().commit()
    }

    fun reschedule(c: Context) {
        val alarms = c.getSystemService(AlarmManager::class.java)
        alarms.cancel(pending(c))
        val next = all(c).minOfOrNull { it.second.getLong("at") } ?: return
        // Inexact, stepping closer on each wake (an early wake delivers
        // nothing and lands here again); Doze can still delay delivery.
        val now = System.currentTimeMillis()
        alarms.wakeBy(maxOf(next, now), pending(c), now)
    }

    fun deliver(c: Context) {
        val now = System.currentTimeMillis()
        val manager = c.getSystemService(NotificationManager::class.java)
        val editor = prefs(c).edit()
        for ((kind, info) in channels) {
            val list = items(c, kind)
            val keep = JSONArray()
            for (i in 0 until list.length()) {
                val item = list.getJSONObject(i)
                val at = item.getLong("at")
                when {
                    at > now -> keep.put(item)
                    now - at < lateLimit && ScheduleReminders.permitted(c) -> {
                        manager.createNotificationChannel(
                            NotificationChannel(info.first, info.second, NotificationManager.IMPORTANCE_DEFAULT))
                        manager.notify(notificationId(kind, item), build(c, info.first, item))
                    }
                }
            }
            editor.putString(kind, keep.toString())
        }
        editor.commit()
        reschedule(c)
    }

    private fun notificationId(kind: String, item: JSONObject) =
        "$kind/${item.getString("id")}".hashCode().let { if (it in 100..199) it + 1000 else it }

    private fun build(c: Context, channel: String, item: JSONObject): Notification {
        val open = PendingIntent.getActivity(c, notificationId(channel, item),
            Intent(c, MainActivity::class.java).setAction(Intent.ACTION_VIEW)
                .setData(Uri.parse(item.optString("link", "niulife://schedule"))),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val body = item.getString("body")
        return Notification.Builder(c, channel).setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(item.getString("title")).setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setContentIntent(open).setAutoCancel(true).build()
    }
}

class CampusNotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) { CampusNotifications.deliver(context) }
}
