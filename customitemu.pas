unit customitemu;

{$t+}

interface
uses Windows, Messages, SysUtils, Controls, Classes, ShellAPI, Math, FileUtil,
  declu, dockh, gfx, toolu, loggeru, itemmodelu, docktimingu, attentionu;

const
  anim_bounce: array [0..15] of single = (0, 0.1670, 0.3290, 0.4680, 0.5956, 0.6937, 0.7790, 0.8453, 0.8984, 0.9360, 0.9630, 0.9810, 0.9920, 0.9976, 0.9997, 1);
  MIN_BORDER = 20;
  TDITEM_WCLASS = 'TDockItemWClass';

type

  TOnMouseHover = procedure(param: boolean) of object;
  TOnBeforeMouseHover = procedure(param: boolean) of object;
  TOnBeforeUndock = procedure of object;

  { TCustomItem is an abstract class }
  TCustomItem = class(TItemModel)
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
    FDockingXAnimation, FDockingYAnimation: TSpringAnimation;
    FDragSampleX, FDragSampleY, FDragSampleAt: Double;
    FDragVelocityX, FDragVelocityY: Double;
    FFrameSampling, FFrameRedraw, FFrameForce: boolean;
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
    FAttentionWindows: TAttentionWindows;

    FFont: TDFontData;
    FImage: Pointer;
    FIW: uint; // image width
    FIH: uint; // image height
    FShowItem: uint;
    FItemAnimationType: integer; // animation type
    FAnimationEnd: integer;
    FAnimationProgress: Double; // continuous reference phase
    FIconAnimationActive: boolean;
    FIconAnimation: TScalarAnimation;

    OnMouseHover: TOnMouseHover;
    OnBeforeMouseHover: TOnBeforeMouseHover;
    OnBeforeUndock: TOnBeforeUndock;

    function ClockNow: QWord; virtual;
    function MotionNow: Double; virtual;
    procedure SampleDragPosition;
    function CreateViewWindow: HWND; virtual;
    procedure Init; virtual;
    procedure BeforeDestruction; override;
    procedure Redraw(Force: boolean = true); // updates item appearance
    procedure Attention(value: boolean);
    function RequestAttention(Window: HWND): boolean;
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
    property AttentionPending: boolean read FAttention;
    property Undocked: boolean read FUndocked;
    property Handle: HWND read FHWnd;
    property ParentWindow: HWND read FHWndParent;
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
    function NeedsFrame: boolean; virtual;
    procedure ForegroundChanged(wnd: HWND); virtual;
    procedure Timer; virtual;
    procedure BeginMotionFrame;
    procedure EndMotionFrame;
    function FrameRedrawPending: boolean;
    function TakeFrameDrawForce: boolean;
    procedure SetDockTarget(Ax, Ay: integer);
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
    procedure PrepareDeletion; virtual;
    procedure ViewDestroyed; override;
    procedure RecreateWindow; virtual;
    function  WindowProc(wnd: HWND; message: uint; wParam: WPARAM; lParam: LPARAM): LRESULT;
  end;

implementation
uses itemregistryu, itemhostu, itemviewu, animationclocku;
//------------------------------------------------------------------------------
function CustomItemClassWindowProc(wnd: HWND; message: uint; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall;
var
  inst: TCustomItem;
  registered: TObject;
  scope: TItemHostScope;
  identity: TItemIdentity;
begin
  if message = WM_NCDESTROY then
  begin
    result := DefWindowProc(wnd, message, wParam, lParam);
    try ItemViews.NativeDestroyed(wnd);
    except on E: Exception do AddLog('ItemView.NativeDestroyed' + LineEnding + E.Message); end;
    exit;
  end;
  inst := nil;
  if ItemRegistry.TryGetAny(wnd, registered) and (registered is TCustomItem) then
    inst := TCustomItem(registered);
  identity := ItemRegistry.IdentityOf(wnd);
  if assigned(inst) and ItemRegistry.Pin(identity) then
  begin
    scope := Default(TItemHostScope);
    try
      scope := BeginItemHostOperation(inst.FHWndParent);
      result := inst.WindowProc(wnd, message, wParam, lParam);
    finally
      try ItemRegistry.Unpin(identity);
      finally EndItemHostOperation(scope); end;
    end;
  end
  else
    result := DefWindowProc(wnd, message, wParam, lParam);
end;
//------------------------------------------------------------------------------
constructor TCustomItem.Create(wndParent: HWND; var AParams: TDItemCreateParams);
begin
  inherited Create;
  Init;

  FHWndParent := wndParent;
  ItemViews.AdoptPending(Self, wndParent);
  FHWnd := CreateViewWindow;
  if FHWnd = 0 then raise EOSError.Create('Cannot create item window');
  dockh.ExcludeFromPeek(FHWnd);

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
  try ItemViews.DestroyWindow(FHWnd, ItemId);
  finally
    try ItemViews.CompleteModelCleanup(ItemId);
    finally inherited; end;
  end;
end;
//------------------------------------------------------------------------------
procedure TCustomItem.BeforeDestruction;
begin
  FFreed := true;
  inherited;
end;
//------------------------------------------------------------------------------
function TCustomItem.CreateViewWindow: HWND;
begin
  result := ItemViews.CreateWindow(Self, FHWndParent, TDITEM_WCLASS,
    @CustomItemClassWindowProc, WS_EX_LAYERED or WS_EX_TOOLWINDOW, FX, FY, FSize);
end;

procedure TCustomItem.ViewDestroyed;
begin
  FHWnd := 0;
  FFreed := true;
  inherited;
end;

procedure TCustomItem.RecreateWindow;
var previous, replacement: HWND; visible, enabled: boolean;
  id: TItemId; scope: TItemHostScope;
begin
  if not Pin then exit;
  id := ItemId;
  scope := Default(TItemHostScope);
  try
    scope := BeginItemHostOperation(FHWndParent);
    previous := FHWnd;
    visible := IsWindowVisible(previous);
    enabled := IsWindowEnabled(previous);
    replacement := CreateViewWindow;
    if replacement = 0 then raise EOSError.Create('Cannot recreate item window');
    FHWnd := replacement;
    try
      ItemViews.ReparentChildren(id, replacement);
      ItemViews.RestoreItemTimers(id);
      EnableWindow(replacement, enabled);
      Redraw(true);
      if visible and not FFreed then ShowWindow(replacement, SW_SHOWNOACTIVATE)
      else ShowWindow(replacement, SW_HIDE);
    except
      FHWnd := previous;
      try ItemViews.ReparentChildren(id, previous);
      finally ItemViews.DestroyWindow(replacement, id); end;
      raise;
    end;
    ItemViews.DestroyWindow(previous, id);
  finally
    try ReleaseItemModel(id);
    finally EndItemHostOperation(scope); end;
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
    FDragVelocityX := 0;
    FDragVelocityY := 0;
    FDragSampleAt := -1;
    SampleDragPosition;
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
    SampleDragPosition;
    FUndocked := false;
    need_dock := true;
    wRect := ScreenRect;
    FDockFromX := wRect.Left;
    FDockFromY := wRect.Top;
    FDockingX := FDockFromX;
    FDockingY := FDockFromY;
    FDockingXAnimation.Reset(MotionNow, FDockFromX);
    FDockingYAnimation.Reset(MotionNow, FDockFromY);
    FDockingXAnimation.Retarget(MotionNow, FX, 180);
    FDockingYAnimation.Retarget(MotionNow, FY, 180);
    FDockingXAnimation.StartVelocity := FDragVelocityX;
    FDockingYAnimation.StartVelocity := FDragVelocityY;
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
  if FFrameSampling then
  begin
    FFrameRedraw := true;
    FFrameForce := FFrameForce or Force;
    exit;
  end;
  Draw(FX, FY, FSize, Force, 0, FShowItem);
end;
//------------------------------------------------------------------------------
function TCustomItem.ClockNow: QWord;
begin Result := GetTickCount64; end;

function TCustomItem.MotionNow: Double;
begin Result := AnimationTimeMs; end;

procedure TCustomItem.SampleDragPosition;
var r: Windows.TRect; now, elapsed: Double;
begin
  if not FUndocked or not GetWindowRect(FHWnd, r) then exit;
  now := MotionNow;
  elapsed := now - FDragSampleAt;
  if (FDragSampleAt >= 0) and (elapsed > 0) then
  begin
    if (elapsed <= 100) and ((r.Left <> FDragSampleX) or (r.Top <> FDragSampleY)) then
    begin
      FDragVelocityX := (r.Left - FDragSampleX) * 1000 / elapsed;
      FDragVelocityY := (r.Top - FDragSampleY) * 1000 / elapsed;
    end
    else if elapsed > 100 then
    begin
      FDragVelocityX := 0;
      FDragVelocityY := 0;
    end;
  end;
  FDragSampleX := r.Left;
  FDragSampleY := r.Top;
  FDragSampleAt := now;
end;

procedure TCustomItem.BeginMotionFrame;
begin FFrameSampling := true; end;
procedure TCustomItem.EndMotionFrame;
begin FFrameSampling := false; end;
function TCustomItem.FrameRedrawPending: boolean;
begin Result := FFrameRedraw; end;
function TCustomItem.TakeFrameDrawForce: boolean;
begin
  Result := FFrameForce;
  FFrameForce := false;
  FFrameRedraw := false;
end;

procedure TCustomItem.SetDockTarget(Ax, Ay: integer);
var now: Double;
begin
  if not need_dock then exit;
  now := MotionNow;
  if FDockingXAnimation.TargetValue <> Ax then
    FDockingXAnimation.Retarget(now, Ax, 180);
  if FDockingYAnimation.TargetValue <> Ay then
    FDockingYAnimation.Retarget(now, Ay, 180);
  FDockingX := Round(FDockingXAnimation.ValueAt(now));
  FDockingY := Round(FDockingYAnimation.ValueAt(now));
end;

procedure TCustomItem.ForegroundChanged(wnd: HWND);
begin
  if FFreed then Exit;
  FAttentionWindows.Observe(wnd);
  Attention(FAttentionWindows.Active);
end;

function TCustomItem.NeedsFrame: boolean;
begin
  Result := not FFreed and not FUpdating and
    (need_dock or FIconAnimationActive or FFrameRedraw);
end;

procedure TCustomItem.Timer;
var now, nextProgress: Double; redrawPosition, redrawImage: boolean;
begin
  if FFreed or FUpdating then exit;
  now := MotionNow;
  redrawPosition := false;
  redrawImage := false;
  // docking after item dropped onto dock //
  if need_dock then
  begin
    SetDockTarget(FX, FY);
    redrawPosition := true;
    if not FDockingXAnimation.ActiveAt(now) and not FDockingYAnimation.ActiveAt(now) then
    begin
      need_dock := false;
      redrawImage := true;
    end;
  end;
  if FIconAnimationActive then
  begin
    nextProgress := FIconAnimation.ValueAt(now);
    if not FIconAnimation.ActiveAt(now) then
    begin
      nextProgress := 0;
      FIconAnimationActive := false;
    end;
    if nextProgress <> FAnimationProgress then
    begin
      FAnimationProgress := nextProgress;
      redrawImage := true;
    end;
  end;
  if redrawPosition or redrawImage then Redraw(redrawImage);
end;
//------------------------------------------------------------------------------
procedure TCustomItem.Attention(value: boolean);
begin
  if FAttention <> value then
  begin
    FAttention := value;
    Redraw;
  end;
  if FAttention then ItemViews.SetItemTimer(ItemId, ID_TIMER_WINDOWACTIVATED, 1000)
  else ItemViews.KillItemTimer(ItemId, ID_TIMER_WINDOWACTIVATED);
end;

function TCustomItem.RequestAttention(Window: HWND): boolean;
begin
  Result := FAttentionWindows.Request(Window, GetForegroundWindow);
  Attention(FAttentionWindows.Active);
  if Result then Animate;
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
    if button = mbLeft then ItemViews.SetItemTimer(ItemId, ID_TIMER_MOUSEHELD, 1000)
    else ItemViews.SetItemTimer(ItemId, ID_TIMER_MOUSEHELD, 800);
    cmd(icSelect, 1);
  end;
end;
//------------------------------------------------------------------------------
function TCustomItem.MouseUp(button: TMouseButton; shift: TShiftState; x, y: integer): boolean;
begin
  result := not FFreed;
  ItemViews.KillItemTimer(ItemId, ID_TIMER_MOUSEHELD);
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
    if not FHover then ItemViews.KillItemTimer(ItemId, ID_TIMER_MOUSEHELD);
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
// item rect in screen coordinates
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
  FAnimationEnd := 0;
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
  if FAnimationEnd = 0 then
  begin
    FAnimationProgress := 0;
    FIconAnimationActive := false;
    exit;
  end;
  FAnimationProgress := 0;
  FIconAnimationActive := true;
  FIconAnimation.StartValue := 0;
  FIconAnimation.TargetValue := FAnimationEnd;
  FIconAnimation.StartedAt := MotionNow;
  FIconAnimation.DurationMs := FAnimationEnd * 15.625;
end;
//------------------------------------------------------------------------------
procedure TCustomItem.LME(lock: boolean);
var services: TItemHostServices; scope: TItemHostScope;
begin
  scope := BeginItemHostOperation(FHWndParent);
  try
    if TryGetItemHost(FHWndParent, services) and assigned(services.OnLockMouseEffect) then
      services.OnLockMouseEffect(FHWnd, lock)
    else dockh.DockletLockMouseEffect(FHWnd, lock);
  finally
    EndItemHostOperation(scope);
  end;
end;
//------------------------------------------------------------------------------
procedure TCustomItem.Delete;
var services: TItemHostServices; scope: TItemHostScope;
begin
  scope := BeginItemHostOperation(FHWndParent);
  try
    FFreed := true;
    ShowWindow(FHWnd, SW_HIDE);
    if TryGetItemHost(FHWndParent, services) and assigned(services.OnDelete) then
      services.OnDelete(FHWnd)
    else dockh.DockDeleteItem(FHWnd);
  finally
    EndItemHostOperation(scope);
  end;
end;

procedure TCustomItem.PrepareDeletion;
begin
  try
    if FHintVisible then dockh.DeactivateHint(FHWnd);
  finally
    FHintVisible := false;
    FHover := false;
    FSelected := false;
    FAttention := false;
    FAttentionWindows.Clear;
    FAnimationProgress := 0;
    FIconAnimationActive := false;
    FIconAnimation := Default(TScalarAnimation);
    FFrameRedraw := false;
    FFrameForce := false;
    need_dock := false;
    ItemViews.CancelInternalTimers(ItemId);
  end;
end;
//------------------------------------------------------------------------------
procedure TCustomItem.notify(message: string);
var services: TItemHostServices; scope: TItemHostScope;
begin
  scope := BeginItemHostOperation(FHWndParent);
  try
    if TryGetItemHost(FHWndParent, services) and assigned(services.OnNotify) then
      services.OnNotify(UTF8Decode(message), false)
    else dockh.notify(FHWnd, pchar(message));
  finally
    EndItemHostOperation(scope);
  end;
end;
//------------------------------------------------------------------------------
function TCustomItem.WindowProc(wnd: HWND; message: uint; wParam: WPARAM; lParam: LPARAM): LRESULT;
var
  idx: integer;
  ShiftState: classes.TShiftState;
  pos: windows.TSmallPoint;
  wpt: windows.TPoint;
  msg: TMessage;
  services: TItemHostServices;
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
                  if TryGetItemHost(FHWndParent, services) and assigned(services.OnUndock) then
                    services.OnUndock(FHWnd)
                  else dockh.Undock(FHWnd);
                  SetWindowPos(FHWnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOSIZE + SWP_NOMOVE + SWP_NOREPOSITION + SWP_NOSENDCHANGING);
                  ReleaseCapture;
                  DefWindowProc(FHWnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
                end;
              end;
              // safety check. dock item if undocked and mouse not pressed //
              if FUndocked and (wParam and MK_LBUTTON = 0) then
              begin
                Dock;
                if TryGetItemHost(FHWndParent, services) and assigned(services.OnDock) then
                  services.OnDock(FHWnd)
                else dockh.Dock(FHWnd);
              end;
        end
        else if message = WM_MOVE then
        begin
              SampleDragPosition;
        end
        else if message = WM_EXITSIZEMOVE then
        begin
              // dock item (the only place to dock) //
              Dock;
                if TryGetItemHost(FHWndParent, services) and assigned(services.OnDock) then
                  services.OnDock(FHWnd)
                else dockh.Dock(FHWnd);
        end
        else if message = WM_COMMAND then
        begin
              WMCommand(wParam, lParam, Result);
        end
        else if message = WM_TIMER then
        begin
              if (wParam = ID_TIMER_WINDOWACTIVATED) and
                ItemViews.ConsumeItemTimer(ItemId, ID_TIMER_WINDOWACTIVATED, ClockNow) then
                ForegroundChanged(GetForegroundWindow);
              // mouse held //
              if (wParam = ID_TIMER_MOUSEHELD) and
                ItemViews.ConsumeItemTimer(ItemId, ID_TIMER_MOUSEHELD, ClockNow) then
              begin
                ItemViews.KillItemTimer(ItemId, ID_TIMER_MOUSEHELD);
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
 
