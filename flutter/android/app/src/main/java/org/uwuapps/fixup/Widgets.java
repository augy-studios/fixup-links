/*
 * The home screen widgets, each a tap away from a clean link:
 *
 *   Bar    "Fix a link", a bar like a search box (res/layout/widget_bar.xml): the logo and words
 *          open uwuFix, the paste button at its end fixes the link you've copied
 *   Paste  that paste button on its own, one cell (res/layout/widget_paste.xml)
 *
 * Fixing what's copied opens the quick screen (FixActivity), which reads the clipboard once it's
 * in front: Android 10 and later let only the app in front read it, so a widget can't.
 *
 * Neither shows anything that changes, so nothing refreshes them (updatePeriodMillis="0" in
 * res/xml/widget_*_info.xml). Android draws them when they're added and after the app updates,
 * and the bar again when it's resized, to drop its words when it's too narrow for them.
 */
package org.uwuapps.fixup;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.Context;
import android.content.Intent;
import android.os.Bundle;
import android.view.View;
import android.widget.RemoteViews;

public final class Widgets {
    // Narrower than this (dp), the bar keeps only the logo and the paste button.
    private static final int BAR_WORDS_MIN_WIDTH = 170;

    private Widgets() {}

    public static class Bar extends AppWidgetProvider {
        @Override
        public void onUpdate(Context context, AppWidgetManager manager, int[] ids) {
            for (int id : ids) draw(context, manager, id, manager.getAppWidgetOptions(id));
        }

        @Override
        public void onAppWidgetOptionsChanged(Context context, AppWidgetManager manager, int id, Bundle options) {
            draw(context, manager, id, options);
        }

        private static void draw(Context context, AppWidgetManager manager, int id, Bundle options) {
            RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.widget_bar);
            views.setOnClickPendingIntent(R.id.widget_open, openApp(context));
            views.setOnClickPendingIntent(R.id.widget_paste, fixCopied(context));
            // The width it's been given in portrait; 0 when the launcher doesn't say.
            int width = options == null ? 0 : options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0);
            views.setViewVisibility(R.id.widget_words, width > 0 && width < BAR_WORDS_MIN_WIDTH ? View.GONE : View.VISIBLE);
            manager.updateAppWidget(id, views);
        }
    }

    public static class Paste extends AppWidgetProvider {
        @Override
        public void onUpdate(Context context, AppWidgetManager manager, int[] ids) {
            RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.widget_paste);
            views.setOnClickPendingIntent(R.id.widget_paste, fixCopied(context));
            manager.updateAppWidget(ids, views);
        }
    }

    // uwuFix as the launcher icon opens it: back to the page as it was left.
    private static PendingIntent openApp(Context context) {
        Intent intent = new Intent(context, MainActivity.class)
                .setAction(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_LAUNCHER)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        return PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
    }

    // The quick screen, fixing what's copied. A fresh one every time (CLEAR_TASK): one left open
    // behind the home screen would otherwise come back as it was, showing the last link.
    private static PendingIntent fixCopied(Context context) {
        Intent intent = new Intent(context, FixActivity.class)
                .setAction(FixActivity.ACTION_FIX_COPIED)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
        return PendingIntent.getActivity(context, 1, intent, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
    }
}
