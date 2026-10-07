package me.windless.niulife

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import org.json.JSONObject
import java.time.LocalDate
import java.time.ZoneId

internal val scheduleZone: ZoneId = ZoneId.of("Asia/Taipei")

/**
 * Wakes no later than [at] without exact-alarm access. An inexact alarm may
 * fire up to 75% of its delay late (capped at an hour), so a far wake lands
 * part way there and the receiver sets the next, closer one; the last step
 * is at most a minute out. Doze can still defer it.
 */
internal fun AlarmManager.wakeBy(at: Long, op: PendingIntent, now: Long = System.currentTimeMillis()) {
    val delay = at - now
    val trigger = if (delay <= 60_000) at else now + (delay / 1.75).toLong()
    setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, trigger, op)
}
/** [lastDay]: a custom course is not shown after it, even if the app isn't opened. */
internal data class Block(val id: String, val title: String, val room: String,
    val weekday: Int, val startMinute: Int, val endMinute: Int, val lastDay: LocalDate? = null,
    val teacher: String = "",
    /** A custom course's chosen colour (light, dark); null colours it by title. */
    val color: Int? = null, val colorDark: Int? = null)
internal data class Snapshot(val start: LocalDate, val end: LocalDate, val blocks: List<Block>) {
    companion object {
        fun parse(json: JSONObject): Snapshot {
            require(json.getInt("version") == 1 && json.getString("timeZone") == "Asia/Taipei")
            val start = LocalDate.parse(json.getString("semesterStart"))
            val end = LocalDate.parse(json.getString("semesterEnd"))
            require(!end.isBefore(start) && end.toEpochDay() - start.toEpochDay() <= 366)
            val entries = json.getJSONArray("blocks")
            require(entries.length() <= 200)
            val blocks = (0 until entries.length()).map { i ->
                val b = entries.getJSONObject(i)
                Block(b.getString("id"), b.getString("title"), b.optString("room"),
                    b.getInt("weekday"), b.getInt("startMinute"), b.getInt("endMinute"),
                    b.optString("lastDay").takeIf { it.isNotEmpty() }?.let(LocalDate::parse),
                    b.optString("teacher"), hexColor(b.optString("color")),
                    hexColor(b.optString("colorDark"))).also {
                    require(it.id.isNotBlank() && it.title.isNotBlank() && it.weekday in 1..7 &&
                        it.startMinute in 0..1439 && it.endMinute in 1..1440 && it.endMinute > it.startMinute)
                }
            }
            require(blocks.map { it.id }.distinct().size == blocks.size)
            return Snapshot(start, end, blocks)
        }
    }
    fun on(date: LocalDate): List<Block> = if (date < start || date > end) emptyList()
        else blocks.filter { it.weekday == date.dayOfWeek.value && (it.lastDay == null || !date.isAfter(it.lastDay)) }
            .sortedBy { it.startMinute }
}

/** `#RRGGBB` → opaque ARGB, or null. */
internal fun hexColor(value: String): Int? =
    if (value.length == 7 && value[0] == '#') value.substring(1).toIntOrNull(16)?.let { it or 0xFF000000.toInt() }
    else null

internal object ScheduleStore {
    fun prefs(c: Context) = c.getSharedPreferences("schedule_v1", Context.MODE_PRIVATE)
    fun load(c: Context): Snapshot? = runCatching {
        Snapshot.parse(JSONObject(prefs(c).getString("snapshot", null) ?: return null))
    }.getOrNull()
    fun save(c: Context, json: JSONObject) {
        require(json.toString().toByteArray().size <= 256 * 1024)
        Snapshot.parse(json)
        check(prefs(c).edit().putString("snapshot", json.toString()).commit())
        ScheduleReminders.reschedule(c)
        ClassInProgress.refresh(c)
        ScheduleWidget.refresh(c)
    }
    fun clear(c: Context) {
        ScheduleReminders.cancel(c)
        ClassInProgress.cancel(c)
        CampusNotifications.clear(c)
        check(prefs(c).edit().clear().commit())
        c.cacheDir.resolve("calendar_exports").deleteRecursively()
        ScheduleWidget.refresh(c)
    }
}
