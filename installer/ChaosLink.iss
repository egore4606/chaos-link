#ifndef AppVersion
  #define AppVersion "0.6.0"
#endif
#ifndef StageDir
  #define StageDir "..\dist\payload"
#endif

[Setup]
AppId={{3B8EE932-A6B7-4B20-96F0-11CB4DA6A62A}
AppName=Chaos Link
AppVersion={#AppVersion}
AppVerName=Chaos Link {#AppVersion}
AppPublisher=Chaos Link
AppPublisherURL=https://github.com/egore4606/chaos-link
AppSupportURL=https://github.com/egore4606/chaos-link/issues
AppUpdatesURL=https://github.com/egore4606/chaos-link/releases/latest
DefaultDirName={localappdata}\ChaosLink
DefaultGroupName=Chaos Link
DisableProgramGroupPage=yes
OutputDir=..\dist
OutputBaseFilename=ChaosLink-Setup
Compression=lzma2/max
SolidCompression=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
MinVersion=10.0.14393
SetupLogging=yes
CloseApplications=yes
RestartApplications=no
AllowNetworkDrive=no
AllowUNCPath=no
AllowRootDirectory=no
UsePreviousAppDir=yes
Uninstallable=yes
UninstallLogMode=append
UninstallDisplayIcon={app}\app\control\ChaosLink.Control.exe
VersionInfoVersion={#AppVersion}.0
VersionInfoCompany=Chaos Link
VersionInfoDescription=Offline installer for Chaos Link
VersionInfoProductName=Chaos Link
WizardStyle=modern

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Dirs]
Name: "{app}\runtime"
Name: "{app}\screamer\images"
Name: "{app}\screamer\sounds"

[InstallDelete]
Type: filesandordirs; Name: "{app}\dotnet"
Type: files; Name: "{app}\Uninstall-ChaosLink.ps1"

[Files]
Source: "{#StageDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "Initialize-ChaosLink.ps1"
Source: "{#StageDir}\Initialize-ChaosLink.ps1"; DestDir: "{app}"; Flags: ignoreversion; AfterInstall: InitializeInstallation

[Icons]
Name: "{group}\Chaos Link"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoLogo -NoProfile -ExecutionPolicy Bypass -File ""{app}\Start-ChaosLink.ps1"""; WorkingDir: "{app}"
Name: "{group}\Остановить Chaos Link"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoLogo -NoProfile -ExecutionPolicy Bypass -File ""{app}\Stop-ChaosLink.ps1"""; WorkingDir: "{app}"
Name: "{group}\Файлы Chaos Link"; Filename: "{sys}\explorer.exe"; Parameters: """{app}"""
Name: "{group}\Удалить Chaos Link"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Chaos Link"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoLogo -NoProfile -ExecutionPolicy Bypass -File ""{app}\Start-ChaosLink.ps1"""; WorkingDir: "{app}"; Tasks: desktopicon
Name: "{autodesktop}\Chaos Link - Остановить"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoLogo -NoProfile -ExecutionPolicy Bypass -File ""{app}\Stop-ChaosLink.ps1"""; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoLogo -NoProfile -ExecutionPolicy Bypass -File ""{app}\Start-ChaosLink.ps1"""; WorkingDir: "{app}"; Description: "Запустить Chaos Link"; Flags: postinstall nowait skipifsilent unchecked

[UninstallRun]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoLogo -NoProfile -ExecutionPolicy Bypass -File ""{app}\Stop-ChaosLink.ps1"" -RemoveFirewallRule"; WorkingDir: "{app}"; Flags: runhidden waituntilterminated; RunOnceId: "StopChaosLink"

[UninstallDelete]
Type: filesandordirs; Name: "{app}\runtime"
Type: filesandordirs; Name: "{app}\screamer"
Type: filesandordirs; Name: "{app}\dotnet"
Type: files; Name: "{app}\.chaos-link-install"
Type: files; Name: "{app}\app\server\appsettings.Production.json"
Type: files; Name: "{app}\Uninstall-ChaosLink.ps1"
Type: dirifempty; Name: "{app}"

[Code]
function RunPowerShell(const ScriptName, ExtraArguments: String): Boolean;
var
  ResultCode: Integer;
  PowerShellPath: String;
  Parameters: String;
begin
  PowerShellPath := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  Parameters := '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
    ExpandConstant('{app}\' + ScriptName) + '" ' + ExtraArguments;
  Log('Running: ' + PowerShellPath + ' ' + Parameters);
  Result := Exec(PowerShellPath, Parameters, ExpandConstant('{app}'), SW_HIDE,
    ewWaitUntilTerminated, ResultCode) and (ResultCode = 0);
  if not Result then
    Log('PowerShell helper failed with exit code ' + IntToStr(ResultCode));
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if FileExists(ExpandConstant('{app}\.chaos-link-install')) then
  begin
    WizardForm.StatusLabel.Caption := 'Остановка предыдущей версии Chaos Link...';
    if not RunPowerShell('Stop-ChaosLink.ps1', '') then
      Result := 'Не удалось остановить предыдущую версию. Закройте Chaos Link и повторите установку.';
  end;
end;

procedure InitializeInstallation;
begin
  WizardForm.StatusLabel.Caption := 'Безопасная настройка Chaos Link...';
  if not RunPowerShell('Initialize-ChaosLink.ps1', '-InstallRoot "' + ExpandConstant('{app}') + '"') then
    RaiseException('Не удалось настроить Chaos Link. Подробности сохранены в %TEMP%\ChaosLink-install-bootstrap.log.');
end;
