package com.aistickynotes.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class NotesWidgetProvider : HomeWidgetProvider() {

  override fun onUpdate(
    context: Context,
    appWidgetManager: AppWidgetManager,
    appWidgetIds: IntArray,
    widgetData: SharedPreferences,
  ) {
    appWidgetIds.forEach { widgetId ->
      val views = RemoteViews(context.packageName, R.layout.notes_widget_layout).apply {

        // Open app on widget tap
        val pendingIntent = HomeWidgetLaunchIntent.getActivity(
          context, MainActivity::class.java
        )
        setOnClickPendingIntent(R.id.widget_container, pendingIntent)

        val pinnedTitle = widgetData.getString("pinned_title", null)
        val pinnedBody  = widgetData.getString("pinned_body", null)

        if (!pinnedTitle.isNullOrBlank()) {
          // ── Pinned mode ──────────────────────────────────────
          setTextViewText(R.id.widget_header, "📌 Pinned note")
          setTextViewText(R.id.widget_title, pinnedTitle)

          if (!pinnedBody.isNullOrBlank()) {
            setTextViewText(R.id.widget_body, pinnedBody)
            setViewVisibility(R.id.widget_body, View.VISIBLE)
          } else {
            setViewVisibility(R.id.widget_body, View.GONE)
          }
        } else {
          // ── Auto mode (latest notes) ─────────────────────────
          val count = widgetData.getInt("notes_count", 0)
          val plural = if (count == 1) "note" else "notes"
          setTextViewText(R.id.widget_header, "$count $plural")

          val latestTitle = widgetData.getString("notes_title", null)
          setTextViewText(
            R.id.widget_title,
            latestTitle ?: context.getString(R.string.widget_no_notes)
          )
          setViewVisibility(R.id.widget_body, View.GONE)
        }
      }

      appWidgetManager.updateAppWidget(widgetId, views)
    }
  }
}
