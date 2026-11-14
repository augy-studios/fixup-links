#include "flutter_window.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <optional>
#include <sstream>

#include <desktop_multi_window/desktop_multi_window_plugin.h>
#include <url_launcher_windows/url_launcher_windows.h>
#include <window_manager/window_manager_plugin.h>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  // The Fix a link widgets' windows (lib/desktop/widgets_window.dart) are engines of their own,
  // which need the plugins they use registered too.
  DesktopMultiWindowSetWindowCreatedCallback([](void* controller) {
    auto* view_controller = reinterpret_cast<flutter::FlutterViewController*>(controller);
    auto* registry = view_controller->engine();
    WindowManagerPluginRegisterWithRegistrar(registry->GetRegistrarForPlugin("WindowManagerPlugin"));
    UrlLauncherWindowsRegisterWithRegistrar(registry->GetRegistrarForPlugin("UrlLauncherWindows"));
  });

  // The app's own channel (lib/desktop/desktop.dart): links and Jump List tasks a second copy
  // passed on.
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "org.uwuapps.fixup/desktop",
      &flutter::StandardMethodCodec::GetInstance());

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Shown by the Dart side once it's drawn and sized (window_manager), so it never flashes.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // A second copy's command line (main.cpp): links open, tasks run, and either way the window
  // comes forward.
  if (message == WM_COPYDATA && channel_) {
    auto* data = reinterpret_cast<COPYDATASTRUCT*>(lparam);
    if (data && data->dwData == 0x75777546) {
      std::string joined(static_cast<const char*>(data->lpData), data->cbData);
      flutter::EncodableList links;
      std::string task;
      std::stringstream lines(joined);
      std::string line;
      while (std::getline(lines, line, '\n')) {
        if (line.rfind("--task=", 0) == 0) {
          task = line.substr(7);
        } else if (!line.empty()) {
          links.push_back(flutter::EncodableValue(line));
        }
      }
      if (!task.empty()) {
        channel_->InvokeMethod("task", std::make_unique<flutter::EncodableValue>(task));
      } else if (!links.empty()) {
        channel_->InvokeMethod("open", std::make_unique<flutter::EncodableValue>(links));
      } else {
        channel_->InvokeMethod("activate", nullptr);
      }
      return TRUE;
    }
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
