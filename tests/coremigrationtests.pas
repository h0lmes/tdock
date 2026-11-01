unit coremigrationtests;

{$mode delphi}

interface

uses Windows, fpcunit, testregistry, dockstateu, dockpolicyu, applifecycleu, dockcommandu, declu, setsu, settingscoordinatoru, SysUtils, hintu, dockapplicationu, dockrendereru, docklayoutu, themeu, itemhostu, win32docku, DropTgtU;

type
  EConstructionFailure = class(Exception);
  TTrackedState = class(TDockState)
    destructor Destroy; override;
  end;
  TFailingApplication = class(TDockApplication)
  protected
    function CreateState: TDockState; override;
    function CreateLifecycle: TApplicationLifecycle; override;
  end;
  TFailingHint = class(THint)
    destructor Destroy; override;
  end;
  TTestRenderer = class(TDockRenderer)
  protected
    function DrawBackground(const Layout: TDockLayoutSnapshot; Theme: TDTheme;
      Alpha: Integer): Boolean; override;
  public
    Calls: Integer;
    FailNext: Boolean;
    LastDraggingFile: Boolean;
  end;
  TTestDropManager = class(TDropManager)
  public
    Runtime: TDockApplication;
    DepthDuringCallback: Integer;
    CloseWasAllowed: Boolean;
    constructor CreateForTests;
    function DragOver(Keys: DWORD; Point: Windows.TPoint; var Effect: DWORD): HResult; override;
  end;
  TCoreMigrationTests = class(TTestCase)
  private
    Calls: Integer;
    DeferredCloses: Integer;
    RuntimeForClose: TDockApplication;
    LastAction: TApplicationAction;
    LastRequest: TCommandRequest;
    procedure RecordDeferredClose;
    procedure CommitDeferredClose;
    procedure RecordCommand(Action: TApplicationAction; const Request: TCommandRequest);
  private
    Trace: string;
    OldZoom, NewZoom: Integer;
    procedure RecordZoomChange(const Change: TDockSettingChange);
    procedure BeforeSetting(const Change: TDockSettingChange);
    procedure ApplyingSetting(const Change: TDockSettingChange);
    procedure NotifySetting(const Change: TDockSettingChange);
    procedure AfterSetting(const Change: TDockSettingChange);
  published
    procedure PluginCallbackDefersShutdownUntilReturn;
    procedure NativeDropCallbackRetainsApplicationServices;
    procedure NativeAdapterInstallsFullWidthProcedure;
    procedure NativeAdapterRestoresFullWidthUserData;
    procedure FailedFrameRetriesIdenticalGeometry;
    procedure DropCompletionRepaintsIdenticalGeometry;
    procedure DragCancellationRepaintsIdenticalGeometry;
    procedure FailedDragCompletionRetriesIdenticalGeometry;
    procedure ConstructionFailurePreservesOriginalException;
    procedure CleanupContinuesAfterDestructorFailure;
    procedure ActiveOperationDefersClose;
    procedure SettingsSnapshotIncludesEveryField;
    procedure ModelUsesAuthoritativeSettings;
    procedure SettingsNormalizeBeforeNotification;
    procedure ItemSizeMaintainsZoomSize;
    procedure ZoomSizeEventKeepsPreviousValue;
    procedure TextSettingsRespectBufferLimits;
    procedure SettingsSaveKeepsSourcePath;
    procedure EmptyCommandLineIsIgnored;
    procedure QuotedCommandKeepsParameters;
    procedure MultipleCommandsKeepCallerAndDirectories;
    procedure InternalCommandUsesTypedRoute;
    procedure WindowLayoutCommandsUseTypedRoutes;
    procedure DisabledAutoHideFinishesMovement;
    procedure DraggingPreventsHide;
    procedure ExplicitHideClearsManualReveal;
    procedure CloakingInvalidatesTaskSnapshots;
    procedure QueryDoesNotDestroyServices;
    procedure CloseRunsOnce;
  end;

implementation

var DestroyedStates: Integer;

function TTestRenderer.DrawBackground(const Layout: TDockLayoutSnapshot; Theme: TDTheme;
  Alpha: Integer): Boolean;
begin
  Inc(Calls);
  Result := not FailNext;
  FailNext := False;
  if Result then LastDraggingFile := Layout.DraggingFile;
end;

destructor TTrackedState.Destroy;
begin Inc(DestroyedStates); inherited Destroy; end;
function TFailingApplication.CreateState: TDockState;
begin Result := TTrackedState.Create; end;
function TFailingApplication.CreateLifecycle: TApplicationLifecycle;
begin raise EConstructionFailure.Create('Expected construction failure'); end;
destructor TFailingHint.Destroy;
begin inherited Destroy; raise EConstructionFailure.Create('Expected cleanup failure'); end;

constructor TTestDropManager.CreateForTests;
begin end;
function TTestDropManager.DragOver(Keys: DWORD; Point: Windows.TPoint; var Effect: DWORD): HResult;
begin
  DepthDuringCallback := Runtime.Lifecycle.OperationDepth;
  Runtime.RequestClose;
  CloseWasAllowed := Runtime.BeginClose;
  Result := S_OK;
end;

procedure TCoreMigrationTests.NativeDropCallbackRetainsApplicationServices;
var App: TDockApplication; Manager: TTestDropManager; Target: TDropTarget;
  Services: TItemHostServices; Point: Windows.TPoint; Effect: DWORD;
begin
  App := TDockApplication.Create(0, nil, nil);
  Manager := TTestDropManager.CreateForTests;
  Target := TDropTarget.Create(9002, Manager);
  DeferredCloses := 0;
  try
    Manager.Runtime := App;
    App.OnDeferredClose := RecordDeferredClose;
    Services := Default(TItemHostServices);
    Services.OnEnter := App.EnterOperation;
    Services.OnLeave := App.LeaveOperation;
    BindItemHost(9002, Services);
    Point.X := 0; Point.Y := 0; Effect := 0;
    AssertEquals(S_OK, Target.DragOver(0, Point, Effect));
    AssertEquals('OLE callbacks must retain application services', 1, Manager.DepthDuringCallback);
    AssertFalse('Nested close must not destroy a native drop callback', Manager.CloseWasAllowed);
    AssertFalse(App.Busy);
    AssertEquals(1, DeferredCloses);
    AssertTrue(App.Lifecycle.ClosePending);
  finally UnbindItemHost(9002); Target.Free; Manager.Free; App.Free; end;
end;

function OriginalAdapterWindowProc(Window: HWND; Message: UINT;
  WParam: WPARAM; LParam: LPARAM): LRESULT; stdcall;
begin
  if Message = WM_APP + 7 then Exit(11);
  Result := Windows.DefWindowProc(Window, Message, WParam, LParam);
end;
function ReplacementAdapterWindowProc(Window: HWND; Message: UINT;
  WParam: WPARAM; LParam: LPARAM): LRESULT; stdcall;
begin
  if Message = WM_APP + 7 then Exit(29);
  Result := Windows.DefWindowProc(Window, Message, WParam, LParam);
end;
function CreateAdapterTestWindow(out ClassName: string): HWND;
var WindowClass: Windows.TWndClass; Id: TGUID;
begin
  CreateGUID(Id);
  ClassName := 'DockAdapterTest' + GUIDToString(Id);
  WindowClass := Default(Windows.TWndClass);
  WindowClass.lpfnWndProc := @OriginalAdapterWindowProc;
  WindowClass.hInstance := HInstance;
  WindowClass.lpszClassName := PChar(ClassName);
  if Windows.RegisterClass(WindowClass) = 0 then RaiseLastOSError;
  Result := Windows.CreateWindowEx(0, PChar(ClassName), nil, WS_POPUP,
    -10000, -10000, 1, 1, 0, 0, HInstance, nil);
  if Result = 0 then RaiseLastOSError;
end;
procedure TCoreMigrationTests.NativeAdapterInstallsFullWidthProcedure;
var Window: HWND; ClassName: string; Adapter: TDockWindowAdapter;
begin
  Window := CreateAdapterTestWindow(ClassName);
  Adapter := TDockWindowAdapter.Create(Window);
  try
    AssertEquals(11, Windows.SendMessage(Window, WM_APP + 7, 0, 0));
    Adapter.Install(Self, @ReplacementAdapterWindowProc);
    AssertEquals('The native callback must retain its complete address',
      29, Windows.SendMessage(Window, WM_APP + 7, 0, 0));
    Adapter.Stop;
    AssertEquals(11, Windows.SendMessage(Window, WM_APP + 7, 0, 0));
  finally
    Adapter.Free;
    Windows.DestroyWindow(Window);
    Windows.UnregisterClass(PChar(ClassName), HInstance);
  end;
end;
procedure TCoreMigrationTests.NativeAdapterRestoresFullWidthUserData;
const PreviousData = QWord($1234567812345678);
var Window: HWND; ClassName: string; Adapter: TDockWindowAdapter;
begin
  Window := CreateAdapterTestWindow(ClassName);
  Adapter := TDockWindowAdapter.Create(Window);
  try
    Windows.SetWindowLongPtr(Window, GWL_USERDATA, PtrInt(PreviousData));
    Adapter.Install(Self, @ReplacementAdapterWindowProc);
    Adapter.Stop;
    AssertEquals('Native state must retain all pointer bits', Int64(PreviousData),
      Int64(Windows.GetWindowLongPtr(Window, GWL_USERDATA)));
  finally
    Adapter.Free;
    Windows.DestroyWindow(Window);
    Windows.UnregisterClass(PChar(ClassName), HInstance);
  end;
end;

procedure TCoreMigrationTests.DisabledAutoHideFinishesMovement;
var State: TDockState; Input: TDockRevealInput;
begin
  State := TDockState.Create;
  try
    State.AutoHide := True;
    State.RequestHide(100, 2, False, 1000);
    AssertTrue(State.Advance(1050));
    AssertTrue('Hide movement must start before auto-hide changes', State.Offset > 0);
    AssertTrue('Hide movement must still be active', State.NeedsFrames);
    State.AutoHide := False;
    Input := Default(TDockRevealInput);
    Input.Shown := True;
    Input.AutoHide := State.AutoHide;
    Input.Thickness := 100;
    Input.VisiblePixels := 2;
    State.Reconcile(Input, 1050);
    AssertTrue('Show movement must finish after disabling auto-hide', State.Advance(1500));
    AssertEquals(0, State.Offset);
    AssertEquals(0, State.Target);
  finally State.Free; end;
end;

procedure TCoreMigrationTests.DraggingPreventsHide;
var State: TDockState;
begin
  State := TDockState.Create;
  try
    State.AutoHide := True;
    State.RequestHide(100, 2, True);
    AssertEquals(0, State.Target);
    State.RequestHide(10, 20, False);
    AssertEquals(0, State.Target);
  finally State.Free; end;
end;

procedure TCoreMigrationTests.ExplicitHideClearsManualReveal;
var State: TDockState;
begin
  State := TDockState.Create;
  try
    State.AutoHide := True;
    State.RequestShow;
    State.RequestHide(100, 15, False);
    AssertFalse(State.RevealSnapshot.ManualReveal);
  finally State.Free; end;
end;

procedure TCoreMigrationTests.CloakingInvalidatesTaskSnapshots;
begin
  AssertTrue(WindowEventChangesTasks($8017));
  AssertTrue(WindowEventChangesTasks($8018));
  AssertTrue(IsForegroundShellEvent($8004));
end;

procedure TCoreMigrationTests.QueryDoesNotDestroyServices;
var Life: TApplicationLifecycle;
begin
  Life := TApplicationLifecycle.Create;
  try
    Life.Started;
    AssertTrue(Life.QueryEndSession);
    AssertEquals(Ord(apRunning), Ord(Life.Phase));
    AssertTrue(Life.QueryEndSession);
    AssertEquals(Ord(apRunning), Ord(Life.Phase));
  finally Life.Free; end;
end;

procedure TCoreMigrationTests.CloseRunsOnce;
var Life: TApplicationLifecycle;
begin
  Life := TApplicationLifecycle.Create;
  try
    AssertTrue(Life.BeginClose);
    AssertFalse(Life.BeginClose);
    Life.EndClose;
    AssertFalse(Life.BeginClose);
  finally Life.Free; end;
end;

procedure TCoreMigrationTests.RecordCommand(Action: TApplicationAction; const Request: TCommandRequest);
begin
  Inc(Calls);
  LastAction := Action;
  LastRequest := Request;
end;

procedure TCoreMigrationTests.EmptyCommandLineIsIgnored;
var Controller: TDockCommandController;
begin
  Calls := 0;
  Controller := TDockCommandController.Create(RecordCommand, nil);
  try Controller.ExecuteCommandLine(''); AssertEquals(0, Calls);
  finally Controller.Free; end;
end;

procedure TCoreMigrationTests.QuotedCommandKeepsParameters;
var Controller: TDockCommandController;
begin
  Controller := TDockCommandController.Create(RecordCommand, nil);
  try
    Controller.ExecuteCommandLine('"C:\Program Files\app.exe" /arg one');
    AssertEquals(Ord(aaLaunch), Ord(LastAction));
    AssertEquals('C:\Program Files\app.exe', LastRequest.Command);
    AssertEquals(' /arg one', LastRequest.Parameters);
  finally Controller.Free; end;
end;

procedure TCoreMigrationTests.MultipleCommandsKeepCallerAndDirectories;
var Controller: TDockCommandController; Caller: HWND;
begin
  Calls := 0;
  Caller := HWND(QWord($1234567887654321));
  Controller := TDockCommandController.Create(RecordCommand, nil);
  try
    Controller.ExecuteMulti('a;b', 'first;second', 'c:\one;c:\two', SW_HIDE, Caller);
    AssertEquals(2, Calls);
    AssertEquals('b', LastRequest.Command);
    AssertEquals('second', LastRequest.Parameters);
    AssertEquals('c:\two', LastRequest.Directory);
    AssertEquals(Int64(Caller), Int64(LastRequest.Caller));
    AssertEquals(SW_HIDE, LastRequest.ShowCommand);
  finally Controller.Free; end;
end;

procedure TCoreMigrationTests.InternalCommandUsesTypedRoute;
var Controller: TDockCommandController;
begin
  Controller := TDockCommandController.Create(RecordCommand, nil);
  try
    Controller.Execute('/itemmgr.insert', 'data', '');
    AssertEquals(Ord(aaItemManager), Ord(LastAction));
    AssertEquals('insert', LastRequest.Command);
    Controller.Execute('/shutdown', 'force', '');
    AssertEquals(Ord(aaShutdown), Ord(LastAction));
  finally Controller.Free; end;
end;

procedure TCoreMigrationTests.BeforeSetting(const Change: TDockSettingChange);
begin Trace := Trace + 'B'; AssertEquals(999, Change.NewValue); end;
procedure TCoreMigrationTests.ApplyingSetting(const Change: TDockSettingChange);
begin Trace := Trace + 'A'; AssertEquals(128, Change.NewValue); end;
procedure TCoreMigrationTests.NotifySetting(const Change: TDockSettingChange);
begin Trace := Trace + 'N'; AssertEquals(128, Change.NewValue); end;
procedure TCoreMigrationTests.AfterSetting(const Change: TDockSettingChange);
begin Trace := Trace + 'Z'; AssertEquals(128, Change.NewValue); end;

procedure TCoreMigrationTests.SettingsNormalizeBeforeNotification;
var Store: TDSets; Coordinator: TSettingsCoordinator;
begin
  Store := TDSets.Create('', '', 0);
  Coordinator := TSettingsCoordinator.Create(Store);
  try
    Store.container.BigItemSize := 256;
    Trace := '';
    Coordinator.OnBeforeChange := BeforeSetting;
    Coordinator.OnApplying := ApplyingSetting;
    Coordinator.OnNotifyItems := NotifySetting;
    Coordinator.OnApplied := AfterSetting;
    Coordinator.Apply(gpItemSize, 999);
    AssertEquals('BANZ', Trace);
    AssertEquals(128, Store.container.ItemSize);
  finally Coordinator.Free; Store.Free; end;
end;

procedure TCoreMigrationTests.ItemSizeMaintainsZoomSize;
var Store: TDSets; Coordinator: TSettingsCoordinator;
begin
  Store := TDSets.Create('', '', 0);
  Coordinator := TSettingsCoordinator.Create(Store);
  try
    Store.container.ItemSize := 32;
    Store.container.BigItemSize := 32;
    Coordinator.Apply(gpItemSize, 64);
    AssertEquals(64, Store.container.ItemSize);
    AssertEquals(64, Store.container.BigItemSize);
  finally Coordinator.Free; Store.Free; end;
end;

procedure TCoreMigrationTests.RecordZoomChange(const Change: TDockSettingChange);
begin
  if Change.Key = gpBigItemSize then
  begin OldZoom := Change.OldValue; NewZoom := Change.NewValue; end;
end;

procedure TCoreMigrationTests.ZoomSizeEventKeepsPreviousValue;
var Store: TDSets; Coordinator: TSettingsCoordinator;
begin
  Store := TDSets.Create('', '', 0);
  Coordinator := TSettingsCoordinator.Create(Store);
  try
    Store.container.ItemSize := 32;
    Store.container.BigItemSize := 48;
    Coordinator.OnApplied := RecordZoomChange;
    OldZoom := 0; NewZoom := 0;
    Coordinator.Apply(gpItemSize, 64);
    AssertEquals('Secondary changes retain their previous value', 48, OldZoom);
    AssertEquals(64, NewZoom);
  finally Coordinator.Free; Store.Free; end;
end;

procedure TCoreMigrationTests.TextSettingsRespectBufferLimits;
var Store: TDSets; Coordinator: TSettingsCoordinator; Font: TDFontData;
begin
  Store := TDSets.Create('', '', 0);
  Coordinator := TSettingsCoordinator.Create(Store);
  try
    Coordinator.SetShell(StringOfChar('s', MAX_PATH * 2));
    Coordinator.SetTheme(StringOfChar('t', MAX_PATH * 2));
    AssertEquals(MAX_PATH, Length(StrPas(@Store.container.Shell[0])));
    AssertEquals(MAX_PATH, Length(StrPas(@Store.container.ThemeName[0])));
    AssertEquals(0, Ord(Store.container.Shell[MAX_PATH]));
    AssertEquals(0, Ord(Store.container.ThemeName[MAX_PATH]));
    Font := Default(TDFontData);
    StrPCopy(@Font.Name[0], 'Example');
    Font.Size := 21; Font.Bold := True;
    Coordinator.SetFont(Font);
    Font.Size := 99;
    AssertEquals(21, Store.container.Font.Size);
    AssertTrue(Store.container.Font.Bold);
    AssertEquals('Example', StrPas(@Store.container.Font.Name[0]));
  finally Coordinator.Free; Store.Free; end;
end;

procedure TCoreMigrationTests.SettingsSaveKeepsSourcePath;
var Store: TDSets; StageName, SourceName: string; Id: TGUID;
begin
  CreateGUID(Id);
  SourceName := ExtractFilePath(ParamStr(0)) + 'source-' + GUIDToString(Id) + '.ini';
  StageName := SourceName + '.tmpini';
  Store := TDSets.Create(SourceName, '', 0);
  try
    Store.SaveTo(StageName);
    AssertEquals(SourceName, Store.SetsPathFile);
    AssertTrue(FileExists(StageName));
    AssertFalse('Snapshot writing must preserve the source file', FileExists(SourceName));
  finally SysUtils.DeleteFile(StageName); Store.Free; end;
end;

procedure TCoreMigrationTests.ConstructionFailurePreservesOriginalException;
var App: TDockApplication; OriginalFailure: Boolean;
begin
  DestroyedStates := 0;
  OriginalFailure := False;
  try
    App := TFailingApplication.Create(0, nil, nil);
    App.Free;
  except on E: EConstructionFailure do OriginalFailure := True; end;
  AssertTrue('Construction must retain the original exception', OriginalFailure);
  AssertEquals('Already-created state must be freed', 1, DestroyedStates);
end;

procedure TCoreMigrationTests.CleanupContinuesAfterDestructorFailure;
var App: TDockApplication;
begin
  App := TDockApplication.Create(0, nil, nil);
  try
    App.Hint := TFailingHint.Create;
    AssertTrue(App.BeginClose);
    App.ReleaseServices;
    AssertTrue(App.Hint = nil);
    AssertEquals(Ord(apClosed), Ord(App.Lifecycle.Phase));
    App.ReleaseServices;
  finally App.Free; end;
end;

procedure TCoreMigrationTests.ActiveOperationDefersClose;
var Life: TApplicationLifecycle;
begin
  Life := TApplicationLifecycle.Create;
  try
    Life.EnterOperation;
    Life.RequestClose;
    AssertFalse('Callbacks must retain their services', Life.BeginClose);
    AssertFalse(Life.TakeCloseRequest);
    Life.LeaveOperation;
    AssertTrue(Life.TakeCloseRequest);
    AssertFalse(Life.TakeCloseRequest);
    AssertTrue(Life.BeginClose);
  finally Life.Free; end;
end;

procedure TCoreMigrationTests.SettingsSnapshotIncludesEveryField;
var Store: TDSets;
begin
  Store := TDSets.Create('', '', 0);
  try
    Store.container.Hello := True;
    Store.container.TaskSystemMenus := True;
    Store.container.Font.Size := 22;
    Store.StoreSetsContainer;
    Store.container.Hello := False;
    Store.container.TaskSystemMenus := False;
    Store.container.Font.Size := 44;
    Store.RestoreSetsContainer;
    AssertTrue(Store.container.Hello);
    AssertTrue(Store.container.TaskSystemMenus);
    AssertEquals(22, Store.container.Font.Size);
  finally Store.Free; end;
end;

procedure TCoreMigrationTests.ModelUsesAuthoritativeSettings;
var Store: TDSets; Model: TDockState;
begin
  Store := TDSets.Create('', '', 0);
  Model := TDockState.Create;
  try
    Model.BindSettings(@Store.container);
    Store.container.Site := bsRight;
    AssertEquals(Ord(bsRight), Ord(Model.Settings.Site));
    Store.container.AutoHide := True;
    AssertTrue(Model.AutoHide);
    Model.AutoHide := False;
    AssertFalse(Store.container.AutoHide);
    Model.SetMouseEffectLock(12, True);
    Model.SetMouseEffectLock(12, True);
    Model.SetMouseEffectLock(12, False);
    AssertTrue(Model.MouseEffectLocked);
    Model.SetMouseEffectLock(12, False);
    AssertFalse(Model.MouseEffectLocked);
  finally Model.Free; Store.Free; end;
end;

procedure TCoreMigrationTests.FailedFrameRetriesIdenticalGeometry;
var Renderer: TTestRenderer; Layout: TDockLayoutSnapshot;
begin
  Renderer := TTestRenderer.Create(0);
  try
    Layout := Default(TDockLayoutSnapshot);
    Layout.BaseWindowRect.X := 100;
    Layout.BaseWindowRect.Width := 200;
    Layout.BaseWindowRect.Height := 32;
    Renderer.FailNext := True;
    Renderer.Paint(Layout, nil, 255, 0, False);
    AssertEquals(1, Renderer.Calls);
    Renderer.Paint(Layout, nil, 255, 0, False);
    AssertEquals('Failed frames remain dirty', 2, Renderer.Calls);
    Renderer.Paint(Layout, nil, 255, 0, False);
    AssertEquals(2, Renderer.Calls);
    Renderer.Paint(Layout, nil, 255, 1, False);
    AssertEquals(3, Renderer.Calls);
  finally Renderer.Free; end;
end;

procedure TCoreMigrationTests.DropCompletionRepaintsIdenticalGeometry;
var Renderer: TTestRenderer; Layout: TDockLayoutSnapshot;
begin
  Renderer := TTestRenderer.Create(0);
  try
    Layout := Default(TDockLayoutSnapshot);
    Layout.BaseWindowRect.Width := 200;
    Layout.BaseWindowRect.Height := 32;
    Renderer.Paint(Layout, nil, 255, 0, False);
    Layout.DraggingFile := True;
    Renderer.Paint(Layout, nil, 255, 1, False);
    AssertTrue('The drag frame must show the drop background', Renderer.LastDraggingFile);
    Layout.DraggingFile := False;
    Renderer.Paint(Layout, nil, 255, 0, False);
    AssertEquals('Drop completion must repaint unchanged geometry', 3, Renderer.Calls);
    AssertFalse('The completed frame must clear the drop background', Renderer.LastDraggingFile);
    Renderer.Paint(Layout, nil, 255, 0, False);
    AssertEquals('An unchanged completed frame must remain cached', 3, Renderer.Calls);
  finally Renderer.Free; end;
end;

procedure TCoreMigrationTests.DragCancellationRepaintsIdenticalGeometry;
var Renderer: TTestRenderer; Layout: TDockLayoutSnapshot;
begin
  Renderer := TTestRenderer.Create(0);
  try
    Layout := Default(TDockLayoutSnapshot);
    Layout.BaseWindowRect.Width := 200;
    Layout.BaseWindowRect.Height := 32;
    Renderer.Paint(Layout, nil, 255, 0, False);
    Layout.DraggingFile := True;
    Renderer.Paint(Layout, nil, 255, 0, False);
    AssertEquals('Drag entry must repaint unchanged geometry', 2, Renderer.Calls);
    Layout.DraggingFile := False;
    Renderer.Paint(Layout, nil, 255, 0, False);
    AssertEquals('Drag cancellation must repaint unchanged geometry', 3, Renderer.Calls);
    AssertFalse('Cancellation must clear the drop background', Renderer.LastDraggingFile);
  finally Renderer.Free; end;
end;

procedure TCoreMigrationTests.FailedDragCompletionRetriesIdenticalGeometry;
var Renderer: TTestRenderer; Layout: TDockLayoutSnapshot;
begin
  Renderer := TTestRenderer.Create(0);
  try
    Layout := Default(TDockLayoutSnapshot);
    Layout.BaseWindowRect.Width := 200;
    Layout.BaseWindowRect.Height := 32;
    Layout.DraggingFile := True;
    Renderer.Paint(Layout, nil, 255, 0, False);
    Layout.DraggingFile := False;
    Renderer.FailNext := True;
    Renderer.Paint(Layout, nil, 255, 0, False);
    AssertEquals('The first cleanup frame must be attempted', 2, Renderer.Calls);
    AssertTrue('A failed frame must preserve the painted state', Renderer.LastDraggingFile);
    Renderer.Paint(Layout, nil, 255, 0, False);
    AssertEquals('The failed cleanup frame must retry', 3, Renderer.Calls);
    AssertFalse('The successful retry must clear the background', Renderer.LastDraggingFile);
  finally Renderer.Free; end;
end;

procedure TCoreMigrationTests.CommitDeferredClose;
begin
  AssertTrue(RuntimeForClose.BeginClose);
  RuntimeForClose.ReleaseServices;
end;

procedure TCoreMigrationTests.RecordDeferredClose;
begin Inc(DeferredCloses); end;

procedure TCoreMigrationTests.PluginCallbackDefersShutdownUntilReturn;
var App: TDockApplication; Services: TItemHostServices; Scope: TItemHostScope;
begin
  App := TDockApplication.Create(0, nil, nil);
  DeferredCloses := 0;
  try
    App.OnDeferredClose := RecordDeferredClose;
    Services := Default(TItemHostServices);
    Services.OnEnter := App.EnterOperation;
    Services.OnLeave := App.LeaveOperation;
    BindItemHost(9000, Services);
    Scope := BeginItemHostOperation(9000);
    try
      App.RequestClose;
      AssertTrue(App.Busy);
      AssertFalse(App.BeginClose);
      AssertEquals(0, DeferredCloses);
      AssertTrue(App.State <> nil);
    finally EndItemHostOperation(Scope); end;
    AssertFalse(App.Busy);
    AssertEquals(1, DeferredCloses);
    AssertTrue('Posted close remains pending until committed', App.Lifecycle.ClosePending);
    EndItemHostOperation(Scope);
    AssertEquals(1, DeferredCloses);
    RuntimeForClose := App;
    AssertTrue(DispatchDockCloseCommand(IDM_QUIT, CommitDeferredClose));
    AssertEquals(Ord(apClosed), Ord(App.Lifecycle.Phase));
    AssertFalse(App.Lifecycle.ClosePending);
    AssertFalse(DispatchDockCloseCommand(IDM_QUIT + 1, CommitDeferredClose));
  finally UnbindItemHost(9000); App.Free; end;
end;

procedure TCoreMigrationTests.WindowLayoutCommandsUseTypedRoutes;
var Controller: TDockCommandController; App: TDockApplication;
begin
  Controller := TDockCommandController.Create(RecordCommand, nil);
  try
    Controller.ExecuteCommandLine('/savewindows');
    AssertEquals(Ord(aaSaveWindows), Ord(LastAction));
    Controller.ExecuteCommandLine('/restorewindows');
    AssertEquals(Ord(aaRestoreWindows), Ord(LastAction));
    Controller.ExecuteCommandLine('/restore');
    AssertEquals('Settings restoration must retain its command', Ord(aaRestore), Ord(LastAction));
  finally Controller.Free; end;
  App := TDockApplication.Create(0, nil, nil);
  try
    AssertTrue(App.WindowLayout <> nil);
    App.ReleaseServices;
    AssertTrue(App.WindowLayout = nil);
  finally App.Free; end;
end;
initialization
  RegisterTest(TCoreMigrationTests);
end.

