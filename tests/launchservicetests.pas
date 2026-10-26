unit launchservicetests;

{$mode delphi}

interface

uses Windows, Classes, SysUtils, ActiveX, ComObj, ShellAPI, ShlObj,
  fpcunit, testregistry, launchserviceu, setsu, PIDL, toolu,
  scitemu, scsubitemu, itemserializationu;

type
  TLaunchRoute = (lrNone, lrApplication, lrDirect, lrThreaded, lrPIDL);
  TRecordingLaunch = class(TLaunchService)
  protected
    procedure ActivatePackagedApp(const AppID: UnicodeString); override;
    procedure ExecuteShellIDList(var Info: TShellExecuteInfoW); override;
    procedure ExecuteShellTarget(const Target, Parameters, Directory: WideString;
      ShowCommand: Integer); override;
    function StartShellWorker(const Target, Parameters, Directory: WideString;
      ShowCommand: Integer): Boolean; override;
  public
    Route: TLaunchRoute;
    Calls, Show: Integer;
    Target, Parameters, Directory: WideString;
    SerializedPIDL: string;
    Mask: DWORD;
    procedure Reset;
  end;

  TLaunchServiceTests = class(TTestCase)
  private
    FService: TRecordingLaunch;
    FSettings: TDSets;
    FOriginalDirectory, FFixtureDirectory, FReport: string;
    procedure Report(Message: WideString; Silent: Boolean);
    procedure CheckApplication(const Target, Expected: string);
    procedure CheckOrdinary(const Target: string);
    procedure CheckPIDL(const Target: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure DifferentApplicationIDsUseActivation;
    procedure AppsFolderPrefixesPassOnlyTheIdentity;
    procedure PathsEndingAppKeepShellRouting;
    procedure URIsEndingAppKeepShellRouting;
    procedure ExistingIdentityShapedFileKeepsShellRouting;
    procedure ExistingIdentityShapedFolderKeepsFolderShell;
    procedure ShortcutsKeepShellRouting;
    procedure ShellRootsKeepShellRouting;
    procedure NamespaceObjectsKeepPIDLRouting;
    procedure SerializedPIDLsKeepPIDLRouting;
    procedure FilesystemPIDLDisplayNameStaysAPath;
    procedure DockAndStackFactoriesPreserveApplicationCommands;
    procedure ExpandedPathsEndingAppKeepShellRouting;
    procedure ClosePreventsApplicationActivation;
  end;

implementation

const
  TestFamily = 'TDOCK.Test_8wekyb3d8bbwe';
  TestApp = TestFamily + '!App';
  AppsGUID = '{4234d49b-0245-4df3-b780-3893943456e1}';

procedure TRecordingLaunch.Reset;
begin
  Route := lrNone;
  Calls := 0;
  Target := '';
  Parameters := '';
  Directory := '';
  SerializedPIDL := '';
  Mask := 0;
end;

procedure TRecordingLaunch.ActivatePackagedApp(const AppID: UnicodeString);
begin Inc(Calls); Route := lrApplication; Target := AppID; end;

procedure TRecordingLaunch.ExecuteShellIDList(var Info: TShellExecuteInfoW);
begin
  Inc(Calls);
  Route := lrPIDL;
  SerializedPIDL := PIDL_ToString(Info.lpIDList);
  Mask := Info.fMask;
  Show := Info.nShow;
end;

procedure TRecordingLaunch.ExecuteShellTarget(const Target, Parameters, Directory: WideString;
  ShowCommand: Integer);
begin
  Inc(Calls);
  Route := lrDirect;
  Self.Target := Target;
  Self.Parameters := Parameters;
  Self.Directory := Directory;
  Show := ShowCommand;
end;

function TRecordingLaunch.StartShellWorker(const Target, Parameters, Directory: WideString;
  ShowCommand: Integer): Boolean;
begin
  ExecuteShellTarget(Target, Parameters, Directory, ShowCommand);
  Route := lrThreaded;
  Result := True;
end;

procedure TLaunchServiceTests.SetUp;
var ID: TGUID;
begin
  OleCheck(OleInitialize(nil));
  FOriginalDirectory := GetCurrentDir;
  repeat
    CreateGUID(ID);
    FFixtureDirectory := ExtractFilePath(ParamStr(0)) + 'fixtures-' + GUIDToString(ID);
    if CreateDir(FFixtureDirectory) then Break;
    if not DirectoryExists(FFixtureDirectory) then RaiseLastOSError;
  until False;
  SetCurrentDir(FFixtureDirectory);
  FSettings := TDSets.Create('', '', 0);
  FSettings.container.useShell := False;
  FService := TRecordingLaunch.Create(FSettings, Report);
  FReport := '';
end;

procedure TLaunchServiceTests.TearDown;
begin
  FService.Free;
  FSettings.Free;
  DeleteFile(IncludeTrailingPathDelimiter(FFixtureDirectory) + TestApp);
  RemoveDir(IncludeTrailingPathDelimiter(FFixtureDirectory) + TestApp);
  SetCurrentDir(FOriginalDirectory);
  RemoveDir(FFixtureDirectory);
  OleUninitialize;
end;

procedure TLaunchServiceTests.Report(Message: WideString; Silent: Boolean);
begin FReport := UTF8Encode(Message); end;

procedure TLaunchServiceTests.CheckApplication(const Target, Expected: string);
var Threaded: Boolean;
begin
  for Threaded := False to True do
  begin
    FSettings.container.RunInThread := Threaded;
    FService.Reset;
    FService.Run(Target);
    AssertEquals(FReport, '', FReport);
    AssertEquals(Target, Ord(lrApplication), Ord(FService.Route));
    AssertEquals(1, FService.Calls);
    AssertEquals('Activation needs a bare AUMID', Expected, UTF8Encode(FService.Target));
  end;
end;

procedure TLaunchServiceTests.CheckOrdinary(const Target: string);
var Threaded: Boolean; ExpectedRoute: TLaunchRoute;
begin
  for Threaded := False to True do
  begin
    FSettings.container.RunInThread := Threaded;
    FService.Reset;
    FService.Run(Target, '--example x!App', FFixtureDirectory, SW_SHOWMINIMIZED);
    AssertEquals(FReport, '', FReport);
    if Threaded then ExpectedRoute := lrThreaded else ExpectedRoute := lrDirect;
    AssertEquals(Target, Ord(ExpectedRoute), Ord(FService.Route));
    AssertEquals(1, FService.Calls);
    AssertEquals(UnzipPath(Target), UTF8Encode(FService.Target));
    AssertEquals('--example x!App', UTF8Encode(FService.Parameters));
    AssertEquals(FFixtureDirectory, UTF8Encode(FService.Directory));
    AssertEquals(SW_SHOWMINIMIZED, FService.Show);
  end;
end;

procedure TLaunchServiceTests.CheckPIDL(const Target: string);
var Threaded: Boolean;
begin
  for Threaded := False to True do
  begin
    FSettings.container.RunInThread := Threaded;
    FService.Reset;
    FService.Run(Target, '', '', SW_SHOWMINIMIZED);
    AssertEquals(FReport, '', FReport);
    AssertEquals(Ord(lrPIDL), Ord(FService.Route));
    AssertEquals(1, FService.Calls);
    AssertEquals(SEE_MASK_IDLIST or SEE_MASK_FLAG_NO_UI, FService.Mask);
    AssertEquals(SW_SHOWMINIMIZED, FService.Show);
    AssertTrue(IsPIDLString(FService.SerializedPIDL));
  end;
end;

procedure TLaunchServiceTests.DifferentApplicationIDsUseActivation;
begin
  CheckApplication(TestApp, TestApp);
  CheckApplication(TestFamily + '!Main', TestFamily + '!Main');
  CheckApplication(TestFamily + '!MicrosoftEdge', TestFamily + '!MicrosoftEdge');
  CheckApplication('microsoft.windowscommunicationsapps_8wekyb3d8bbwe!microsoft.windowslive.calendar',
    'microsoft.windowscommunicationsapps_8wekyb3d8bbwe!microsoft.windowslive.calendar');
end;

procedure TLaunchServiceTests.AppsFolderPrefixesPassOnlyTheIdentity;
const AppID = TestFamily + '!MiXeD.Main';
begin
  CheckApplication('shell:AppsFolder\' + AppID, AppID);
  CheckApplication('ShElL:ApPsFoLdEr\' + AppID, AppID);
  CheckApplication('shell:::' + AppsGUID + '\' + AppID, AppID);
  CheckApplication('::' + AppsGUID + '\' + AppID, AppID);
end;

procedure TLaunchServiceTests.PathsEndingAppKeepShellRouting;
begin
  CheckOrdinary('C:\Example!App');
  CheckOrdinary('\\server\share\Example!App');
  CheckOrdinary('.\Example!App');
  CheckOrdinary('folder/Example!App');
  CheckOrdinary('Example!App');
end;

procedure TLaunchServiceTests.URIsEndingAppKeepShellRouting;
begin
  CheckOrdinary('https://example.invalid/!App');
  CheckOrdinary('custom:!App');
  CheckOrdinary('custom:' + TestApp);
  CheckOrdinary('file:///C:/Example!App');
end;

procedure TLaunchServiceTests.ExistingIdentityShapedFileKeepsShellRouting;
var Stream: TFileStream;
begin
  Stream := TFileStream.Create(TestApp, fmCreate);
  Stream.Free;
  CheckOrdinary(TestApp);
end;

procedure TLaunchServiceTests.ExistingIdentityShapedFolderKeepsFolderShell;
var Threaded: Boolean; ShellPath: string;
begin
  AssertTrue(CreateDir(TestApp));
  ShellPath := GetEnvironmentVariable('SystemRoot') + '\System32\notepad.exe';
  AssertTrue(FileExists(ShellPath));
  FSettings.container.useShell := True;
  FSettings.container.Shell := ShellPath;
  for Threaded := False to True do
  begin
    FSettings.container.RunInThread := Threaded;
    FService.Reset;
    FService.Run(TestApp);
    AssertEquals(FReport, '', FReport);
    AssertEquals(ShellPath, UTF8Encode(FService.Target));
    AssertEquals('"' + TestApp + '"', UTF8Encode(FService.Parameters));
    AssertEquals('', UTF8Encode(FService.Directory));
    AssertTrue(FService.Route in [lrDirect, lrThreaded]);
  end;
end;

procedure TLaunchServiceTests.ShortcutsKeepShellRouting;
begin
  CheckOrdinary('C:\Example!App.lnk');
  CheckOrdinary('C:\Example!App.url');
  CheckOrdinary('C:\Example!App.appref-ms');
end;

procedure TLaunchServiceTests.ShellRootsKeepShellRouting;
begin
  CheckPIDL('shell:AppsFolder');
  CheckPIDL('shell:::' + AppsGUID);
  FService.Reset;
  FService.Run('shell:AppsFolder\DesktopApp');
  AssertFalse('Desktop identities do not use packaged activation', FService.Route = lrApplication);
  AssertFalse('Explicit Shell names never fall back to filenames', FService.Route in [lrDirect, lrThreaded]);
  FService.Reset;
  FService.Run('shell:AppsFolder\PackageFamily!App');
  AssertFalse('Invalid package identities do not use packaged activation', FService.Route = lrApplication);
  AssertFalse('Explicit Shell names never fall back to filenames', FService.Route in [lrDirect, lrThreaded]);
end;

procedure TLaunchServiceTests.NamespaceObjectsKeepPIDLRouting;
begin
  CheckPIDL('::{20D04FE0-3AEA-1069-A2D8-08002B30309D}');
  CheckPIDL('::{645FF040-5081-101B-9F08-00AA002F954E}');
end;

procedure TLaunchServiceTests.SerializedPIDLsKeepPIDLRouting;
var IDList: PItemIDList; Saved: string;
begin
  IDList := PIDL_GetFromPath(PChar(GetEnvironmentVariable('SystemRoot') + '\System32\notepad.exe'));
  AssertTrue(IDList <> nil);
  try Saved := PIDL_ToString(IDList); finally PIDL_Free(IDList); end;
  CheckPIDL(Saved);
  AssertEquals('PIDL bytes must remain unchanged', Saved, FService.SerializedPIDL);
end;

procedure TLaunchServiceTests.FilesystemPIDLDisplayNameStaysAPath;
var IDList: PItemIDList; Path: string;
begin
  Path := GetEnvironmentVariable('SystemRoot') + '\System32\notepad.exe';
  IDList := PIDL_GetFromPath(PChar(Path));
  AssertTrue(IDList <> nil);
  try AssertTrue(SameFileName(Path, PIDL_GetDisplayName2(IDList)));
  finally PIDL_Free(IDList); end;
end;

procedure TLaunchServiceTests.DockAndStackFactoriesPreserveApplicationCommands;
const AppID = TestFamily + '!Main';
var Target: string; DockData, StackData: TShortcutDtoV1; Prefix: Integer;
begin
  for Prefix := 0 to 3 do
  begin
    case Prefix of
      0: Target := AppID;
      1: Target := 'shell:AppsFolder\' + AppID;
      2: Target := 'shell:::' + AppsGUID + '\' + AppID;
      3: Target := '::' + AppsGUID + '\' + AppID;
    end;
    DockData := ReadShortcutText(TShortcutItem.MakeFromFilename(Target));
    StackData := ReadShortcutText(TShortcutSubitem.MakeFromFilename(Target));
    AssertEquals(Target, DockData.Command);
    AssertEquals(Target, StackData.Command);
    AssertEquals('?', UTF8Encode(DockData.Caption));
    CheckApplication(DockData.Command, AppID);
    CheckApplication(StackData.Command, AppID);
  end;
end;

procedure TLaunchServiceTests.ExpandedPathsEndingAppKeepShellRouting;
begin
  CheckOrdinary('%pp%\Example!App');
  CheckOrdinary('%sysdir%\Example!App');
end;

procedure TLaunchServiceTests.ClosePreventsApplicationActivation;
begin
  FService.Reset;
  FService.Close;
  FService.Run(TestApp);
  AssertEquals(0, FService.Calls);
end;

initialization
  RegisterTest(TLaunchServiceTests);
end.
