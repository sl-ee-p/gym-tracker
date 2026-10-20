package com.slp.platelog

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Shows the weekly goal and workout heatmap on the home screen.
 *
 * The content is drawn in Dart — HomeWidgetService renders the app's own
 * canvas to a PNG and stores its path under [IMAGE_KEY]. This class blits
 * that file and draws the card around it. Rebuilding the grid natively would
 * mean up to 364 nested RemoteViews and a Kotlin reimplementation of the
 * Material 3 tonal palette the empty cells are coloured from.
 *
 * The card *is* native, though, and that split is deliberate: the PNG has one
 * fixed aspect ratio while a resizable launcher cell has many, so a card
 * baked into the image could only ever be letterboxed inside the box. Drawing
 * it here means it fills the box at every size, tinted to match the theme the
 * image was rendered with.
 */
class HeatmapWidgetProvider : HomeWidgetProvider() {

    companion object {
        /** Must match HomeWidgetService.imageKey on the Dart side. */
        private const val IMAGE_KEY = "hw_heatmap_image"

        /**
         * Must match HomeWidgetService's backgroundColorKey, borderColorKey
         * and textColorKey.
         *
         * Stored as decimal *strings*: an ARGB value with a full alpha byte
         * overflows 32-bit signed, so an int would cross the platform channel
         * as an Int for some colours and a Long for others and then throw a
         * ClassCastException here on whichever one this didn't expect.
         */
        private const val BACKGROUND_COLOR_KEY = "hw_background_color"
        private const val BORDER_COLOR_KEY = "hw_border_color"
        private const val TEXT_COLOR_KEY = "hw_text_color"

        private const val LAUNCH_URI = "gymtracker://heatmap"
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val backgroundColor = widgetData.color(BACKGROUND_COLOR_KEY)
        val borderColor = widgetData.color(BORDER_COLOR_KEY)
        val textColor = widgetData.color(TEXT_COLOR_KEY)

        appWidgetIds.forEach { appWidgetId ->
            // A fresh RemoteViews per id — reusing one instance across
            // updateAppWidget calls is not safe on every API level.
            val views = RemoteViews(context.packageName, R.layout.hw_heatmap_widget)

            // ImageView.setColorFilter(int) is @RemotableViewMethod and tints
            // SRC_ATOP, so the shape's alpha survives — which is what lets the
            // 1dp stroke layer be transparent everywhere but the stroke.
            // Left untinted when absent: the drawables carry light/-night
            // fallbacks for the cold start before Dart has saved a theme.
            if (backgroundColor != null) {
                views.setInt(R.id.hw_background, "setColorFilter", backgroundColor)
            }
            if (borderColor != null) {
                views.setInt(R.id.hw_border, "setColorFilter", borderColor)
            }
            // The placeholder sits on the tinted card, so it has to follow the
            // *app's* theme, not the system's. Its @color fallback is
            // -night-qualified, which is only right until Dart has saved one.
            if (textColor != null) {
                views.setInt(R.id.hw_placeholder, "setTextColor", textColor)
            }

            val path = widgetData.getString(IMAGE_KEY, null)
            // decodeFile returns null rather than throwing when the file is
            // gone — after "Clear app data", or before the app has ever been
            // opened. Both must fall back to the placeholder, otherwise the
            // widget is a silent blank rectangle.
            val bitmap = path?.let { BitmapFactory.decodeFile(it) }

            if (bitmap != null) {
                views.setImageViewBitmap(R.id.hw_image, bitmap)
                views.setViewVisibility(R.id.hw_image, View.VISIBLE)
                views.setViewVisibility(R.id.hw_placeholder, View.GONE)
            } else {
                views.setViewVisibility(R.id.hw_image, View.GONE)
                views.setViewVisibility(R.id.hw_placeholder, View.VISIBLE)
            }

            views.setOnClickPendingIntent(
                R.id.hw_root,
                HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse(LAUNCH_URI),
                ),
            )

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    /**
     * The colour saved under [key], or null when the app has not written one
     * yet. Anything missing, unparseable, or stored under a different type is
     * treated the same way — a card in its fallback colour beats an
     * exception, which the launcher renders as "Problem loading widget".
     */
    private fun SharedPreferences.color(key: String): Int? =
        runCatching { getString(key, null)?.toLongOrNull()?.toInt() }.getOrNull()
}
