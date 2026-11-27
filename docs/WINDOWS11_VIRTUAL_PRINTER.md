# Windows 11 virtual printer implementation decision

## Selected Windows print architecture

Use Microsoft's **Print Support Virtual Printer (PSA v4 / Software Endpoint)** architecture, packaged as MSIX. Do not use a legacy V3/V4 printer driver, a fabricated printer queue, a port monitor DLL, or a PowerShell-only registration script.

Microsoft documents that the `windows.printSupportVirtualPrinterWorkflow` manifest contract installs a real Windows print queue and invokes the packaged app when a user submits a print job. The workflow receives a PDL stream and can launch a job UI through `PrintWorkflowUILauncher`.

References:
- https://learn.microsoft.com/windows-hardware/drivers/devapps/msix-manifest-specification-print-support-virtual-printer
- https://learn.microsoft.com/windows-hardware/drivers/devapps/print-support-app-v4-design-guide
- https://github.com/microsoft/print-oem-samples/tree/master/PSASamples/WinAppSdk/CSharp

## Windows version baseline

The initial engineering target is **Windows 11 24H2 (build 26100) or later, x64**. Microsoft's current WinAppSDK C# PSA v4 sample targets `net10.0-windows10.0.26100.0`, Windows SDK `10.0.26100.0`, and describes Windows 11 24H2 as its supported baseline. Windows 11 22H2/23H2 are not declared supported by this implementation until a separate compatibility build and device test proves otherwise.

The Flutter desktop app remains a separate process and retains its existing USB/Bluetooth + ESC/POS path. The PSA package is a companion component; it must never load Flutter code in the Windows print workflow host.

## Required behavior

- Queue display name: `XP-P323B Virtual Printer`.
- Queue appears in Windows Settings and in the print dialogs of desktop applications such as Word and Excel.
- Default workflow: receive the completed print job, show the existing XP-P323B preview workflow, and wait for the user to press Print or Cancel.
- Direct-print mode: when the saved app preference is enabled, skip preview and send the converted pages to the existing ESC/POS raster engine.
- Keep page boundaries, page order, job title, and source application metadata.
- Never forward OXPS/EMF/RAW spool bytes directly to the physical thermal printer. Convert the job to a page representation supported by the current Flutter preview/renderer first.
- Keep the existing physical printer connection and transport code unchanged.

## Package and workflow design

1. Build a companion WinUI 3 / Windows App SDK MSIX package containing the PSA v4 app and a registered `IBackgroundTask` implementation.
2. Declare `windows.printSupportVirtualPrinterWorkflow` in `Package.appxmanifest`, with `PreferredInputFormat="application/oxps"`, a mandatory PDC resource, a unique `PrinterUri`, and display name resources.
3. In `VirtualPrinterBackgroundTask`, subscribe to `VirtualPrinterDataAvailable` before starting the session. Read the input PDL stream, validate its content type and size, stage the job safely, and complete the workflow with an accurate success/failure/canceled status.
4. Use the PSA job-UI activation contract for preview-first. The UI process must not block the spooler. Connect the packaged workflow to the existing Flutter app using a versioned, authenticated local handoff (staged files plus a local IPC/activation protocol); do not assume the Flutter app can directly receive a WinRT activation.
5. Render OXPS pages to a stable page format for the existing preview and ESC/POS raster pipeline. Confirm the conversion API and test Arabic, images, tables, page sizes, and multi-page documents.
6. Add install/update/uninstall scripts for the signed MSIX package. Do not silently trust an ad-hoc certificate on customer machines; define a production signing/distribution approach before shipping an installer.
7. Add a Windows 11 24H2 CI job using Visual Studio/MSBuild and the Windows SDK required by the PSA sample. The existing Flutter Windows build remains a separate job.

## Security, reliability, and acceptance tests

- Bound job size, page count, and processing time; use unique job IDs and private staging locations.
- Clean up completed, canceled, failed, and expired jobs.
- Never report a print job as successful until its payload is safely staged and the handoff is acknowledged.
- Test queue installation/removal on a clean Windows 11 24H2 VM.
- Print from Word, Excel, Notepad, and Edge; test preview, direct mode, cancel, retry, multi-page output, and app-not-running behavior.
- Test the physical XP-P323B over USB and Bluetooth separately after the virtual-job path works.
- Confirm the original Flutter build, USB/Bluetooth bridge, and ESC/POS raster tests remain unchanged.

## Current status

This decision record selects the Windows 11 PSA v4/MSIX path and defines the integration boundary. It does **not** claim that the queue, MSIX package, background task, page conversion, signing, or end-to-end printing have been implemented. Those are the next engineering tasks and must be validated by Windows build output and real print-dialog tests.
