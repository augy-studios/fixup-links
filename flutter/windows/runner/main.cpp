// uwuFix for Windows: the runner (docs/flutter-desktop-app-spec.md §2.7).
//
// - One copy at a time: a second copy (a shortcut, a uwu://fix link, a Jump List task) sends its
//   command line to the first with WM_COPYDATA and exits; the first shows itself and opens what
//   it was given (flutter_window.cpp, lib/desktop/desktop.dart).
// - The app's identity for Windows, org.uwuapps.fixup (AppUserModelID): notifications, the
//   taskbar group, pins and the Jump List hang on it.
// - The Jump List's tasks: Fix copied link, History, Share history, Add a Fix a link widget, each
//   starting uwuFix.exe with --task=<id>, which the running copy is handed.
// - The window starts hidden: the Dart side shows it once it's drawn (window_manager).
#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <shobjidl.h>
#include <propkey.h>
#include <propvarutil.h>

#include <string>

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr wchar_t kAppId[] = L"org.uwuapps.fixup";
constexpr wchar_t kMutex[] = L"org.uwuapps.fixup.single-instance";
constexpr wchar_t kWindowClass[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr wchar_t kTitle[] = L"uwuFix";

// The first copy's window, found by its class and title.
HWND FindRunning() { return ::FindWindowW(kWindowClass, kTitle); }

// This copy's command line, as UTF-8 arguments joined by newlines, to the first copy.
bool ForwardToRunning() {
  HWND running = FindRunning();
  if (!running) return false;
  std::vector<std::string> args = GetCommandLineArguments();
  std::string joined;
  for (const auto& a : args) {
    if (!joined.empty()) joined += "\n";
    joined += a;
  }
  COPYDATASTRUCT data;
  data.dwData = 0x75777546;  // "uwuF"
  data.cbData = static_cast<DWORD>(joined.size());
  data.lpData = joined.empty() ? nullptr : const_cast<char*>(joined.data());
  DWORD pid = 0;
  ::GetWindowThreadProcessId(running, &pid);
  ::AllowSetForegroundWindow(pid);
  ::SendMessageW(running, WM_COPYDATA, 0, reinterpret_cast<LPARAM>(&data));
  return true;
}

// A Jump List task: this exe with an argument.
IShellLinkW* Task(const std::wstring& exe, const wchar_t* title, const wchar_t* arg) {
  IShellLinkW* link = nullptr;
  if (FAILED(::CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&link)))) return nullptr;
  link->SetPath(exe.c_str());
  link->SetArguments(arg);
  link->SetIconLocation(exe.c_str(), 0);
  link->SetDescription(title);
  IPropertyStore* store = nullptr;
  if (SUCCEEDED(link->QueryInterface(IID_PPV_ARGS(&store)))) {
    PROPVARIANT pv;
    if (SUCCEEDED(::InitPropVariantFromString(title, &pv))) {
      store->SetValue(PKEY_Title, pv);
      store->Commit();
      ::PropVariantClear(&pv);
    }
    store->Release();
  }
  return link;
}

void SetJumpList() {
  wchar_t path[MAX_PATH];
  if (!::GetModuleFileNameW(nullptr, path, MAX_PATH)) return;
  std::wstring exe(path);
  ICustomDestinationList* list = nullptr;
  if (FAILED(::CoCreateInstance(CLSID_DestinationList, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&list)))) return;
  list->SetAppID(kAppId);
  UINT slots = 0;
  IObjectArray* removed = nullptr;
  if (SUCCEEDED(list->BeginList(&slots, IID_PPV_ARGS(&removed)))) {
    IObjectCollection* tasks = nullptr;
    if (SUCCEEDED(::CoCreateInstance(CLSID_EnumerableObjectCollection, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&tasks)))) {
      const wchar_t* items[][2] = {
          {L"Fix copied link", L"--task=paste"},
          {L"History", L"--task=history"},
          {L"Share history", L"--task=sync"},
          {L"Add a Fix a link widget", L"--task=widget"},
      };
      for (auto& item : items) {
        if (IShellLinkW* link = Task(exe, item[0], item[1])) {
          tasks->AddObject(link);
          link->Release();
        }
      }
      IObjectArray* array = nullptr;
      if (SUCCEEDED(tasks->QueryInterface(IID_PPV_ARGS(&array)))) {
        list->AddUserTasks(array);
        array->Release();
      }
      tasks->Release();
    }
    list->CommitList();
    if (removed) removed->Release();
  }
  list->Release();
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t* command_line, _In_ int show_command) {
  // One copy at a time. desktop_multi_window's extra windows are engines in this process, not
  // copies, so they never come here.
  HANDLE mutex = ::CreateMutexW(nullptr, TRUE, kMutex);
  if (mutex && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    if (ForwardToRunning()) {
      ::CloseHandle(mutex);
      return EXIT_SUCCESS;
    }
  }

  // Attach to console when present (e.g., 'flutter run') or create a new console when running
  // with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  ::SetCurrentProcessExplicitAppUserModelID(kAppId);

  // COM, for the library and plugins, and the Jump List.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  SetJumpList();

  flutter::DartProject project(L"data");
  std::vector<std::string> command_line_arguments = GetCommandLineArguments();
  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(300, 360);
  if (!window.Create(kTitle, origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (mutex) ::CloseHandle(mutex);
  return EXIT_SUCCESS;
}
