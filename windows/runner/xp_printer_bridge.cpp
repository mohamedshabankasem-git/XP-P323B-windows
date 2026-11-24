#include "xp_printer_bridge.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <windows.h>
#include <winspool.h>

#include <string>
#include <vector>

namespace {
HANDLE g_serial = INVALID_HANDLE_VALUE;
HANDLE g_printer = nullptr;
DWORD g_job_id = 0;
bool g_page_started = false;

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) return {};
  const int size = MultiByteToWideChar(CP_UTF8, 0, value.c_str(),
                                       static_cast<int>(value.size()), nullptr, 0);
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
  std::string result(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                      static_cast<int>(value.size()), result.data(), size,
                      nullptr, nullptr);
  return result;
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
    if (!printers[i].pPrinterName) continue;
    flutter::EncodableMap item;
    item[flutter::EncodableValue("name")] =
        flutter::EncodableValue(WideToUtf8(printers[i].pPrinterName));
    item[flutter::EncodableValue("port")] =
        flutter::EncodableValue(printers[i].pPortName
                                    ? WideToUtf8(printers[i].pPortName) : "");
    item[flutter::EncodableValue("status")] =
        flutter::EncodableValue(static_cast<int>(printers[i].Status));
    result.emplace_back(flutter::EncodableValue(item));
  }
  return result;
}

flutter::EncodableList EnumerateBluetoothSerialPorts() {
  flutter::EncodableList result;
  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_LOCAL_MACHINE,
                    L"HARDWARE\\DEVICEMAP\\SERIALCOMM", 0, KEY_READ,
                    &key) != ERROR_SUCCESS) return result;
  for (DWORD index = 0;; ++index) {
    wchar_t value_name[256]{};
    wchar_t value_data[256]{};
    DWORD name_size = 256, data_size = sizeof(value_data), type = 0;
    const LONG status = RegEnumValueW(key, index, value_name, &name_size,
                                      nullptr, &type,
                                      reinterpret_cast<BYTE*>(value_data),
                                      &data_size);
    if (status == ERROR_NO_MORE_ITEMS) break;
    if (status != ERROR_SUCCESS || type != REG_SZ) continue;
    const std::wstring port(value_data);
    flutter::EncodableMap item;
    item[flutter::EncodableValue("name")] = flutter::EncodableValue(WideToUtf8(port));
    item[flutter::EncodableValue("port")] = flutter::EncodableValue(WideToUtf8(port));
    item[flutter::EncodableValue("description")] =
        flutter::EncodableValue("Bluetooth / serial COM port");
    result.emplace_back(flutter::EncodableValue(item));
  }
  RegCloseKey(key);
  return result;
}

void CloseConnection() {
  if (g_printer) {
    if (g_page_started) EndPagePrinter(g_printer);
    if (g_job_id) EndDocPrinter(g_printer);
    ClosePrinter(g_printer);
  }
  if (g_serial != INVALID_HANDLE_VALUE) CloseHandle(g_serial);
  g_printer = nullptr;
  g_serial = INVALID_HANDLE_VALUE;
  g_job_id = 0;
  g_page_started = false;
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
            result->Error("OPEN_PRINTER_FAILED", "Windows could not open this printer queue.",
                          flutter::EncodableValue(static_cast<int>(GetLastError())));
            return;
          }
          DOC_INFO_1W document{};
          document.pDocName = const_cast<LPWSTR>(L"XP-P323B ESC/POS Job");
          document.pDatatype = const_cast<LPWSTR>(L"RAW");
          g_job_id = StartDocPrinterW(g_printer, 1,
                                      reinterpret_cast<LPBYTE>(&document));
          if (!g_job_id || !StartPagePrinter(g_printer)) {
            const DWORD error = GetLastError();
            CloseConnection();
            result->Error("START_PRINT_JOB_FAILED", "Could not start a RAW print job.",
                          flutter::EncodableValue(static_cast<int>(error)));
            return;
          }
          g_page_started = true;
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
            result->Error("OPEN_COM_FAILED", "Could not open the Bluetooth COM port.",
                          flutter::EncodableValue(static_cast<int>(GetLastError())));
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
          SetCommTimeouts(g_serial, &timeouts);
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
          DWORD written = 0;
          BOOL ok = FALSE;
          if (g_printer) {
            ok = WritePrinter(g_printer, const_cast<uint8_t*>(bytes->data()),
                              static_cast<DWORD>(bytes->size()), &written);
          } else if (g_serial != INVALID_HANDLE_VALUE) {
            ok = WriteFile(g_serial, bytes->data(),
                           static_cast<DWORD>(bytes->size()), &written, nullptr);
          } else {
            result->Error("NOT_CONNECTED", "No printer connection is open.");
            return;
          }
          if (!ok || written != bytes->size()) {
            result->Error("WRITE_FAILED", "Windows could not send all printer bytes.",
                          flutter::EncodableValue(static_cast<int>(GetLastError())));
            return;
          }
          result->Success(flutter::EncodableValue(static_cast<int>(written)));
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
