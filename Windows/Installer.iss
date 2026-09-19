#define MyAppName "ChatGPT Usage"
#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif
#define MyAppExeName "ChatGPTUsage.Windows.exe"

[Setup]
AppId={{85D35CB7-34B0-4D09-9E6F-8E4AE03AFAFA}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
DefaultDirName={localappdata}\Programs\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
AppMutex=Local\ChatGPTUsage.Windows
; The official Codex CLI installer creates managed per-user junctions.
RedirectionGuard=no
OutputDir=dist
OutputBaseFilename=ChatGPTUsage-Setup-{#MyAppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
InfoBeforeFile=..\UNSIGNED-INSTALL.txt

[Files]
Source: "InstallerPayload\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\UNSIGNED-INSTALL.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\Assets\ChatGPTUsage.ico"; IconIndex: 0
Name: "{group}\Installation and security notice"; Filename: "{app}\UNSIGNED-INSTALL.txt"
Name: "{group}\MIT License"; Filename: "{app}\LICENSE"

[InstallDelete]
Type: files; Name: "{userprograms}\ChatGPT Usage.lnk"

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "ChatGPT Usage"; ValueData: """{app}\{#MyAppExeName}"""; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\asetho\ChatGPT Usage"; ValueType: none; Flags: uninsdeletekey

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent

[Code]
var
  CodexInstallPage: TInputOptionWizardPage;

const
  CodexInstallScript =
    '$ErrorActionPreference = ''Stop''' + #13#10 +
    '$env:CODEX_NON_INTERACTIVE = ''1''' + #13#10 +
    '$transcriptPath = Join-Path $env:LOCALAPPDATA ''Temp\ChatGPTUsage-CodexInstall.log''' + #13#10 +
    'Start-Transcript -Path $transcriptPath -Force' + #13#10 +
    'try {' + #13#10 +
    '  Invoke-RestMethod ''https://chatgpt.com/codex/install.ps1'' | Invoke-Expression' + #13#10 +
    '} finally {' + #13#10 +
    '  Stop-Transcript' + #13#10 +
    '}' + #13#10;

function IsCodexCliInstalled: Boolean;
var
  ConfiguredExecutable: String;
  SearchPath: String;
begin
  ConfiguredExecutable := GetEnv('CODEX_EXECUTABLE');
  SearchPath := GetEnv('PATH');

  Result :=
    ((ConfiguredExecutable <> '') and FileExists(ConfiguredExecutable)) or
    FileExists(ExpandConstant('{localappdata}\Programs\OpenAI\Codex\bin\codex.exe')) or
    FileExists(ExpandConstant('{userappdata}\npm\codex.cmd')) or
    (FileSearch('codex.exe', SearchPath) <> '') or
    (FileSearch('codex.cmd', SearchPath) <> '');
end;

procedure InitializeWizard;
begin
  if not IsCodexCliInstalled then
  begin
    CodexInstallPage := CreateInputOptionPage(
      wpSelectDir,
      'Codex CLI required',
      'ChatGPT Usage requires the Codex CLI to read your account usage.',
      'Codex CLI was not found for this Windows account. Setup can install the official CLI now. You may need to run codex once after setup to sign in with ChatGPT.',
      False,
      False);
    CodexInstallPage.Add('Install the official Codex CLI now (recommended)');
    CodexInstallPage.Values[0] := True;
  end;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if (CodexInstallPage <> nil) and
     (CurPageID = CodexInstallPage.ID) and
     (not CodexInstallPage.Values[0]) then
  begin
    Result := MsgBox(
      'Without Codex CLI, ChatGPT Usage cannot display usage limits. Continue without installing it?',
      mbConfirmation,
      MB_YESNO) = IDYES;
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  InstallScriptPath: String;
  PowerShellPath: String;
  PowerShellParams: String;
  ResultCode: Integer;
begin
  Result := '';
  if (CodexInstallPage = nil) or
     (not CodexInstallPage.Values[0]) or
     IsCodexCliInstalled then
  begin
    Exit;
  end;

  InstallScriptPath := ExpandConstant('{tmp}\install-codex-cli.ps1');
  if not SaveStringToFile(InstallScriptPath, CodexInstallScript, False) then
  begin
    Result :=
      'Setup could not prepare the Codex CLI installer. Go back and retry, ' +
      'or install Codex CLI manually before using ChatGPT Usage.';
    Exit;
  end;

  PowerShellPath := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  PowerShellParams :=
    '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "' + InstallScriptPath + '"';

  if (not Exec(PowerShellPath, PowerShellParams, '', SW_HIDE,
      ewWaitUntilTerminated, ResultCode)) or (ResultCode <> 0) then
  begin
    Log(Format('Codex CLI installer failed with exit code %d.', [ResultCode]));
    Result :=
      'Codex CLI could not be installed. Check your internet connection and try again, ' +
      'or go back and continue without it. ChatGPT Usage will not work until Codex CLI is installed. ' +
      'Details were saved to ' +
      ExpandConstant('{localappdata}\Temp\ChatGPTUsage-CodexInstall.log') + '.';
    Exit;
  end;

  if not IsCodexCliInstalled then
  begin
    Result :=
      'The Codex installer completed, but Codex CLI could not be found. ' +
      'Go back and retry, or install Codex CLI manually before using ChatGPT Usage.';
    Exit;
  end;

  DeleteFile(ExpandConstant('{localappdata}\Temp\ChatGPTUsage-CodexInstall.log'));
end;
