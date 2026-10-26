//------------------------------------------------------------------------------
//
//
//
// This unit implements functionality to interact with
// shell tray and tray icons
//
//
//
//------------------------------------------------------------------------------

unit trayu;

interface
uses Windows, Classes, SysUtils, Registry, declu, docktimingu;

const
  CTLW_OFFSET = 10;
  SHELL_POPUP_TIMEOUT = 3000;

type

  TShellPopupPhase = (spIdle, spWaiting, spVisible, spFailed);
  TShellPopupState = record
    Phase: TShellPopupPhase;
    Deadline: TDeadline;
    TimeoutMs: QWord;
    procedure Start(Now, Timeout: QWord);
    procedure Observe(Now: QWord; Exists, Visible: Boolean);
    procedure Cancel;
    function NeedsPolling: Boolean;
  end;

  { TTrayController }

  TTrayController = class
  private
    FParentHWnd: THandle;
    FSite: TBaseSite;
    FControlWindow: THandle;
    Fx: integer;
    Fy: integer;
    FPopupState: TShellPopupState;
    FPopupClass, FPopupCaption: string;
    FPopupProcessId: DWORD;
    FOpenWhenFound: Boolean;
    FPoint: windows.TPoint;
    FBaseRect: windows.TRect;
    FMonitorRect: windows.TRect;
    FWin10: boolean;
    function GetPlacementPhase: TShellPopupPhase;
    procedure RunAvailableNetworks;
    procedure RunNotificationAreaIcons;
    procedure RunDateAndTime;
    procedure RunPowerOptions;
    procedure RunMobilityCenter;
    procedure Run(exename: string; params: string = ''; dir: string = ''; showcmd: integer = sw_shownormal);
  protected
    function ClockNow: QWord; virtual;
    function LookupPopup(const ClassName, Caption: string): HWND; virtual;
    function ValidPopup(Window: HWND): Boolean; virtual;
    function PopupVisible(Window: HWND): Boolean; virtual;
    function ReadPopupRect(Window: HWND; out Bounds: Windows.TRect): Boolean; virtual;
    function PlacePopup(Window: HWND; X, Y: Integer): Boolean; virtual;
    procedure ActivatePopup(Window: HWND); virtual;
    procedure BeginPopup(const ClassName, Caption: string; OpenWhenFound: Boolean = False);
  public
    constructor Create;
    function AutoTrayEnabled: boolean;
    procedure SwitchAutoTray;
    procedure EnableAutoTray;
    procedure DisableAutoTray;
    procedure ShowTrayOverflow(site: TBaseSite; host_wnd: THandle; baseRect, monitorRect: windows.TRect);
		procedure ShowActionCenter(site: TBaseSite; host_wnd: THandle; baseRect, monitorRect: windows.TRect);
    procedure ShowVolumeControl(site: TBaseSite; host_wnd: THandle; baseRect, monitorRect: windows.TRect);
    procedure ShowNetworks(site: TBaseSite; host_wnd: THandle; baseRect, monitorRect: windows.TRect);
    procedure ShowBattery(site: TBaseSite; host_wnd: THandle; baseRect, monitorRect: windows.TRect);
    procedure Timer;
    function NeedsPolling: Boolean;
    procedure ObserveWindowChange(Window: HWND);
    property PlacementPhase: TShellPopupPhase read GetPlacementPhase;
  end;

implementation

procedure TShellPopupState.Start(Now, Timeout: QWord);
begin
  Phase := spWaiting;
  Deadline.Schedule(Now, Timeout);
  TimeoutMs := Timeout;
end;

procedure TShellPopupState.Observe(Now: QWord; Exists, Visible: Boolean);
begin
  if not NeedsPolling then Exit;
  if (Phase = spWaiting) and Deadline.IsDue(Now) then
  begin Phase := spFailed; Deadline.Cancel; Exit; end;
  if Exists and Visible then
  begin Phase := spVisible; Deadline.Cancel; end
  else if Phase = spVisible then
    if Exists then Cancel else Start(Now, TimeoutMs);
end;

procedure TShellPopupState.Cancel;
begin Phase := spIdle; Deadline.Cancel; end;

function TShellPopupState.NeedsPolling: Boolean;
begin Result := Phase in [spWaiting, spVisible]; end;

function TTrayController.ClockNow: QWord;
begin Result := GetTickCount64; end;

function TTrayController.LookupPopup(const ClassName, Caption: string): HWND;
var WindowCaption: PChar;
begin
  WindowCaption := nil;
  if Caption <> '' then WindowCaption := PChar(Caption);
  Result := FindWindow(PChar(ClassName), WindowCaption);
end;

function TTrayController.ValidPopup(Window: HWND): Boolean;
var Name: array[0..255] of Char; ProcessId, ShellProcessId: DWORD; Shell: HWND;
begin
  Result := False;
  if not Windows.IsWindow(Window) then Exit;
  if GetClassName(Window, @Name[0], Length(Name)) = 0 then Exit;
  if not SameText(StrPas(@Name[0]), FPopupClass) then Exit;
  ProcessId := 0;
  GetWindowThreadProcessId(Window, @ProcessId);
  if (ProcessId = 0) or ((FPopupProcessId <> 0) and (ProcessId <> FPopupProcessId)) then Exit;
  if (FPopupClass = 'NotifyIconOverflowWindow') or (FPopupClass = 'BatMeterFlyout') then
  begin
    Shell := FindWindow('Shell_TrayWnd', nil);
    ShellProcessId := 0;
    if Shell <> 0 then GetWindowThreadProcessId(Shell, @ShellProcessId);
    if (ShellProcessId <> 0) and (ProcessId <> ShellProcessId) then Exit;
  end;
  Result := True;
end;

function TTrayController.PopupVisible(Window: HWND): Boolean;
begin Result := IsWindowVisible(Window); end;

function TTrayController.ReadPopupRect(Window: HWND; out Bounds: Windows.TRect): Boolean;
begin Result := GetWindowRect(Window, Bounds); end;

function TTrayController.PlacePopup(Window: HWND; X, Y: Integer): Boolean;
begin Result := SetWindowPos(Window, 0, X, Y, 0, 0, SWP_NOSIZE or SWP_NOZORDER); end;

procedure TTrayController.ActivatePopup(Window: HWND);
var ProcessId: DWORD; AllowForeground: function(ProcessId: DWORD): BOOL; stdcall;
begin
  ProcessId := 0;
  GetWindowThreadProcessId(Window, @ProcessId);
  @AllowForeground := GetProcAddress(GetModuleHandle('user32.dll'), 'AllowSetForegroundWindow');
  if Assigned(AllowForeground) then AllowForeground(ProcessId);
  Windows.SetForegroundWindow(Window);
  Windows.SetActiveWindow(Window);
end;

procedure TTrayController.BeginPopup(const ClassName, Caption: string; OpenWhenFound: Boolean);
begin
  FControlWindow := 0;
  FPopupProcessId := 0;
  FPopupClass := ClassName;
  FPopupCaption := Caption;
  FOpenWhenFound := OpenWhenFound;
  FPopupState.Start(ClockNow, SHELL_POPUP_TIMEOUT);
end;

function TTrayController.GetPlacementPhase: TShellPopupPhase;
begin Result := FPopupState.Phase; end;

function TTrayController.NeedsPolling: Boolean;
begin Result := FPopupState.Phase = spWaiting; end;

procedure TTrayController.ObserveWindowChange(Window: HWND);
begin
  if FPopupState.NeedsPolling and
    ((Window = 0) or (Window = FControlWindow) or NeedsPolling) then Timer;
end;
//------------------------------------------------------------------------------
constructor TTrayController.Create;
var
  VerInfo: windows.TOSVersioninfo;
begin
  inherited;
  FPopupState.Cancel;
  FParentHWnd := FindWindow('Window', PROGRAM_NAME);
  VerInfo.dwOSVersionInfoSize:= sizeof(TOSVersionInfo);
  windows.GetVersionEx(VerInfo);
  FWin10 := VerInfo.dwMajorVersion >= 10;
end;
//------------------------------------------------------------------------------
function TTrayController.AutoTrayEnabled: boolean;
begin
  result := false;
  with TRegIniFile.Create do
  begin
    RootKey := HKEY_CURRENT_USER;
    result := 1 = ReadInteger('Software\Microsoft\Windows\CurrentVersion\Explorer', 'EnableAutoTray', 0);
    Free;
  end;
end;
//------------------------------------------------------------------------------
procedure TTrayController.SwitchAutoTray;
begin
  if AutoTrayEnabled then DisableAutoTray else EnableAutoTray;
end;
//------------------------------------------------------------------------------
procedure TTrayController.EnableAutoTray;
begin
  with TRegIniFile.Create do
  begin
    RootKey := HKEY_CURRENT_USER;
    LazyWrite := False;
    WriteInteger('Software\Microsoft\Windows\CurrentVersion\Explorer', 'EnableAutoTray', 1);
    Free;
  end;

  SendMessageTimeout(HWND_BROADCAST, WM_SETTINGCHANGE, 0, 0, SMTO_ABORTIFHUNG, 5000, nil);
end;
//------------------------------------------------------------------------------
procedure TTrayController.DisableAutoTray;
begin
  with TRegIniFile.Create do
  begin
    RootKey := HKEY_CURRENT_USER;
    LazyWrite := False;
    WriteInteger('Software\Microsoft\Windows\CurrentVersion\Explorer', 'EnableAutoTray', 0);
    Free;
  end;

  SendMessageTimeout(HWND_BROADCAST, WM_SETTINGCHANGE, 0, 0, SMTO_ABORTIFHUNG, 5000, nil);
end;
//------------------------------------------------------------------------------
procedure TTrayController.ShowTrayOverflow(site: TBaseSite; host_wnd: THandle; baseRect, monitorRect: windows.TRect);
var
  HWnd: THandle;
  hostRect: windows.TRect;
begin
  if not AutoTrayEnabled then
  begin
    messageboxw(FParentHWnd, pwchar(UTF8Decode(XMsgNotificationAreaIcons)), '', MB_ICONEXCLAMATION);
    RunNotificationAreaIcons;
    exit;
  end;

  FSite := site;
  FBaseRect := baseRect;
  FMonitorRect := monitorRect;
  GetCursorPos(FPoint);
  if IsWindow(host_wnd) and GetWindowRect(host_wnd, @hostRect) then
  begin
    case FSite of
      bsLeft, bsRight: FPoint.y := (hostRect.Top + hostRect.Bottom) div 2;
      bsTop, bsBottom: FPoint.x := (hostRect.Left + hostRect.Right) div 2;
    end;
  end;

  BeginPopup('NotifyIconOverflowWindow', '');
  // open Tray overflow window
  hwnd := FindWindow('Shell_TrayWnd', nil);
  hwnd := FindWindowEx(hwnd, 0, 'TrayNotifyWnd', nil);
  hwnd := FindWindowEx(hwnd, 0, 'Button', nil);
  SetActiveWindow(hwnd);
  SetForegroundWindow(hwnd);
  SendMessage(hwnd, BM_CLICK, 0, 0);
end;
//------------------------------------------------------------------------------
// win 10 feature. not yet working. TODO
procedure TTrayController.ShowActionCenter(site: TBaseSite; host_wnd: THandle; baseRect, monitorRect: windows.TRect);
var
  HWnd: THandle;
begin
  FControlWindow := 0;
  FPopupState.Cancel;
  // open Win 10 style Action Center window
  hwnd := FindWindow('Shell_TrayWnd', nil);
  hwnd := FindWindowEx(hwnd, 0, 'TrayNotifyWnd', nil);
  hwnd := FindWindowEx(hwnd, 0, 'TrayButton', nil);
  SetActiveWindow(hwnd);
  SetForegroundWindow(hwnd);
  SendMessage(hwnd, BM_CLICK, 0, 0); // this for sure does a click but nothing happens
end;
//------------------------------------------------------------------------------
procedure TTrayController.ShowVolumeControl(site: TBaseSite; host_wnd: THandle; baseRect, monitorRect: windows.TRect);
var
  hostRect: windows.TRect;
begin
  FSite := site;
  FBaseRect := baseRect;
  FMonitorRect := monitorRect;
  GetCursorPos(FPoint);
  if IsWindow(host_wnd) and GetWindowRect(host_wnd, @hostRect) then
  begin
    case FSite of
      bsLeft, bsRight: FPoint.y := (hostRect.Top + hostRect.Bottom) div 2;
      bsTop, bsBottom: FPoint.x := (hostRect.Left + hostRect.Right) div 2;
    end;
  end;

  FControlWindow := 0;
  FPopupState.Cancel;
  // open volume control
  Run('sndvol.exe', '-f ' + inttostr(FPoint.x + FPoint.y * $10000), '', sw_shownormal);
end;
//------------------------------------------------------------------------------
procedure TTrayController.ShowNetworks(site: TBaseSite; host_wnd: THandle; baseRect, monitorRect: windows.TRect);
var
  hostRect: windows.TRect;
begin
  FSite := site;
  FBaseRect := baseRect;
  FMonitorRect := monitorRect;
  GetCursorPos(FPoint);
  if IsWindow(host_wnd) and GetWindowRect(host_wnd, @hostRect) then
  begin
    case FSite of
      bsLeft, bsRight: FPoint.y := (hostRect.Top + hostRect.Bottom) div 2;
      bsTop, bsBottom: FPoint.x := (hostRect.Left + hostRect.Right) div 2;
    end;
  end;

  // open View Available Networks
  RunAvailableNetworks;
  if FWin10 then
  begin
    BeginPopup('NativeHWNDHost', 'View Available Networks');
	end else begin
    FControlWindow := 0;
    FPopupState.Cancel;
	end;
end;
//------------------------------------------------------------------------------
procedure TTrayController.ShowBattery(site: TBaseSite; host_wnd: THandle; baseRect, monitorRect: windows.TRect);
var
  hostRect: windows.TRect;
begin
  FSite := site;
  FBaseRect := baseRect;
  FMonitorRect := monitorRect;
  GetCursorPos(FPoint);
  if IsWindow(host_wnd) and GetWindowRect(host_wnd, @hostRect) then
  begin
    case FSite of
      bsLeft, bsRight: FPoint.y := (hostRect.Top + hostRect.Bottom) div 2;
      bsTop, bsBottom: FPoint.x := (hostRect.Left + hostRect.Right) div 2;
    end;
  end;

  BeginPopup('BatMeterFlyout', '', True);
  Timer;
end;
//------------------------------------------------------------------------------
procedure TTrayController.Timer;
var
  wRect: windows.TRect;
  Exists, Shown: Boolean;
begin
  if FPopupState.NeedsPolling then
  begin
    if (FPopupState.Phase = spWaiting) and FPopupState.Deadline.IsDue(ClockNow) then
    begin
      FPopupState.Observe(ClockNow, False, False);
      Exit;
    end;
    if not ValidPopup(FControlWindow) then
    begin
      FPopupProcessId := 0;
      FControlWindow := LookupPopup(FPopupClass, FPopupCaption);
    end;
    Exists := ValidPopup(FControlWindow);
    if Exists and (FPopupProcessId = 0) then
      GetWindowThreadProcessId(FControlWindow, @FPopupProcessId);
    if Exists and FOpenWhenFound then
    begin
      FOpenWhenFound := False;
      ShowWindow(FControlWindow, SW_SHOW);
      ActivatePopup(FControlWindow);
    end;
    Shown := Exists and PopupVisible(FControlWindow);
    FPopupState.Observe(ClockNow, Exists, Shown);
    if FPopupState.Phase = spVisible then
    begin
      if not ReadPopupRect(FControlWindow, wRect) then Exit;
      if FSite = bsLeft then
      begin
        Fx := FBaseRect.Right + CTLW_OFFSET;
        Fy := FPoint.y - (wRect.Bottom - wRect.Top) div 2;
      end
      else
      if FSite = bsTop then
      begin
        Fx := FPoint.x - (wRect.Right - wRect.Left) div 2;
        Fy := FBaseRect.Bottom + CTLW_OFFSET;
      end
      else
      if FSite = bsRight then
      begin
        Fx := FBaseRect.Left - CTLW_OFFSET - (wRect.Right - wRect.Left);
        Fy := FPoint.y - (wRect.Bottom - wRect.Top) div 2;
      end
      else
      begin
        Fx := FPoint.x - (wRect.Right - wRect.Left) div 2;
        Fy := FBaseRect.Top - CTLW_OFFSET - (wRect.Bottom - wRect.Top);
      end;
      if Fx < FMonitorRect.Left then Fx := FMonitorRect.Left;
      if Fx > FMonitorRect.Right - wRect.Right + wRect.Left then Fx := FMonitorRect.Right - wRect.Right + wRect.Left;
      if Fy < FMonitorRect.Top then Fy := FMonitorRect.Top;
      if Fy > FMonitorRect.Bottom - wRect.Bottom + wRect.Top then Fy := FMonitorRect.Bottom - wRect.Bottom + wRect.Top;

      if (wRect.Left <> Fx) or (wRect.Top <> Fy) then
        PlacePopup(FControlWindow, Fx, Fy);
    end;
  end;
end;
//------------------------------------------------------------------------------
procedure TTrayController.RunAvailableNetworks;
begin
  if FWin10 then Run('ms-settings:network')
  else Run('rundll32.exe', 'van.dll,RunVAN');
end;
//------------------------------------------------------------------------------
procedure TTrayController.RunNotificationAreaIcons;
begin
  Run('control.exe', '/name Microsoft.NotificationAreaIcons');
end;
//------------------------------------------------------------------------------
procedure TTrayController.RunDateAndTime;
begin
  Run('control.exe', '/name Microsoft.DateAndTime');
end;
//------------------------------------------------------------------------------
procedure TTrayController.RunPowerOptions;
begin
  Run('control.exe', '/name Microsoft.PowerOptions');
end;
//------------------------------------------------------------------------------
procedure TTrayController.RunMobilityCenter;
begin
  Run('control.exe', '/name Microsoft.MobilityCenter');
end;
//------------------------------------------------------------------------------
procedure TTrayController.Run(exename: string; params: string = ''; dir: string = ''; showcmd: integer = sw_shownormal);
var
  pparams, pdir: pchar;
begin
  try
    pparams := nil;
    pdir := nil;
    if params <> '' then pparams := PChar(params);
    if dir <> '' then pdir := PChar(dir);
    shellexecute(FParentHWnd, nil, pchar(exename), pparams, pdir, showcmd);
  except
    on e: Exception do raise Exception.Create('TrayController.Run ' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------
end.

