#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>

#include "deep_link.h"
#include "flutter_window.h"
#include "utils.h"

namespace {

// Devuelve el primer argumento que sea una URI ytdlinux:// (o cadena vacía).
std::wstring FindDeepLinkArg() {
  int argc = 0;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  std::wstring uri;
  if (argv != nullptr) {
    for (int i = 1; i < argc; i++) {
      if (wcsncmp(argv[i], L"ytdlinux:", 9) == 0) {
        uri = argv[i];
        break;
      }
    }
    ::LocalFree(argv);
  }
  return uri;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Mantener el esquema ytdlinux:// registrado (ruta del .exe al día).
  RegisterDeepLinkScheme();

  // Instancia única: si ya hay una primaria corriendo, reenviarle la URI de
  // deep link (o solo enfocarla) y salir. El navegador lanza una instancia
  // nueva por cada click — sin esto, la descarga nunca llega a la app abierta.
  const std::wstring deep_link_uri = FindDeepLinkArg();
  HANDLE single_instance_mutex =
      ::CreateMutexW(nullptr, FALSE, kSingleInstanceMutexName);
  bool already_running =
      single_instance_mutex != nullptr &&
      ::GetLastError() == ERROR_ALREADY_EXISTS;
  if (already_running) {
    if (!deep_link_uri.empty()) {
      ForwardDeepLinkToPrimary(deep_link_uri);
    } else {
      HWND primary =
          ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", kMainWindowTitle);
      if (primary != nullptr) {
        ::SetForegroundWindow(primary);
      }
    }
    if (single_instance_mutex != nullptr) {
      ::CloseHandle(single_instance_mutex);
    }
    return EXIT_SUCCESS;
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"ytdlinux", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
