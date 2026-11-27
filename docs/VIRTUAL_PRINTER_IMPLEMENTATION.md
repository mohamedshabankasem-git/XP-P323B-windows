# XP-P323B Virtual Printer — implementation plan

## Goal

Install a Windows print queue named XP-P323B Virtual Printer. Word, Excel and other Windows applications submit normal print jobs to it. The queue hands each job to the existing XP-P323B desktop app, with preview-first by default and optional direct printing. The existing ESC/POS raster engine remains the only path that sends bytes to the physical printer.

## Selected architecture

Windows 11 24H2 (build 26100) or later, x64, using Microsoft's Print Support App v4 / Software Endpoint architecture packaged as MSIX.

1. The MSIX declares the Windows Print Support Virtual Printer workflow and registers the queue.
2. A CsWinRT background task receives the OXPS print stream.
3. PrintWorkflowUILauncher opens the PSA Job UI, which offers Continue and Cancel.
4. On Continue, the task converts OXPS to PDF and stores it in the package-private LocalFolder.
5. The task starts the package's full-trust broker.
6. The broker claims each captured job, copies the PDF into the per-user XP-P323B staging directory, and launches the installed Flutter executable with the PDF path.
7. Flutter's existing file-open flow loads the PDF and applies the persisted directPrintOnOpen setting. The existing ESC/POS raster engine and USB/Bluetooth bridge remain the physical output path.

## Current implementation in this branch

- WinUI 3 / Windows App SDK PSA host.
- Virtual-printer manifest entry, print capabilities and job UI activation.
- Continue/Cancel UI for submitted print jobs.
- OXPS-to-PDF conversion and package-private staging.
- Packaged full-trust broker and per-user PDF handoff to Flutter.
- Inno Setup writes the installed Flutter executable path to HKCU Software XP-P323B Windows / AppExePath.
- Dedicated Windows CI workflow for MSIX compilation and unsigned artifact generation.

## Known limitations and gates

- Source changes have not yet been validated by a successful Windows MSIX build. The current environment cannot run the Windows SDK/MSBuild toolchain.
- The MSIX is unsigned. A trusted code-signing certificate matching the manifest Publisher is required before customer installation and Setup.exe integration.
- Real queue registration and print-dialog submissions from Word, Excel, Notepad and Edge remain untested.
- The Flutter direct-print preference requires a live physical printer connection in the Flutter process. Automatic restoration of the physical connection for a newly launched instance remains to be verified/implemented.
- The broker handoff and cleanup logic need runtime tests for multiple jobs, interrupted launch, app-not-installed, malformed metadata and expired jobs.
- Signed MSIX installation/removal has not yet been integrated into Inno Setup.

## Safety boundaries

- Do not modify or replace the Xprinter physical printer driver.
- Do not send Windows spooler OXPS/RAW bytes directly to the thermal printer.
- Never silently install or trust an unsigned/self-signed package.
- Uninstall must remove only the XP-P323B virtual printer package and its queue.
- A successful Flutter build or MSIX compilation alone is not proof of end-to-end printing.
