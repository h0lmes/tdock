unit shelltraywndu;

interface
uses Windows, Classes, SysUtils, Forms, declu, GDIPAPI, dockh, trayu;

type

  { TShellTrayWndController }

  TShellTrayWndController = class
  private
    FIsEdgeReserved: boolean;
    FReservedSite: TBaseSite;
    FReservedMonitor: integer;
    FTaskbarRetry, FTaskbarHide, FTaskbarLayoutValid: Boolean;
    FTaskbarLayout: Windows.TRect;
    FSite: TBaseSite;
    FPoint: windows.TPoint;
    FBaseRect, FMonitorRect: windows.TRect;
    Fx, FxPic: integer;
    Fy, FyPic: integer;
    FPopupState: TShellPopupState;
    FStartProcessId: DWORD;
    FStartMenuWnd: THandle;
    FDesktopUserPictureWnd: THandle;
    function GetPlacementPhase: TShellPopupPhase;
  protected
    function ClockNow: QWord; virtual;
    function FindStartMenu: HWND; virtual;
    function ValidStartMenu(Window: HWND): Boolean; virtual;
    function PopupVisible(Window: HWND): Boolean; virtual;
    function PlacePopup(Window: HWND; X, Y: Integer): Boolean; virtual;
    function GetMonitorWorkareaRect(Monitor: integer): Windows.TRect; virtual;
    function GetMonitorBoundsRect(Monitor: integer): Windows.TRect; virtual;
    function FindShellWindow: HWND; virtual;
    function FindStartButton: HWND; virtual;
    function ShellWindowExists(Window: HWND): Boolean; virtual;
    function ShellWindowVisible(Window: HWND): Boolean; virtual;
    procedure ShowShellWindow(Window: HWND; Visible: Boolean); virtual;
    function MonitorForDockRect(const DockRect: GDIPAPI.TRect): Integer; virtual;
    function ReadWindowRect(Window: HWND; out Bounds: Windows.TRect): Boolean; virtual;
    function GetRectCenter(rect: Windows.TRect): Windows.TPoint;
    function GetMaximizedWindows(monitorBounds: windows.TRect): TFPList;
    function SetWorkarea(NewWorkArea: windows.TRect): Boolean; virtual;
  public
    class procedure Cleanup;
    constructor Create;
    procedure HideTaskbar(hide: boolean);
    procedure ReserveScreenEdge(DockMonitor: integer; DockSite: TBaseSite; Percent: integer; DockWindowRect: GDIPAPI.TRect; DockAutoHide: boolean);
    procedure UnreserveScreenEdge;
    procedure ShowStartMenu(site: TBaseSite; host_wnd: THandle; baseRect, monitorRect: windows.TRect);
    procedure Timer;
    function NeedsPolling: Boolean;
    procedure ObserveWindowChange(Window: HWND);
    property PlacementPhase: TShellPopupPhase read GetPlacementPhase;
    property EdgeReserved: Boolean read FIsEdgeReserved;
  end;

var ShellTrayWndController: TShellTrayWndController;

function ReservedWorkarea(Workarea, Bounds: Windows.TRect; Site: TBaseSite;
  Percent: Integer; DockRect: GDIPAPI.TRect; AutoHide: Boolean): Windows.TRect;

implementation

function ReservedWorkarea(Workarea, Bounds: Windows.TRect; Site: TBaseSite;
  Percent: Integer; DockRect: GDIPAPI.TRect; AutoHide: Boolean): Windows.TRect;
var Position: Integer;
begin
  Result := Workarea;
  case Site of
    bsLeft:
      begin
        Position := Bounds.Left;
        if not AutoHide then Inc(Position, DockRect.Width * Percent div 100);
        Result.Left := Position;
      end;
    bsTop:
      begin
        Position := Bounds.Top;
        if not AutoHide then Inc(Position, DockRect.Height * Percent div 100);
        Result.Top := Position;
      end;
    bsRight:
      begin
        if AutoHide then Position := Bounds.Right
        else Position := Bounds.Right - DockRect.Width * Percent div 100;
        Result.Right := Position;
      end;
    bsBottom:
      begin
        if AutoHide then Position := Bounds.Bottom
        else Position := Bounds.Bottom - DockRect.Height * Percent div 100;
        Result.Bottom := Position;
      end;
  end;
end;

function TShellTrayWndController.FindShellWindow: HWND;
begin Result := FindWindow('Shell_TrayWnd', nil); end;

function TShellTrayWndController.ClockNow: QWord;
begin Result := GetTickCount64; end;

function TShellTrayWndController.FindStartMenu: HWND;
begin
  Result := FindWindow('ImmersiveLauncher', nil);
  if Result = 0 then Result := FindWindow('DV2ControlHost', nil);
end;

function TShellTrayWndController.ValidStartMenu(Window: HWND): Boolean;
var Name: array[0..255] of Char; ProcessId: DWORD;
begin
  Result := False;
  if not IsWindow(Window) then Exit;
  if GetClassName(Window, @Name[0], Length(Name)) = 0 then Exit;
  if not SameText(StrPas(@Name[0]), 'ImmersiveLauncher') and
    not SameText(StrPas(@Name[0]), 'DV2ControlHost') then Exit;
  ProcessId := 0;
  GetWindowThreadProcessId(Window, @ProcessId);
  Result := (ProcessId <> 0) and ((FStartProcessId = 0) or (FStartProcessId = ProcessId));
end;

function TShellTrayWndController.PopupVisible(Window: HWND): Boolean;
begin Result := IsWindowVisible(Window); end;

function TShellTrayWndController.PlacePopup(Window: HWND; X, Y: Integer): Boolean;
begin Result := SetWindowPos(Window, 0, X, Y, 0, 0, SWP_NOSIZE or SWP_NOZORDER); end;

function TShellTrayWndController.GetPlacementPhase: TShellPopupPhase;
begin Result := FPopupState.Phase; end;

function TShellTrayWndController.NeedsPolling: Boolean;
begin Result := FPopupState.Phase = spWaiting; end;

procedure TShellTrayWndController.ObserveWindowChange(Window: HWND);
begin
  if FPopupState.NeedsPolling and
    ((Window = 0) or (Window = FStartMenuWnd) or
     (Window = FDesktopUserPictureWnd) or NeedsPolling) then Timer;
end;

function TShellTrayWndController.FindStartButton: HWND;
begin Result := FindWindowW('Button', pwchar(UTF8Decode(XStartButtonText))); end;

function TShellTrayWndController.ShellWindowExists(Window: HWND): Boolean;
begin Result := IsWindow(Window); end;

function TShellTrayWndController.ShellWindowVisible(Window: HWND): Boolean;
begin Result := IsWindowVisible(Window); end;

procedure TShellTrayWndController.ShowShellWindow(Window: HWND; Visible: Boolean);
begin
  if Visible then ShowWindow(Window, SW_SHOWNORMAL) else ShowWindow(Window, SW_HIDE);
end;

function TShellTrayWndController.MonitorForDockRect(const DockRect: GDIPAPI.TRect): Integer;
var Point: Windows.TPoint;
begin
  if Screen.MonitorCount = 0 then Exit(-1);
  Point.X := DockRect.X + DockRect.Width div 2;
  Point.Y := DockRect.Y + DockRect.Height div 2;
  Result := Screen.MonitorFromPoint(Point).MonitorNum;
end;

function TShellTrayWndController.ReadWindowRect(Window: HWND; out Bounds: Windows.TRect): Boolean;
begin Result := Windows.GetWindowRect(Window, Bounds); end;
//------------------------------------------------------------------------------
class procedure TShellTrayWndController.Cleanup;
begin
  if assigned(ShellTrayWndController) then ShellTrayWndController.Free;
  ShellTrayWndController := nil;
end;
//------------------------------------------------------------------------------
constructor TShellTrayWndController.Create;
begin
  inherited;
  FPopupState.Cancel;
  FIsEdgeReserved := false;
  FReservedMonitor := 0;
  FReservedSite := bsBottom;
end;
//------------------------------------------------------------------------------
function TShellTrayWndController.GetMonitorWorkareaRect(Monitor: integer): Windows.TRect;
begin
  Result := Default(Windows.TRect);
  if Screen.MonitorCount = 0 then Exit;
  if Monitor < 0 then Monitor := 0;
  if Monitor >= screen.MonitorCount then Monitor := screen.MonitorCount - 1;
  if Monitor >= 0 then Result := screen.Monitors[Monitor].WorkareaRect;
end;
//------------------------------------------------------------------------------
function TShellTrayWndController.GetMonitorBoundsRect(Monitor: integer): Windows.TRect;
begin
  Result := Default(Windows.TRect);
  if Screen.MonitorCount = 0 then Exit;
  if Monitor < 0 then Monitor := 0;
  if Monitor >= screen.MonitorCount then Monitor := screen.MonitorCount - 1;
  if Monitor >= 0 then Result := screen.Monitors[Monitor].BoundsRect;
end;
//------------------------------------------------------------------------------
function TShellTrayWndController.GetRectCenter(rect: Windows.TRect): Windows.TPoint;
begin
  result.x := (rect.Left + rect.Right) div 2;
  result.y := (rect.Top + rect.Bottom) div 2;
end;
//------------------------------------------------------------------------------
// hide/show taskbar and start button
procedure TShellTrayWndController.HideTaskbar(hide: boolean);
var
  hwndTaskbar, hwndButton: THandle;
  buttonVisible, taskbarVisible, updateWorkarea: boolean;
  taskbarRect, taskbarMonitorWorkarea, taskbarMonitorBounds: Windows.TRect;
  monitorCenter, taskbarCenter: windows.TPoint;
  taskbarMonitorIndex: integer; // a monitor on which the taskbar is
  taskbarSite: TBaseSite;
begin
  try
    if FTaskbarRetry and (FTaskbarHide <> hide) then FTaskbarLayoutValid := False;
    FTaskbarHide := hide;
    FTaskbarRetry := True;
    hwndTaskbar := FindShellWindow;
    if not ShellWindowExists(hwndTaskbar) then Exit;
    hwndButton := FindStartButton;
    taskbarVisible := ShellWindowVisible(hwndTaskbar);
    buttonVisible := ShellWindowVisible(hwndButton);
    updateWorkarea := false;

    // if workarea should be changed
    if (hide = taskbarVisible) or FTaskbarLayoutValid then
    begin
      // get monitor index and site where taskbar is located
      taskbarMonitorIndex := 0;
      if not ReadWindowRect(hwndTaskbar, taskbarRect) then Exit;
      if (taskbarRect.Right <= taskbarRect.Left) or
        (taskbarRect.Bottom <= taskbarRect.Top) then Exit;
      begin
        // monitor index
        taskbarCenter := GetRectCenter(taskbarRect);
        taskbarMonitorIndex := screen.MonitorFromPoint(taskbarCenter).MonitorNum;
        // monitor center point
        taskbarMonitorBounds := GetMonitorBoundsRect(taskbarMonitorIndex);
        taskbarMonitorWorkarea := GetMonitorWorkareaRect(taskbarMonitorIndex);
        if (taskbarMonitorBounds.Right <= taskbarMonitorBounds.Left) or
          (taskbarMonitorBounds.Bottom <= taskbarMonitorBounds.Top) or
          (taskbarMonitorWorkarea.Right <= taskbarMonitorWorkarea.Left) or
          (taskbarMonitorWorkarea.Bottom <= taskbarMonitorWorkarea.Top) then Exit;
        monitorCenter := GetRectCenter(taskbarMonitorBounds);
        // taskbar site
        if taskbarRect.Bottom - taskbarRect.Top < taskbarRect.Right - taskbarRect.Left then
        begin
          if taskbarCenter.y > monitorCenter.y then taskbarSite := bsBottom else taskbarSite := bsTop;
        end else begin
          if taskbarCenter.x > monitorCenter.x then taskbarSite := bsRight else taskbarSite := bsLeft;
        end;
      end;

      // do not change WA if the taskbar and the dock occupy the same monitor/site and dock already controls WA
      updateWorkarea := not FIsEdgeReserved or (taskbarMonitorIndex <> FReservedMonitor) or (taskbarSite <> FReservedSite);

      // calculate new WA
      if updateWorkarea and hide then
      begin
        case taskbarSite of
          bsBottom: taskbarMonitorWorkarea.Bottom := taskbarMonitorBounds.Bottom;
          bsTop: taskbarMonitorWorkarea.Top := taskbarMonitorBounds.Top;
          bsLeft: taskbarMonitorWorkarea.Left := taskbarMonitorBounds.Left;
          bsRight: taskbarMonitorWorkarea.Right := taskbarMonitorBounds.Right;
        end;
      end;
      if updateWorkarea and not hide then
      begin
        case taskbarSite of
          bsBottom: taskbarMonitorWorkarea.Bottom := taskbarMonitorBounds.Bottom - taskbarRect.Bottom + taskbarRect.Top;
          bsTop: taskbarMonitorWorkarea.Top := taskbarMonitorBounds.Top + taskbarRect.Bottom - taskbarRect.Top;
          bsLeft: taskbarMonitorWorkarea.Left := taskbarMonitorBounds.Left + taskbarRect.Right - taskbarRect.Left;
          bsRight: taskbarMonitorWorkarea.Right := taskbarMonitorBounds.Right - taskbarRect.Right + taskbarRect.Left;
        end;
      end;
      FTaskbarLayoutValid := updateWorkarea;
      if updateWorkarea then FTaskbarLayout := taskbarMonitorWorkarea;
    end;

    // hide or show Start Button
    if ShellWindowExists(hwndButton) then
    begin
      if hide and buttonVisible then         ShowShellWindow(hwndButton, False);
      if not hide and not buttonVisible then ShowShellWindow(hwndButton, True);
    end;

    // hide or show Taskbar
    if hide and taskbarVisible then         ShowShellWindow(hwndTaskbar, False);
    if not hide and not taskbarVisible then ShowShellWindow(hwndTaskbar, True);

    if not ShellWindowExists(hwndTaskbar) or (ShellWindowVisible(hwndTaskbar) = hide) then Exit;

    // Keep failed layout work after the native visibility transition succeeds.
    if FTaskbarLayoutValid then
    begin
      if not SetWorkarea(FTaskbarLayout) then Exit;
      FTaskbarLayoutValid := False;
    end;
    FTaskbarRetry := False;
  except
    on e: Exception do raise Exception.Create('TShellTrayWndController.HideTaskbar' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------
function TShellTrayWndController.GetMaximizedWindows(monitorBounds: windows.TRect): TFPList;
var
  wnd: THandle;
  wp: WINDOWPLACEMENT;
  rect: windows.TRect;
  center: windows.TPoint;
begin
  result := TFPList.Create;
  wp.length := sizeof(wp);
  wnd := FindWindow('Progman', nil);
  wnd := GetWindow(wnd, GW_HWNDPREV);
  while wnd <> 0 do
  begin
    // exclude hidden and tool windows
    if IsWindowVisible(wnd) and (GetWindowLongPtr(wnd, GWL_EXSTYLE) and WS_EX_TOOLWINDOW = 0) then
    begin
      if GetWindowPlacement(wnd, wp) and GetWindowRect(wnd, rect) then
      begin
        center.x := (rect.left + rect.right) div 2;
        center.y := (rect.top + rect.bottom) div 2;
        if (wp.showCmd = SW_SHOWMAXIMIZED) and PtInRect(monitorBounds, center) then result.Add(pointer(wnd));
      end;
    end;
    wnd := GetWindow(wnd, GW_HWNDPREV);
  end;
end;
//------------------------------------------------------------------------------
function TShellTrayWndController.SetWorkarea(NewWorkArea: windows.TRect): Boolean;
var
  monitor: integer;
  bounds: windows.TRect;
  i: integer;
begin
  Result := False;
  if (NewWorkArea.Right <= NewWorkArea.Left) or
    (NewWorkArea.Bottom <= NewWorkArea.Top) then Exit;
  Result := SystemParametersInfo(SPI_SETWORKAREA, 0, @NewWorkArea, SPIF_UPDATEINIFILE);
  if not Result then Exit;
  monitor := screen.MonitorFromPoint(GetRectCenter(NewWorkArea)).MonitorNum;
  bounds := GetMonitorBoundsRect(monitor);
  with GetMaximizedWindows(bounds) do
  try
    i := 0;
    while i < Count do // reposition maximized windows to match new workarea
    begin
      SetWindowPos(THandle(Items[i]), 0, NewWorkArea.Left, NewWorkArea.Top,
        NewWorkArea.Right - NewWorkArea.Left, NewWorkArea.Bottom - NewWorkArea.Top,
        SWP_NOACTIVATE + SWP_NOZORDER + SWP_NOOWNERZORDER);
      inc(i);
    end;
  finally Free; end;
end;
//------------------------------------------------------------------------------
procedure TShellTrayWndController.ReserveScreenEdge(DockMonitor: integer; DockSite: TBaseSite; Percent: integer; DockWindowRect: GDIPAPI.TRect; DockAutoHide: boolean);
var WorkArea, Bounds, Planned: Windows.TRect;
begin
  try
    // All-monitor layouts reserve the monitor containing the dock center.
    if DockMonitor < 0 then DockMonitor := MonitorForDockRect(DockWindowRect);
    if DockMonitor < 0 then Exit;
    if FIsEdgeReserved and ((FReservedMonitor <> DockMonitor) or (FReservedSite <> DockSite)) then
    begin
      UnreserveScreenEdge;
      if FIsEdgeReserved then Exit;
    end;
    WorkArea := GetMonitorWorkareaRect(DockMonitor);
    Bounds := GetMonitorBoundsRect(DockMonitor);
    if (Bounds.Right <= Bounds.Left) or (Bounds.Bottom <= Bounds.Top) or
      (WorkArea.Right <= WorkArea.Left) or (WorkArea.Bottom <= WorkArea.Top) then Exit;
    Planned := ReservedWorkarea(WorkArea, Bounds, DockSite, Percent, DockWindowRect, DockAutoHide);
    if not EqualRect(WorkArea, Planned) and not SetWorkarea(Planned) then Exit;
    FIsEdgeReserved := true;
    FReservedMonitor := DockMonitor;
    FReservedSite := DockSite;
  except
    on e: Exception do raise Exception.Create('TShellTrayWndController.ReserveScreenEdge' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------
procedure TShellTrayWndController.UnreserveScreenEdge;
var
  Changed, MustRestoreShellWorkArea: boolean;
  Position: integer;
  WorkArea, Bounds, Shell_TrayRect: Windows.TRect;
  Shell_TrayWnd: THandle;
  Shell_TrayCenter, MonitorCenter: Windows.TPoint;
  Shell_TrayEdge: TBaseSite;
begin
  if FIsEdgeReserved then
  try
    Changed := false;
    WorkArea := GetMonitorWorkareaRect(FReservedMonitor);
    Bounds := GetMonitorBoundsRect(FReservedMonitor);
    if (Bounds.Right <= Bounds.Left) or (Bounds.Bottom <= Bounds.Top) or
      (WorkArea.Right <= WorkArea.Left) or (WorkArea.Bottom <= WorkArea.Top) then Exit;

    Position := Bounds.Bottom;
    if FReservedSite = bsTop then Position := Bounds.Top
    else if FReservedSite = bsLeft then Position := Bounds.Left
    else if FReservedSite = bsRight then Position := Bounds.Right;

    // restore workarea for Shell_TrayWnd ? //
    Shell_TrayWnd := FindShellWindow;
    if IsWindowVisible(Shell_TrayWnd) and ReadWindowRect(Shell_TrayWnd, Shell_TrayRect) then
    begin
      Shell_TrayCenter := GetRectCenter(Shell_TrayRect);
      MonitorCenter := GetRectCenter(Bounds);
      Shell_TrayEdge := bsBottom;
      if Shell_TrayCenter.y < MonitorCenter.y - 10 then Shell_TrayEdge := bsTop
      else if Shell_TrayCenter.x < MonitorCenter.x - 10 then Shell_TrayEdge := bsLeft
      else if Shell_TrayCenter.x > MonitorCenter.x + 10 then Shell_TrayEdge := bsRight;
      MustRestoreShellWorkArea := ptinrect(Bounds, Shell_TrayCenter) and (Shell_TrayEdge = FReservedSite);
      if MustRestoreShellWorkArea then
      begin
        Position := Shell_TrayRect.Top;
        if Shell_TrayEdge = bsTop then Position := Shell_TrayRect.Bottom;
        if Shell_TrayEdge = bsLeft then Position := Shell_TrayRect.Right;
        if Shell_TrayEdge = bsRight then Position := Shell_TrayRect.Left;
      end;
    end;

    if FReservedSite = bsLeft then
    begin
      if WorkArea.Left <> Position then
      begin
        WorkArea.Left := Position;
        Changed := true;
      end;
    end
    else if FReservedSite = bsTop then
    begin
      if WorkArea.Top <> Position then
      begin
        WorkArea.Top := Position;
        Changed := true;
      end;
    end
    else if FReservedSite = bsRight then
    begin
      if WorkArea.Right <> Position then
      begin
        WorkArea.Right := Position;
        Changed := true;
      end;
    end
    else if FReservedSite = bsBottom then
    begin
      if WorkArea.Bottom <> Position then
      begin
        WorkArea.Bottom := Position;
        Changed := true;
      end;
    end;

    if Changed and not SetWorkarea(WorkArea) then Exit;
    FIsEdgeReserved := false;
  except
    on e: Exception do raise Exception.Create('TShellTrayWndController.UnreserveScreenEdge' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------
procedure TShellTrayWndController.ShowStartMenu(site: TBaseSite; host_wnd: THandle; baseRect, monitorRect: windows.TRect);
var
  hostRect: windows.TRect;
begin
  FSite := site;
  FBaseRect := baseRect;
  FMonitorRect := monitorRect;

  GetCursorPos(FPoint);
  if IsWindow(host_wnd) and ReadWindowRect(host_wnd, hostRect) then
  begin
    case FSite of
      bsLeft, bsRight: FPoint.y := (hostRect.Top + hostRect.Bottom) div 2;
      bsTop, bsBottom: FPoint.x := (hostRect.Left + hostRect.Right) div 2;
    end;
  end;

  FStartProcessId := 0;
  FStartMenuWnd := 0;
  FDesktopUserPictureWnd := findwindow('Desktop User Picture', nil);
  //FDesktopSpecialFoldersWnd := findwindowex(FStartMenuWnd, 0, 'DesktopSpecialFolders', nil);

  FPopupState.Start(ClockNow, SHELL_POPUP_TIMEOUT);
  sendmessage(host_wnd, WM_SYSCOMMAND, SC_TASKLIST, 0);
end;
//------------------------------------------------------------------------------
procedure TShellTrayWndController.Timer;
var
  wRect, picRect: windows.TRect;
  Exists, Shown, HasPicture: Boolean;
begin
  if FTaskbarRetry then HideTaskbar(FTaskbarHide);
  if FPopupState.NeedsPolling then
  begin
    if not ValidStartMenu(FStartMenuWnd) then
    begin
      FStartProcessId := 0;
      FStartMenuWnd := FindStartMenu;
      FDesktopUserPictureWnd := FindWindow('Desktop User Picture', nil);
    end;
    Exists := ValidStartMenu(FStartMenuWnd);
    if Exists and (FStartProcessId = 0) then GetWindowThreadProcessId(FStartMenuWnd, @FStartProcessId);
    Shown := Exists and PopupVisible(FStartMenuWnd);
    FPopupState.Observe(ClockNow, Exists, Shown);
    if FPopupState.Phase = spVisible then
    begin
      if not ReadWindowRect(FStartMenuWnd, wRect) then Exit;
      HasPicture := IsWindow(FDesktopUserPictureWnd) and
        ReadWindowRect(FDesktopUserPictureWnd, picRect);
      if not HasPicture then picRect := Default(Windows.TRect);
      FxPic := (wRect.Right - wRect.Left) * 3 div 4 - (picRect.Right - picRect.Left);
      FyPic := -(picRect.Bottom - picRect.Top) div 2;
      if FSite = bsLeft then
      begin
        Fx := FBaseRect.Right + 5;
        Fy := FPoint.y - (wRect.Bottom - wRect.Top) div 2;
      end
      else
      if FSite = bsTop then
      begin
        Fx := FPoint.x - (wRect.Right - wRect.Left) div 2;
        Fy := FBaseRect.Bottom + 5;
      end
      else
      if FSite = bsRight then
      begin
        Fx := FBaseRect.Left - 5 - (wRect.Right - wRect.Left);
        Fy := FPoint.y - (wRect.Bottom - wRect.Top) div 2;
      end
      else
      begin
        Fx := FPoint.x - (wRect.Right - wRect.Left) div 2;
        Fy := FBaseRect.Top - 5 - (wRect.Bottom - wRect.Top);
      end;
      if Fx < FMonitorRect.Left then Fx := FMonitorRect.Left;
      if Fx > FMonitorRect.Right - wRect.Right + wRect.Left then Fx := FMonitorRect.Right - wRect.Right + wRect.Left;
      if Fy < FMonitorRect.Top then Fy := FMonitorRect.Top;
      if Fy > FMonitorRect.Bottom - wRect.Bottom + wRect.Top then Fy := FMonitorRect.Bottom - wRect.Bottom + wRect.Top;

      if (wRect.Left <> Fx) or (wRect.Top <> Fy) then
      begin
        if PlacePopup(FStartMenuWnd, Fx, Fy) and HasPicture then
          PlacePopup(FDesktopUserPictureWnd, Fx + FxPic, Fy + FyPic);
      end;
    end;
  end;
end;
//------------------------------------------------------------------------------
end.

