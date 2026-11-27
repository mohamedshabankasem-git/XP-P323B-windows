# XP-P323B Virtual Printer — implementation plan

## Goal

Install a Windows print queue named **XP-P323B Virtual Printer**. Applications such as Word and Excel must be able to submit normal Windows print jobs to it. The queue must hand each completed job to the XP-P323B desktop app, where the default action is preview-first. The existing ESC/POS raster engine remains the only path that sends bytes to the physical printer.

## Important distinction

The current file picker, drag-and-drop, Open with, and Send to integrations are Windows Shell file-opening features. They do not create a Windows print queue and do not receive jobs submitted from an application's Print dialog.

A real queue needs an installed Windows printer driver and a spooler-side component. A queue name created with PowerShell alone is not sufficient.

## Proposed architecture

1. **Virtual queue package**
   - A printer INF package declares the virtual model and the required driver components.
   - The package creates the queue with the display name XP-P323B Virtual Printer.
   - Installation and removal run elevated, are explicit, and verify each spooler operation.
2. **Spooler job capture**
   - A native Windows print component receives the completed spooler job.
   - It preserves page boundaries and job metadata, and transfers the job to the desktop app over a versioned local IPC protocol.
   - The component must not execute Flutter code inside the spooler process.
3. **Desktop broker**
   - The Flutter app owns the user-facing workflow and accepts jobs only from the local broker.
   - Each job is staged in a private temporary directory with bounded size, unique identifiers, and cleanup after completion or expiry.
   - The app acknowledges a job only after it has safely staged the complete payload.
4. **Rendering and preview**
   - Render the spooler document to page images at the selected paper width.
   - Default behavior: open the existing preview workspace and wait for the user to press Print.
   - When the saved direct-print setting is enabled, skip preview and send pages through the existing ESC/POS raster engine.
5. **Physical output**
   - Reuse the existing USB/Bluetooth transport and ESC/POS raster conversion.
   - Do not send Windows EMF/XPS/RAW spool data directly to the thermal printer.

## Implementation gates

- Confirm the selected Windows print path and supported Windows versions.
- Implement the spooler-side native component and local IPC broker.
- Implement document conversion for the actual spool format emitted by the selected driver.
- Add elevated install/uninstall scripts and include all package files in the installer.
- Verify install, queue visibility, Word/Excel test jobs, preview, cancel, retry, uninstall, and spooler recovery on a clean Windows VM.
- Verify physical USB and Bluetooth printing separately on XP-P323B hardware.

## Security and packaging constraints

- Never install an unsigned or unverified kernel-mode driver silently.
- Do not replace or modify the Xprinter physical printer driver.
- Do not run the Flutter UI or wait for user interaction inside the spooler process.
- Bound job size and processing time; reject malformed or incomplete jobs.
- Uninstall must remove only the XP-P323B Virtual Printer queue and components installed by this package.
- A successful Flutter build is not evidence that a virtual queue is installed or operational.

## Current status

The Windows Shell file-opening workflow and ESC/POS preview/print UI exist in the feature branch. The actual virtual printer queue, spooler component, and spooler-to-app transport are **not implemented yet**. This document records the implementation boundary so later work does not mistake Open with / Send to for print-dialog integration.
