package app.pamnot.pamnot.widget

import android.graphics.Color
import org.json.JSONObject
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId

/** One row of the widget (`items[]` in the `pamnot_today` JSON). */
internal class PamnotTodayItem(
    val title: String,
    val time: String,
    val kind: String,
    val done: Boolean,
    val color: Int,
)

/** `nextReminder` in the `pamnot_today` JSON. */
internal class PamnotTodayReminder(val title: String, val time: String)

/**
 * Parsed form of the `pamnot_today` JSON written by the Flutter side. All strings are already
 * localized by the app. [parse] never throws; it returns null for missing/invalid data so the
 * widget falls back to its placeholder.
 */
internal class PamnotTodayData(
    val updatedDate: LocalDate?,
    val lang: String,
    val title: String,
    val dateLabel: String,
    val done: Int,
    val total: Int,
    val progressLabel: String,
    val emptyText: String,
    val items: List<PamnotTodayItem>,
    val nextReminder: PamnotTodayReminder?,
) {
    /** True when the data was written on an earlier calendar day than today (device time zone). */
    fun isStale(today: LocalDate = LocalDate.now()): Boolean =
        updatedDate != null && updatedDate.isBefore(today)

    companion object {
        const val MAX_ITEMS = 6

        private const val LAVENDER = 0xFF9B8AD8.toInt()
        private const val PEACH = 0xFFF2A88A.toInt()
        private const val MINT = 0xFF86C5B0.toInt()

        fun parse(raw: String?): PamnotTodayData? {
            if (raw.isNullOrBlank()) return null
            return try {
                val json = JSONObject(raw)
                val items = ArrayList<PamnotTodayItem>(MAX_ITEMS)
                val array = json.optJSONArray("items")
                if (array != null) {
                    var i = 0
                    while (i < array.length() && items.size < MAX_ITEMS) {
                        val obj = array.optJSONObject(i)
                        i++
                        if (obj == null) continue
                        val title = obj.str("title")
                        if (title.isEmpty()) continue
                        val kind = obj.str("kind")
                        items.add(
                            PamnotTodayItem(
                                title = title,
                                time = obj.str("time"),
                                kind = kind,
                                done = obj.optBoolean("done", false),
                                color = parseColor(obj.str("color"), fallbackColor(kind)),
                            ),
                        )
                    }
                }
                val total = json.optInt("total", items.size).coerceAtLeast(0)
                val next = json.optJSONObject("nextReminder")?.let {
                    val title = it.str("title")
                    if (title.isEmpty()) null else PamnotTodayReminder(title, it.str("time"))
                }
                PamnotTodayData(
                    updatedDate = localDateOf(json.str("updatedAt")),
                    lang = json.str("lang"),
                    title = json.str("title"),
                    dateLabel = json.str("dateLabel"),
                    done = json.optInt("done", 0).coerceIn(0, total),
                    total = total,
                    progressLabel = json.str("progressLabel"),
                    emptyText = json.str("emptyText"),
                    items = items,
                    nextReminder = next,
                )
            } catch (e: Exception) {
                null
            }
        }

        /** optString() turns JSON null into the text "null"; treat null/missing as empty. */
        private fun JSONObject.str(key: String): String =
            if (isNull(key)) "" else optString(key, "").trim()

        private fun fallbackColor(kind: String): Int = when (kind) {
            "reminder" -> PEACH
            "event" -> MINT
            else -> LAVENDER
        }

        private fun parseColor(value: String, fallback: Int): Int {
            if (value.isEmpty()) return fallback
            val normalized = if (value.startsWith("#")) value else "#$value"
            return try {
                Color.parseColor(normalized)
            } catch (e: IllegalArgumentException) {
                fallback
            }
        }

        /**
         * Accepts Dart's `DateTime.toIso8601String()` output, local ("2026-10-27T10:00:00.000") or
         * UTC ("...Z"). Unknown formats yield null, which never marks the data as stale.
         */
        private fun localDateOf(iso: String): LocalDate? {
            if (iso.length < 10) return null
            return try {
                if (iso.endsWith("Z") || iso.lastIndexOf('+') > 10 || iso.lastIndexOf('-') > 10) {
                    OffsetDateTime.parse(iso).atZoneSameInstant(ZoneId.systemDefault()).toLocalDate()
                } else if (iso.length > 10) {
                    LocalDateTime.parse(iso).toLocalDate()
                } else {
                    LocalDate.parse(iso)
                }
            } catch (e: Exception) {
                try {
                    LocalDate.parse(iso.substring(0, 10))
                } catch (e2: Exception) {
                    null
                }
            }
        }
    }
}
