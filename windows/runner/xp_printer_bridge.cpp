#include "xp_printer_bridge.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <windows.h>
#include <winspool.h>
#include <setupapi.h>
#include <devguid.h>

#include <algorithm>
#include <cwctype>
#include <string>
#include <vector>

namespace {
HANDLE g_serial = INVALID_HANDLE_VALUE;
HANDLE g_printer = nullptr;

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) return {};
  const int size = MultiByteToWideChar(CP_UTF8, 0, value.c_str(),
                                       static_cast<int>(value.size()), nullptr, 0);
  if (size <= 0) return {};
  std::wstring result(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(),
                      static_cast<int>(value.size()), result.data(), size);
  return result;
}

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) return {};
  const int size = WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                                       static_cast<int>(value.size()), nullptr, 0,
                                       nullptr, nullptr);
  if (size <= 0) return {};
  std::string result(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                      static_cast<int>(value.size()), result.data(), size,
                      nullptr, nullptr);
  return result;
}

bool ContainsIgnoreCase(const std::wstring& value, const std::wstring& token) {
  return std::search(value.begin(), value.end(), token.begin(), token.end(),
      [](wchar_t a, wchar_t b) { return towlower(a) == towlower(b); }) != value.end();
}

std::wstring ReadDeviceProperty(HDEVINFO devices, SP_DEVINFO_DATA* device,
                                DWORD property) {
  DWORD required = 0;
  SetupDiGetDeviceRegistryPropertyW(devices, device, property, nullptr,
                                    nullptr, 0, &required);
  if (!required) return {};
  std::vector<BYTE> buffer(required + sizeof(wchar_t), 0);
  if (!SetupDiGetDeviceRegistryPropertyW(
          devices, device, property, nullptr, buffer.data(),
          static_cast<DWORD>(buffer.size()), nullptr)) return {};
  return std::wstring(reinterpret_cast<const wchar_t*>(buffer.data()));
}

std::wstring ExtractComPort(const std::wstring& friendly_name) {
  for (size_t i = 0; i + 4 < friendly_name.size(); ++i) {
    if (friendly_name[i] != L'(' || towlower(friendly_name[i + 1]) != L'c' ||
        towlower(friendly_name[i + 2]) != L'o' ||
        towlower(friendly_name[i + 3]) != L'm') continue;
    size_t end = i + 4;
    while (end < friendly_name.size() &&
           friendly_name[end] >= L'0' && friendly_name[end] <= L'9') ++end;
    if (end > i + 4 && end < friendly_name.size() && friendly_name[end] == L')')
      return friendly_name.substr(i + 1, end - i - 1);
  }
  return {};
}

flutter::EncodableList EnumerateUsbPrinters() {
  DWORD needed = 0, returned = 0;
  EnumPrintersW(PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS, nullptr, 2,
                nullptr, 0, &needed, &returned);
  flutter::EncodableList result;
  if (!needed) return result;
  std::vector<BYTE> buffer(needed);
  if (!EnumPrintersW(PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS, nullptr, 2,
                     buffer.data(), needed, &needed, &returned)) return result;
  auto* printers = reinterpret_cast<PRINTER_INFO_2W*>(buffer.data());
  for (DWORD i = 0; i < returned; ++i) {
    if (!printers[i].pPrinterName || !printers[i].pPortName) continue;
    const std::wstring port(printers[i].pPortName);
    if (!ContainsIgnoreCase(port, L"USB")) continue;
    flutter::EncodableMap item;
    item[flutter::EncodableValue("name")] =
        flutter::EncodableValue(WideToUtf8(printers[i].pPrinterName));
    item[flutter::EncodableValue("port")] =
        flutter::EncodableValue(WideToUtf8(port));
    item[flutter::EncodableValue("status")] =
        flutter::EncodableValue(static_cast<int>(printers[i].Status));
    result.emplace_back(flutter::EncodableValue(item));
  }
  return result;
}

flutter::EncodableList EnumerateBluetoothSerialPorts() {
  flutter::EncodableList result;
  HDEVINFO devices = SetupDiGetClassDevsW(
      &GUID_DEVCLASS_PORTS, nullptr, nullptr, DIGCF_PRESENT);
  if (devices == INVALID_HANDLE_VALUE) return result;

  for (DWORD index = 0;; ++index) {
    SP_DEVINFO_DATA device{};
    device.cbSize = sizeof(device);
    if (!SetupDiEnumDeviceInfo(devices, index, &device)) {
      if (GetLastError() == ERROR_NO_MORE_ITEMS) break;
      continue;
    }

    wchar_t instance_id[1024]{};
    if (!SetupDiGetDeviceInstanceIdW(devices, &device, instance_id, 1024, nullptr))
      continue;
    if (!ContainsIgnoreCase(instance_id, L"BTHENUM")) continue;

    std::wstring friendly = ReadDeviceProperty(devices, &device, SPDRP_FRIENDLYNAME);
    if (friendly.empty())
      friendly = ReadDeviceProperty(devices, &device, SPDRP_DEVICEDESC);
    const std::wstring port = ExtractComPort(friendly);
    if (port.empty()) continue;

    flutter::EncodableMap item;
    item[flutter::EncodableValue("name")] =
        flutter::EncodableValue(WideToUtf8(friendly));
    item[flutter::EncodableValue("port")] =
        flutter::EncodableValue(WideToUtf8(port));
    item[flutter::EncodableValue("description")] =
        flutter::EncodableValue("Paired Bluetooth serial device");
    result.emplace_back(flutter::EncodableValue(item));
  }
  SetupDiDestroyDeviceInfoList(devices);
  return result;
}

void CloseConnection() {
  if (g_printer) {
    ClosePrinter(g_printer);
    g_printer = nullptr;
  }
  if (g_serial != INVALID_HANDLE_VALUE) {
    CloseHandle(g_serial);
    g_serial = INVALID_HANDLE_VALUE;
  }
}

bool WriteAllToPrinter(const std::vector<uint8_t>& bytes, DWORD* error) {
  DOC_INFO_1W document{};
  document.pDocName = const_cast<LPWSTR>(L"XP-P323B ESC/POS Job");
  document.pDatatype = const_cast<LPWSTR>(L"RAW");
  const DWORD job_id = StartDocPrinterW(
      g_printer, 1, reinterpret_cast<LPBYTE>(&document));
  if (!job_id) {
    *error = GetLastError();
    return false;
  }

  const bool page_started = StartPagePrinter(g_printer) != FALSE;
  bool success = page_started;
  if (!page_started) *error = GetLastError();

  size_t offset = 0;
  while (success && offset < bytes.size()) {
    const DWORD chunk = static_cast<DWORD>(std::min<size_t>(
        bytes.size() - offset, static_cast<size_t>(MAXDWORD)));
    DWORD written = 0;
    if (!WritePrinter(g_printer, const_cast<uint8_t*>(bytes.data() + offset),
                      chunk, &written) || written == 0) {
      *error = GetLastError();
      success = false;
      break;
    }
    offset += written;
  }

  if (page_started && !EndPagePrinter(g_printer) && success) {
    *error = GetLastError();
    success = false;
  }
  if (!EndDocPrinter(g_printer) && success) {
    *error = GetLastError();
    success = false;
  }
  return success;
}

bool WriteAllToSerial(const std::vector<uint8_t>& bytes, DWORD* error) {
  size_t offset = 0;
  while (offset < bytes.size()) {
    const DWORD chunk = static_cast<DWORD>(std::min<size_t>(
        bytes.size() - offset, static_cast<size_t>(MAXDWORD)));
    DWORD written = 0;
    if (!WriteFile(g_serial, bytes.data() + offset, chunk, &written, nullptr) ||
        written == 0) {
      *error = GetLastError();
      return false;
    }
    offset += written;
  }
  return true;
}

void RegisterMethodChannel(flutter::BinaryMessenger* messenger) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "xp_p323b/windows_printer",
      &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [](const auto& call, auto result) {
        const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
        auto get_string = [&](const char* key) -> std::string {
          if (!args) return {};
          auto it = args->find(flutter::EncodableValue(key));
          if (it == args->end()) return {};
          const auto* value = std::get_if<std::string>(&it->second);
          return value ? *value : std::string();
        };

        if (call.method_name() == "listUsbPrinters") {
          result->Success(flutter::EncodableValue(EnumerateUsbPrinters()));
          return;
        }
        if (call.method_name() == "listBluetoothPorts") {
          result->Success(flutter::EncodableValue(EnumerateBluetoothSerialPorts()));
          return;
        }
        if (call.method_name() == "disconnect") {
          CloseConnection();
          result->Success(flutter::EncodableValue(true));
          return;
        }
        if (call.method_name() == "connectUsb") {
          CloseConnection();
          const std::wstring name = Utf8ToWide(get_string("name"));
          if (name.empty()) {
            result->Error("INVALID_ARGUMENT", "Printer name is required.");
            return;
          }
          PRINTER_DEFAULTSW defaults{};
          defaults.DesiredAccess = PRINTER_ACCESS_USE;
          if (!OpenPrinterW(const_cast<LPWSTR>(name.c_str()), &g_printer, &defaults)) {
            const DWORD error = GetLastError();
            result->Error("OPEN_PRINTER_FAILED", "Windows could not open this printer queue.",
                          flutter::EncodableValue(static_cast<int>(error)));
            return;
          }
          result->Success(flutter::EncodableValue(true));
          return;
        }
        if (call.method_name() == "connectBluetooth") {
          CloseConnection();
          std::wstring port = Utf8ToWide(get_string("port"));
          if (port.empty()) {
            result->Error("INVALID_ARGUMENT", "Bluetooth COM port is required.");
            return;
          }
          if (port.rfind(L"\\\\.\\", 0) != 0) port = L"\\\\.\\" + port;
          g_serial = CreateFileW(port.c_str(), GENERIC_READ | GENERIC_WRITE, 0,
                                 nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
          if (g_serial == INVALID_HANDLE_VALUE) {
            const DWORD error = GetLastError();
            result->Error("OPEN_COM_FAILED", "Could not open the Bluetooth COM port.",
                          flutter::EncodableValue(static_cast<int>(error)));
            return;
          }
          DCB dcb{};
          dcb.DCBlength = sizeof(dcb);
          if (!GetCommState(g_serial, &dcb)) {
            const DWORD error = GetLastError();
            CloseConnection();
            result->Error("COM_CONFIG_FAILED", "Could not read COM port settings.",
                          flutter::EncodableValue(static_cast<int>(error)));
            return;
          }
          dcb.BaudRate = CBR_115200;
          dcb.ByteSize = 8;
          dcb.Parity = NOPARITY;
          dcb.StopBits = ONESTOPBIT;
          dcb.fBinary = TRUE;
          if (!SetCommState(g_serial, &dcb)) {
            const DWORD error = GetLastError();
            CloseConnection();
            result->Error("COM_CONFIG_FAILED", "Could not configure the COM port.",
                          flutter::EncodableValue(static_cast<int>(error)));
            return;
          }
          COMMTIMEOUTS timeouts{};
          timeouts.WriteTotalTimeoutConstant = 5000;
          timeouts.WriteTotalTimeoutMultiplier = 10;
          if (!SetCommTimeouts(g_serial, &timeouts)) {
            const DWORD error = GetLastError();
            CloseConnection();
            result->Error("COM_TIMEOUT_CONFIG_FAILED", "Could not configure COM timeouts.",
                          flutter::EncodableValue(static_cast<int>(error)));
            return;
          }
          result->Success(flutter::EncodableValue(true));
          return;
        }
        if (call.method_name() == "write") {
          if (!args) {
            result->Error("INVALID_ARGUMENT", "Byte data is required.");
            return;
          }
          auto it = args->find(flutter::EncodableValue("bytes"));
          const auto* bytes = it == args->end()
                                  ? nullptr
                                  : std::get_if<std::vector<uint8_t>>(&it->second);
          if (!bytes || bytes->empty()) {
            result->Error("INVALID_ARGUMENT", "Byte data is empty.");
            return;
          }
          if (!g_printer && g_serial == INVALID_HANDLE_VALUE) {
            result->Error("NOT_CONNECTED", "No printer connection is open.");
            return;
          }

          DWORD error = ERROR_SUCCESS;
          const bool success = g_printer
              ? WriteAllToPrinter(*bytes, &error)
              : WriteAllToSerial(*bytes, &error);
          if (!success) {
            result->Error("WRITE_FAILED", "Windows could not send the complete printer data.",
                          flutter::EncodableValue(static_cast<int>(error)));
            return;
          }
          result->Success(flutter::EncodableValue(static_cast<int>(bytes->size())));
          return;
        }
        result->NotImplemented();
      });
  channel.release();
}
}  // namespace

void RegisterXpPrinterBridge(flutter::BinaryMessenger* messenger) {
  RegisterMethodChannel(messenger);
}
