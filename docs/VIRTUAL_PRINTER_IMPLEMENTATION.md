# XP-P323B Virtual Printer — implementation plan

## Goal

Install a Windows print queue named XP-P323B Virtual Printer. Applications such as Word and Excel submit normal Windows print jobs to it. The queue sends each job through the existing XP-P323B app, with preview-first by default and optional direct printing. The existing ESC/POS raster engine remains the only path that sends bytes to the physical printer.

## Selected architecture

Windows 11 24H2 (build 26100) or later, x64, using Microsoft's Print Support App v4 / Software Endpoint architecture packaged as MSIX.

1. MSIX declares the virtual-printer workflow and registers the queue.
2. PSA background task receives OXPS print data.
3. PSA invokes the Windows Print Support Job UI through PrintWorkflowUILauncher.LaunchAndCompleteUIAsync(). The job UI supports Continue and Cancel.
4. After Continue, the background task converts OXPS to PDF and stores it in package-private LocalFolder.
5. Pending: hand the staged PDF to the installed Flutter desktop app using a package full-trust broker and a per-user staging directory.
6. Flutter opens the PDF in the existing preview workspace, or follows the persisted directPrintOnOpen setting and uses the existing ESC/POS raster + USB/Bluetooth bridge.

## Current implementation in this branch

- Packaged WinUI 3 / Windows App SDK PSA host and CsWinRT background task.
- Virtual printer manifest entry and PDC capabilities.
- Print Support Job UI activation page with Continue/Cancel.
- OXPS-to-PDF conversion and package-private job staging.
- PowerShell build scripts and a dedicated GitHub Actions build workflow.
- The Flutter handoff, direct-print routing for incoming virtual jobs, signed MSIX installation and uninstall integration are not complete.
- No changes have been made to the existing physical USB/Bluetooth transport or ESC/POS raster implementation.

## Acceptance gates

- Build the MSIX on Windows 11 / Windows SDK 10.0.26100.
- Install the signed package on a clean Windows 11 24H2 x64 machine and verify queue registration.
- Send jobs from Word, Excel, Notepad and Edge; verify the UI appears, Continue captures the document and Cancel cancels it.
- Implement authenticated full-trust broker handoff and connect it to Flutter's existing print workspace.
- Verify preview-first and direct-print preference paths.
- Test USB and Bluetooth physical output on XP-P323B hardware.
- Verify upgrade/uninstall removes only this package and its virtual queue.

## Security and packaging

- Do not install unsigned packages silently or add an untrusted certificate to machine trust.
- Do not modify the physical Xprinter driver.
- Do not pass spooler RAW/OXPS bytes directly to the thermal printer.
- Keep staged jobs private, bound job size and expiry, and clean up after acknowledgement/cancel/failure.
- A successful Flutter build or MSIX compile alone is not proof of end-to-end printing.
