// Frosted Glass's backdrop, on the two ways a Linux desktop blurs behind a window:
//
// - X11: _KDE_NET_WM_BLUR_BEHIND_REGION, empty for the whole window. KWin's blur reads it, and so
//   does Deepin's window manager (deepin-kwin, DDE's), each putting the atom on the root window
//   while it blurs, which is how it's told it'll be honoured.
// - Wayland: ext-background-effect-v1, the standard protocol for it (COSMIC's compositor, KWin),
//   when the compositor offers it.
//
// Anywhere else (GNOME, an X11 desktop with no compositor), nothing is asked and the window stays
// opaque.
#include "glass.h"

#include <climits>
#include <cstring>

#ifdef GDK_WINDOWING_X11
#include <X11/Xatom.h>
#include <gdk/gdkx.h>
#endif

#if defined(GDK_WINDOWING_WAYLAND) && defined(HAVE_BACKGROUND_EFFECT)
#include <gdk/gdkwayland.h>

#include "ext-background-effect-v1-client-protocol.h"
#endif

namespace {

// Whether glass_prepare gave the window a visual with alpha, so it can be clear.
gboolean g_window_has_alpha = FALSE;

// The view's background when it's opaque (as my_application.cc sets it), and when it's clear.
const GdkRGBA kOpaque = {0xEE / 255.0, 0xF2 / 255.0, 0xF0 / 255.0, 1.0};
const GdkRGBA kClear = {0, 0, 0, 0};

#ifdef GDK_WINDOWING_X11
// X11: asks for the blur behind the whole window, or takes the ask back. Only asks when the window
// manager has put the blur atom on the root window, which says it will honour it. Whether it's on.
gboolean x11_blur(GdkWindow* window, gboolean on) {
  Display* display = GDK_DISPLAY_XDISPLAY(gdk_window_get_display(window));
  const Window window_id = GDK_WINDOW_XID(window);
  const Atom blur_atom = XInternAtom(display, "_KDE_NET_WM_BLUR_BEHIND_REGION", False);
  if (!on) {
    XDeleteProperty(display, window_id, blur_atom);
    XFlush(display);
    return FALSE;
  }
  int property_count = 0;
  Atom* announced = XListProperties(display, DefaultRootWindow(display), &property_count);
  gboolean blurs = FALSE;
  for (int property_index = 0; property_index < property_count; property_index++) {
    if (announced[property_index] == blur_atom) {
      blurs = TRUE;
    }
  }
  if (announced != nullptr) {
    XFree(announced);
  }
  if (!blurs) {
    return FALSE;
  }
  XChangeProperty(display, window_id, blur_atom, XA_CARDINAL, 32, PropModeReplace, nullptr, 0);
  XFlush(display);
  return TRUE;
}
#endif

#if defined(GDK_WINDOWING_WAYLAND) && defined(HAVE_BACKGROUND_EFFECT)
// What has been found out from the Wayland compositor, looked up once, and the window's effect.
struct Wayland {
  gboolean looked_up;
  wl_compositor* compositor;
  ext_background_effect_manager_v1* manager;
  ext_background_effect_surface_v1* effect;
  wl_surface* surface;
};
Wayland g_wayland = {};

// Called for each global the compositor offers: keeps the two this file uses.
void on_global(void*, wl_registry* registry, uint32_t name, const char* interface, uint32_t) {
  if (strcmp(interface, wl_compositor_interface.name) == 0) {
    g_wayland.compositor = static_cast<wl_compositor*>(wl_registry_bind(registry, name, &wl_compositor_interface, 1));
  } else if (strcmp(interface, ext_background_effect_manager_v1_interface.name) == 0) {
    g_wayland.manager = static_cast<ext_background_effect_manager_v1*>(
        wl_registry_bind(registry, name, &ext_background_effect_manager_v1_interface, 1));
  }
}

void on_global_remove(void*, wl_registry*, uint32_t) {}

const wl_registry_listener kRegistryListener = {on_global, on_global_remove};

// Wayland: sets or clears the blur region of the window's background effect, where the compositor
// offers ext-background-effect-v1. Whether it's on.
gboolean wayland_blur(GdkWindow* window, gboolean on) {
  wl_display* display = gdk_wayland_display_get_wl_display(gdk_window_get_display(window));
  wl_surface* surface = gdk_wayland_window_get_wl_surface(window);
  if (display == nullptr || surface == nullptr) {
    return FALSE;
  }
  if (!g_wayland.looked_up) {
    // What the compositor offers, asked on a queue of our own so GDK's events aren't touched.
    g_wayland.looked_up = TRUE;
    wl_event_queue* queue = wl_display_create_queue(display);
    wl_registry* registry = wl_display_get_registry(display);
    wl_proxy_set_queue(reinterpret_cast<wl_proxy*>(registry), queue);
    wl_registry_add_listener(registry, &kRegistryListener, nullptr);
    wl_display_roundtrip_queue(display, queue);
    if (g_wayland.compositor != nullptr) {
      wl_proxy_set_queue(reinterpret_cast<wl_proxy*>(g_wayland.compositor), nullptr);
    }
    if (g_wayland.manager != nullptr) {
      wl_proxy_set_queue(reinterpret_cast<wl_proxy*>(g_wayland.manager), nullptr);
    }
    wl_registry_destroy(registry);
    wl_event_queue_destroy(queue);
  }
  if (g_wayland.manager == nullptr || g_wayland.compositor == nullptr) {
    return FALSE;
  }
  if (g_wayland.effect != nullptr && g_wayland.surface != surface) {
    ext_background_effect_surface_v1_destroy(g_wayland.effect);
    g_wayland.effect = nullptr;
  }
  if (g_wayland.effect == nullptr) {
    g_wayland.effect = ext_background_effect_manager_v1_get_background_effect(g_wayland.manager, surface);
    g_wayland.surface = surface;
  }
  if (on) {
    // The whole window, as the compositor clips it to the surface.
    wl_region* region = wl_compositor_create_region(g_wayland.compositor);
    wl_region_add(region, 0, 0, SHRT_MAX, SHRT_MAX);
    ext_background_effect_surface_v1_set_blur_region(g_wayland.effect, region);
    wl_region_destroy(region);
  } else {
    ext_background_effect_surface_v1_set_blur_region(g_wayland.effect, nullptr);
  }
  return on;
}
#endif

}  // namespace

void glass_prepare(GtkWindow* window) {
  GdkScreen* screen = gtk_window_get_screen(window);
  GdkVisual* visual = gdk_screen_get_rgba_visual(screen);
  if (visual == nullptr || !gdk_screen_is_composited(screen)) {
    return;
  }
  gtk_widget_set_visual(GTK_WIDGET(window), visual);
  gtk_widget_set_app_paintable(GTK_WIDGET(window), TRUE);
  g_window_has_alpha = TRUE;
}

gboolean glass_set_backdrop(GtkWindow* window, FlView* view, gboolean on) {
  GdkWindow* gdk_window = gtk_widget_get_window(GTK_WIDGET(window));
  gboolean blurred = FALSE;
  if (g_window_has_alpha && gdk_window != nullptr) {
#ifdef GDK_WINDOWING_X11
    if (GDK_IS_X11_WINDOW(gdk_window)) {
      blurred = x11_blur(gdk_window, on);
    }
#endif
#if defined(GDK_WINDOWING_WAYLAND) && defined(HAVE_BACKGROUND_EFFECT)
    if (GDK_IS_WAYLAND_WINDOW(gdk_window)) {
      blurred = wayland_blur(gdk_window, on);
    }
#endif
  }
  if (blurred) {
    fl_view_set_background_color(view, &kClear);
  } else {
    fl_view_set_background_color(view, &kOpaque);
  }
  // A frame, so the window's committed with the change.
  if (gdk_window != nullptr) {
    gdk_window_invalidate_rect(gdk_window, nullptr, TRUE);
  }
  gtk_widget_queue_draw(GTK_WIDGET(view));
  return blurred;
}
