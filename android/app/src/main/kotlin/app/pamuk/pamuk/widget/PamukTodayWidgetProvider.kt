package app.pamuk.pamuk.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.content.res.Configuration
import android.content.res.Resources
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.text.SpannableString
import android.text.Spanned
import android.text.style.StrikethroughSpan
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import app.pamuk.pamuk.MainActivity
import app.pamuk.pamuk.R
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import java.util.Locale
import kotlin.math.floor

/**
 * "Pamuk · Today" home-screen widget.
 *
 * Data comes from the Flutter side:
 * ```dart
 * HomeWidget.saveWidgetData<String>('pamuk_today', jsonString);
 * HomeWidget.updateWidget(qualifiedAndroidName: 'app.pamuk.pamuk.widget.PamukTodayWidgetProvider');
 * ```
 * Rendering uses plain RemoteViews with pre-declared rows (no RemoteViewsService / ListView).
 * The JSON is parsed once per update and shared by every widget instance and size.
 */
class PamukTodayWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        if (appWidgetIds.isEmpty()) return
        // Parsed once; shared by every instance and every size variant below.
        val render = RenderInput.create(context, widgetData.getString(DATA_KEY, null))
        for (appWidgetId in appWidgetIds) {
            val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
            appWidgetManager.updateAppWidget(appWidgetId, buildForOptions(context, render, options))
        }
    }

    /** Re-renders a single instance after the user resized it. */
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle?,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        val render = RenderInput.create(context, HomeWidgetPlugin.getData(context).getString(DATA_KEY, null))
        appWidgetManager.updateAppWidget(appWidgetId, buildForOptions(context, render, newOptions))
    }

    /** Everything a render needs that does not depend on the widget size. */
    private class RenderInput(
        val data: PamukTodayData?,
        val res: Resources,
        val stale: Boolean,
        val launch: PendingIntent,
    ) {
        companion object {
            fun create(context: Context, json: String?): RenderInput {
                val data = PamukTodayData.parse(json)
                return RenderInput(
                    data = data,
                    res = if (data == null) context.resources else localizedResources(context, data.lang),
                    stale = data?.isStale() ?: false,
                    launch = launchIntent(context),
                )
            }

            /** Resources in the app's language ("lang" in the JSON) for the few strings drawn natively. */
            private fun localizedResources(context: Context, lang: String): Resources {
                if (lang.isEmpty()) return context.resources
                val wanted = Locale.forLanguageTag(lang)
                val base = context.resources.configuration
                if (wanted.language.isEmpty() || base.locales.get(0)?.language == wanted.language) {
                    return context.resources
                }
                val config = Configuration(base)
                config.setLocale(wanted)
                return context.createConfigurationContext(config).resources
            }

            private fun launchIntent(context: Context): PendingIntent =
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse(LAUNCH_URI))
        }
    }

    private fun buildForOptions(context: Context, render: RenderInput, options: Bundle?): RemoteViews {
        // Android 12+: hand the launcher one RemoteViews per size it reported (portrait/landscape),
        // so it can switch layouts on its own without waking the app.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && options != null) {
            val sizes = readSizes(options)
            if (!sizes.isNullOrEmpty()) {
                val bySize = LinkedHashMap<SizeF, RemoteViews>()
                for (size in sizes) {
                    if (bySize.size >= MAX_SIZE_MAPPINGS) break
                    if (!bySize.containsKey(size)) {
                        bySize[size] = build(context, render, size.width, size.height)
                    }
                }
                return RemoteViews(bySize)
            }
        }
        // Older Android: portrait size = min width x max height.
        val width = options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0) ?: 0
        val height = options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0) ?: 0
        return build(
            context,
            render,
            if (width > 0) width.toFloat() else DEFAULT_WIDTH_DP,
            if (height > 0) height.toFloat() else DEFAULT_HEIGHT_DP,
        )
    }

    private fun readSizes(options: Bundle): List<SizeF>? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            options.getParcelableArrayList(AppWidgetManager.OPTION_APPWIDGET_SIZES, SizeF::class.java)
        } else {
            @Suppress("DEPRECATION")
            options.getParcelableArrayList<SizeF>(AppWidgetManager.OPTION_APPWIDGET_SIZES)
        }

    private fun build(context: Context, render: RenderInput, widthDp: Float, heightDp: Float): RemoteViews {
        val small = widthDp < WIDE_MIN_WIDTH_DP
        val views = RemoteViews(
            context.packageName,
            if (small) R.layout.pamuk_today_widget_small else R.layout.pamuk_today_widget_medium,
        )
        views.setOnClickPendingIntent(android.R.id.background, render.launch)

        val res = render.res
        val data = render.data
        if (data == null) {
            showPlaceholder(views, res, res.getString(R.string.pamuk_widget_placeholder_text))
            return views
        }
        if (render.stale) {
            // Yesterday's plan must not be shown under "Today".
            showPlaceholder(views, res, res.getString(R.string.pamuk_widget_stale_text))
            return views
        }

        views.setViewVisibility(R.id.pw_placeholder, View.GONE)
        views.setViewVisibility(R.id.pw_content, View.VISIBLE)
        views.setTextViewText(
            R.id.pw_title,
            data.title.ifEmpty { res.getString(R.string.pamuk_widget_default_title) },
        )
        views.setTextViewText(R.id.pw_date, data.dateLabel)

        // Progress (done/total).
        if (data.total > 0) {
            views.setViewVisibility(R.id.pw_progress, View.VISIBLE)
            views.setProgressBar(R.id.pw_progress, data.total, data.done, false)
        } else {
            views.setViewVisibility(R.id.pw_progress, View.GONE)
        }

        var showNext = false
        if (small) {
            views.setTextViewText(R.id.pw_count, if (data.total > 0) "${data.done}/${data.total}" else "")
            views.setViewVisibility(R.id.pw_count, if (data.total > 0) View.VISIBLE else View.GONE)
        } else {
            views.setTextViewText(R.id.pw_progress_label, data.progressLabel)
            views.setViewVisibility(
                R.id.pw_progress_label,
                if (data.progressLabel.isNotEmpty()) View.VISIBLE else View.GONE,
            )
            val next = data.nextReminder
            showNext = next != null && heightDp >= NEXT_MIN_HEIGHT_DP
            if (next != null && showNext) {
                views.setTextViewText(R.id.pw_next_text, nextReminderText(res, next))
            }
            views.setViewVisibility(R.id.pw_next, if (showNext) View.VISIBLE else View.GONE)
        }

        bindRows(views, res, data, small, heightDp, showNext)
        return views
    }

    private fun bindRows(
        views: RemoteViews,
        res: Resources,
        data: PamukTodayData,
        small: Boolean,
        heightDp: Float,
        showNext: Boolean,
    ) {
        val items = data.items
        val rowSlots = if (small) SMALL_ROWS else MEDIUM_ROWS
        val capacity = rowCapacity(small, heightDp, showNext).coerceIn(1, rowSlots)
        // When not everything fits, keep the last line for "+N more".
        val shown = if (items.size > capacity) (capacity - 1).coerceAtLeast(1) else items.size

        for (i in 0 until rowSlots) {
            val item = if (i < shown) items[i] else null
            if (item == null) {
                views.setViewVisibility(ROW_IDS[i], View.GONE)
                continue
            }
            views.setViewVisibility(ROW_IDS[i], View.VISIBLE)
            views.setImageViewResource(DOT_IDS[i], markerFor(item.kind))
            views.setInt(DOT_IDS[i], "setColorFilter", item.color)
            views.setInt(DOT_IDS[i], "setImageAlpha", if (item.done) DONE_MARKER_ALPHA else 255)
            views.setTextViewText(ITEM_IDS[i], if (item.done) strikeThrough(item.title) else item.title)
            // Disabled state switches to the dimmed colour of the @color/pamuk_widget_item_* selectors.
            views.setBoolean(ITEM_IDS[i], "setEnabled", !item.done)
            if (item.time.isEmpty()) {
                views.setViewVisibility(TIME_IDS[i], View.GONE)
            } else {
                views.setViewVisibility(TIME_IDS[i], View.VISIBLE)
                views.setTextViewText(TIME_IDS[i], item.time)
                views.setBoolean(TIME_IDS[i], "setEnabled", !item.done)
            }
        }

        val hidden = items.size - shown
        if (hidden > 0) {
            views.setTextViewText(R.id.pw_more, res.getString(R.string.pamuk_widget_more, hidden))
            views.setViewVisibility(R.id.pw_more, View.VISIBLE)
        } else {
            views.setViewVisibility(R.id.pw_more, View.GONE)
        }

        if (items.isEmpty() && data.emptyText.isNotEmpty()) {
            views.setTextViewText(R.id.pw_empty, data.emptyText)
            views.setViewVisibility(R.id.pw_empty, View.VISIBLE)
        } else {
            views.setViewVisibility(R.id.pw_empty, View.GONE)
        }
    }

    private fun showPlaceholder(views: RemoteViews, res: Resources, message: String) {
        views.setViewVisibility(R.id.pw_content, View.GONE)
        views.setViewVisibility(R.id.pw_placeholder, View.VISIBLE)
        views.setTextViewText(
            R.id.pw_placeholder_title,
            res.getString(R.string.pamuk_widget_placeholder_title),
        )
        views.setTextViewText(R.id.pw_placeholder_text, message)
    }

    private fun nextReminderText(res: Resources, next: PamukTodayReminder): String = buildString {
        append(res.getString(R.string.pamuk_widget_next_label))
        append(" · ")
        if (next.time.isNotEmpty()) {
            append(next.time)
            append("  ")
        }
        append(next.title)
    }

    private fun rowCapacity(small: Boolean, heightDp: Float, withNext: Boolean): Int {
        val chrome = if (small) SMALL_CHROME_DP else MEDIUM_CHROME_DP + (if (withNext) NEXT_PILL_DP else 0f)
        val rowHeight = if (small) SMALL_ROW_DP else MEDIUM_ROW_DP
        return floor((heightDp - chrome) / rowHeight).toInt()
    }

    private fun markerFor(kind: String): Int = when (kind) {
        "reminder" -> R.drawable.pamuk_widget_dot_ring
        "event" -> R.drawable.pamuk_widget_dot_event
        else -> R.drawable.pamuk_widget_dot
    }

    private fun strikeThrough(text: String): CharSequence =
        SpannableString(text).apply {
            setSpan(StrikethroughSpan(), 0, length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }

    companion object {
        /** Key written by `HomeWidget.saveWidgetData<String>('pamuk_today', ...)`. */
        const val DATA_KEY = "pamuk_today"

        /** Delivered to Dart via HomeWidget.initiallyLaunchedFromHomeWidget() / widgetClicked. */
        const val LAUNCH_URI = "pamuk://today?homeWidget"

        private const val WIDE_MIN_WIDTH_DP = 200f
        private const val DEFAULT_WIDTH_DP = 250f
        private const val DEFAULT_HEIGHT_DP = 110f
        private const val NEXT_MIN_HEIGHT_DP = 170f
        private const val MAX_SIZE_MAPPINGS = 8

        // Rough vertical budget (dp) of everything except item rows, per layout.
        private const val SMALL_CHROME_DP = 72f
        private const val MEDIUM_CHROME_DP = 70f
        private const val NEXT_PILL_DP = 28f
        private const val SMALL_ROW_DP = 18f
        private const val MEDIUM_ROW_DP = 21f

        private const val SMALL_ROWS = 3
        private const val MEDIUM_ROWS = PamukTodayData.MAX_ITEMS
        private const val DONE_MARKER_ALPHA = 110

        private val ROW_IDS = intArrayOf(
            R.id.pw_row_0, R.id.pw_row_1, R.id.pw_row_2, R.id.pw_row_3, R.id.pw_row_4, R.id.pw_row_5,
        )
        private val DOT_IDS = intArrayOf(
            R.id.pw_dot_0, R.id.pw_dot_1, R.id.pw_dot_2, R.id.pw_dot_3, R.id.pw_dot_4, R.id.pw_dot_5,
        )
        private val ITEM_IDS = intArrayOf(
            R.id.pw_item_0, R.id.pw_item_1, R.id.pw_item_2, R.id.pw_item_3, R.id.pw_item_4, R.id.pw_item_5,
        )
        private val TIME_IDS = intArrayOf(
            R.id.pw_time_0, R.id.pw_time_1, R.id.pw_time_2, R.id.pw_time_3, R.id.pw_time_4, R.id.pw_time_5,
        )
    }
}
