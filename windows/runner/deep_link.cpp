#include "deep_link.h"

#include "win32_window.h"  // para la clase de ventana de Flutter

namespace {

// Escribe un valor string en HKCU\Software\Classes\<subkey>.
bool SetClassesRegValue(const std::wstring& subkey, const wchar_t* value_name,
                        const std::wstring& data) {
  const std::wstring full = L"Software\\Classes\\" + subkey;
  HKEY key = nullptr;
  LSTATUS s = RegCreateKeyExW(HKEY_CURRENT_USER, full.c_str(), 0, nullptr,
                              REG_OPTION_NON_VOLATILE, KEY_WRITE, nullptr,
                              &key, nullptr);
  if (s != ERROR_SUCCESS) {
    return false;
  }
  s = RegSetValueExW(
      key, value_name, 0, REG_SZ,
      reinterpret_cast<const BYTE*>(data.c_str()),
      static_cast<DWORD>((data.size() + 1) * sizeof(wchar_t)));
  RegCloseKey(key);
  return s == ERROR_SUCCESS;
}

}  // namespace

void RegisterDeepLinkScheme() {
  wchar_t exe_path[MAX_PATH];
  DWORD len = GetModuleFileNameW(nullptr, exe_path, MAX_PATH);
  if (len == 0 || len >= MAX_PATH) {
    return;
  }

  const std::wstring scheme(kDeepLinkScheme);
  // HKCU\Software\Classes\ytdlinux
  SetClassesRegValue(scheme, nullptr, L"URL:ytdlinux Protocol");
  SetClassesRegValue(scheme, L"URL Protocol", L"");
  // ...\shell\open\command  (Default) = "C:\ruta\app.exe" "%1"
  const std::wstring command =
      L"\"" + std::wstring(exe_path) + L"\" \"%1\"";
  SetClassesRegValue(scheme + L"\\shell\\open\\command", nullptr, command);
}

bool ForwardDeepLinkToPrimary(const std::wstring& uri) {
  // La ventana primaria usa la clase de Flutter + título "ytdlinux".
  HWND target = FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", kMainWindowTitle);
  if (target == nullptr) {
    return false;
  }

  COPYDATASTRUCT cds{};
  cds.dwData = kDeepLinkCopyDataMagic;
  cds.cbData =
      static_cast<DWORD>((uri.size() + 1) * sizeof(wchar_t));  // incl. null
  cds.lpData = const_cast<wchar_t*>(uri.c_str());

  // Trae la ventana primaria al frente antes de entregar la URI.
  SetForegroundWindow(target);
  SendMessageW(target, WM_COPYDATA, 0, reinterpret_cast<LPARAM>(&cds));
  return true;
}
