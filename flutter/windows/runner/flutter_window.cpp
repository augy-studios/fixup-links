#include "flutter_window.h"

#include <dwmapi.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <optional>
#include <sstream>

#include <desktop_multi_window/desktop_multi_window_plugin.h>
#include <url_launcher_windows/url_launcher_windows.h>
#include <window_manager/window_manager_plugin.h>

#include "flutter/generated_plugin_registrant.h"

namespace {

// DWM's attributes, for a Windows SDK older than 10.0.22621.
constexpr DWORD kImmersiveDarkMode = 20;  // DWMWA_USE_IMMERSIVE_DARK_MODE
constexpr DWORD kSystemBackdropType = 38;  // DWMWA_SYSTEMBACKDROP_TYPE, Windows 11 22H2
constexpr DWORD kMicaEffect = 1029;        // Windows 11 21H2's, before the backdrop types
constexpr int kBackdropAuto = 0;           // DWMSBT_AUTO
constexpr int kBackdropMica = 2;           // DWMSBT_MAINWINDOW

// Windows' build number, as it is (GetVersionEx says what the manifest asks for).
DWORD WindowsBuild() {
  using RtlGetVersion = LONG(WINAPI*)(PRTL_OSVERSIONINFOW);
  auto get_version = reinterpret_cast<RtlGetVersion>(
      GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "RtlGetVersion"));
  RTL_OSVERSIONINFOW info{};
  info.dwOSVersionInfoSize = sizeof(info);
  if (get_version == nullptr || get_version(&info) != 0) {
    return 0;
  }
  return info.dwBuildNumber;
}

}  // namespace

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
  // Asked of the window by the Dart side: Mica behind it, or not (lib/desktop/backdrop.dart).
  channel_->SetMethodCallHandler([this](const flutter::MethodCall<flutter::EncodableValue>& call,
                                        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    if (call.method_name() != "setBackdrop") {
      result->NotImplemented();
      return;
    }
    bool on = false;
    bool dark = false;
    const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
    if (arguments != nullptr) {
      // Whether the arguments hold `true` under the key; false when the key is missing or not a bool.
      auto flag = [arguments](const char* key) {
        auto entry = arguments->find(flutter::EncodableValue(key));
        if (entry == arguments->end()) {
          return false;
        }
        const auto* value = std::get_if<bool>(&entry->second);
        return value != nullptr && *value;
      };
      on = flag("on");
      dark = flag("dark");
    }
    result->Success(flutter::EncodableValue(SetBackdrop(on, dark)));
  });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Shown by the Dart side once it's drawn and sized (window_manager), so it never flashes.
  flutter_controller_->ForceRedraw();

  return true;
}

// Mica: the wallpaper, blurred and tinted, behind the window, drawn by DWM wherever Flutter leaves
// the window clear. Windows 11 only: 22H2 and later by the backdrop type, 21H2 by its own
// attribute. Windows 10 has nothing like it, and the Dart side draws its own backdrop instead.
// The title bar stays the app's own (window_manager's hidden style): the frame is extended over
// the whole window, which window_manager puts back to none whenever it sets a title bar style, so
// the Dart side asks again after each.
bool FlutterWindow::SetBackdrop(bool on, bool dark) {
  HWND window = GetHandle();
  if (window == nullptr) {
    return false;
  }
  BOOL dark_mode = FALSE;
  if (dark) {
    dark_mode = TRUE;
  }
  DwmSetWindowAttribute(window, kImmersiveDarkMode, &dark_mode, sizeof(dark_mode));
  const DWORD build = WindowsBuild();
  const bool mica = on && build >= 22000;
  MARGINS margins = MARGINS{0, 0, 0, 0};
  if (mica) {
    margins = MARGINS{-1, -1, -1, -1};
  }
  DwmExtendFrameIntoClientArea(window, &margins);
  // With the frame over the whole window DWM would draw its own minimise, maximise and close
  // behind the app's clear title bar, which has buttons of its own: without the system menu it
  // draws none.
  const LONG_PTR style = GetWindowLongPtr(window, GWL_STYLE);
  LONG_PTR wanted_style = style | WS_SYSMENU;
  if (mica) {
    wanted_style = style & ~static_cast<LONG_PTR>(WS_SYSMENU);
  }
  if (wanted_style != style) {
    SetWindowLongPtr(window, GWL_STYLE, wanted_style);
    SetWindowPos(window, nullptr, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
  }
  if (build >= 22621) {
    int type = kBackdropAuto;
    if (mica) {
      type = kBackdropMica;
    }
    DwmSetWindowAttribute(window, kSystemBackdropType, &type, sizeof(type));
  } else if (build >= 22000) {
    BOOL effect = FALSE;
    if (mica) {
      effect = TRUE;
    }
    DwmSetWindowAttribute(window, kMicaEffect, &effect, sizeof(effect));
  }
  return mica;
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
          // The task's name, after the 7 characters of "--task=".
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
