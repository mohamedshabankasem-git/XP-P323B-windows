# XP-P323B Windows 11 virtual printer package

This is the first native Windows Print Support App (PSA v4) component for the XP-P323B application. It targets Windows 11 24H2 (build 26100) or later, x64.

## What this phase implements

- Declares a Windows Print Support Virtual Printer named **XP-P323B Virtual Printer** using the Windows 11 PSA virtual-printer workflow.
- Receives the OXPS print stream from the Windows print workflow.
- Converts OXPS to PDF using the Windows print workflow PDL converter.
- Stores each accepted job and a small metadata record in the package's private LocalFolder.

This is a real print-workflow implementation foundation, not yet the finished Flutter handoff. The captured PDF is not yet forwarded to the existing Flutter preview or physical printer. Do not advertise this phase as end-to-end printing.

## Project layout

- `PrintSupportApp`: packaged WinUI 3 / Windows App SDK app and package manifest.
- `Tasks`: CsWinRT background task activated by the virtual printer workflow.
- `PrintSupportApp/Config/PrinterPdc.xml`: printer capabilities supplied to Windows.

## Build

Build on Windows 11 24H2 with Visual Studio 2026, Windows SDK 10.0.26100.0, .NET 10 SDK, and MSIX Packaging Tools:

```powershell
.\scripts\build_virtual_printer.ps1
```

The CI package is intentionally unsigned. A production installer must use a trusted signing certificate whose subject matches the package Publisher. Do not install a self-signed certificate into machine trust stores as a workaround.

## Job output

Captured jobs are written under the package's private LocalFolder in `VirtualPrinterJobs` as `<job-id>.pdf` and `<job-id>.json`. Windows removes the spooler job only after the converted output has been written successfully.

## Next integration gates

1. Add authenticated job handoff from the packaged PSA component to the Flutter desktop process.
2. Open the existing Flutter print workspace by default and wait for Print/Cancel.
3. Reuse the existing ESC/POS raster engine and USB/Bluetooth bridge for direct print when the persisted direct-print preference is enabled.
4. Add signed MSIX deployment to the Inno Setup installer, including safe upgrade and uninstall behavior.
5. Validate real print-dialog submissions from Word, Excel, Notepad, and Edge on a clean Windows 11 24H2 machine.

## Microsoft reference

Implementation is based on Microsoft's Print Support Virtual Printer and Windows App SDK C# PSA sample. See:
- https://learn.microsoft.com/windows-hardware/drivers/devapps/msix-manifest-specification-print-support-virtual-printer
- https://learn.microsoft.com/windows-hardware/drivers/devapps/print-support-app-v4-design-guide
- https://github.com/microsoft/print-oem-samples/tree/master/PSASamples/WinAppSdk/CSharp
