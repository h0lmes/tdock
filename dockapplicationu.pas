unit dockapplicationu;

{$mode delphi}

interface

uses Windows, SysUtils, SyncObjs, declu, setsu, themeu, itemmgru, hintu,
  DropTgtU, trayu, dockstateu, applifecycleu, dockcommandu, settingscoordinatoru,
  dockrendereru, win32docku, win32commandu, launchserviceu, pluginhostu, itemsettingsu, settingssaveu,
  itemmodelu, windowlayoutu;

type
  TDeferredCloseEvent = procedure of object;
  TDockApplication = class
  private
    FWindow: HWND;
    FSettings: TDSets;
    FTheme: TDTheme;
    FItems: TItemManager;
    FDrop: TDropManager;
    FHint: THint;
    FTray: TTrayController;
    FPlugins: TPluginHost;
    FState: TDockState;
    FLifecycle: TApplicationLifecycle;
    FCommands: TDockCommandController;
    FSettingsCoordinator: TSettingsCoordinator;
    FRenderer: TDockRenderer;
    FNativeWindow: TDockWindowAdapter;
    FNativeCommands: TWin32CommandAdapter;
    FWindowLayout: TWindowLayoutService;
    FLaunch: TLaunchService;
    FSaveLock: TCriticalSection;
    FPersistence: TSettingsSaveCoordinator;
    FOnDeferredClose: TDeferredCloseEvent;
    FOnActivity: TDeferredCloseEvent;
    function GetBusy: Boolean;
    procedure ItemRemoved(Id: TItemId);
  protected
    function CreateState: TDockState; virtual;
    function CreateLifecycle: TApplicationLifecycle; virtual;
  public
    constructor Create(Window: HWND; ApplicationHandler: TApplicationCommandHandler;
      DockHandler: TDockCommandHandler);
    destructor Destroy; override;
    procedure Load(const SettingsFile: string; Repaint: TItemRepaintEvent;
      Report: TLaunchReport);
    procedure CreateDropManager;
    procedure CreateTray;
    procedure EnterOperation;
    procedure LeaveOperation;
    procedure RequestClose;
    function BeginClose: Boolean;
    property Busy: Boolean read GetBusy;
    property OnDeferredClose: TDeferredCloseEvent read FOnDeferredClose write FOnDeferredClose;
    property OnActivity: TDeferredCloseEvent read FOnActivity write FOnActivity;
    procedure ReleaseServices;
    procedure DispatchLaunchReports;
    property Settings: TDSets read FSettings;
    property Theme: TDTheme read FTheme;
    property Items: TItemManager read FItems;
    property Drop: TDropManager read FDrop;
    property Hint: THint read FHint write FHint;
    property Tray: TTrayController read FTray;
    property Plugins: TPluginHost read FPlugins;
    property State: TDockState read FState;
    property Lifecycle: TApplicationLifecycle read FLifecycle;
    property Commands: TDockCommandController read FCommands;
    property SettingsCoordinator: TSettingsCoordinator read FSettingsCoordinator;
    property Renderer: TDockRenderer read FRenderer;
    property NativeWindow: TDockWindowAdapter read FNativeWindow;
    property NativeCommands: TWin32CommandAdapter read FNativeCommands;
    property WindowLayout: TWindowLayoutService read FWindowLayout;
    property Launch: TLaunchService read FLaunch;
    property SaveLock: TCriticalSection read FSaveLock;
    property Persistence: TSettingsSaveCoordinator read FPersistence;
  end;

implementation

uses toolu, loggeru, itemhostu, dropimportu;

procedure RecordCleanupFailure(E: Exception);
begin
  try AddLog('Dock cleanup: ' + E.Message); except end;
end;

function TDockApplication.CreateState: TDockState;
begin
  Result := TDockState.Create;
end;

function TDockApplication.CreateLifecycle: TApplicationLifecycle;
begin
  Result := TApplicationLifecycle.Create;
end;

constructor TDockApplication.Create(Window: HWND; ApplicationHandler: TApplicationCommandHandler;
  DockHandler: TDockCommandHandler);
begin
  inherited Create;
  FWindow := Window;
  FState := CreateState;
  FLifecycle := CreateLifecycle;
  FCommands := TDockCommandController.Create(ApplicationHandler, DockHandler);
  FRenderer := TDockRenderer.Create(Window);
  FNativeWindow := TDockWindowAdapter.Create(Window);
  FNativeCommands := TWin32CommandAdapter.Create(Window);
  FWindowLayout := TWindowLayoutService.Create;
  FSaveLock := TCriticalSection.Create;
end;

procedure TDockApplication.Load(const SettingsFile: string; Repaint: TItemRepaintEvent;
  Report: TLaunchReport);
begin
  FSettings := TDSets.Create(SettingsFile, UnzipPath('%pp%'), FWindow);
  sets := FSettings;
  FSettings.Load;
  FState.BindSettings(@FSettings.container);
  FTheme := TDTheme.Create(PChar(@FSettings.container.ThemeName), FSettings.container.Site);
  themeu.theme := FTheme;
  if not FTheme.Load then raise Exception.Create('Cannot load dock theme');
  FItems := TItemManager.Create(FWindow, ItemSettingsFromContainer(FSettings.container), Repaint);
  FItems.OnItemRemoved := ItemRemoved;
  FSettingsCoordinator := TSettingsCoordinator.Create(FSettings);
  FPersistence := TSettingsSaveCoordinator.Create(FSettings.SaveTo, FItems.SaveTo);
  FLaunch := TLaunchService.Create(FSettings, Report, nil, FWindow);
  FPlugins := TPluginHost.Create;
  PluginHost := FPlugins;
  FPlugins.Bind(FItems);
end;

procedure TDockApplication.CreateDropManager;
begin
  if FDrop = nil then
  begin
    FDrop := TDropManager.Create(FWindow);
    if FSettings <> nil then
      FDrop.ImportStorage := UTF8Decode(ExtractFilePath(ExpandFileName(UnzipPath(FSettings.SetsPathFile)))) + 'ImportedFiles';
    CleanupIncompleteImports(FDrop.ImportStorage);
  end;
end;

procedure TDockApplication.ItemRemoved(Id: TItemId);
begin
  if FState = nil then exit;
  FState.ReleaseItemLocks(Id);
  if FItems <> nil then FItems.SetParam(gpLockMouseEffect, Ord(FState.MouseEffectLocked));
end;

procedure TDockApplication.CreateTray;
begin
  if FTray = nil then FTray := TTrayController.Create;
end;

function TDockApplication.GetBusy: Boolean;
begin
  Result := (FLifecycle <> nil) and (FLifecycle.OperationDepth > 0);
end;

procedure TDockApplication.EnterOperation;
begin
  if FLifecycle <> nil then FLifecycle.EnterOperation;
end;

procedure TDockApplication.LeaveOperation;
begin
  if FLifecycle = nil then Exit;
  FLifecycle.LeaveOperation;
  if FLifecycle.TakeCloseRequest and Assigned(FOnDeferredClose) then FOnDeferredClose;
  if (FLifecycle.OperationDepth = 0) and not FLifecycle.ClosePending and
    (FLifecycle.Phase = apRunning) and Assigned(FOnActivity) then
    try FOnActivity;
    except on E: Exception do AddLog('Dock activity: ' + E.Message); end;
end;

procedure TDockApplication.RequestClose;
begin
  if FLifecycle <> nil then FLifecycle.RequestClose;
end;

function TDockApplication.BeginClose: Boolean;
begin
  Result := FLifecycle.BeginClose;
  if not Result then Exit;
  if FNativeWindow <> nil then FNativeWindow.Stop;
  if FLaunch <> nil then FLaunch.Close;
end;

procedure TDockApplication.ReleaseServices;
begin
  if (FLifecycle <> nil) and (FLifecycle.Phase = apClosed) then Exit;
  if FLaunch <> nil then FLaunch.Close;
  if FNativeWindow <> nil then FNativeWindow.Stop;
  if FPlugins <> nil then FPlugins.Unbind;
  UnbindItemHost(FWindow);
  try FreeAndNil(FWindowLayout); except on E: Exception do RecordCleanupFailure(E); end;
  try FreeAndNil(FPersistence); except on E: Exception do RecordCleanupFailure(E); end;
  try FreeAndNil(FDrop); except on E: Exception do RecordCleanupFailure(E); end;
  try FreeAndNil(FItems); except on E: Exception do RecordCleanupFailure(E); end;
  try FreeAndNil(FHint); except on E: Exception do RecordCleanupFailure(E); end;
  if PluginHost = FPlugins then PluginHost := nil;
  try FreeAndNil(FPlugins); except on E: Exception do RecordCleanupFailure(E); end;
  try FreeAndNil(FLaunch); except on E: Exception do RecordCleanupFailure(E); end;
  try FreeAndNil(FSettingsCoordinator); except on E: Exception do RecordCleanupFailure(E); end;
  if themeu.theme = FTheme then themeu.theme := nil;
  try FreeAndNil(FTheme); except on E: Exception do RecordCleanupFailure(E); end;
  if FState <> nil then FState.BindSettings(nil);
  if sets = FSettings then sets := nil;
  try FreeAndNil(FSettings); except on E: Exception do RecordCleanupFailure(E); end;
  try FreeAndNil(FTray); except on E: Exception do RecordCleanupFailure(E); end;
  if FRenderer <> nil then
    try FRenderer.DestroyBlur; except on E: Exception do RecordCleanupFailure(E); end;
  if FLifecycle <> nil then FLifecycle.EndClose;
end;

procedure TDockApplication.DispatchLaunchReports;
begin
  if (FLifecycle = nil) or (FLifecycle.Phase in [apClosing, apClosed]) or FLifecycle.ClosePending then Exit;
  EnterOperation;
  try
    if FLaunch <> nil then FLaunch.DispatchPending;
  finally LeaveOperation; end;
end;

destructor TDockApplication.Destroy;
begin
  ReleaseServices;
  try FreeAndNil(FCommands); except on E: Exception do RecordCleanupFailure(E); end;
  try FreeAndNil(FNativeCommands); except on E: Exception do RecordCleanupFailure(E); end;
  try FreeAndNil(FNativeWindow); except on E: Exception do RecordCleanupFailure(E); end;
  try FreeAndNil(FRenderer); except on E: Exception do RecordCleanupFailure(E); end;
  try FreeAndNil(FState); except on E: Exception do RecordCleanupFailure(E); end;
  try FreeAndNil(FLifecycle); except on E: Exception do RecordCleanupFailure(E); end;
  try FreeAndNil(FSaveLock); except on E: Exception do RecordCleanupFailure(E); end;
  inherited Destroy;
end;

end.
