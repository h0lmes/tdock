unit shortcutactivationtests;

{$mode delphi}

interface

uses Windows, Messages, SysUtils, Classes, Controls, Forms, ActiveX, ComObj, ShlObj,
  fpcunit, testregistry, declu, scsubitemu, processhlp, themeu;

type
  TShortcutActivationTests = class(TTestCase)
  private
    Shortcut: TShortcutSubitem;
    AppWindow, PreviousForeground: HWND;
    PreviousHelper: TProcessHelper;
    PreviousTheme, FixtureTheme: TDTheme;
    FixtureDirectory, LinkPath: string;
    procedure Click(Shift: TShiftState = []);
    procedure CheckOriginalLaunch;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure RunningLinkActivatesWithoutLaunching;
    procedure RunningExecutableActivatesWithoutLaunching;
    procedure MissingWindowLaunchesOriginalLink;
    procedure CtrlClickLaunchesOriginalLink;
    procedure DisabledActivationLaunchesOriginalLink;
    procedure RunMenuLaunchesOriginalLink;
    procedure DisabledBadgesStillActivateRunningLink;
  end;

procedure DockExecute(Id: HWND; Command, Params, Directory: PChar; ShowCmd: Integer); stdcall;

implementation

var LaunchCount, LaunchShowCmd: Integer;
  LaunchCommand, LaunchParams, LaunchDirectory: string;

procedure DockExecute(Id: HWND; Command, Params, Directory: PChar; ShowCmd: Integer); stdcall;
begin
  Inc(LaunchCount);
  LaunchCommand := string(Command);
  LaunchParams := string(Params);
  LaunchDirectory := string(Directory);
  LaunchShowCmd := ShowCmd;
end;

procedure TShortcutActivationTests.SetUp;
var Id: TGUID; Link: IShellLinkW; Persist: IPersistFile; Params: TDItemCreateParams;
  Target: WideString;
begin
  OleCheck(OleInitialize(nil));
  PreviousForeground := GetForegroundWindow;
  PreviousHelper := ProcessHelper;
  PreviousTheme := theme;
  FixtureTheme := TDTheme(TDTheme.NewInstance);
  theme := FixtureTheme;
  ProcessHelper := TProcessHelper.Create;
  OleCheck(CreateGUID(Id));
  FixtureDirectory := ExtractFilePath(ParamStr(0)) + 'shortcut-' + GUIDToString(Id);
  AssertTrue(CreateDir(FixtureDirectory));
  LinkPath := FixtureDirectory + '\Running program.lnk';
  Link := CreateComObject(CLSID_ShellLink) as IShellLinkW;
  Target := ParamStr(0);
  OleCheck(Link.SetPath(PWideChar(Target)));
  OleCheck(Link.SetArguments('--from-shortcut'));
  OleCheck(Link.SetWorkingDirectory(PWideChar(WideString(FixtureDirectory))));
  Persist := Link as IPersistFile;
  OleCheck(Persist.Save(PWideChar(WideString(LinkPath)), True));

  AppWindow := CreateWindowExW(WS_EX_APPWINDOW or WS_EX_TOOLWINDOW,
    'STATIC', 'Shortcut activation fixture', WS_OVERLAPPEDWINDOW,
    -20000, -20000, 100, 100, 0, 0, HInstance, nil);
  AssertTrue(AppWindow <> 0);
  ShowWindow(AppWindow, SW_SHOWMINNOACTIVE);
  ProcessHelper.EnumProc;
  ProcessHelper.EnumAppWindows;
  AssertEquals('The target must have one real process window', 1,
    ProcessHelper.GetProcessWindowsCount(ParamStr(0)));

  Params := Default(TDItemCreateParams);
  Params.ItemSize := 48;
  Params.ActivateRunning := True;
  StrPLCopy(@Params.Font.Name[0], 'Segoe UI', High(Params.Font.Name));
  Shortcut := TShortcutSubitem.Create(0, Params);
  Shortcut.FromString(TShortcutSubitem.Make('Running shortcut', LinkPath,
    '--item-argument', FixtureDirectory, '', SW_SHOWMINNOACTIVE));
  Shortcut.cmd(icUpdateRunning, 0);
  AssertEquals('Shortcut resolution must find the running target', 1, Shortcut.WindowCount);
  LaunchCount := 0;
  LaunchCommand := '';
  LaunchParams := '';
  LaunchDirectory := '';
  LaunchShowCmd := 0;
end;

procedure TShortcutActivationTests.TearDown;
begin
  Shortcut.Free;
  if AppWindow <> 0 then DestroyWindow(AppWindow);
  ProcessHelper.Free;
  ProcessHelper := PreviousHelper;
  theme := PreviousTheme;
  FixtureTheme.Free;
  DeleteFile(LinkPath);
  RemoveDir(FixtureDirectory);
  if IsWindow(PreviousForeground) then Windows.SetForegroundWindow(PreviousForeground);
  OleUninitialize;
end;

procedure TShortcutActivationTests.Click(Shift: TShiftState);
begin
  Shortcut.MouseDown(mbLeft, Shift, 0, 0);
  AssertTrue(Shortcut.MouseUp(mbLeft, Shift, 0, 0));
  Application.ProcessMessages;
end;

procedure TShortcutActivationTests.CheckOriginalLaunch;
begin
  AssertEquals('The item must issue exactly one launch', 1, LaunchCount);
  AssertEquals('Launch must preserve the original shortcut', LinkPath, LaunchCommand);
  AssertEquals('--item-argument', LaunchParams);
  AssertEquals(FixtureDirectory, LaunchDirectory);
  AssertEquals(SW_SHOWMINNOACTIVE, LaunchShowCmd);
end;

procedure TShortcutActivationTests.RunningLinkActivatesWithoutLaunching;
begin
  Click;
  AssertEquals('A running shortcut target must not start again', 0, LaunchCount);
  AssertFalse('Activation must restore the existing window', IsIconic(AppWindow));
end;

procedure TShortcutActivationTests.RunningExecutableActivatesWithoutLaunching;
begin
  Shortcut.Command := ParamStr(0);
  Shortcut.Update;
  Click;
  AssertEquals(0, LaunchCount);
  AssertFalse(IsIconic(AppWindow));
end;

procedure TShortcutActivationTests.MissingWindowLaunchesOriginalLink;
begin
  DestroyWindow(AppWindow);
  AppWindow := 0;
  Click;
  CheckOriginalLaunch;
end;

procedure TShortcutActivationTests.CtrlClickLaunchesOriginalLink;
begin
  Click([ssCtrl]);
  CheckOriginalLaunch;
end;

procedure TShortcutActivationTests.DisabledActivationLaunchesOriginalLink;
begin
  Shortcut.cmd(gpActivateRunning, 0);
  Click;
  CheckOriginalLaunch;
end;

procedure TShortcutActivationTests.RunMenuLaunchesOriginalLink;
var Result: LRESULT;
begin
  Shortcut.WMCommand($f006, 0, Result);
  CheckOriginalLaunch;
end;

procedure TShortcutActivationTests.DisabledBadgesStillActivateRunningLink;
begin
  Shortcut.cmd(gpShowRunningIndicator, 0);
  AssertFalse(Shortcut.Running);
  Click;
  AssertEquals(0, LaunchCount);
  AssertFalse(IsIconic(AppWindow));
end;

initialization
  RegisterTest(TShortcutActivationTests);
end.
