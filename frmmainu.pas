unit frmmainu;

{$undef EXT_DEBUG}

interface
uses
  jwaWindows, Windows, Messages, SysUtils, Classes, Controls, LCLType, Forms,
  Menus, Dialogs, ExtCtrls, ShellAPI, ComObj, Math, Syncobjs, MMSystem, LMessages,
  declu, GDIPAPI, gfx, dwm_unit, hintu, notifieru, itemmgru,
  DropTgtU, setsu, trayu, shelltraywndu, aeropeeku, loggeru,
  dockapplicationu, dockstateu, applifecycleu, dockcommandu, settingscoordinatoru,
  dockrendereru, win32docku, win32inputu, docklayoutu, pluginhostu, itemhostu,
  docktimingu, dockpolicyu, win32hotkeyu, windowlayoutu;

type
  { Tfrmmain }

  Tfrmmain = class(TForm)
    trayicon: TTrayIcon;
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure FormMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: integer);
    procedure FormKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure trayiconMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
  private
    FApp: TDockApplication;
    FState: TDockState;
    FCommands: TDockCommandController;
    FRenderer: TDockRenderer;
    FSettingsCoordinator: TSettingsCoordinator;
    function GetProgramIsClosing: Boolean;
    function GetItemManager: TItemManager;
    function GetDropManager: TDropManager;
    function GetHint: THint;
    function GetTray: TTrayController;
    function GetMonitorIndex: Integer;
    procedure BindPluginHost;
    procedure PostDeferredClose;
    procedure RepaintDock(ForceDraw: Boolean);
    function HandleDockCommand(const Request: TDockCommandRequest): Boolean;
    procedure HandleApplicationCommand(Action: TApplicationAction; const Request: TCommandRequest);
    procedure BeforeSetting(const Change: TDockSettingChange);
    procedure ApplyingSetting(const Change: TDockSettingChange);
    procedure NotifyItemSetting(const Change: TDockSettingChange);
    procedure AfterSetting(const Change: TDockSettingChange);
    function PluginVisible: Boolean;
    function PluginSite: TBaseSite;
    procedure SetPluginSite(Site: TBaseSite);
    function PluginCenterOffset: Integer;
    procedure SetPluginCenterOffset(Value: Integer);
    procedure ExecutePlugin(Id: HWND; const Exename, Params, Dir: string; ShowCmd: Integer);
    procedure ExcludePluginFromPeek(Id: HWND);
    procedure PluginError(Where: string; E: Exception);
    property FProgramIsClosing: Boolean read GetProgramIsClosing;
    property FMonitor: Integer read GetMonitorIndex;
  private
    FSessionEndCommitted: Boolean;
    FAllowCloseProgram: boolean;
    crsection: TCriticalSection;
    FHideKeysPressed: boolean;
    FConsoleKeysPressed: boolean;
    FLastMouseHookPoint: Windows.TPoint;
    FMouseOver: boolean;
    FMouseOverEdge: boolean;
    FInitDone: boolean;
    FHotkeys: TDockHotkeys;
    FSettingsOpen, FScheduling, FFrameArmed, FRollArmed: Boolean;
    FTaskArmed, FObservationArmed, FRaiseArmed, FDragArmed: Boolean;
    FRollDue: QWord;
    FRaiseDeadline, FTaskDeadline, FObservationDeadline, FDragDeadline: TDeadline;
    procedure RefreshScheduling;
    procedure ReconcileRevealState;
    procedure ApplyEffectiveVisibility;
    procedure ObserveFullscreen;
    procedure ScheduleTaskRefresh;
    procedure ObserveForeground;
  private
    //FHook: THandle;
    FMenu: THandle;
    FMenuCreate: THandle;
    function  CloseQueryI: integer;
    procedure CreateBlurWindow;
    procedure DestroyBlurWindow;
    procedure DoGlobalHotkeys;
    procedure FlashTaskWindow(hwnd: HWND);
    function IsHotkeyPressed(hotkey: integer): boolean;
    procedure SaveSets;
    procedure RegisterRawInput;
    procedure NativeWndProc(var message: TMessage);
    procedure AppException(Sender: TObject; e: Exception);
    procedure AppDeactivate(Sender: TObject);
    procedure UpdateBlurWindow;
    procedure WMCopyData(var Message: TMessage);
    procedure WMTimer(var msg: TMessage);
    procedure WMUser(var msg: TMessage);
    procedure WMCommand(var msg: TMessage);
    procedure WMDisplayChange(var Message: TMessage);
    procedure WMSettingChange(var Message: TMessage);
    procedure WMCompositionChanged(var Message: TMessage);
    procedure WMDPIChanged(var Message: TMessage);
    procedure WHRawMouse(mouse: TRawMouseData);
    procedure WHButtonDown(button: integer);
    procedure WHMouseMove(LParam: LParam);
    procedure OnMouseEnter;
    procedure OnMouseLeave;
    procedure DoMenu;
    procedure OnTimerMain;
    procedure OnTimerSlow;
    procedure OnTimerFSA;
    procedure OnTimerRoll;
    procedure OnTimerForeground;
    procedure OnTimerDragLeave;
    procedure UpdateRunning;
    function  IsHiddenDown: boolean;
    procedure DoRollDown;
    procedure DoRollUp;
    procedure OnTimerDoRollUpDown;
    procedure SetForeground;
    procedure SetNotForeground;
    procedure MaintainNotForeground;
    procedure BasePaint(flags: integer);
  public
    property ItemMgr: TItemManager read GetItemManager;
    property DropMgr: TDropManager read GetDropManager;
    property AHint: THint read GetHint;
    property Tray: TTrayController read GetTray;
    property ClosingRequested: Boolean read GetProgramIsClosing;
    function BeginUserOperation: Boolean;
    procedure EndUserOperation;
    destructor Destroy; override;
    procedure Init(SetsFilename: string);
    procedure ExecAutorun;
    procedure CloseProgram;
    procedure ApplyParams;
    procedure SettingsOpenChanged(Value: Boolean);
    function HotkeyBinding(Index: Integer): TDockHotkeyBinding;
    procedure Restore(backupFile: string);
    procedure err(where: WideString; e: Exception);
    procedure notify(message: WideString; silent: boolean = False);
    procedure alert(message: WideString);
    procedure ActivateHint(hwnd: THandle; ACaption: WideString; x, y: integer);
    procedure DeactivateHint(hwnd: THandle);
    procedure SetTheme(ATheme: string);
    procedure SetShell(const Value: string);
    function  BaseCmd(id: TDParam; param: PtrInt): PtrInt;
    procedure SetParam(id: TDParam; Value: integer);
    function  GetHMenu(ParentMenu: THandle): THandle;
    function  ContextMenu(pt: Windows.TPoint): boolean;
    procedure SetFont(var Value: TDFontData);
    procedure LockMouseEffect(hWnd: HWND; lock: boolean);
    function  IsMouseEffectLocked: boolean;
    function  GetMonitorWorkareaRect(pMonitor: PInteger = nil): Windows.TRect;
    function  GetMonitorBoundsRect(pMonitor: PInteger = nil): Windows.TRect;
    procedure MoveDock(iDirection: integer);
    procedure OnDragEnter(list: TStrings; hWnd: THandle);
    procedure OnDragOver;
    procedure OnDragLeave;
    procedure OnDragReset;
    procedure OnDrop(files: TDropImportBatch; hWnd: THandle);
    procedure DropFiles(files: TStrings);
    procedure AddFile; overload;
    procedure AddFile(Filename: string); overload;
    procedure NewDock;
    procedure RemoveDock;
    procedure OpenWith(filename: string);
    function  FullScreenAppActive: boolean; virtual;
    function  ListFullScreenApps: string;
    procedure ThemesMenu;
    procedure SetTaskSpot(wnd: THandle);
    procedure ListTasksAndModules;
    procedure execute_multi(cmd: string; params: string = ''; dir: string = ''; showcmd: integer = sw_shownormal; hwnd: HWND = 0);
    procedure execute_cmdline(cmd: string; showcmd: integer = sw_shownormal);
    procedure execute(cmd: string; params: string = ''; dir: string = ''; showcmd: integer = sw_shownormal; hwndCaller: HWND = 0);
    procedure Run(exename: string; params: string = ''; dir: string = ''; showcmd: integer = sw_shownormal);
  end;

var frmmain: Tfrmmain;

implementation
uses themeu, toolu, scitemu, PIDL, frmsetsu, frmcmdu, frmitemoptu,
  frmStackPropu, frmAddCommandU, frmthemeeditoru, processhlp, frmhellou,
  frmtipu, multidocku, frmrestoreu, mixeru, runthreadu, itemviewu, itemmodelu;
{$R *.lfm}
{$R Resource\res.res}
//------------------------------------------------------------------------------
function MainWindowProc(wnd: HWND; message: uint; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall;
var
  inst: Tfrmmain;
  msg: TMessage;
  Scoped: Boolean;
begin
  inst := Tfrmmain(GetWindowLongPtr(wnd, GWL_USERDATA));
  if assigned(inst) then
  begin
    msg.msg := message;
    msg.wParam := wParam;
    msg.lParam := lParam;
    Scoped := not (message in [WM_CLOSE, WM_QUERYENDSESSION, WM_ENDSESSION]) and
      not ((message = WM_COMMAND) and IsDockCloseCommand(wParam));
    if Scoped then inst.FApp.EnterOperation;
    try
      try
        inst.NativeWndProc(msg);
        Result := msg.Result;
      except
        on E: Exception do
        begin
          AddLog('MainWindowProc: ' + E.Message);
          Result := DefWindowProc(wnd, message, wParam, lParam);
        end;
      end;
    finally
      if Scoped then inst.FApp.LeaveOperation;
    end;
  end
  else
    result := DefWindowProc(wnd, message, wParam, lParam);
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.Init(SetsFilename: string);
begin
  try
    FApp := TDockApplication.Create(Handle, HandleApplicationCommand, HandleDockCommand);
    FState := FApp.State;
    FCommands := FApp.Commands;
    FRenderer := FApp.Renderer;
    crsection := FApp.SaveLock;
    FApp.OnDeferredClose := PostDeferredClose;
    FApp.OnActivity := RefreshScheduling;
    FHotkeys := TDockHotkeys.Create(Handle);
    FApp.EnterOperation;
    try
    FSessionEndCommitted := False;
    FAllowCloseProgram := false;
    FInitDone := false;
    Application.OnException := AppException;
    Application.OnDeactivate := AppDeactivate;
    trayicon.Icon := application.Icon;
    FMouseOver := false;
    FMouseOverEdge := false;

    FApp.NativeWindow.Install(Self, @MainWindowProc);
    dwm.ExcludeFromPeek(Handle);
    FApp.Load(SetsFilename, RepaintDock, notify);
    FSettingsCoordinator := FApp.SettingsCoordinator;
    FSettingsCoordinator.OnBeforeChange := BeforeSetting;
    FSettingsCoordinator.OnApplying := ApplyingSetting;
    FSettingsCoordinator.OnNotifyItems := NotifyItemSetting;
    FSettingsCoordinator.OnApplied := AfterSetting;
    BindPluginHost;
    if sets.container.BlurEnabled then CreateBlurWindow;

    SetParam(gpSite, integer(sets.container.site));
    SetParam(gpCenterOffsetPercent, sets.container.CenterOffsetPercent);
    SetParam(gpEdgeOffset, sets.container.EdgeOffset);
    SetParam(gpAutoHide, integer(sets.container.AutoHide));
    SetParam(gpAutoHidePixels, integer(sets.container.AutoHidePixels));
    SetParam(gpHideSystemTaskbar, integer(sets.container.HideSystemTaskbar));
    SetParam(gpReserveScreenEdge, sets.GetParam(gpReserveScreenEdge));
    SetParam(gpOccupyFullMonitor, integer(sets.container.OccupyFullMonitor));
    SetParam(gpBlurEnabled, sets.GetParam(gpBlurEnabled));
    BaseCmd(tcThemeChanged, 0);
    {$ifdef EXT_DEBUG} AddLog('BaseCmd(tcThemeChanged)'); {$endif}

    // load items //
    try
      ItemMgr.Load(UnzipPath(sets.SetsPathFile));
      {$ifdef EXT_DEBUG} AddLog('ItemMgr.Load'); {$endif}
      ItemMgr.Enable(true);
      {$ifdef EXT_DEBUG} AddLog('ItemMgr.Enable'); {$endif}
      if not sets.Backup then
      begin
        AddLog('Init.BackupFailed');
        messageboxw(handle, pwchar(UTF8Decode(XErrorSetsBackupFailed)), PROGRAM_NAME, MB_ICONERROR);
      end;
      {$ifdef EXT_DEBUG} AddLog('sets.Backup'); {$endif}
    except
      on e: Exception do
      begin
        SaveSets;
        AddLog('Init.LoadItems failed' + LineEnding + e.message);
        messageboxw(handle, pwchar(UTF8Decode(XErrorSetsCorrupted + ' ' + XMsgRunRestore)), PROGRAM_NAME, MB_ICONEXCLAMATION);
        TfrmRestore.Open;
      end;
    end;

    // Timers //
    SetTimer(handle, ID_TIMER_SLOW, 1000, nil);
    SetTimer(handle, ID_TIMER_FSA, 5000, nil);
    {$ifdef EXT_DEBUG} AddLog('Timers'); {$endif}

    // Tray and StartMenu controllers //
    FApp.CreateTray;
    {$ifdef EXT_DEBUG} AddLog('Tray'); {$endif}

    // show the dock //
    BaseCmd(tcSetVisible, 1);
    if sets.GetParam(gpStayOnTop) = 1 then SetParam(gpStayOnTop, 1); // apply StayOnTop
    {$ifdef EXT_DEBUG} AddLog('show dock'); {$endif}

    // RawInput (replacement for hook) //
    RegisterRawInput;
    {$ifdef EXT_DEBUG} AddLog('RegisterRawInput'); {$endif}

    // DropManager //
    FApp.CreateDropManager;
    DropMgr.OnDrop := OnDrop;
    DropMgr.OnError := notify;
    DropMgr.OnDragEnter := OnDragEnter;
    DropMgr.OnDragOver := OnDragOver;
    DropMgr.OnDragLeave := OnDragLeave;
    DropMgr.OnDragReset := OnDragReset;
    {$ifdef EXT_DEBUG} AddLog('TDropManager.Create'); {$endif}

    // apply theme. trigger full repaint //
    BaseCmd(tcThemeChanged, 0);
    {$ifdef EXT_DEBUG} AddLog('apply theme. trigger full repaint'); {$endif}

    // 'RollDown' on startup if set so //
    FState.RequestShow;
    DoRollDown;

    UpdateRunning;
    if sets.container.Hello then TfrmHello.Open;
    FInitDone := True;
    FApp.Lifecycle.Started;
    ObserveForeground;
    ObserveFullscreen;
    AddLog('InitDone');
    finally FApp.LeaveOperation; end;
  except
    on e: Exception do
    begin
      err('Base.Init', e);
      FAllowCloseProgram := True;
      CloseQueryI;
      raise;
    end;
  end;
end;
//------------------------------------------------------------------------------
function Tfrmmain.BeginUserOperation: Boolean;
begin
  Result := (FApp <> nil) and not FProgramIsClosing;
  if Result then FApp.EnterOperation;
end;

procedure Tfrmmain.EndUserOperation;
begin
  if FApp <> nil then FApp.LeaveOperation;
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.ExecAutorun;
var idx: Integer;
begin
  if (FApp = nil) or FProgramIsClosing or (sets = nil) then Exit;
  FApp.EnterOperation;
  try
    try
      if Assigned(sets.AutoRunList) then
      begin
        idx := 0;
        while not FProgramIsClosing and (idx < sets.AutoRunList.Count) do
        begin
          if sets.AutoRunList.Strings[idx] <> '' then
          begin
            if Copy(sets.AutoRunList.Strings[idx], 1, 1) = '#' then
              execute_cmdline(Copy(sets.AutoRunList.Strings[idx], 2, 1023), SW_MINIMIZE)
            else execute_cmdline(sets.AutoRunList.Strings[idx]);
          end;
          if not FProgramIsClosing then Application.ProcessMessages;
          Inc(idx);
        end;
      end;
    except on E: Exception do err('Base.ExecAutorun', E); end;
  finally FApp.LeaveOperation; end;
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.CreateBlurWindow;
begin FRenderer.CreateBlur; end;
//------------------------------------------------------------------------------
procedure Tfrmmain.DestroyBlurWindow;
begin if FRenderer <> nil then FRenderer.DestroyBlur; end;
//------------------------------------------------------------------------------
procedure Tfrmmain.CloseProgram;
begin
  FAllowCloseProgram := true;
  Close;
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  if CloseQueryI = 0 then CloseAction := caNone else CloseAction := caFree;
end;
//------------------------------------------------------------------------------
// check if program can close and, if yes, free all resources
function Tfrmmain.CloseQueryI: integer;
begin
  Result := 0;
  if FApp = nil then Exit(1);
  if FApp.Lifecycle.Phase = apClosed then Exit(1);
  if FApp.Lifecycle.Phase = apClosing then Exit;
  if not FAllowCloseProgram then Exit;
  if FApp.Busy then
  begin FApp.RequestClose; Exit; end;
  if not FApp.BeginClose then Exit;
  Application.OnDeactivate := nil;
  Application.OnException := nil;
  AddLog('CloseQueryI.begin');
  try
    if not FSessionEndCommitted then SaveSets;
    if Assigned(ShellTrayWndController) then
    begin
      ShellTrayWndController.UnreserveScreenEdge;
      ShellTrayWndController.HideTaskbar(False);
    end;
    TAeroPeekWindow.Cleanup;
    if Assigned(docks) and not docks.ThisDockRemovalScheduled then docks.CloseOtherDocks;
  except
    on E: Exception do AddLog('CloseQueryI: ' + E.Message);
  end;
  FApp.ReleaseServices;
  FSettingsCoordinator := nil;
  AddLog('CloseQueryI.done');
  Result := 1;
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.ApplyParams;
begin
  if FProgramIsClosing or (FSettingsCoordinator = nil) then Exit;
  FApp.EnterOperation;
  try
  FSettingsCoordinator.Reapply;
  ItemMgr.ApplySettings(ItemSettingsFromContainer(sets.container));
  ItemMgr.SetParam(gpLockMouseEffect, Ord(IsMouseEffectLocked));
  BaseCmd(tcThemeChanged, 0);
  UpdateRunning;
  finally FApp.LeaveOperation; end;
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.SaveSets;
begin
  if (FApp = nil) or (FApp.Persistence = nil) or (sets = nil) then Exit;
  if FApp.Persistence.Saving then Exit;
  try
    FApp.EnterOperation;
    try
      crsection.Acquire;
      try FApp.Persistence.Save(sets.SetsPathFile);
      finally crsection.Release; end;
    finally FApp.LeaveOperation; end;
    AddLog('SaveSets.done');
  except on E: Exception do err('Base.BaseSaveSettings', E); end;
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.Restore(backupFile: string);
begin
  if not BeginUserOperation then Exit;
  try
  notify('Restore: ' + backupFile);
  if sets.Restore(backupFile) then
  begin
    AddLog('Restore.Succeeded');
    messageboxw(handle, pwchar(UTF8Decode(XMsgSetsRestored + ' ' + XMsgRunAgain)), PROGRAM_NAME, MB_ICONEXCLAMATION);
    halt;
  end else begin
    AddLog('Restore.Failed');
    messageboxw(handle, pwchar(UTF8Decode(XErrorSetsRestoreFailed + ' ' + XErrorContactDeveloper)), PROGRAM_NAME, MB_ICONERROR);
    halt;
  end;
  finally EndUserOperation; end;
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.SetShell(const Value: string);
begin
  if Assigned(FSettingsCoordinator) and not FProgramIsClosing then FSettingsCoordinator.SetShell(Value);
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.SetTheme(ATheme: string);
begin
  if FProgramIsClosing or (FSettingsCoordinator = nil) then Exit;
  FSettingsCoordinator.SetTheme(ATheme);
  theme.setTheme(PChar(@sets.container.ThemeName[0]));
  BaseCmd(tcThemeChanged, 0);
end;
//------------------------------------------------------------------------------
function Tfrmmain.BaseCmd(id: TDParam; param: PtrInt): PtrInt;
begin
  Result := 0;
  if Assigned(FCommands) and not FProgramIsClosing then
  begin
    FApp.EnterOperation;
    try Result := FCommands.LegacyCommand(id, param);
    finally FApp.LeaveOperation; end;
  end;
end;
//------------------------------------------------------------------------------
// stores given parameter value and propagates it to subsequent objects       //
// e.g. ItemManager and all items                                             //
procedure Tfrmmain.SetParam(id: TDParam; value: integer);
begin
  if not FProgramIsClosing and Assigned(FSettingsCoordinator) then
  begin
    FApp.EnterOperation;
    try FSettingsCoordinator.Apply(id, value);
    finally FApp.LeaveOperation; end;
  end;
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.RegisterRawInput;
begin
  if not FApp.NativeWindow.RegisterMouse then notify('RegisterRawInput failed!');
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.NativeWndProc(var message: TMessage);
var
  Mouse: TRawMouseData;
  Observation: TDockWindowObservation;
  HotkeyAction: Integer;
begin
  message.result := 0;

  if message.msg = DOCK_OBSERVATION_MESSAGE then
  begin
    Observation := FApp.NativeWindow.TakeObservation;
    if FProgramIsClosing then Exit;
    if Observation.ForegroundChanged then ObserveForeground;
    if Observation.TasksChanged then ScheduleTaskRefresh;
    if Observation.WindowsChanged then
    begin
      if Assigned(Tray) then Tray.ObserveWindowChange(Observation.Window);
      if Assigned(ShellTrayWndController) then ShellTrayWndController.ObserveWindowChange(Observation.Window);
      if not FObservationDeadline.Active then
      begin
        FObservationDeadline.Schedule(GetTickCount64, 50);
        FObservationArmed := SetTimer(Handle, DOCK_OBSERVATION_TIMER, 50, nil) <> 0;
      end;
    end;
    Exit;
  end;
  if (FApp.NativeWindow.TaskbarMessage <> 0) and
    (message.msg = FApp.NativeWindow.TaskbarMessage) then
  begin
    if not FProgramIsClosing then
    begin
      if Assigned(Tray) then Tray.ObserveWindowChange(0);
      if Assigned(ShellTrayWndController) then ShellTrayWndController.ObserveWindowChange(0);
      OnTimerFSA;
      ScheduleTaskRefresh;
    end;
    Exit;
  end;

  if message.msg = WM_INPUT then
  begin
     if assigned(ItemMgr) then
       if not FProgramIsClosing and ItemMgr.Visible then
       begin
         if ReadRawMouse(message.lParam, Mouse) then WHRawMouse(Mouse);
       end;
     if message.wParam = RIM_INPUT then
       message.Result := DefWindowProc(Handle, WM_INPUT, message.wParam, message.lParam);
     exit;
  end;

  if message.msg = FApp.NativeWindow.ShellMessage then
  begin
    if FProgramIsClosing then Exit;
    if      message.wParam = HSHELL_FLASH           then FlashTaskWindow(message.lParam)
    else if message.wParam = HSHELL_WINDOWCREATED   then ScheduleTaskRefresh
    else if message.wParam = HSHELL_WINDOWDESTROYED then UpdateRunning
    else if message.wParam = HSHELL_MONITORCHANGED  then UpdateRunning
    else if IsForegroundShellEvent(message.wParam) then ObserveForeground
    else if message.wParam = HSHELL_REDRAW then ScheduleTaskRefresh;
    exit;
  end;

  case message.msg of
    WM_HOTKEY:
      if not FProgramIsClosing and Assigned(FHotkeys) and not Tfrmsets.IsVisible then
      begin
        HotkeyAction := FHotkeys.Resolve(message.wParam, message.lParam);
        if HotkeyAction = 0 then BaseCmd(tcToggleVisible, 0)
        else if HotkeyAction = 1 then execute_cmdline('/cmdna');
      end;
    WM_TIMER :                 WMTimer(message);
    WM_USER :                  WMUser(message);
    WM_COMMAND :               WMCommand(message);
    WM_QUERYENDSESSION :
      begin
        message.Result := Ord(FApp.Lifecycle.QueryEndSession);
      end;
    WM_ENDSESSION:
      if message.wParam <> 0 then
      begin
        if not FSessionEndCommitted then
        begin
          FSessionEndCommitted := True;
          FApp.RequestClose;
          if FInitDone then SaveSets;
        end;
        FAllowCloseProgram := True;
        CloseQueryI;
      end;
    WM_COPYDATA :              WMCopyData(message);
    WM_DISPLAYCHANGE :         WMDisplayChange(message);
    WM_SETTINGCHANGE :         WMSettingChange(message);
    WM_DWMCOMPOSITIONCHANGED : WMCompositionChanged(message);
    WM_DPICHANGED :            WMDPIChanged(message);
    else
      message.result := FApp.NativeWindow.CallPrevious(message);
  end;
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.WHRawMouse(mouse: TRawMouseData);
begin
  WHMouseMove(0);
  if mouse.ButtonFlags and RI_MOUSE_LEFT_BUTTON_DOWN <> 0 then WHButtonDown(1);
  if mouse.ButtonFlags and RI_MOUSE_RIGHT_BUTTON_DOWN <> 0 then WHButtonDown(2);
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.WHButtonDown(button: integer);
begin
  if not IsMouseEffectLocked and not FMouseOver and not sets.container.StayOnTop then SetNotForeground;
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.WHMouseMove(LParam: LParam);
var
  pt: Windows.Tpoint;
  monitorRect, itemMgrRect: Windows.TRect;
  oldMouseOver, oldMouseOverEdge: boolean;
begin
  if not IsMouseEffectLocked and assigned(ItemMgr) and not FProgramIsClosing then
    if ItemMgr.Visible then
    begin
      Windows.GetCursorPos(pt);
      if (pt.x <> FLastMouseHookPoint.x) or (pt.y <> FLastMouseHookPoint.y) or (LParam = $fffffff) then
      begin
        FLastMouseHookPoint.x := pt.x;
        FLastMouseHookPoint.y := pt.y;
        ItemMgr.WHMouseMove(pt, (LParam <> $fffffff) and not IsHiddenDown);

        // detect mouse enter/leave //
        oldMouseOver := FMouseOver;
        oldMouseOverEdge := FMouseOverEdge;
        monitorRect := ItemMgr.LayoutSnapshot.MonitorRect;
        itemMgrRect := ItemMgr.Rect;
        if sets.container.site = bsBottom then
          FMouseOver := (pt.y >= monitorRect.Bottom - 1) and (pt.x >= itemMgrRect.Left) and (pt.x <= itemMgrRect.Right)
        else if sets.container.site = bsTop then
          FMouseOver := (pt.y <= monitorRect.Top) and (pt.x >= itemMgrRect.Left) and (pt.x <= itemMgrRect.Right)
        else if sets.container.site = bsLeft then
          FMouseOver := (pt.x <= monitorRect.Left) and (pt.y >= itemMgrRect.Top) and (pt.y <= itemMgrRect.Bottom)
        else if sets.container.site = bsRight then
          FMouseOver := (pt.x >= monitorRect.Right - 1) and (pt.y >= itemMgrRect.Top) and (pt.y <= itemMgrRect.Bottom);
        FMouseOverEdge := FMouseOver;
        FMouseOver := FMouseOver or ItemMgr.CheckMouseOn or ItemMgr.InteractionSnapshot.DraggingItem;
        if (FMouseOver and not oldMouseOver) or (FMouseOverEdge and not oldMouseOverEdge) then OnMouseEnter;
        if not FMouseOver and oldMouseOver then OnMouseLeave;
      end;
    end;
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.OnMouseEnter;
begin
  ReconcileRevealState;
  // set foreground if 'activate' option selected //
  if IsWindowVisible(handle) and sets.container.ActivateOnMouse then
  begin
    if sets.container.ActivateOnMouseInterval = 0 then
      SetForeground
    else
    begin
      FRaiseDeadline.Schedule(GetTickCount64, sets.container.ActivateOnMouseInterval);
      FRaiseArmed := SetTimer(Handle, ID_TIMER_FOREGROUND,
        sets.container.ActivateOnMouseInterval, nil) <> 0;
    end;
  end;
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.OnMouseLeave;
begin
  FRaiseDeadline.Cancel;
  FRaiseArmed := False;
  KillTimer(Handle, ID_TIMER_FOREGROUND);
  // just to be sure
  ItemMgr.DragLeave;
  ReconcileRevealState;
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.FlashTaskWindow(hwnd: HWND);
begin
  if assigned(ItemMgr) then ItemMgr.AllItemCmd(icFlashTaskWindow, hwnd);
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.FormMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  // put blur exactly behind the dock
  SetWindowPos(FRenderer.BlurWindow, Handle, 0, 0, 0, 0, SWP_NO_FLAGS);
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.FormMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: integer);
begin
  if button = mbRight then DoMenu;
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.FormKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
begin
  if shift = [] then
  begin
    if key = 112 {F1} then execute_cmdline('/help');
    if key = 192 {tilda} then execute_cmdline('/cmd');
  end
  else if shift = [ssAlt] then
  begin
    if key = 37 then MoveDock(0);
    if key = 38 then MoveDock(1);
    if key = 39 then MoveDock(2);
    if key = 40 then MoveDock(3);
  end
  else if shift = [ssCtrl] then
  begin
    if key = 90 {Ctrl+Z} then execute_cmdline('/undelete');
  end;
end;
//------------------------------------------------------------------------------
// moves dock to another edge and/or monitor
procedure Tfrmmain.MoveDock(iDirection: integer);
var NewMonitor: Integer;
begin
  if iDirection = 0 then
  begin
    if sets.GetMonitorCount = 1 then SetParam(gpSite, 0)
    else
      if (sets.GetParam(gpMonitor) > 0) and (sets.GetParam(gpSite) = 0) then
      begin
        NewMonitor := sets.GetParam(gpMonitor) - 1;
        SetParam(gpSite, 2);
        SetParam(gpMonitor, NewMonitor);
      end else
        SetParam(gpSite, 0);
  end;

  if iDirection = 2 then
  begin
    if sets.GetMonitorCount = 1 then SetParam(gpSite, 2)
    else
      if (sets.GetParam(gpMonitor) < sets.GetMonitorCount - 1) and (sets.GetParam(gpSite) = 2) then
      begin
        NewMonitor := sets.GetParam(gpMonitor) + 1;
        SetParam(gpSite, 0);
        SetParam(gpMonitor, NewMonitor);
      end else
        SetParam(gpSite, 2);
  end;

  if iDirection = 1 then SetParam(gpSite, 1);
  if iDirection = 3 then SetParam(gpSite, 3);
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.WMUser(var msg: TMessage);
begin
  if (msg.wParam = wm_activate) and (msg.lParam = 0) then
  begin
    BaseCmd(tcSetVisible, 1);
    DoRollUp;
  end;
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.WMTimer(var msg: TMessage);
begin
  if FProgramIsClosing then Exit;
  try
    if msg.WParam = ID_TIMER then OnTimerMain
    else if msg.WParam = ID_TIMER_SLOW then OnTimerSlow
    else if msg.WParam = ID_TIMER_FSA then OnTimerFSA
    else if msg.WParam = ID_TIMER_ROLL then OnTimerRoll
    else if msg.WParam = ID_TIMER_DRAGLEAVE then OnTimerDragLeave
    else if msg.WParam = ID_TIMER_WINDOWCREATED then
    begin
      if FTaskDeadline.Consume(GetTickCount64) then
      begin
        KillTimer(handle, ID_TIMER_WINDOWCREATED);
        FTaskArmed := False;
        UpdateRunning;
      end;
    end
    else if msg.WParam = DOCK_OBSERVATION_TIMER then
    begin
      if FObservationDeadline.Consume(GetTickCount64) then
      begin
        KillTimer(Handle, DOCK_OBSERVATION_TIMER);
        FObservationArmed := False;
        ObserveFullscreen;
      end;
    end
    else if msg.WParam = ID_TIMER_FOREGROUND then OnTimerForeground;
  except
    on e: Exception do err('Base.WMTimer', e);
  end;
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.OnTimerMain;
begin
  if FProgramIsClosing then Exit;
  if IsWindowVisible(Handle) then
  begin
    try if assigned(ItemMgr) then ItemMgr.Timer;
    except on E: Exception do AddLog('Item frame: ' + E.Message); end;
    try OnTimerDoRollUpDown;
    except on E: Exception do AddLog('Roll frame: ' + E.Message); end;
  end;
  try if assigned(Tray) and Tray.NeedsPolling then Tray.Timer;
  except on E: Exception do AddLog('Tray frame: ' + E.Message); end;
  try if assigned(ShellTrayWndController) and ShellTrayWndController.NeedsPolling then ShellTrayWndController.Timer;
  except on E: Exception do AddLog('Shell frame: ' + E.Message); end;
  if not FProgramIsClosing and not Tfrmsets.IsVisible and Assigned(FHotkeys) and
    FHotkeys.NeedsFallback then DoGlobalHotkeys;
end;

procedure Tfrmmain.ScheduleTaskRefresh;
begin
  if FProgramIsClosing or FTaskDeadline.Active then Exit;
  FTaskDeadline.Schedule(GetTickCount64, 200);
  FTaskArmed := SetTimer(Handle, ID_TIMER_WINDOWCREATED, 200, nil) <> 0;
end;

procedure Tfrmmain.ObserveForeground;
var Window: HWND;
begin
  if FProgramIsClosing or not Assigned(ProcessHelper) then Exit;
  Window := Windows.GetForegroundWindow;
  ProcessHelper.ForegroundWindowHandle := Window;
  if Assigned(ItemMgr) then ItemMgr.ForegroundChanged(Window);
end;

procedure Tfrmmain.ObserveFullscreen;
begin
  if FProgramIsClosing or (FState = nil) or (sets = nil) or (ItemMgr = nil) then Exit;
  FState.ObserveFullscreen(FullScreenAppActive, sets.container.AutoHideOnFullScreenApp);
  ApplyEffectiveVisibility;
end;

procedure Tfrmmain.ApplyEffectiveVisibility;
var ShowDock, WasShown: Boolean;
begin
  if (FState = nil) or (ItemMgr = nil) then Exit;
  ShowDock := FState.Visible;
  WasShown := IsWindowVisible(Handle);
  if (ShowDock = WasShown) and (ItemMgr.Visible = ShowDock) then Exit;
  if not ShowDock then
  begin
    FRaiseDeadline.Cancel;
    FRaiseArmed := False;
    KillTimer(Handle, ID_TIMER_FOREGROUND);
    FMouseOver := False;
    FMouseOverEdge := False;
    if Assigned(AHint) then AHint.DeactivateImmediate;
    TAeroPeekWindow.Close;
    ItemMgr.Visible := False;
  end;
  Visible := ShowDock;
  UpdateBlurWindow;
  if ShowDock then
  begin
    ItemMgr.Visible := True;
    WHMouseMove($fffffff);
    if not WasShown then UpdateRunning;
  end;
  ReconcileRevealState;
end;

procedure Tfrmmain.ReconcileRevealState;
var Input: TDockRevealInput; PreviousOffset: Integer;
begin
  if not FInitDone or FProgramIsClosing or (FState = nil) or
    (ItemMgr = nil) or (sets = nil) then Exit;
  Input := Default(TDockRevealInput);
  Input.Shown := FState.Visible;
  Input.AutoHide := sets.container.AutoHide;
  Input.PointerOver := FMouseOver;
  Input.Dragging := ItemMgr.InteractionSnapshot.DraggingItem or
    ItemMgr.InteractionSnapshot.DraggingFile;
  Input.Locked := IsMouseEffectLocked;
  Input.SettingsOpen := FSettingsOpen;
  if sets.getBaseOrientation = boVertical then
    Input.Thickness := ItemMgr.LayoutSnapshot.BaseWindowRect.Width
  else Input.Thickness := ItemMgr.LayoutSnapshot.BaseWindowRect.Height;
  Input.VisiblePixels := sets.container.AutoHidePixels;
  Input.ShowDelay := Max(10, sets.container.AutoShowTime);
  Input.HideDelay := Max(10, sets.container.AutoHideTime);
  PreviousOffset := FState.Offset;
  FState.Reconcile(Input, GetTickCount64);
  if PreviousOffset <> FState.Offset then ItemMgr.WndOffset := FState.Offset;
end;

procedure Tfrmmain.RefreshScheduling;
var NeedFrame: Boolean; Reveal: TDockRevealState; Delay: QWord;
  procedure RetryDeadline(Id: UINT; const Deadline: TDeadline; var Armed: Boolean);
  var Remaining: QWord;
  begin
    if not Deadline.Active then Exit;
    if Armed then Exit;
    Remaining := Deadline.Remaining(GetTickCount64);
    if Remaining < 10 then Remaining := 10;
    if Remaining > High(Integer) then Remaining := High(Integer);
    Armed := SetTimer(Handle, Id, Cardinal(Remaining), nil) <> 0;
  end;
begin
  if FScheduling or not FInitDone or FProgramIsClosing or (FState = nil) or
    (ItemMgr = nil) or (sets = nil) then Exit;
  FScheduling := True;
  try
    if Assigned(FHotkeys) then
    begin
      FHotkeys.Configure(0, sets.container.GlobalHotkeyFlag_Hide,
        sets.container.GlobalHotkeyValue_Hide);
      FHotkeys.Configure(1, sets.container.GlobalHotkeyFlag_Console,
        sets.container.GlobalHotkeyValue_Console);
      FHotkeys.Suspend(FSettingsOpen);
    end;
    ReconcileRevealState;
    RetryDeadline(ID_TIMER_WINDOWCREATED, FTaskDeadline, FTaskArmed);
    RetryDeadline(DOCK_OBSERVATION_TIMER, FObservationDeadline, FObservationArmed);
    RetryDeadline(ID_TIMER_FOREGROUND, FRaiseDeadline, FRaiseArmed);
    RetryDeadline(ID_TIMER_DRAGLEAVE, FDragDeadline, FDragArmed);
    Reveal := FState.RevealSnapshot;
    if Reveal.Deadline.Active then
    begin
      if not FRollArmed or (FRollDue <> Reveal.Deadline.DueAt) then
      begin
        Delay := Reveal.Deadline.Remaining(GetTickCount64);
        if Delay < 10 then Delay := 10;
        if Delay > High(Integer) then Delay := High(Integer);
        FRollArmed := SetTimer(Handle, ID_TIMER_ROLL, Cardinal(Delay), nil) <> 0;
        FRollDue := Reveal.Deadline.DueAt;
      end;
    end
    else if FRollArmed then
    begin
      KillTimer(Handle, ID_TIMER_ROLL);
      FRollArmed := False;
    end;
    NeedFrame := (FState.Visible and (FState.NeedsFrames or ItemMgr.NeedsFrames)) or
      (Assigned(Tray) and Tray.NeedsPolling) or
      (Assigned(ShellTrayWndController) and ShellTrayWndController.NeedsPolling) or
      (Assigned(FHotkeys) and FHotkeys.NeedsFallback);
    if NeedFrame and not FFrameArmed then
    begin
      FFrameArmed := SetTimer(Handle, ID_TIMER, 10, nil) <> 0;
    end
    else if not NeedFrame and FFrameArmed then
    begin
      KillTimer(Handle, ID_TIMER);
      FFrameArmed := False;
    end;
  finally FScheduling := False; end;
end;

procedure Tfrmmain.SettingsOpenChanged(Value: Boolean);
begin
  FSettingsOpen := Value;
  FHideKeysPressed := False;
  FConsoleKeysPressed := False;
  if Assigned(FHotkeys) then FHotkeys.Suspend(Value);
  if not Value then WHMouseMove($fffffff);
  ReconcileRevealState;
  RefreshScheduling;
end;

function Tfrmmain.HotkeyBinding(Index: Integer): TDockHotkeyBinding;
begin
  Result := Default(TDockHotkeyBinding);
  if Assigned(FHotkeys) then Result := FHotkeys.Binding(Index);
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.OnTimerSlow;
begin
  if FApp <> nil then FApp.DispatchLaunchReports;
  if FProgramIsClosing then Exit;
  if assigned(ItemMgr) and assigned(sets) then
  try
    if IsWindowVisible(Handle) then
    begin
      WHMouseMove($fffffff);
      MaintainNotForeground;
    end;
    ItemMgr.CheckDeleted;
    if Assigned(Tray) then Tray.Timer;
    if Assigned(ShellTrayWndController) then ShellTrayWndController.Timer;
    if Tfrmsets.IsVisible <> FSettingsOpen then SettingsOpenChanged(Tfrmsets.IsVisible);

    // maintain visibility
    //if ItemMgr.visible and not IsWindowVisible(handle) then BaseCmd(tcSetVisible, 1);
    // maintain taskbar visibility
    if sets.container.HideSystemTaskbar then ShellTrayWndController.HideTaskbar(true);
  except
    on e: Exception do raise Exception.Create('Base.OnTimerSlow' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.OnTimerFSA;
begin
  try
    // keep the edge of the screen reserved if set so
    if sets.container.ReserveScreenEdge then
      ShellTrayWndController.ReserveScreenEdge(
        sets.container.Monitor,
        sets.container.Site,
        sets.container.ReserveScreenEdgePercent,
        ItemMgr.LayoutSnapshot.BaseWindowRect,
        sets.container.AutoHide);

    ObserveForeground;
    ObserveFullscreen;
  except
    on e: Exception do raise Exception.Create('Base.OnTimerFSA' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.OnTimerRoll;
begin
  if FState = nil then Exit;
  OnTimerDoRollUpDown;
  RefreshScheduling;
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.OnTimerForeground;
begin
  if not FRaiseDeadline.Consume(GetTickCount64) then Exit;
  KillTimer(Handle, ID_TIMER_FOREGROUND);
  FRaiseArmed := False;
  if not FProgramIsClosing and Visible and FMouseOver and
    not IsMouseEffectLocked and sets.container.ActivateOnMouse and
    not FSettingsOpen then SetForeground;
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.UpdateRunning;
var
  parent: THandle = 0;
begin
  try
    if sets.container.ShowRunningIndicator or sets.container.Taskbar then
    begin
      if sets.container.TaskSameMonitor then parent := Handle;
      ProcessHelper.EnumAppWindows(parent);
      if ProcessHelper.WindowsCountChanged then ProcessHelper.EnumProc;
      if sets.container.ShowRunningIndicator then ItemMgr.SetParam(icUpdateRunning, 0);
		  if sets.container.Taskbar then ItemMgr.Taskbar;
		end;
	except
    on e: Exception do raise Exception.Create('Base.UpdateRunning' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------
function Tfrmmain.IsHiddenDown: boolean;
begin Result := (FState <> nil) and ((FState.Target > 0) or (FState.Offset > 0)); end;
//------------------------------------------------------------------------------
procedure Tfrmmain.DoRollDown;
var Thickness: Integer;
begin
  if ItemMgr = nil then Exit;
  if sets.getBaseOrientation = boVertical then Thickness := ItemMgr.LayoutSnapshot.BaseWindowRect.Width
  else Thickness := ItemMgr.LayoutSnapshot.BaseWindowRect.Height;
  FState.RequestHide(Thickness, sets.container.AutoHidePixels,
    ItemMgr.InteractionSnapshot.DraggingItem or ItemMgr.InteractionSnapshot.DraggingFile,
    GetTickCount64);
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.DoRollUp;
begin if FState <> nil then FState.RequestShow; end;
//------------------------------------------------------------------------------
procedure Tfrmmain.OnTimerDoRollUpDown;
begin
  if (FState <> nil) and FState.Advance(GetTickCount64) and Assigned(ItemMgr) then
    ItemMgr.WndOffset := FState.Offset;
end;
//------------------------------------------------------------------------------
function Tfrmmain.IsHotkeyPressed(hotkey: integer): boolean;
var
  key, shift, pressedShift: integer;
begin
  result := false;
  key := hotkey and not (scShift + scCtrl + scAlt);
  shift := hotkey and (scShift + scCtrl + scAlt);
  if key <= 0 then exit;
  result := getasynckeystate(key) < 0;
  pressedShift := scNone;
  if getasynckeystate(16) < 0 then inc(pressedShift, scShift);
  if getasynckeystate(17) < 0 then inc(pressedShift, scCtrl);
  if getasynckeystate(18) < 0 then inc(pressedShift, scAlt);
  if shift <> pressedShift then result := false;
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.DoGlobalHotkeys;
var
  KeyPressed: boolean;
begin
  // hide/show
  if sets.container.GlobalHotkeyFlag_Hide and not FHotkeys.Registered(0) then
  begin
	    KeyPressed := IsHotkeyPressed(sets.container.GlobalHotkeyValue_Hide);
	    if not KeyPressed then FHideKeysPressed := false
	    else begin
	      if not FHideKeysPressed then BaseCmd(tcToggleVisible, 0);
	      FHideKeysPressed := true;
	    end;
	end;
	// command window (console)
  if sets.container.GlobalHotkeyFlag_Console and not FHotkeys.Registered(1) then
  begin
	    KeyPressed := IsHotkeyPressed(sets.container.GlobalHotkeyValue_Console);
	    if not KeyPressed then FConsoleKeysPressed := false
	    else begin
	      if not FConsoleKeysPressed then execute_cmdline('/cmdna');
	      FConsoleKeysPressed := true;
	    end;
	end;
end;
//------------------------------------------------------------------------------
// bring the dock along with all items to foreground
procedure Tfrmmain.SetForeground;
  procedure setfore(h: THandle);
  begin
    SetWindowPos(h, HWND_TOPMOST, 0, 0, 0, 0, SWP_NO_FLAGS);
    SetWindowPos(h, HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NO_FLAGS);
  end;
begin
  if assigned(ItemMgr) then
  begin
	    // set all items topmost and place the dock window right underneath
	    SetWindowPos(handle, ItemMgr.ZOrder(HWND_TOPMOST), 0, 0, 0, 0, SWP_NO_FLAGS);
      // set dock window non topmost
	    SetWindowPos(handle, HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NO_FLAGS);
	    // set blur window underneath the dock
	    SetWindowPos(FRenderer.BlurWindow, Handle, 0, 0, 0, 0, SWP_NO_FLAGS);
	    // set all items non topmost
      SetWindowPos(handle, ItemMgr.ZOrder(HWND_NOTOPMOST), 0, 0, 0, 0, SWP_NO_FLAGS);
	end;

  // bring to the foreground other program windows if any visible
  if assigned(frmItemProp) then setfore(frmItemProp.handle);
  if assigned(frmStackProp) then setfore(frmStackProp.handle);
  if assigned(frmSets) then setfore(frmSets.handle);
  if assigned(frmThemeEditor) then setfore(frmThemeEditor.handle);
end;
//------------------------------------------------------------------------------
// it is complicated. describe later ...
procedure Tfrmmain.SetNotForeground;

function IsDockWnd(wnd: THandle): boolean;
begin
  result := (wnd = handle) or (wnd = FRenderer.BlurWindow) or (ItemMgr.IsItem(wnd) <> 0);
end;

function ZOrderIndex(hWnd: THandle): integer;
var
  index: integer;
  h: THandle;
begin
  result := 0;
  index := 0;
  h := FindWindow('Progman', nil);
  while (h <> 0) and (h <> hWnd) do
  begin
    inc(index);
    h := GetWindow(h, GW_HWNDPREV);
  end;
  result := index;
end;

function DockAboveWnd(wnd: THandle): boolean;
var
  rect, dockrect: windows.TRect;
  buf: array [0..MAX_PATH - 1] of char;
begin
  result := false;
  ZeroMemory(@buf, MAX_PATH);
  ZeroMemory(@dockrect, sizeof(dockrect));
  if IsWindowVisible(wnd) and not IsIconic(wnd) then
  begin
    GetWindowRect(wnd, @rect);
    if assigned(ItemMgr) then dockrect := ItemMgr.Rect;
    if IntersectRect(rect, dockrect, rect) then
    begin
      GetClassName(wnd, buf, MAX_PATH);
      if (strpas(buf) <> 'Progman')
         and (strpas(buf) <> 'WorkerW')
         and (strpas(buf) <> 'Shell_TrayWnd')
         and (ZOrderIndex(wnd) < ZOrderIndex(handle)) then result := true;
    end;
  end;
end;

var
  pt: windows.TPoint;
  wnd, awnd: THandle;
begin
  if FProgramIsClosing then exit;
  GetCursorPos(pt);
  wnd := WindowFromPoint(pt);
  if IsDockWnd(wnd) then exit;
  awnd := GetAncestor(wnd, GA_ROOTOWNER);
  if IsWindow(awnd) then wnd := awnd;
  if assigned(ItemMgr) and DockAboveWnd(wnd) then
  begin
    SetWindowPos(FRenderer.BlurWindow, wnd, 0, 0, 0, 0, SWP_NO_FLAGS);
    SetWindowPos(handle, wnd, 0, 0, 0, 0, SWP_NO_FLAGS);
    SetWindowPos(handle, ItemMgr.ZOrder(wnd), 0, 0, 0, 0, SWP_NO_FLAGS);
  end;
end;
//------------------------------------------------------------------------------
// keep all items on top of the dock window
procedure Tfrmmain.MaintainNotForeground;
var
  h: THandle;
  blurFound: boolean = false;
begin
  // enum windows starting with Progman and up in the Z-order
  h := FindWindow('Progman', nil);
  h := GetWindow(h, GW_HWNDPREV);
	while h <> 0 do
	begin
    if h = FRenderer.BlurWindow then
      blurFound := true
    else
    if h = Handle then
    begin
      // if BlurWindow above the dock - put BlurWindow exactly under the dock, done
      if not blurFound and IsWindow(FRenderer.BlurWindow) then SetWindowPos(FRenderer.BlurWindow, Handle, 0, 0, 0, 0, SWP_NO_FLAGS);
      exit;
    end
    else
    if ItemMgr.IsItem(h) <> 0 then // one of the items found (but not the dock yet) - adjust dock position
    begin
      if IsWindow(FRenderer.BlurWindow) then SetWindowPos(FRenderer.BlurWindow, h, 0, 0, 0, 0, SWP_NO_FLAGS);
      SetWindowPos(handle, h, 0, 0, 0, 0, SWP_NO_FLAGS);
      if IsWindow(FRenderer.BlurWindow) then SetWindowPos(FRenderer.BlurWindow, handle, 0, 0, 0, 0, SWP_NO_FLAGS);
      exit;
    end
    else
    if blurFound then // if BlurWindow found, and then found some other window before - put blur exactly behind the dock
      SetWindowPos(FRenderer.BlurWindow, Handle, 0, 0, 0, 0, SWP_NO_FLAGS);

    h := GetWindow(h, GW_HWNDPREV);
	end;
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.DoMenu;
var
  pt: Windows.TPoint;
begin
  Windows.GetCursorPos(pt);
  ContextMenu(pt);
end;
//------------------------------------------------------------------------------
function Tfrmmain.ContextMenu(pt: Windows.TPoint): boolean;
var
  msg: TMessage;
begin
  Result := False;
  if not BeginUserOperation then Exit;
  try
  GetHMenu(0);
  LockMouseEffect(Handle, true);
  SetForegroundWindow(handle);
  SetForeground;
  msg.WParam := WPARAM(TrackPopupMenuEx(FMenu, TPM_RETURNCMD, pt.x, pt.y, handle, nil));
  WMCommand(msg);
  Result := True;
  finally EndUserOperation; end;
end;
//------------------------------------------------------------------------------
function Tfrmmain.GetHMenu(ParentMenu: THandle): THandle;
  function IsValidItemString(str: string): boolean;
  var
    classname: string;
  begin
    classname := FetchValue(str, 'class="', '";');
    result := (classname = 'shortcut') or (classname = 'stack');
  end;
var
  idx: integer;
begin
  if IsMenu(FMenu) then DestroyMenu(FMenu);
  if ParentMenu = 0 then FMenu := CreatePopupMenu else FMenu := ParentMenu;

  if ParentMenu = 0 then
    if IsValidItemString(GetClipboard) then
      AppendMenuW(FMenu, MF_STRING, IDM_PASTE, pwchar(UTF8Decode(XPaste)));

  // create submenu 'Add...' //

  FMenuCreate := CreatePopupMenu;
  AppendMenuW(FMenuCreate, MF_STRING + ifthen(ItemMgr.DeletedCount > 0, 0, MF_DISABLED),
    $f026, pwchar(UTF8Decode(XUndeleteIcon)));
  AppendMenuW(FMenuCreate, MF_STRING, $f023, pwchar(UTF8Decode(XSpecificIcons)));
  AppendMenuW(FMenuCreate, MF_STRING, $f021, pwchar(UTF8Decode(XEmptyIcon)));
  AppendMenuW(FMenuCreate, MF_STRING, $f022, pwchar(UTF8Decode(XFile)));
  AppendMenuW(FMenuCreate, MF_STRING, $f024, pwchar(UTF8Decode(XSeparator)));
  AppendMenuW(FMenuCreate, MF_STRING, $f025, pwchar(UTF8Decode(XDock)));
  if sets.GetPluginCount = -1 then sets.ScanPlugins;
  if sets.GetPluginCount > 0 then
  begin
    AppendMenuW(FMenuCreate, MF_SEPARATOR, 0, '-');
    idx := 0;
    while idx < sets.GetPluginCount do
    begin
      AppendMenuW(FMenuCreate, MF_STRING, $f041 + idx, pwchar(WideString(sets.GetPluginName(idx))));
      inc(idx);
    end;
  end;

  // insert all menu items //
  if ParentMenu <> 0 then AppendMenuW(FMenu, MF_SEPARATOR, 0, '-');
  AppendMenuW(FMenu, MF_STRING + MF_POPUP, FMenuCreate, pwchar(UTF8Decode(XAddIcon)));
  AppendMenuW(FMenu, MF_STRING + ifthen(sets.container.LockDragging, MF_CHECKED, 0), IDM_LOCKICONS, pwchar(UTF8Decode(XLockIcons)));
  AppendMenuW(FMenu, MF_STRING, IDM_COLLECTION, pwchar(UTF8Decode(XIconCollection)));
  AppendMenuW(FMenu, MF_SEPARATOR, 0, '-');
  AppendMenuW(FMenu, MF_STRING, IDM_TASKMGR, pwchar(UTF8Decode(XTaskManager)));
  AppendMenuW(FMenu, MF_SEPARATOR, 0, '-');
  AppendMenuW(FMenu, MF_STRING, IDM_SETS, pwchar(UTF8Decode(XProgramSettings)));
  AppendMenuW(FMenu, MF_STRING, IDM_QUIT, pwchar(UTF8Decode(XExit)));

  Result := FMenu;
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.WMCommand(var msg: TMessage);
var
  cmd: string;
begin
  try
    LockMouseEffect(Handle, false);
    msg.Result := 0;
    if IsMenu(FMenu) then DestroyMenu(FMenu);
    FMenu := 0;
    if DispatchDockCloseCommand(msg.WParam, CloseProgram) then Exit;

    if (msg.wparam >= $f021) and (msg.wparam < $f040) then
    begin
      case msg.wparam of
        $f021: cmd := '/itemmgr.shortcut';
        $f022: cmd := '/program';
        $f023: cmd := '/command';
        $f024: cmd := '/itemmgr.separator';
        $f025: cmd := '/newdock';
        $f026: cmd := '/undelete';

        IDM_PASTE: cmd := '/paste';
        IDM_LOCKICONS: cmd := '/lockdragging';
        IDM_COLLECTION: cmd := '/collection';
        IDM_TASKMGR: cmd := '/taskmgr';
        IDM_SETS: cmd := '/sets';
        IDM_QUIT: cmd := '/quit';
      end;
      execute_cmdline(cmd);
    end
    else
    if (msg.wparam >= $f041) and (msg.wparam <= $f0ff) then
    begin
      ItemMgr.command('plugin', sets.GetPluginFileName(msg.wparam - $f041));
    end;

  except
    on e: Exception do err('Base.WMCommand', e);
  end;
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.BasePaint(flags: integer);
begin
  if Assigned(ItemMgr) and Assigned(theme) and ItemMgr.Visible and not FProgramIsClosing then
    FRenderer.Paint(ItemMgr.LayoutSnapshot, theme, sets.container.BaseAlpha,
      flags, sets.container.BlurEnabled);
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.UpdateBlurWindow;
begin
  if Assigned(ItemMgr) and Assigned(theme) and Assigned(sets) then
    FRenderer.UpdateBlur(ItemMgr.LayoutSnapshot, theme, sets.container.BlurEnabled);
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.trayiconMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  DoMenu;
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.err(where: WideString; e: Exception);
begin
  where := UTF8Decode(XErrorIn) + ' ' + where;
  if assigned(e) then where := where + LineEnding + WideString(e.message);
  notify(where);
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.notify(message: WideString; silent: boolean = False);
begin
  if FApp <> nil then FApp.EnterOperation;
  try
  if assigned(Notifier) then Notifier.Message(message, GetMonitorWorkareaRect, False, silent)
  else if not silent then messageboxw(handle, pwchar(message), nil, mb_iconerror);
  finally if FApp <> nil then FApp.LeaveOperation; end;
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.alert(message: WideString);
begin
  if FApp <> nil then FApp.EnterOperation;
  try
  if assigned(Notifier) then Notifier.Message(message, GetMonitorWorkareaRect, True, False)
  else messageboxw(handle, pwchar(message), nil, mb_iconerror);
  finally if FApp <> nil then FApp.LeaveOperation; end;
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.ActivateHint(hwnd: THandle; ACaption: WideString; x, y: integer);
var
  monitor: THandle;
begin
  try
    if not FProgramIsClosing and not IsHiddenDown and not IsMouseEffectLocked
       and not ItemMgr.InteractionSnapshot.DraggingFile and not ItemMgr.InteractionSnapshot.DraggingItem then
    begin
      if FInitDone and not assigned(AHint) then FApp.Hint := THint.Create;
      if hwnd = 0 then monitor := MonitorFromWindow(Handle, 0) else monitor := MonitorFromWindow(hwnd, 0);
      if assigned(AHint) then AHint.ActivateHint(hwnd, ACaption, x, y, monitor, sets.container.Site);
    end;
  except
    on e: Exception do AddLog('frmmain.ActivateHint' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.DeactivateHint(hwnd: THandle);
begin
  if not FProgramIsClosing and assigned(AHint) then AHint.DeactivateHint(hwnd);
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.LockMouseEffect(hWnd: HWND; lock: boolean);
var id: TItemId;
begin
  if FProgramIsClosing or (FState = nil) then Exit;
  if lock then id := ItemViews.AcquireMouseLock(hWnd)
  else id := ItemViews.ReleaseMouseLock(hWnd);
  if id <> NO_ITEM_ID then FState.SetMouseEffectLock(id, lock);
  if IsMouseEffectLocked and Assigned(AHint) then AHint.DeactivateImmediate;
  SetParam(gpLockMouseEffect, Ord(IsMouseEffectLocked));
end;
//------------------------------------------------------------------------------
function Tfrmmain.IsMouseEffectLocked: boolean;
begin Result := (FState <> nil) and FState.MouseEffectLocked; end;
//------------------------------------------------------------------------------
procedure Tfrmmain.SetFont(var Value: TDFontData);
begin
  if FProgramIsClosing or (FSettingsCoordinator = nil) then Exit;
  FSettingsCoordinator.SetFont(Value);
  if Assigned(ItemMgr) then ItemMgr.SetFont(sets.container.Font);
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.AppException(Sender: TObject; e: Exception);
begin
  notify('[AppException] ' + LineEnding + Sender.ClassName + LineEnding + e.message);
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.AppDeactivate(Sender: TObject);
begin
  if not FProgramIsClosing and Assigned(ItemMgr) then ItemMgr.WMDeactivateApp;
end;
//------------------------------------------------------------------------------
// returns DesktopRect for monitor indexes < 0
function Tfrmmain.GetMonitorWorkareaRect(pMonitor: PInteger = nil): Windows.TRect;
var
  monitor: integer;
begin
  result := screen.DesktopRect;
  if assigned(pMonitor) then monitor := pMonitor^ else monitor := FMonitor;
  if monitor >= screen.MonitorCount then monitor := screen.MonitorCount - 1;
  if monitor >= 0 then Result := screen.Monitors[monitor].WorkareaRect;
end;
//------------------------------------------------------------------------------
// returns DesktopRect for monitor indexes < 0
function Tfrmmain.GetMonitorBoundsRect(pMonitor: PInteger = nil): Windows.TRect;
var
  monitor: integer;
begin
  result := screen.DesktopRect;
  if assigned(pMonitor) then monitor := pMonitor^ else monitor := FMonitor;
  if monitor >= screen.MonitorCount then monitor := screen.MonitorCount - 1;
  if monitor >= 0 then Result := screen.Monitors[monitor].BoundsRect;
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.OnDragEnter(list: TStrings; hWnd: THandle);
begin
  if not BeginUserOperation then Exit;
  try
  FDragDeadline.Cancel;
  FDragArmed := False;
  KillTimer(Handle, ID_TIMER_DRAGLEAVE); // stop tracing mouse pointer
  ItemMgr.DragEnter;
  BasePaint(1);
  finally EndUserOperation; end;
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.OnDragOver;
begin
  if not BeginUserOperation then Exit;
  try
  ItemMgr.DragOver;
  finally EndUserOperation; end;
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.OnDragReset;
begin
  if not BeginUserOperation then Exit;
  try
    FDragDeadline.Cancel;
    FDragArmed := False;
    KillTimer(Handle, ID_TIMER_DRAGLEAVE);
    if ItemMgr <> nil then ItemMgr.DragLeave;
    BasePaint(1);
  finally EndUserOperation; end;
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.OnDragLeave;
begin
  if not BeginUserOperation then Exit;
  try
  // do not actually take OnDragLeave actions
  // but start to trace mouse pointer
  FDragDeadline.Schedule(GetTickCount64, 200);
  FDragArmed := SetTimer(Handle, ID_TIMER_DRAGLEAVE, 200, nil) <> 0;
  finally EndUserOperation; end;
end;
//------------------------------------------------------------------------------
// trace mouse pointer until it actually leaves the dock area
procedure Tfrmmain.OnTimerDragLeave;
var
  pt: windows.TPoint;
begin
  if not FDragDeadline.IsDue(GetTickCount64) or (ItemMgr = nil) then Exit;
  if not GetCursorPos(pt) then
  begin
    FDragDeadline.Schedule(GetTickCount64, 200);
    Exit;
  end;
  if not PtInRect(ItemMgr.Rect, pt) then
  begin
    FDragDeadline.Cancel;
    FDragArmed := False;
    KillTimer(Handle, ID_TIMER_DRAGLEAVE);
    ItemMgr.DragLeave;
    BasePaint(1);
  end
  else FDragDeadline.Schedule(GetTickCount64, 200);
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.OnDrop(files: TDropImportBatch; hWnd: THandle);
var
  pt: Windows.TPoint;
begin
  if not BeginUserOperation then Exit;
  try
    FDragDeadline.Cancel;
    FDragArmed := False;
    KillTimer(Handle, ID_TIMER_DRAGLEAVE); // stop tracing mouse pointer
    Windows.GetCursorPos(pt);
    try
      if files.Count > 0 then ItemMgr.ImportDropFiles(files, hWnd, pt);
    finally
    ItemMgr.DragLeave;
    ItemMgr.WHMouseMove(pt);
    end;
    SetActiveWindow(handle);
    SetForegroundWindow(handle); // set foreground to finalize dragdrop operation
  finally EndUserOperation; end;
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.DropFiles(files: TStrings);
begin
  ItemMgr.InsertFiles(files);
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.WMCopyData(var Message: TMessage);
var
  pcds: PCOPYDATASTRUCT;
  ppd: PTDProgramData;
begin
  message.Result := 1;
  pcds := PCOPYDATASTRUCT(message.lParam);

  if pcds^.dwData = DATA_PROGRAM then
  begin
    if pcds^.cbData <> sizeof(TDProgramData) then
    begin
      message.Result := 0;
      notify(UTF8Decode(XErrorInvalidProgramDataStructureSize));
      exit;
    end;
    ppd := PTDProgramData(pcds^.lpData);
    ItemMgr.InsertItem(TShortcutItem.Make(pchar(ppd^.Name), ZipPath(pchar(ppd^.Filename)), '', '', '', SW_SHOWNORMAL));
  end;
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.AddFile;
begin
  if not BeginUserOperation then Exit;
  try
  with TOpenDialog.Create(Self) do
  try
    if Execute and not FProgramIsClosing then AddFile(Filename);
  finally Free; end;
  finally EndUserOperation; end;
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.AddFile(Filename: string);
begin
  if assigned(ItemMgr) then
    ItemMgr.InsertFile(Filename);
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.NewDock;
begin
  if assigned(docks) then
    if docks.HaveFreeSite then docks.NewDock;
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.RemoveDock;
begin
  if assigned(docks) then
  begin
    docks.RequestRemoveDock(sets.SetsPathFile);
    execute_cmdline('/quit');
  end;
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.OpenWith(filename: string);
var
  _file: string;
begin
  _file := toolu.UnzipPath(filename);
  if not fileexists(_file) then _file := toolu.FindFile(_file);
  ShellExecute(application.mainform.handle, nil, 'rundll32.exe', pchar('shell32.dll,OpenAs_RunDLL ' + _file), nil, 1);
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.WMDisplayChange(var Message: TMessage);
begin
  screen.UpdateMonitors;
  BaseCmd(tcThemeChanged, 0);
  message.Result := 0;
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.WMSettingChange(var Message: TMessage);
begin
  BaseCmd(tcThemeChanged, 0);
  message.Result := 0;
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.WMCompositionChanged(var Message: TMessage);
begin
  BaseCmd(tcThemeChanged, 0);
  message.Result := 0;
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.WMDPIChanged(var Message: TMessage);
begin
  BaseCmd(tcThemeChanged, 0);
  message.Result := 0;
end;
//------------------------------------------------------------------------------
function Tfrmmain.FullScreenAppActive: boolean;
const
  clsPM = 'Progman';
  clsWW = 'WorkerW';
  clsAVP = 'AVP.SandboxBorderWindow'; // Kaspersky
  MAX_CLS_LEN = 24;
var
  wnd: hWnd;
  rc, rMonitor: windows.TRect;
  cls: array [0..MAX_CLS_LEN - 1] of char;
begin
  result := false;
  ZeroMemory(@cls, MAX_CLS_LEN);
  rMonitor := ItemMgr.LayoutSnapshot.MonitorRect;
  wnd := GetWindow(Handle, GW_HWNDFIRST);
  while wnd <> 0 do
  begin
    if wnd = Handle then exit; // exit if we reached main dock window
    if IsWindow(wnd) then
    begin
      if IsWindowVisible(wnd) and not DWM.IsWindowCloaked(wnd) then
      begin
        if GetWindowLongPtr(wnd, GWL_STYLE) and WS_CAPTION = 0 then
        begin
          GetWindowRect(wnd, rc);
          if (rc.Left <= rMonitor.Left) and (rc.Top <= rMonitor.Top) and (rc.Right >= rMonitor.Right) and (rc.Bottom >= rMonitor.Bottom) then
          begin
            GetClassName(wnd, cls, MAX_CLS_LEN - 1);
		        if (strlcomp(@cls, clsPM, 7) <> 0) and (strlcomp(@cls, clsWW, 7) <> 0) and (strlcomp(@cls, clsAVP, 23) <> 0) then
            begin
              result := true;
              exit;
						end;
					end;
				end;
	    end;
		end;
		wnd := GetWindow(wnd, GW_HWNDNEXT);
  end;
end;
//------------------------------------------------------------------------------
function Tfrmmain.ListFullScreenApps: string;
var
  wnd: hWnd;
  rc, rMonitor: windows.TRect;
  cls: array [0..MAX_PATH - 1] of char;
begin
  result := '';
  rMonitor := ItemMgr.LayoutSnapshot.MonitorRect;
  wnd := GetWindow(Handle, GW_HWNDFIRST);
  while wnd <> 0 do
  begin
    if wnd = Handle then
    begin
      result := result + 'HWnd = ' + inttostr(wnd) + LineEnding;
      FillChar(cls, MAX_PATH, #0);
      GetClassName(wnd, cls, MAX_PATH);
      result := result + 'Class = ' + strpas(@cls) + LineEnding;
      FillChar(cls, MAX_PATH, #0);
      GetWindowText(wnd, cls, MAX_PATH);
      result := result + 'Text = ' + strpas(@cls) + LineEnding;
      GetWindowRect(wnd, rc);
      result := result + 'Rect = ' + inttostr(rc.Left) + ', ' + inttostr(rc.Top) + ', ' + inttostr(rc.Right) + ', ' + inttostr(rc.Bottom) + LineEnding;
      FillChar(cls, MAX_PATH, #0);
      GetWindowModuleFileName(wnd, cls, MAX_PATH);
      result := result + 'Module = ' + strpas(@cls) + LineEnding + LineEnding;
		end
    else
		if IsWindowVisible(Wnd) then
    begin
        GetWindowRect(wnd, rc);
        if (GetWindowLongPtr(wnd, GWL_STYLE) and WS_CAPTION = 0) and
          (rc.Left <= rMonitor.Left) and (rc.Top <= rMonitor.Top) and (rc.Right >= rMonitor.Right) and (rc.Bottom >= rMonitor.Bottom) then
        begin
          result := result + 'HWnd = ' + inttostr(wnd) + LineEnding;
          FillChar(cls, MAX_PATH, #0);
          GetClassName(wnd, cls, MAX_PATH);
          result := result + 'Class = ' + strpas(@cls) + LineEnding;
          FillChar(cls, MAX_PATH, #0);
          GetWindowText(wnd, cls, MAX_PATH);
          result := result + 'Text = ' + strpas(@cls) + LineEnding;
          result := result + 'Rect = ' + inttostr(rc.Left) + ', ' + inttostr(rc.Top) + ', ' + inttostr(rc.Right) + ', ' + inttostr(rc.Bottom) + LineEnding;
          FillChar(cls, MAX_PATH, #0);
          GetWindowModuleFileName(wnd, cls, MAX_PATH);
          result := result + 'Module = ' + strpas(@cls) + LineEnding + LineEnding;
        end;
    end;
    wnd := GetWindow(wnd, GW_HWNDNEXT);
  end;
end;
//------------------------------------------------------------------------------
// show popup menu to select a theme
procedure Tfrmmain.ThemesMenu;
var
  menu: HMENU;
  pt: windows.TPoint;
  ret: integer;
  mii: TMenuItemInfo;
  mname: array [0..MAX_PATH - 1] of char;
begin
  if not BeginUserOperation then Exit;
  try
  GetCursorPos(pt);
  menu := CreatePopupMenu;
  AppendMenuW(menu, MF_STRING, $f000, pwchar(UTF8Decode(XOpenThemesFolder)));
  AppendMenuW(menu, MF_SEPARATOR, 0, '-');
  theme.ThemesMenu(pchar(sets.container.ThemeName), menu);
  LockMouseEffect(Handle, true);
  SetForegroundWindow(handle);
  SetForeground;
  ret := integer(TrackPopupMenuEx(menu, TPM_RETURNCMD, pt.x, pt.y, handle, nil));
  LockMouseEffect(Handle, false);
  if ret = $f000 then execute_cmdline(theme.ThemesFolder)
  else
  if ret <> 0 then
  begin
    FillChar(mii, sizeof(mii), #0);
    mii.cbSize := sizeof(mii);
    mii.dwTypeData := @mname;
    mii.cch := MAX_PATH;
    mii.fMask := MIIM_STRING;
    GetMenuItemInfo(menu, ret, false, @mii);
    if strlen(pchar(@mname)) > 0 then setTheme(pchar(@mname));
  end;
  finally EndUserOperation; end;
end;
//------------------------------------------------------------------------------
// set a position for taskbar icons to be placed on the dock
procedure Tfrmmain.SetTaskSpot(wnd: THandle);
var
  spot: integer;
begin
  spot := ItemMgr.ItemIndex(wnd);
  if spot = ItemMgr.ItemCount - 1 then spot := -1;
  SetParam(gpTaskSpot, spot);
end;
//------------------------------------------------------------------------------
// show the list of running tasks (processes) and modules
procedure Tfrmmain.ListTasksAndModules;
begin
  notify('----- tasks -----');
  notify(WideString(ProcessHelper.Processes));
  notify('----- modules -----');
  notify(WideString(ProcessHelper.ProcessesFullName));
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.execute_multi(cmd: string; params: string = ''; dir: string = '';
  showcmd: integer = SW_SHOWNORMAL; hwnd: HWND = 0);
begin
  if not FProgramIsClosing and Assigned(FCommands) then
    begin
      FApp.EnterOperation;
      try FCommands.ExecuteMulti(cmd, params, dir, showcmd, hwnd);
      finally FApp.LeaveOperation; end;
    end;
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.execute_cmdline(cmd: string; showcmd: integer = SW_SHOWNORMAL);
begin
  if not FProgramIsClosing and Assigned(FCommands) then
    begin
      FApp.EnterOperation;
      try FCommands.ExecuteCommandLine(cmd, showcmd);
      finally FApp.LeaveOperation; end;
    end;
end;
//------------------------------------------------------------------------------
procedure Tfrmmain.execute(cmd: string; params: string = ''; dir: string = '';
  showcmd: integer = SW_SHOWNORMAL; hwndCaller: HWND = 0);
begin
  if not FProgramIsClosing and Assigned(FCommands) then
    begin
      FApp.EnterOperation;
      try FCommands.Execute(cmd, params, dir, showcmd, hwndCaller);
      finally FApp.LeaveOperation; end;
    end;
end;
//------------------------------------------------------------------------------
// create new thread if needed and run a program
procedure Tfrmmain.Run(exename: string; params: string = ''; dir: string = '';
  showcmd: integer = SW_SHOWNORMAL);
begin
  if not FProgramIsClosing and (FApp <> nil) and (FApp.Launch <> nil) then
    FApp.Launch.Run(exename, params, dir, showcmd);
end;
//------------------------------------------------------------------------------
function Tfrmmain.GetProgramIsClosing: Boolean;
begin
  Result := (FApp <> nil) and ((FApp.Lifecycle.Phase in [apClosing, apClosed]) or FApp.Lifecycle.ClosePending);
end;

function Tfrmmain.GetItemManager: TItemManager;
begin if FApp <> nil then Result := FApp.Items else Result := nil; end;

function Tfrmmain.GetDropManager: TDropManager;
begin if FApp <> nil then Result := FApp.Drop else Result := nil; end;

function Tfrmmain.GetHint: THint;
begin if FApp <> nil then Result := FApp.Hint else Result := nil; end;

function Tfrmmain.GetTray: TTrayController;
begin if FApp <> nil then Result := FApp.Tray else Result := nil; end;

function Tfrmmain.GetMonitorIndex: Integer;
begin if Assigned(sets) then Result := sets.GetParam(gpMonitor) else Result := 0; end;

destructor Tfrmmain.Destroy;
begin
  FreeAndNil(FHotkeys);
  Application.OnDeactivate := nil;
  Application.OnException := nil;
  FreeAndNil(FApp);
  FState := nil;
  FCommands := nil;
  FRenderer := nil;
  crsection := nil;
  inherited Destroy;
end;

procedure Tfrmmain.RepaintDock(ForceDraw: Boolean);
begin
  BasePaint(Ord(ForceDraw));
  RefreshScheduling;
end;

function Tfrmmain.HandleDockCommand(const Request: TDockCommandRequest): Boolean;
var
  Layout: TDockLayoutConfiguration;
begin
  Result := False;
  if FProgramIsClosing then Exit;
  case Request.Kind of
    dcActivate:
      begin
        SetForegroundWindow(Handle);
        SetActiveWindow(Handle);
        if sets.container.StayOnTop then SetForeground;
      end;
    dcRepaint: BasePaint(Request.PaintFlags);
    dcMenu: DoMenu;
    dcSaveSettings: SaveSets;
    dcThemeChanged:
      if Assigned(ItemMgr) and Assigned(theme) then
      begin
        Layout := Default(TDockLayoutConfiguration);
        Layout.ItemsArea := theme.CorrectMargins(theme.ItemsArea);
        Layout.ItemsArea2 := theme.CorrectMargins(theme.ItemsArea2);
        Layout.Margin := theme.Margin;
        Layout.Margin2 := theme.Margin2;
        Layout.MonitorRect := GetMonitorBoundsRect;
        case sets.container.Site of
          bsLeft, bsRight:
            begin
              Layout.MonitorRect.Top += sets.container.StartOffset;
              Layout.MonitorRect.Bottom -= sets.container.EndOffset;
            end;
          bsTop, bsBottom:
            begin
              Layout.MonitorRect.Left += sets.container.StartOffset;
              Layout.MonitorRect.Right -= sets.container.EndOffset;
            end;
        end;
        ItemMgr.ConfigureLayout(Layout);
        ItemMgr.SetTheme;
      end;
    dcSetVisible:
      begin
        FState.Visible := Request.Visible;
        ApplyEffectiveVisibility;
      end;
    dcToggleVisible: BaseCmd(tcSetVisible, Ord(not FState.UserShown));
    dcToggleTaskbar: SetParam(gpHideSystemTaskbar, Ord(sets.GetParam(gpHideSystemTaskbar) = 0));
    dcGetVisible: if Assigned(ItemMgr) then Result := ItemMgr.Visible;
    dcDebug: if Assigned(ItemMgr) then ItemMgr.AllItemCmd(tcDebugInfo, 0);
  end;
end;

procedure Tfrmmain.HandleApplicationCommand(Action: TApplicationAction; const Request: TCommandRequest);
var
  Params: string;
  hwndCaller: HWND;
begin
  if FProgramIsClosing then Exit;
  Params := Request.Parameters;
  hwndCaller := Request.Caller;
  if FApp.NativeCommands.Execute(Action, Params) then Exit;
  case Action of
    aaLaunch: Run(Request.Command, Params, Request.Directory, Request.ShowCommand);
    aaItemManager: ItemMgr.command(Request.Command, toolu.UnzipPath(Params));
    aaQuit: CloseProgram;
    aaHide: BaseCmd(tcSetVisible, 0);
    aaSay: notify(toolu.UnzipPath(params));
    aaAlert: alert(toolu.UnzipPath(params));
    aaToggleVisible: BaseCmd(tcToggleVisible, 0);
    aaToggleTaskbar: BaseCmd(tcToggleTaskbar, 0);
    aaSettings: Tfrmsets.Open;
    aaCommandWindow: Tfrmcmd.Open;
    aaCommandWindowNoActivate: Tfrmcmd.Open(true);
    aaCollection: Run('%pp%\images');
    aaTaskManager: Run('%sysdir%\taskmgr.exe');
    aaUndo: ItemMgr.UnDelete;
    aaAddProgram: AddFile;
    aaNewDock: NewDock;
    aaRemoveDock: RemoveDock;
    aaAddCommand: TfrmAddCommand.Open;
    aaHello: TfrmHello.Open;
    aaHelp: TfrmTip.Open;
    aaBackup: sets.Backup;
    aaRestore: TfrmRestore.Open;
    aaSaveWindows: notify(UTF8Decode(WindowLayoutMessage(FApp.WindowLayout.Save)));
    aaRestoreWindows: notify(UTF8Decode(WindowLayoutMessage(FApp.WindowLayout.Restore)));
    aaPaste: ItemMgr.InsertItem(GetClipboard);
    aaAutoTray: Tray.SwitchAutoTray;
    aaTray: Tray.ShowTrayOverflow(sets.container.Site, hwndCaller, ItemMgr.Rect, GetMonitorWorkareaRect);
    aaVolume: Tray.ShowVolumeControl(sets.container.Site, hwndCaller, ItemMgr.Rect, GetMonitorWorkareaRect);
    aaNetworks: Tray.ShowNetworks(sets.container.Site, hwndCaller, ItemMgr.Rect, GetMonitorWorkareaRect);
    aaBattery: Tray.ShowBattery(sets.container.Site, hwndCaller, ItemMgr.Rect, GetMonitorWorkareaRect);
    aaActionCenter: Tray.ShowActionCenter(sets.container.Site, hwndCaller, ItemMgr.Rect, GetMonitorWorkareaRect);
    aaStartMenu: ShellTrayWndController.ShowStartMenu(sets.container.Site, hwndCaller, ItemMgr.Rect, GetMonitorWorkareaRect);
    aaThemes: ThemesMenu;
    aaTaskSpot: SetTaskSpot(hwndCaller);
    aaThemeEditor: TfrmThemeEditor.Open;
    aaLockDragging: SetParam(gpLockDragging, ifthen(sets.GetParam(gpLockDragging) = 0, 1, 0));
    aaSite: SetParam(gpSite, integer(StringToSite(params)));
    aaDebug: BaseCmd(tcDebugInfo, 0);
    aaTasks: ListTasksAndModules;
  end;
end;

procedure Tfrmmain.BeforeSetting(const Change: TDockSettingChange);
begin
  case Change.Key of
    gpMonitor, gpSite:
      if Change.NewValue <> Change.OldValue then ShellTrayWndController.UnreserveScreenEdge;
  end;
end;

procedure Tfrmmain.ApplyingSetting(const Change: TDockSettingChange);
var Value: Integer;
begin
  Value := Change.NewValue;
  case Change.Key of
    gpMonitor: BaseCmd(tcThemeChanged, 0);
    gpSite:
      begin
        if Assigned(theme) then theme.Site := sets.container.Site;
        BaseCmd(tcThemeChanged, 0);
      end;
    gpAutoHide: FState.AutoHide := Value <> 0;
    gpHideSystemTaskbar: ShellTrayWndController.HideTaskbar(Value <> 0);
    gpReserveScreenEdge:
      if Value = 0 then ShellTrayWndController.UnreserveScreenEdge
      else ShellTrayWndController.ReserveScreenEdge(sets.container.Monitor,
        sets.container.Site, sets.container.ReserveScreenEdgePercent,
        ItemMgr.LayoutSnapshot.BaseWindowRect, sets.container.AutoHide);
    gpStayOnTop: if Value <> 0 then SetForeground else SetNotForeground;
    gpBaseAlpha: BasePaint(1);
    gpBlurEnabled:
      begin
        if Value = 0 then DestroyBlurWindow else CreateBlurWindow;
        BasePaint(1);
      end;
    gpShowRunningIndicator: if Value <> 0 then UpdateRunning;
  end;
end;

procedure Tfrmmain.NotifyItemSetting(const Change: TDockSettingChange);
begin
  if Assigned(ItemMgr) then ItemMgr.ApplySetting(Change.Key, Change.NewValue);
end;

procedure Tfrmmain.AfterSetting(const Change: TDockSettingChange);
begin
  case Change.Key of
    gpLockMouseEffect: WHMouseMove($fffffff);
    gpOccupyFullMonitor, gpStartOffset, gpEndOffset: BaseCmd(tcThemeChanged, 0);
    gpTaskbar: UpdateRunning;
    gpAutoHideOnFullScreenApp: ObserveFullscreen;
    gpGlobalHotkeyFlag_Hide, gpGlobalHotkeyValue_Hide,
    gpGlobalHotkeyFlag_Console, gpGlobalHotkeyValue_Console:
      begin
        FHideKeysPressed := False;
        FConsoleKeysPressed := False;
      end;
  end;
  ReconcileRevealState;
  RefreshScheduling;
end;

function Tfrmmain.PluginVisible: Boolean;
begin Result := IsWindowVisible(Handle); end;

function Tfrmmain.PluginSite: TBaseSite;
begin Result := sets.container.Site; end;

procedure Tfrmmain.SetPluginSite(Site: TBaseSite);
begin SetParam(gpSite, Ord(Site)); end;

function Tfrmmain.PluginCenterOffset: Integer;
begin Result := sets.container.CenterOffsetPercent; end;

procedure Tfrmmain.SetPluginCenterOffset(Value: Integer);
begin SetParam(gpCenterOffsetPercent, Value); end;

procedure Tfrmmain.ExecutePlugin(Id: HWND; const Exename, Params, Dir: string; ShowCmd: Integer);
begin execute_multi(Exename, Params, Dir, ShowCmd, Id); end;

procedure Tfrmmain.ExcludePluginFromPeek(Id: HWND);
begin dwm.ExcludeFromPeek(Id); end;

procedure Tfrmmain.PluginError(Where: string; E: Exception);
begin err(Where, E); end;

procedure Tfrmmain.PostDeferredClose;
begin PostMessage(Handle, WM_COMMAND, IDM_QUIT, 0); end;

procedure Tfrmmain.BindPluginHost;
var Services: TItemHostServices;
begin
  Services := Default(TItemHostServices);
  Services.OnEnter := FApp.EnterOperation;
  Services.OnLeave := FApp.LeaveOperation;
  Services.OnDelete := ItemMgr.DeleteItem;
  Services.OnDock := ItemMgr.Dock;
  Services.OnUndock := ItemMgr.Undock;
  Services.OnNotify := notify;
  Services.OnLockMouseEffect := LockMouseEffect;
  FCommands.OnDocument := FApp.Launch.OpenDocument;
  Services.OnOpenDocument := FCommands.OpenDocument;
  BindItemHost(Handle, Services);
  FApp.Plugins.OnVisible := PluginVisible;
  FApp.Plugins.OnGetSite := PluginSite;
  FApp.Plugins.OnSetSite := SetPluginSite;
  FApp.Plugins.OnGetCenterOffset := PluginCenterOffset;
  FApp.Plugins.OnSetCenterOffset := SetPluginCenterOffset;
  FApp.Plugins.OnExecute := ExecutePlugin;
  FApp.Plugins.OnMenu := GetHMenu;
  FApp.Plugins.OnNotify := notify;
  FApp.Plugins.OnActivateHint := ActivateHint;
  FApp.Plugins.OnDeactivateHint := DeactivateHint;
  FApp.Plugins.OnLockMouseEffect := LockMouseEffect;
  FApp.Plugins.OnAddProgram := AddFile;
  FApp.Plugins.OnExcludeFromPeek := ExcludePluginFromPeek;
  FApp.Plugins.OnError := PluginError;
end;

end.

