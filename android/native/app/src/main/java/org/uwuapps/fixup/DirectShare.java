/*
 * uwuFix in the share sheet's Direct Share row, the shortcuts above the list of apps, so it's
 * one tap away when sharing a link rather than a scroll down the list. A sharing shortcut
 * (res/xml/shortcuts.xml's share-target, for text) that opens FixActivity like the share sheet
 * does. Android picks which of these to show from how often each is used, so every link shared
 * to uwuFix tells it (used).
 */
package org.uwuapps.fixup;

import android.content.Context;
import android.content.Intent;
import android.net.Uri;

import androidx.core.content.pm.ShortcutInfoCompat;
import androidx.core.content.pm.ShortcutManagerCompat;
import androidx.core.graphics.drawable.IconCompat;

import java.util.Collections;

final class DirectShare {
    private static final String ID = "fix_link";
    // The same as res/xml/shortcuts.xml's share-target category.
    private static final String CATEGORY = "org.uwuapps.fixup.category.FIX_LINK";

    private DirectShare() {}

    static void publish(Context context) {
        ShortcutInfoCompat shortcut = new ShortcutInfoCompat.Builder(context, ID)
                .setShortLabel(context.getString(R.string.fix_link))
                .setLongLabel(context.getString(R.string.fix_link_long))
                .setIcon(IconCompat.createWithResource(context, R.mipmap.ic_launcher))
                // Only used if it's opened from somewhere other than the share sheet.
                .setIntent(new Intent(Intent.ACTION_VIEW, Uri.parse(MainActivity.SITE + "/"), context, MainActivity.class))
                .setCategories(Collections.singleton(CATEGORY))
                .setLongLived(true)
                .build();
        try {
            ShortcutManagerCompat.pushDynamicShortcut(context, shortcut);
        } catch (RuntimeException ignored) {
            // A launcher that limits shortcuts: the share sheet's own list still has uwuFix.
        }
    }

    static void used(Context context) {
        try {
            ShortcutManagerCompat.reportShortcutUsed(context, ID);
        } catch (RuntimeException ignored) {
            // Only a ranking hint.
        }
    }
}
