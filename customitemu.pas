unit customitemu;

{$t+}

interface
uses Windows, Messages, SysUtils, Controls, Classes, ShellAPI, Math, FileUtil,
  declu, dockh, gfx, toolu, loggeru;

const
  anim_bounce: array [0..15] of single = (0, 0.1670, 0.3290, 0.4680, 0.5956, 0.6937, 0.7790, 0.8453, 0.8984, 0.9360, 0.9630, 0.9810, 0.9920, 0.9976, 0.9997, 1);
  MIN_BORDER = 20;
  TDITEM_WCLASS = 'TDockItemWClass';

type

  TOnMouseHover = procedure(param: boolean) of object;
  TOnBeforeMouseHover = procedure(param: boolean) of object;
  TOnBeforeUndock = procedure of object;

  { TCustomItem is an abstract class }
  TCustomItem = class
  private
    FHover: boolean;
  protected
    FFreed: boolean;
    FHWnd: HWND;
    FHWndParent: HWND;
    FHMenu: THandle;
    FCaption: WideString;
    FColorData: integer;
    FX: integer;
    FY: integer;
    FSize: integer;
    FBorder: integer;
    FDockFromX: integer;
    FDockFromY: integer;
    FDockingX: integer;
    FDockingY: integer;
    need_dock: boolean;
    FDockingProgress: single;
    FNCHitTestNC: boolean; // if true - HitTest returns true for non-client area

    FEnabled: boolean;
    FUpdating: boolean;
    FUndocked: boolean;
    FSelected: boolean;
    FDropIndicator: integer;
    FReflection: boolean;
    FReflectionSize: integer;
    FShowHint: boolean; // global option
    FHideHint: boolean; // local option
    FHintVisible: boolean; // is hint currently visible?
    FMonitor: integer;
    FSite: integer;
    FLockDragging: boolean;
    FLockMouseEffect: boolean;
    FItemSize: integer;
    FBigItemSize: integer;
    FItemSpacing: integer;
    FLaunchInterval: integer;
    FActivateRunning: boolean;
    MouseDownPoint: windows.TPoint;
    FMouseDownButton: TMouseButton;
    FNeedMouseWheel: boolean;
    FAttention: boolean;

    FFont: TDFontData;
    FImage: Pointer;
    FIW: uint; // image width
    FIH: uint; // image height
    FShowItem: uint;
    FItemAnimationType: integer; // animation type
    FAnimationEnd: integer;
    FAnimationProgress: integer; // animation progress 0..FAnimationEnd

    OnMouseHover: TOnMouseHover;
    OnBeforeMouseHover: TOnBeforeMouseHover;
    OnBeforeUndock: TOnBeforeUndock;

    procedure RegisterWindowItemClass;
    procedure Init; virtual;
    procedure Redraw(Force: boolean = true); // updates item appearance
    procedure Attention(value: boolean);
    procedure SetCaption(value: WideString);
    procedure MouseHover(AHover: boolean);
    procedure UpdateHint(Ax: integer = -32000; Ay: integer = -32000);
    function GetRectFromSize(ASize: integer): windows.TRect;
    function ExpandRect(r: windows.TRect; value: integer): windows.TRect;
    function GetClientRect: windows.TRect;
    function GetScreenRect: windows.TRect;
    procedure notify(message: string);
    procedure err(where: string; e: Exception);
  public
    property Freed: boolean read FFreed write FFreed;
    property Undocked: boolean read FUndocked;
    property Handle: HWND read FHWnd;
    property Caption: WideString read FCaption write SetCaption;
    property ColorData: integer read FColorData write FColorData;
    property X: integer read FX;
    property Y: integer read FY;
    property Size: integer read FSize;
    property Rect: windows.TRect read GetClientRect;
    property ScreenRect: windows.TRect read GetScreenRect;

    constructor Create(wndParent: HWND; var AParams: TDItemCreateParams); virtual;
    destructor Destroy; override;
    procedure SetFont(var Value: TDFontData); virtual;
    procedure Draw(Ax, Ay, ASize: integer; AForce: boolean; wpi: HDWP; AShowItem: uint); virtual; abstract;
    function  ToString: string; virtual; abstract;
    procedure MouseDown(button: TMouseButton; shift: TShiftState; x, y: integer); virtual;
    function  MouseUp(button: TMouseButton; shift: TShiftState; x, y: integer): boolean; virtual;
    procedure MouseClick(button: TMouseButton; shift: TShiftState; x, y: integer); virtual;
    procedure MouseHeld(button: TMouseButton); virtual;
    function  DblClick(button: TMouseButton; shift: TShiftState; x, y: integer): boolean; virtual;
    procedure WndMessage(var msg: TMessage); virtual; abstract;
    procedure WMCommand(wParam: WPARAM; lParam: LPARAM; var Result: LRESULT); virtual; abstract;
    function  cmd(id: TDParam; param: PtrInt): PtrInt; virtual;
    procedure Timer; virtual;
    procedure Configure; virtual;
    function  CanOpenFolder: boolean; virtual;
    procedure OpenFolder; virtual;
    function  Executable: string; virtual;
    function  DropFile(wnd: HWND; pt: windows.TPoint; filename: string): boolean; virtual;
    procedure Save(ini, section: string); virtual; abstract;

    procedure Undock;
    procedure Dock;
    function  HitTest(Ax, Ay: integer): boolean;
    function  ScreenHitTest(Ax, Ay: integer): boolean;
    procedure Animate;
    procedure LME(lock: boolean);
    procedure Delete;
    function  WindowProc(wnd: HWND; message: uint; wParam: WPARAM; lParam: LPARAM): LRESULT;
  end;

implementation
//------------------------------------------------------------------------------
function CustomItemClassWindowProc(wnd: HWND; message: uint; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall;
var
  inst: TCustomItem;
begin
  inst := TCustomItem(GetWindowLongPtr(wnd, GWL_USERDATA));
  if assigned(inst) then
    result := inst.WindowProc(wnd, message, wParam, lParam)
  else
    result := DefWindowProc(wnd, message, wParam, lParam);
end;
//------------------------------------------------------------------------------
constructor TCustomItem.Create(wndParent: HWND; var AParams: TDItemCreateParams);
begin
  inherited Create;
  Init;

  FHWndParent := wndParent;
  RegisterWindowItemClass;
  FHWnd := CreateWindowEx(WS_EX_LAYERED + WS_EX_TOOLWINDOW, TDITEM_WCLASS, nil, WS_POPUP,
    FX, FY, FSize, FSize, FHWndParent, 0, hInstance, nil);
  if not IsWindow(FHWnd) then
  begin
    FFreed := true;
    exit;
  end;
  dockh.ExcludeFromPeek(FHWnd);
  SetWindowLongPtr(FHWnd, GWL_USERDATA, PtrUint(self));

  FItemSize          := AParams.ItemSize;
  FSize              := FItemSize;
  FBigItemSize       := AParams.BigItemSize;
  FItemSpacing       := AParams.ItemSpacing;
  FItemAnimationType := AParams.AnimationType;
  FLaunchInterval    := AParams.LaunchInterval;
  FActivateRunning   := AParams.ActivateRunning;
  FReflection        := AParams.Reflection;
  FReflectionSize    := AParams.ReflectionSize;
  FBorder            := max(FReflectionSize, MIN_BORDER);
  FSite              := AParams.Site;
  FShowHint          := AParams.ShowHint;
  FLockDragging      := AParams.LockDragging;
  CopyFontData(AParams.Font, FFont);
end;
//------------------------------------------------------------------------------
destructor TCustomItem.Destroy;
begin
  SetWindowLongPtr(FHWnd, GWL_USERDATA, PtrUint(0));
  if IsWindow(FHWnd) then DestroyWindow(FHWnd);
  FHWnd := 0;
  inherited;
end;
//------------------------------------------------------------------------------
procedure TCustomItem.RegisterWindowItemClass;
var
  wndClass: windows.TWndClass;
begin
  try
    wndClass.style          := CS_DBLCLKS;
    wndClass.lpfnWndProc    := @CustomItemClassWindowProc;
    wndClass.cbClsExtra     := 0;
    wndClass.cbWndExtra     := 0;
    wndClass.hInstance      := hInstance;
    wndClass.hIcon          := 0;
    wndClass.hCursor        := LoadCursor(0, idc_Arrow);
    wndClass.hbrBackground  := 0;
    wndClass.lpszMenuName   := nil;
    wndClass.lpszClassName  := TDITEM_WCLASS;
    windows.RegisterClass(wndClass);
  except
    on e: Exception do err('CustomItem.RegisterWindowClass', e);
  end;
end;
//------------------------------------------------------------------------------
procedure TCustomItem.Init;
begin
  FFreed := false;
  FEnabled := true;
  FCaption := '';
  FX := -9999;
  FY := -9999;
  FSize := 32;
  FCaption := '';
  FUpdating := false;
  FUndocked := false;
  FSelected := false;
  FColorData := DEF_COLOR_DATA;
  FDropIndicator := 0;
  FReflection := false;
  FReflectionSize := 16;
  FBorder := FReflectionSize;
  FShowHint := true;
  FHideHint := false;
  FHintVisible := false;
  FAttention := false;
  FSite := 3;
  FHover := false;
  FLockMouseEffect := false;
  FItemSize := 32;
  FBigItemSize := 32;
  FAnimationProgress := 0;
  FImage := nil;
  FIW := 32;
  FIH := 32;
  FShowItem := SWP_HIDEWINDOW;
  FDockingX := 0;
  FDockingY := 0;
  need_dock := false;
  FNCHitTestNC := false;
  FNeedMouseWheel := false;
end;
//------------------------------------------------------------------------------
function TCustomItem.cmd(id: TDParam; param: PtrInt): PtrInt;
begin
  result:= 0;
  try
    case id of
      // parameters //
      gpItemSize:
        begin
          FItemSize := param;
          Redraw;
        end;
      gpBigItemSize: FBigItemSize := word(param);
      gpItemSpacing:
        begin
          FItemSpacing := word(param);
          Redraw;
        end;
      gpReflectionEnabled:
        begin
          FReflection := boolean(param);
          Redraw;
        end;
      gpReflectionSize:
        begin
          FReflectionSize := min(param, FItemSize);
          FBorder := max(FReflectionSize, MIN_BORDER);
          Redraw;
        end;
      gpMonitor: FMonitor := param;
      gpSite:
        if param <> FSite then
        begin
          FSite := param;
          Redraw;
        end;
      gpLockMouseEffect:
        begin
          FLockMouseEffect := param <> 0;
          UpdateHint;
        end;
      gpShowHint:
        begin
          FShowHint := boolean(param);
          UpdateHint;
        end;
      gpLockDragging: FLockDragging := param <> 0;
      gpLaunchInterval: FLaunchInterval := param;
      gpActivateRunning: FActivateRunning := boolean(param);
      gpItemAnimationType: FItemAnimationType := param;

      // commands //

      icSelect:
        if FSelected <> boolean(param) then
        begin
          FSelected := boolean(param);
          Redraw;
        end;

      icDropIndicator:
        if FDropIndicator <> param then
        begin
          FDropIndicator := param;
          Redraw;
        end;

      icHover:
        begin
          if param = 0 then cmd(icSelect, 0);
          MouseHover(boolean(param));
        end;

      icFree: FFreed := param <> 0;
    end;

  except
    on e: Exception do raise Exception.Create('CustomItem.Cmd ' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------
procedure TCustomItem.Undock;
begin
  if not FUndocked then
  begin
    FUndocked := true;
    FHover := false;
    FSelected := false;
    need_dock := false;
    Redraw;
  end;
end;
//------------------------------------------------------------------------------
procedure TCustomItem.Dock;
var
  wRect: windows.TRect;
begin
  if FUndocked then
  begin
    FUndocked := false;
    FDockingProgress := 0;
    need_dock := true;
    wRect := ScreenRect;
    FDockFromX := wRect.Left;
    FDockFromY := wRect.Top;
    FDockingX := FDockFromX;
    FDockingY := FDockFromY;
    Redraw;
  end;
end;
//------------------------------------------------------------------------------
procedure TCustomItem.SetFont(var Value: TDFontData);
begin
  CopyFontData(Value, FFont);
end;
//------------------------------------------------------------------------------
procedure TCustomItem.Redraw(Force: boolean = true);
begin
  Draw(FX, FY, FSize, Force, 0, FShowItem);
end;
//------------------------------------------------------------------------------
procedure TCustomItem.Timer;
begin
  if FFreed or FUpdating then exit;
  // docking after item dropped onto dock //
  if need_dock then
  begin
    FDockingProgress += 0.1;
    FDockingX := FDockFromX + round((FX - FDockFromX) * FDockingProgress);
    FDockingY := FDockFromY + round((FY - FDockFromY) * FDockingProgress);
    Redraw(false);
    if FDockingProgress >= 1 then need_dock := false;
  end;
end;
//------------------------------------------------------------------------------
procedure TCustomItem.Attention(value: boolean);
begin
  FAttention := value;
  if not FAttention then Redraw;
end;
//------------------------------------------------------------------------------
procedure TCustomItem.Configure;
begin
end;
//------------------------------------------------------------------------------
function TCustomItem.DblClick(button: TMouseButton; shift: TShiftState; x, y: integer): boolean;
begin
  result := true;
end;
//------------------------------------------------------------------------------
procedure TCustomItem.MouseDown(button: TMouseButton; shift: TShiftState; x, y: integer);
begin
  if not FFreed then
  begin
    FMouseDownButton := button;
    if button = mbLeft then SetTimer(FHWnd, ID_TIMER_MOUSEHELD, 1000, nil)
    else SetTimer(FHWnd, ID_TIMER_MOUSEHELD, 800, nil);
    cmd(icSelect, 1);
  end;
end;
//------------------------------------------------------------------------------
function TCustomItem.MouseUp(button: TMouseButton; shift: TShiftState; x, y: integer): boolean;
begin
  result := not FFreed;
  KillTimer(FHWnd, ID_TIMER_MOUSEHELD);
  if not FFreed and FSelected then
  begin
    cmd(icSelect, 0);
    MouseClick(button, shift, x, y);
  end;
end;
//------------------------------------------------------------------------------
procedure TCustomItem.MouseClick(button: TMouseButton; shift: TShiftState; x, y: integer);
begin
end;
//------------------------------------------------------------------------------
procedure TCustomItem.MouseHeld(button: TMouseButton);
begin
  cmd(icSelect, 0);
  if button = mbLeft then
  begin
    if assigned(OnBeforeUndock) then OnBeforeUndock;
    Undock; // do not undock actually, just mark as undocked and make item semitransparent
  end;
end;
//------------------------------------------------------------------------------
procedure TCustomItem.MouseHover(AHover: boolean);
begin
  if not FFreed and not (AHover = FHover) then
  begin
    if assigned(OnBeforeMouseHover) then OnBeforeMouseHover(AHover);
    FHover := AHover;
    if not FHover then KillTimer(FHWnd, ID_TIMER_MOUSEHELD);
    UpdateHint;
    if assigned(OnMouseHover) then OnMouseHover(FHover);
  end;
end;
//------------------------------------------------------------------------------
function TCustomItem.DropFile(wnd: HWND; pt: windows.TPoint; filename: string): boolean;
begin
  result := false;
end;
//------------------------------------------------------------------------------
function TCustomItem.CanOpenFolder: boolean;
begin
  result := false;
end;
//------------------------------------------------------------------------------
procedure TCustomItem.OpenFolder;
begin
end;
//------------------------------------------------------------------------------
function TCustomItem.Executable: string;
begin
  result := '';
end;
//------------------------------------------------------------------------------
procedure TCustomItem.SetCaption(value: WideString);
begin
  if not (FCaption = value) then
  begin
    FCaption := value;
    UpdateHint;
  end;
end;
//------------------------------------------------------------------------------
procedure TCustomItem.UpdateHint(Ax: integer = -32000; Ay: integer = -32000);
var
  hx, hy: integer;
  wrect, baserect: windows.TRect;
  do_show: boolean;
  hint_offset: integer;
begin
  if not FFreed then
  try
    do_show := FShowHint and not FHideHint and FHover and not FUndocked and not FLockMouseEffect and (trim(FCaption) <> '');
    if not do_show then
    begin
      if FHintVisible then dockh.DeactivateHint(FHWnd);
      FHintVisible := false;
      exit;
    end;

    if (Ax <> -32000) and (Ay <> -32000) then
    begin
      wRect := Rect;
      hx := Ax + wRect.Left + FSize div 2;
      hy := Ay + wRect.Top + FSize div 2;
    end else begin
      wRect := ScreenRect;
      hx := wRect.left + FSize div 2;
      hy := wRect.top + FSize div 2;
    end;

    hint_offset := 10;
    baserect := dockh.DockGetRect;
    if FSite = 0 then hx := max(baserect.right,  hx + FSize div 2 + hint_offset)
    else
    if FSite = 1 then hy := max(baserect.bottom, hy + FSize div 2 + hint_offset)
    else
    if FSite = 2 then hx := min(baserect.left,   hx - FSize div 2 - hint_offset)
    else
                      hy := min(baserect.top,    hy - FSize div 2 - hint_offset);

    FHintVisible := true;
    dockh.ActivateHint(FHWnd, PWideChar(FCaption), hx, hy);
  except
    on e: Exception do raise Exception.Create('TCustomItem.UpdateHint ' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------
function TCustomItem.GetRectFromSize(ASize: integer): windows.TRect;
begin
  result := classes.rect(FBorder, FBorder, FBorder + ASize, FBorder + ASize);
end;
//------------------------------------------------------------------------------
// item rect in client coordinates
function TCustomItem.GetClientRect: windows.TRect;
begin
  result := GetRectFromSize(FSize);
end;
//------------------------------------------------------------------------------
// item rect in screen coordinates
function TCustomItem.GetScreenRect: windows.TRect;
var
  r: windows.TRect;
begin
  result := GetClientRect;
  GetWindowRect(FHWnd, @r);
  inc(result.Left, r.Left);
  inc(result.Right, r.Left);
  inc(result.Top, r.Top);
  inc(result.Bottom, r.Top);
end;
//------------------------------------------------------------------------------
function TCustomItem.ExpandRect(r: windows.TRect; value: integer): windows.TRect;
begin
  result := r;
  dec(result.Left, value);
  dec(result.Top, value);
  inc(result.Right, value);
  inc(result.Bottom, value);
end;
//------------------------------------------------------------------------------
function TCustomItem.HitTest(Ax, Ay: integer): boolean;
begin
  if FNCHitTestNC then
  begin
    result := true;
    exit;
  end;
  result := ptinrect(GetClientRect, classes.Point(Ax, Ay));
end;
//------------------------------------------------------------------------------
function TCustomItem.ScreenHitTest(Ax, Ay: integer): boolean;
begin
  if FNCHitTestNC then
  begin
    result := true;
    exit;
  end;
  result := ptinrect(GetScreenRect, classes.Point(Ax, Ay));
end;
//------------------------------------------------------------------------------
procedure TCustomItem.Animate;
begin
  case FItemAnimationType of
    1: FAnimationEnd := 60; // rotate
    2: FAnimationEnd := 30; // bounce 1
    3: FAnimationEnd := 60; // bounce 2
    4: FAnimationEnd := 90; // bounce 3
    5: FAnimationEnd := 60; // quake
    6: FAnimationEnd := 56; // swing
    7: FAnimationEnd := 56; // vibrate
    8: FAnimationEnd := 56; // zoom
  end;
  FAnimationProgress := 1;
end;
//------------------------------------------------------------------------------
procedure TCustomItem.LME(lock: boolean);
begin
  dockh.DockletLockMouseEffect(FHWnd, lock);
end;
//------------------------------------------------------------------------------
procedure TCustomItem.Delete;
begin
  FFreed := true;
  ShowWindow(FHWnd, SW_HIDE);
  dockh.DockDeleteItem(FHWnd);
end;
//------------------------------------------------------------------------------
procedure TCustomItem.notify(message: string);
begin
  dockh.notify(FHWnd, pchar(message));
end;
//------------------------------------------------------------------------------
function TCustomItem.WindowProc(wnd: HWND; message: uint; wParam: WPARAM; lParam: LPARAM): LRESULT;
var
  idx: integer;
  ShiftState: classes.TShiftState;
  pos: windows.TSmallPoint;
  wpt: windows.TPoint;
  msg: TMessage;
  //
  filecount: integer;
  filename: array [0..MAX_PATH - 1] of char;
begin
  if not FFreed then
  try
    msg.msg := message;
    msg.wParam := wParam;
    msg.lParam := lParam;
    WndMessage(msg);
    result := msg.Result;
  except
    on e: Exception do err('CustomItem.WindowProc.WndMessage', e);
  end;

  try
    if not FFreed then
    begin
        result := 0;
        pos := TSmallPoint(dword(lParam));
        ShiftState := [];
        if HIBYTE(GetKeyState(VK_MENU)) and $80 <> 0 then Include(ShiftState, ssAlt);
        if wParam and MK_SHIFT <> 0 then Include(ShiftState, ssShift);
        if wParam and MK_CONTROL <> 0 then Include(ShiftState, ssCtrl);

        if (message >= wm_keyfirst) and (message <= wm_keylast) then
        begin
          result := sendmessage(FHWndParent, message, wParam, lParam);
          exit;
        end;

        if message = WM_LBUTTONDOWN then
        begin
              MouseDownPoint.x:= pos.x;
              MouseDownPoint.y:= pos.y;
              if HitTest(pos.x, pos.y) then MouseDown(mbLeft, ShiftState, pos.x, pos.y)
              else begin
                SetActiveWindow(FHWndParent);
                sendmessage(FHWndParent, message, wParam, lParam);
              end;
        end
        else if message = WM_RBUTTONDOWN then
        begin
              MouseDownPoint.x:= pos.x;
              MouseDownPoint.y:= pos.y;
              if HitTest(pos.x, pos.y) then MouseDown(mbRight, ShiftState, pos.x, pos.y)
              else begin
                SetActiveWindow(FHWndParent);
                sendmessage(FHWndParent, message, wParam, lParam);
              end;
        end
        else if message = WM_LBUTTONUP then
        begin
              Dock;
              if HitTest(pos.x, pos.y) then MouseUp(mbLeft, ShiftState, pos.x, pos.y)
              else begin
                SetActiveWindow(FHWndParent);
                sendmessage(FHWndParent, message, wParam, lParam);
              end;
        end
        else if message = WM_RBUTTONUP then
        begin
              if not FFreed then
              begin
                if HitTest(pos.x, pos.y) then MouseUp(mbRight, ShiftState, pos.x, pos.y)
                else begin
                  SetActiveWindow(FHWndParent);
                  sendmessage(FHWndParent, message, wParam, lParam);
                end;
              end;
        end
        else if message = WM_LBUTTONDBLCLK then
        begin
              if not HitTest(pos.x, pos.y) then sendmessage(FHWndParent, message, wParam, lParam)
              else
              if not DblClick(mbLeft, ShiftState, pos.x, pos.y) then sendmessage(FHWndParent, message, wParam, lParam);
        end
        else if message = WM_MOUSEWHEEL then
        begin
              if not FNeedMouseWheel then sendmessage(FHWndParent, message, wParam, lParam);
        end
        else if message = WM_MOUSEMOVE then
        begin
              // actually undock item (the only place to undock) //
              if (not FLockMouseEffect and not FLockDragging and (wParam and MK_LBUTTON <> 0)) or FUndocked then
              begin
                if (abs(pos.x - MouseDownPoint.x) >= 4) or (abs(pos.y - MouseDownPoint.y) >= 4) then
                begin
                  Undock;
                  dockh.Undock(FHWnd);
                  SetWindowPos(FHWnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOSIZE + SWP_NOMOVE + SWP_NOREPOSITION + SWP_NOSENDCHANGING);
                  ReleaseCapture;
                  DefWindowProc(FHWnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
                end;
              end;
              // safety check. dock item if undocked and mouse not pressed //
              if FUndocked and (wParam and MK_LBUTTON = 0) then
              begin
                Dock;
                dockh.Dock(FHWnd);
              end;
        end
        else if message = WM_EXITSIZEMOVE then
        begin
              // dock item (the only place to dock) //
              Dock;
              dockh.Dock(FHWnd);
        end
        else if message = WM_COMMAND then
        begin
              WMCommand(wParam, lParam, Result);
        end
        else if message = WM_TIMER then
        begin
              // mouse held //
              if wParam = ID_TIMER_MOUSEHELD then
              begin
                KillTimer(FHWnd, ID_TIMER_MOUSEHELD);
                GetCursorPos(wpt);
                if WindowFromPoint(wpt) = FHWnd then MouseHeld(FMouseDownButton);
              end;
        end
        else if message = WM_DROPFILES then
        begin
              filecount := DragQueryFile(wParam, $ffffffff, nil, 0);
              GetCursorPos(wpt);
              idx := 0;
              while idx < filecount do
              begin
                windows.dragQueryFile(wParam, idx, pchar(filename), MAX_PATH);
                if ScreenHitTest(wpt.x, wpt.y) then DropFile(FHWnd, wpt, pchar(filename));
                inc(idx);
              end;
        end
        else if (message = WM_CLOSE) or (message = WM_QUIT) then exit;

    end; // end if not FFreed
    if FHWnd <> 0 then
      result := DefWindowProc(FHWnd, message, wParam, lParam);
  except
    on e: Exception do err('CustomItem.WindowProc[ Msg=0x' + inttohex(message, 8) + ' ]', e);
  end;
end;
//------------------------------------------------------------------------------
procedure TCustomItem.err(where: string; e: Exception);
begin
  if assigned(e) then
  begin
    AddLog(where + LineEnding + e.message);
    notify(where + LineEnding + e.message);
  end else begin
    AddLog(where);
    messagebox(FHWnd, PChar(where), declu.PROGRAM_NAME, MB_ICONERROR);
  end;
end;
//------------------------------------------------------------------------------
end.
 
