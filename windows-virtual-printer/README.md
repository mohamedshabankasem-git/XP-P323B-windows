# XP-P323B Windows 11 virtual printer package

Native Windows Print Support App (PSA v4) package for Windows 11 24H2 (build 26100) or later, x64.

## Implemented in this branch

- Registers a real Windows virtual print queue named **XP-P323B Virtual Printer** through the Windows Print Support Virtual Printer workflow.
- Receives OXPS jobs submitted by Windows applications.
- Opens the Print Support Job UI with Continue and Cancel actions.
- Converts accepted OXPS jobs to PDF using the Windows PDL converter.
- Stores PDF and metadata in the package-private LocalFolder.
- Launches a packaged full-trust broker. The broker copies captured PDFs to the per-user XP-P323B staging folder and starts the installed Flutter app with the PDF path.
- The Flutter app's existing file-open path then applies its saved preview/direct-print preference. The broker validates job IDs and rejects empty or oversized PDFs (over 256 MB).

The broker handoff is implemented in source but has not yet passed a Windows build or runtime test. The direct-print path still requires a connected physical printer in the Flutter process. The MSIX package is unsigned. The Inno Setup script now includes the signed package and install/uninstall scripts; scripts/build_windows_installer.ps1 signs the MSIX with a trusted PFX and builds the combined Setup.exe. A matching trusted certificate is required.

## Project layout

- PrintSupportApp: packaged WinUI 3 / Windows App SDK PSA host, job UI and manifest.
- Tasks: CsWinRT virtual-printer background task and OXPS-to-PDF conversion.
- XpJobBroker: full-trust process that transfers staged jobs to the desktop app.
- PrintSupportApp/Config/PrinterPdc.xml: print capabilities supplied to Windows.

## Build

Build on Windows 11 24H2 with Visual Studio 2026, Windows SDK 10.0.26100.0, .NET 10 SDK and MSIX Packaging Tools:

```powershell
.\scripts\build_virtual_printer.ps1
```

The CI package is intentionally unsigned. Production installation requires a trusted code-signing certificate whose subject exactly matches CN=XP-P323B in Package.appxmanifest. Never silently trust a self-signed certificate. After building Flutter Release and the MSIX, run scripts/build_windows_installer.ps1 -MsixPath <path-to-msix> with XP_P323B_SIGNING_PFX_BASE64 and XP_P323B_SIGNING_PFX_PASSWORD set.

## Handoff

The broker expects the Inno Setup installer to write the installed Flutter executable path to HKCU\Software\XP-P323B\Windows, value AppExePath. The installer script now writes that value. Captured PDFs are copied to %LOCALAPPDATA%\XP-P323B\VirtualPrinterJobs and retained for up to 24 hours.

## Remaining verification

1. Build the MSIX in Windows CI and fix any SDK/compiler issues.
2. Install a signed package on a clean Windows 11 24H2 x64 VM and confirm the queue appears.
3. Submit real jobs from Word, Excel, Notepad and Edge; test Continue, Cancel, multi-page and retry.
4. Verify the broker launches Flutter and the correct PDF opens in the existing preview.
5. Verify direct-print mode with a previously connected USB and Bluetooth XP-P323B.
6. Integrate signed MSIX install/uninstall into Setup.exe and verify safe upgrades/removal.

## Microsoft references

- https://learn.microsoft.com/windows-hardware/drivers/devapps/msix-manifest-specification-print-support-virtual-printer
- https://learn.microsoft.com/windows-hardware/drivers/devapps/print-support-app-v4-design-guide
- https://learn.microsoft.com/en-us/uwp/api/windows.applicationmodel.fulltrustprocesslauncher
- https://github.com/microsoft/print-oem-samples/tree/master/PSASamples/WinAppSdk/CSharp
