# XP-P323B Virtual Printer — implementation plan

## Goal

Install a Windows print queue named **XP-P323B Virtual Printer**. Applications such as Word and Excel must be able to submit normal Windows print jobs to it. The queue must hand each completed job to the XP-P323B desktop app, where the default action is preview-first. The existing ESC/POS raster engine remains the only path that sends bytes to the physical printer.

## Important distinction

The current file picker, drag-and-drop, Open with, and Send to integrations are Windows Shell file-opening features. They do not create a Windows print queue and do not receive jobs submitted from an application's Print dialog.

A real queue needs the Windows Print Support Virtual Printer workflow. A queue name created with PowerShell alone is not sufficient.

## Selected architecture

Windows 11 24H2 (build 26100) or later, x64, using Microsoft's Print Support App v4 / Software Endpoint architecture packaged as MSIX.

1. **Virtual queue package**
   - MSIX package declares `windows.printSupportVirtualPrinterWorkflow`.
   - Queue display name: `XP-P323B Virtual Printer`.
   - Preferred input: `application/oxps`.
2. **Spooler job capture**
   - Packaged PSA background task receives the OXPS stream.
   - Windows' PDL converter converts OXPS to PDF.
   - The initial implementation stores the PDF and metadata in the package-private LocalFolder.
3. **Desktop broker — pending**
   - Add a versioned, authenticated local IPC handoff from the packaged component to Flutter.
   - The Flutter app must acknowledge the complete payload before the PSA marks the job successful.
4. **Rendering and preview — pending**
   - Feed the received PDF into the existing print-document loader and preview workspace.
   - Default behavior: open preview and wait for Print or Cancel.
   - When the persisted direct-print setting is enabled, skip preview and use the existing ESC/POS raster engine.
5. **Physical output**
   - Reuse existing USB/Bluetooth transport and ESC/POS raster conversion.
   - Never forward OXPS/EMF/RAW spool bytes directly to the thermal printer.

## Current implementation in this branch

- Added `windows-virtual-printer/PrintSupportApp`, a packaged WinUI 3 / Windows App SDK PSA host.
- Added `windows-virtual-printer/Tasks`, a CsWinRT background task that receives OXPS and converts it to PDF.
- Added a PDC capability file, package manifest, and PowerShell asset/build scripts.
- Added a separate GitHub Actions workflow that builds an unsigned MSIX artifact.
- The current background task stores PDF jobs in package-private storage. It does **not** yet hand them to Flutter or send them to the physical printer.
- No changes were made to the existing Flutter USB/Bluetooth bridge or ESC/POS raster engine.

## Remaining implementation gates

- Build and validate the MSIX project in CI against Windows SDK 10.0.26100.
- Test queue registration and removal on a clean Windows 11 24H2 VM.
- Implement secure handoff from the PSA package to Flutter.
- Connect default preview and the existing direct-print preference to the incoming job.
- Add the signed MSIX to the Inno Setup installer and remove only this package/queue during uninstall.
- Obtain and configure a trusted package-signing certificate; CI intentionally emits an unsigned package.
- Verify Word, Excel, Notepad, and Edge print jobs, including multi-page, cancel, retry, and app-not-running cases.
- Verify physical USB and Bluetooth printing separately on XP-P323B hardware.

## Security and packaging constraints

- Never install an unsigned or unverified kernel-mode driver silently.
- Do not replace or modify the Xprinter physical printer driver.
- Do not run Flutter code inside the Windows spooler process.
- Bound job size, page count, and processing time; reject malformed or incomplete jobs.
- Keep staged jobs private and implement cleanup after successful handoff, cancellation, failure, or expiry.
- Uninstall must remove only the XP-P323B virtual printer package and queue.
- A successful Flutter build or an MSIX compilation is not evidence of end-to-end print-dialog operation.
