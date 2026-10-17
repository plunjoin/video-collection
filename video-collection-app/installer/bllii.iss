#ifndef MyAppVersion
#define MyAppVersion "1.0.1"
#endif

#define MyAppName "Bllii"
#define MyAppPublisher "Bllii"
#define MyAppExeName "video_collection_app.exe"
#define MyAppIcon "..\windows\runner\resources\app_icon.ico"
#define SourceDir "..\build\windows\x64\runner\Release"
#define OutputDir "..\dist"

[Setup]
; 唯一应用识别 GUID
AppId={{D377B73F-9109-4DF5-B86B-13AC76CD699F}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
OutputDir={#OutputDir}
OutputBaseFilename=bllii_setup_windows_{#MyAppVersion}
SetupIconFile={#MyAppIcon}
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
WizardSizePercent=120
WizardImageFile=wizard.bmp
WizardSmallImageFile=wizard-small.bmp
DisableReadyPage=yes
DisableProgramGroupPage=yes
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
CloseApplications=force

[Messages]
chinesesimplified.WelcomeLabel1=欢迎安装 Bllii 视频合集
chinesesimplified.WelcomeLabel2=More Stories, Together%n%n向导将指引您完成 Bllii 桌面客户端的安装。%n%n建议在继续之前关闭其他正在运行的应用程序。
chinesesimplified.FinishedHeadingLabel=Bllii 安装完成
chinesesimplified.FinishedLabel=Bllii 已成功安装到您的电脑中。%n%n点击“完成”即可立即开启精彩视频之旅。

[Languages]
Name: "chinesesimplified"; MessagesFile: "ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
