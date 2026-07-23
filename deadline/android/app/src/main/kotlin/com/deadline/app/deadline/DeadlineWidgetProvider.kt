package com.deadline.app.deadline

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/// Reads whatever TaskStore last pushed via HomeWidget.saveWidgetData and
/// paints the next-deadline card. Data is written by the Flutter side; this
/// class only ever renders it.
class DeadlineWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.deadline_widget)

            val title = widgetData.getString("title", "Nothing due") ?: "Nothing due"
            val countdown = widgetData.getString("countdown", "") ?: ""
            val overdue = widgetData.getString("overdue", "") ?: ""

            views.setTextViewText(R.id.widget_title, title)
            views.setTextViewText(R.id.widget_countdown, countdown)
            if (overdue.isNotEmpty()) {
                views.setTextViewText(R.id.widget_overdue, overdue)
                views.setViewVisibility(R.id.widget_overdue, View.VISIBLE)
            } else {
                views.setViewVisibility(R.id.widget_overdue, View.GONE)
            }

            val pendingIntent = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)

            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
