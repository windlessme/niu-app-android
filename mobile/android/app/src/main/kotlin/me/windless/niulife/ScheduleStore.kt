package me.windless.niulife

import android.content.Context
import org.json.JSONObject
import java.time.LocalDate
import java.time.ZoneId

internal val scheduleZone: ZoneId = ZoneId.of("Asia/Taipei")
internal data class Block(val id: String, val title: String, val room: String,
    val weekday: Int, val startMinute: Int, val endMinute: Int)
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
                    b.getInt("weekday"), b.getInt("startMinute"), b.getInt("endMinute")).also {
                    require(it.id.isNotBlank() && it.title.isNotBlank() && it.weekday in 1..7 &&
                        it.startMinute in 0..1439 && it.endMinute in 1..1440 && it.endMinute > it.startMinute)
                }
            }
            require(blocks.map { it.id }.distinct().size == blocks.size)
            return Snapshot(start, end, blocks)
        }
    }
    fun on(date: LocalDate): List<Block> = if (date < start || date > end) emptyList()
        else blocks.filter { it.weekday == date.dayOfWeek.value }.sortedBy { it.startMinute }
}

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
        ScheduleWidget.refresh(c)
    }
    fun clear(c: Context) {
        ScheduleReminders.cancel(c)
        CampusNotifications.clear(c)
        check(prefs(c).edit().clear().commit())
        c.cacheDir.resolve("calendar_exports").deleteRecursively()
        ScheduleWidget.refresh(c)
    }
}
