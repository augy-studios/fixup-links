// Frosted Glass on Linux (lib/desktop/backdrop.dart): the desktop blurred behind the window, where
// the compositor does that, with the window clear over it.
#ifndef RUNNER_GLASS_H_
#define RUNNER_GLASS_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

// Before the window is realized: a visual with alpha, where the screen is composited, so the
// window can be clear at all.
void glass_prepare(GtkWindow* window);

// The blur behind the window on or off; whether it's on. Off, or where nothing blurs, the Flutter
// view is opaque again and the Dart side draws a backdrop of its own.
gboolean glass_set_backdrop(GtkWindow* window, FlView* view, gboolean on);

#endif  // RUNNER_GLASS_H_
