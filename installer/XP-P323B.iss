#define MyAppName "XP-P323B Windows"
#define MyAppVersion "0.1.0"
#define MyAppPublisher "XP-P323B"
#define MyAppExeName "xp_p323b_windows.exe"

[Setup]
AppId={{7A9F2E3B-1C64-4A8D-9D32-8E21F4A8B630}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\XP-P323B Windows
DefaultGroupName=XP-P323B Windows
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
OutputDir=..\dist
OutputBaseFilename=XP-P323B-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
ChangesAssociations=yes
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "arabic"; MessagesFile: "compiler:Languages\Arabic.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "payload\XP-P323B.VirtualPrinter.msix"; DestDir: "{app}\VirtualPrinter"; Flags: ignoreversion
Source: "payload\XP-P323B-TestSigning.cer"; DestDir: "{app}\VirtualPrinter"; Flags: ignoreversion
Source: "install_virtual_printer.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "uninstall_virtual_printer.ps1"; DestDir: "{app}"; Flags: ignoreversion

[Registry]
Root: HKCU; Subkey: "Software\XP-P323B\Windows"; ValueType: string; ValueName: "AppExePath"; ValueData: "{app}\{#MyAppExeName}"; Flags: uninsdeletevalue

[Icons]
Name: "{autoprograms}\XP-P323B Windows"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{autodesktop}\XP-P323B Windows"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\install_virtual_printer.ps1"" -MsixPath ""{app}\VirtualPrinter\XP-P323B.VirtualPrinter.msix"" -CertificatePath ""{app}\VirtualPrinter\XP-P323B-TestSigning.cer"""; Flags: runhidden waituntilterminated
Filename: "{app}\{#MyAppExeName}"; Description: "Launch XP-P323B Windows"; Flags: postinstall nowait skipifsilent

[UninstallRun]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\uninstall_virtual_printer.ps1"""; Flags: runhidden waituntilterminated
