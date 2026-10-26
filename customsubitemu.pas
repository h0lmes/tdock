unit customsubitemu;

{$t+}

interface
uses Windows, Messages, SysUtils, Controls, Classes, Math, ComObj,
  GDIPAPI, gfx, PIDL, declu, dockh, customitemu, loggeru, itemmodelu;

const
  MIN_BORDER = 8;
  BGMARGIN = 3;
  MAX_CAPTION_LENGTH = 32;
  TDSUBITEM_WCLASS = 'TDockSubItemWClass';

type

  { TCustomSubitem is an abstract class }

  TCustomSubitem = class(TItemModel)
  protected
    FFreed: boolean;
    FHWnd: HWND;
    FInitialParent: HWND;
    FHMenu: THandle;
    FCaption: WideString;
    FCaptionWidth: integer;
    FCaptionHeight: integer;
    Fx: integer;
    Fy: integer;
    FSize: integer;
    FAngle: single;
    FAlpha: integer;
    FHintAlign: integer;
    FHintAlpha: integer;
    FBackground: boolean;
    FQueryDelete: boolean;
    FFont: TDFontData;
    FIsExecutable: boolean;
    FExecutable: WideString;

    FEnabled: boolean;
    FUpdating: boolean;
    FSelected: boolean; // when mouse button is down - icon becomes darken //
    FRunning: boolean;
    FProcessWindowsCount: integer;
    FShowHint: boolean;
    FSite: integer;
    FItemSize: integer;
    FLaunchInterval: integer;
    FActivateRunning: boolean;
    MouseDownPoint: windows.TPoint;
    FMouseDownButton: TMouseButton;
    FLockDragging: boolean;

    FImage: Pointer;
    FIW: uint; // image width
    FIH: uint; // image height

    function GetParentWindow: HWND;
    property FHWndParent: HWND read GetParentWindow;
    function CreateViewWindow: HWND; virtual;
    procedure BeforeDestruction; override;
    procedure Init; virtual;
    procedure Redraw;
    function GetNCRect: windows.TRect;
    function GetClientRect: windows.TRect;
    function GetScreenRect: windows.TRect;
    procedure CloseStack;
    procedure UpdateCaptionExtent;
    procedure err(where: string; e: Exception);
  public
    property Freed: boolean read FFreed write FFreed;
    property Handle: HWND read FHWnd;
    property Caption: WideString read FCaption write FCaption;
    property X: integer read Fx;
    property Y: integer read Fy;
    property Size: integer read FSize;
    property Rect: windows.TRect read GetClientRect;
    property ScreenRect: windows.TRect read GetScreenRect;
    property Running: boolean read FRunning;
    property WindowCount: integer read FProcessWindowsCount;
    property QueryDelete: boolean read FQueryDelete;
    property Image: pointer read FImage;
    property ImageW: uint read FIW;
    property ImageH: uint read FIH;

    function HitTest(Ax, Ay: integer): boolean; virtual;
    function ScreenHitTest(Ax, Ay: integer): boolean;
    procedure SetFont(var Value: TDFontData);

    constructor Create(wndParent: HWND; AParams: TDItemCreateParams); virtual;
    destructor Destroy; override;
    procedure FromString(data: string); virtual; abstract;
    procedure HideItem; virtual;
    procedure Draw(Ax, Ay, ASize: integer; AAlpha: integer; AAngle: single;
      AHintAlign: integer; AHintAlpha: integer; ABackground, AForce: boolean); virtual; abstract;
    procedure DrawPreview(graphics: Pointer; Ax, Ay, ASize: integer); virtual; abstract;
    function ToString: string; override;
    procedure MouseDown(button: TMouseButton; shift: TShiftState; x, y: integer); virtual;
    function MouseUp(button: TMouseButton; shift: TShiftState; x, y: integer): boolean; virtual;
    procedure MouseHeld(button: TMouseButton); virtual;
    procedure WMCommand(wParam: WPARAM; lParam: LPARAM; var result: LRESULT); virtual; abstract;
    procedure Configure; virtual; abstract;
    function cmd(id: TDParam; param: PtrInt): PtrInt; virtual;
    function CanOpenFolder: boolean; virtual; abstract;
    procedure OpenFolder; virtual; abstract;
    function DropFile(pt: windows.TPoint; filename: string): boolean; virtual; abstract;
    procedure Delete(AllowUndo: boolean = true); virtual;
    procedure BeginDrag; virtual;
    procedure ViewDestroyed; override;
    function WindowProc(wnd: HWND; message: uint; wParam: WPARAM; lParam: LPARAM): LRESULT;
  end;


implementation
uses itemregistryu, itemhostu, itemviewu;
//------------------------------------------------------------------------------
function CustomSubitemClassWindowProc(wnd: HWND; message: uint; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall;
var
  inst: TCustomSubitem;
  registered, owner: TObject;
  identity, ownerIdentity: TItemIdentity;
  scope: TItemHostScope;
begin
  if message = WM_NCDESTROY then
  begin
    result := DefWindowProc(wnd, message, wParam, lParam);
    try ItemViews.NativeDestroyed(wnd);
    except on E: Exception do AddLog('SubitemView.NativeDestroyed' + LineEnding + E.Message); end;
    exit;
  end;
  if not ItemRegistry.TryGetAny(wnd, registered) or
    not (registered is TCustomSubitem) then
    exit(DefWindowProc(wnd, message, wParam, lParam));
  inst := TCustomSubitem(registered);
  if not ItemRegistry.TryGetAny(inst.FHWndParent, owner) or
    not (owner is TCustomItem) then
    exit(DefWindowProc(wnd, message, wParam, lParam));
  ownerIdentity := ItemRegistry.IdentityOf(inst.FHWndParent);
  if not ItemRegistry.Pin(ownerIdentity) then
    exit(DefWindowProc(wnd, message, wParam, lParam));
  identity := ItemRegistry.IdentityOf(wnd);
  if not ItemRegistry.Pin(identity) then
  begin
    ItemRegistry.Unpin(ownerIdentity);
    exit(DefWindowProc(wnd, message, wParam, lParam));
  end;
  scope := Default(TItemHostScope);
  try
    scope := BeginItemHostOperation(TCustomItem(owner).ParentWindow);
    result := inst.WindowProc(wnd, message, wParam, lParam);
  finally
    try ItemRegistry.Unpin(identity);
    finally
      try ItemRegistry.Unpin(ownerIdentity);
      finally EndItemHostOperation(scope); end;
    end;
  end;
end;
//------------------------------------------------------------------------------
constructor TCustomSubitem.Create(wndParent: HWND; AParams: TDItemCreateParams);
begin
  inherited Create;
  Init;

  FInitialParent := wndParent;
  ItemViews.AdoptPending(Self, wndParent, true);
  FHWnd := CreateViewWindow;
  if FHWnd = 0 then raise EOSError.Create('Cannot create subitem window');

  FItemSize        := AParams.ItemSize;
  FLaunchInterval  := AParams.LaunchInterval;
  FActivateRunning := AParams.ActivateRunning;
  FSite            := AParams.Site;
  FShowHint        := AParams.ShowHint;
  FLockDragging    := AParams.LockDragging;
  CopyFontData(AParams.Font, FFont);
end;
//------------------------------------------------------------------------------
procedure TCustomSubitem.BeforeDestruction;
begin
  FFreed := true;
  inherited;
end;
//------------------------------------------------------------------------------
destructor TCustomSubitem.Destroy;
begin
  try ItemViews.DestroyWindow(FHWnd, ItemId);
  finally
    try ItemViews.CompleteModelCleanup(ItemId);
    finally inherited; end;
  end;
end;
//------------------------------------------------------------------------------
function TCustomSubitem.CreateViewWindow: HWND;
begin
  result := ItemViews.CreateWindow(Self, FHWndParent, TDSUBITEM_WCLASS,
    @CustomSubitemClassWindowProc, WS_EX_LAYERED or WS_EX_TOOLWINDOW or WS_EX_ACCEPTFILES,
    FX, FY, FSize);
end;
//------------------------------------------------------------------------------
function TCustomSubitem.GetParentWindow: HWND;
begin
  if ParentItemId = NO_ITEM_ID then Result := FInitialParent
  else Result := ItemViews.HandleOf(ParentItemId);
end;

procedure TCustomSubitem.ViewDestroyed;
begin
  FHWnd := 0;
  FFreed := true;
  inherited;
end;
//------------------------------------------------------------------------------
procedure TCustomSubitem.Init;
begin
  FFreed := false;
  FQueryDelete := false;
  FEnabled := true;
  FHWnd := 0;
  FCaption := '';
  Fx := -9999;
  Fy := -9999;
  FSize := 32;
  FCaption := '';
  FUpdating := false;
  FSelected := false;
  FRunning := false;
  FProcessWindowsCount := 0;
  FShowHint := true;
  FSite := 3;
  FItemSize := 32;
  FImage := nil;
  FIW := 32;
  FIH := 32;
end;
//------------------------------------------------------------------------------
procedure TCustomSubitem.HideItem;
var
  bmp: _SimpleBitmap;
  ClientRect: windows.TRect;
begin
  FSelected := false;
  ClientRect := GetClientRect;
  bmp.topleft.x := Fx - FSize div 2 - ClientRect.Left;
  bmp.topleft.y := Fy - FSize div 2 - ClientRect.Top;
  bmp.width := 1;
  bmp.height := 1;
  if not CreateBitmap(bmp, FHWnd) then exit;
  UpdateLWindow(FHWnd, bmp, FAlpha);
  DeleteBitmap(bmp);
end;
//------------------------------------------------------------------------------
procedure TCustomSubitem.Redraw;
begin
  if IsWindowVisible(FHWnd) then Draw(Fx, Fy, FSize, 255, FAngle, FHintAlign, FHintAlpha, FBackground, true);
end;
//------------------------------------------------------------------------------
function TCustomSubitem.cmd(id: TDParam; param: PtrInt): PtrInt;
begin
  result := 0;
  try
    case id of
      // parameters //
      gpItemSize: FItemSize := param;
      gpSite: FSite := param;
      gpShowHint: FShowHint := boolean(param);
      gpLaunchInterval: FLaunchInterval := param;
      gpActivateRunning: FActivateRunning := boolean(param);
      gpLockDragging: FLockDragging := param <> 0;

      // commands //

      icSelect:
        if FSelected <> boolean(param) then
        begin
          FSelected := boolean(param);
          if IsWindowVisible(FHwnd) then Redraw;
        end;
    end;

  except
    on e: Exception do raise Exception.Create('TCustomSubitem.Cmd ' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------
function TCustomSubitem.ToString: string;
begin
  result := '';
end;
//------------------------------------------------------------------------------
procedure TCustomSubitem.MouseDown(button: TMouseButton; shift: TShiftState; x, y: integer);
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
function TCustomSubitem.MouseUp(button: TMouseButton; shift: TShiftState; x, y: integer): boolean;
begin
  ItemViews.KillItemTimer(ItemId, ID_TIMER_MOUSEHELD);
  result := not FFreed;
end;
//------------------------------------------------------------------------------
procedure TCustomSubitem.MouseHeld(button: TMouseButton);
begin
  FSelected := false;
  if button = mbLeft then BeginDrag;
end;
//------------------------------------------------------------------------------
// item window rect in client coordinates
function TCustomSubitem.GetNCRect: windows.TRect;
var
  Border: integer;
begin
  Border := FCaptionWidth + FCaptionHeight + MIN_BORDER;
  result.Left   := 0;
  result.Top    := 0;
  result.Right  := Border + FSize + Border;
  result.Bottom := Border + FSize + Border;
end;
//------------------------------------------------------------------------------
// item rect in client coordinates
function TCustomSubitem.GetClientRect: windows.TRect;
var
  Border: integer;
begin
  Border := FCaptionWidth + FCaptionHeight + MIN_BORDER;
  result.Left   := Border;
  result.Top    := Border;
  result.Right  := Border + FSize;
  result.Bottom := Border + FSize;
end;
//------------------------------------------------------------------------------
// item rect in screen coordinates
function TCustomSubitem.GetScreenRect: windows.TRect;
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
function TCustomSubitem.HitTest(Ax, Ay: integer): boolean;
begin
  result := ptinrect(GetClientRect, classes.Point(Ax, Ay));
end;
//------------------------------------------------------------------------------
function TCustomSubitem.ScreenHitTest(Ax, Ay: integer): boolean;
begin
  result := ptinrect(GetScreenRect, classes.Point(Ax, Ay));
end;
//------------------------------------------------------------------------------
procedure TCustomSubitem.CloseStack;
begin
  sendmessage(FHWndParent, WM_ACTIVATE, 0, 0);
end;
//------------------------------------------------------------------------------
procedure TCustomSubitem.Delete(AllowUndo: boolean = true);
var
  wnd: THandle;
  Inst: TCustomItem;
  registered: TObject;
  identity: TItemIdentity;
  pt: windows.TPoint;
  deleted: boolean;
begin
  if FFreed or FQueryDelete then exit;
  if AllowUndo then
  begin
    wnd := dockh.DockCreateItem(pchar(ToString));
    identity := ItemRegistry.IdentityOf(wnd);
    if not ItemRegistry.TryGetAny(wnd, registered) or not (registered is TCustomItem)
      or not ItemRegistry.Pin(identity) then exit;
    Inst := TCustomItem(registered);
    deleted := false;
    try
      GetCursorPos(pt);
      Inst.Draw(pt.x - Inst.Size div 2, pt.y - Inst.Size div 2, FSize, true, 0, SWP_SHOWWINDOW);
      SetWindowPos(wnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE + SWP_NOSIZE + SWP_NOACTIVATE + SWP_NOREPOSITION + SWP_SHOWWINDOW);
      Inst.Dock;
      Inst.Delete;
      deleted := Inst.State = imsDeleted;
    finally
      try
        if not deleted and (Inst.State = imsPending) then Inst.Free;
      finally ItemRegistry.Unpin(identity); end;
    end;
    if not deleted then exit;
  end;
  FQueryDelete := true;
  ItemViews.CancelInternalTimers(ItemId);
  ShowWindow(FHWnd, SW_HIDE);
end;
//------------------------------------------------------------------------------
procedure TCustomSubitem.BeginDrag;
var
  wnd: THandle;
  Inst: TCustomItem;
  registered: TObject;
  identity: TItemIdentity;
  pt: windows.TPoint;
  adopted: boolean;
begin
  if FFreed or FQueryDelete then exit;
  wnd := dockh.DockCreateItem(pchar(ToString));
  identity := ItemRegistry.IdentityOf(wnd);
  if not ItemRegistry.TryGetAny(wnd, registered) or not (registered is TCustomItem)
    or not ItemRegistry.Pin(identity) then exit;
  Inst := TCustomItem(registered);
  adopted := false;
  try
    GetCursorPos(pt);
    Inst.Draw(pt.x - Inst.Size div 2, pt.y - Inst.Size div 2, FSize, true, 0, SWP_SHOWWINDOW);
    SetWindowPos(wnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE + SWP_NOSIZE + SWP_NOACTIVATE + SWP_NOREPOSITION + SWP_SHOWWINDOW);
    Inst.Undock;
    dockh.Undock(wnd);
    adopted := Inst.State = imsDragging;
    if adopted then Delete(false);
  finally
    try
      if not adopted and (Inst.State = imsPending) then Inst.Free;
    finally ItemRegistry.Unpin(identity); end;
  end;
end;
//------------------------------------------------------------------------------
procedure TCustomSubitem.SetFont(var Value: TDFontData);
begin
  CopyFontData(Value, FFont);
  UpdateCaptionExtent;
end;
//------------------------------------------------------------------------------
procedure TCustomSubitem.UpdateCaptionExtent;
var
  hgdip, font, ff: Pointer;
  rect: TRectF;
  dc: HDC;
  DisplayableCaption: WideString;
begin
  FCaptionWidth := 0;
  FCaptionHeight := 0;
  if FShowHint and (length(FCaption) > 0) then
  begin
    DisplayableCaption := copy(FCaption, 1, min(length(FCaption), MAX_CAPTION_LENGTH));

    dc := CreateCompatibleDC(0);
    if dc = 0 then raise Exception.Create('CustomSubitem.UpdateCaptionExtent.CreateCompatibleDC failed');
    try
      GdipCreateFromHDC(dc, hgdip);
      try
        if Ok <> GdipCreateFontFamilyFromName(PWideChar(WideString(PChar(@FFont.Name))), nil, ff) then
          raise Exception.Create('CustomSubitem.UpdateCaptionExtent.CreateFontFamily failed');
        try
          if Ok <> GdipCreateFont(ff, FFont.size2, integer(FFont.bold) + integer(FFont.italic) * 2, 2, font) then
            raise Exception.Create('CustomSubitem.UpdateCaptionExtent.CreateFont failed');
          try
            rect.x := 0;
            rect.y := 0;
            rect.Width := 0;
            rect.Height := 0;
            GdipMeasureString(hgdip, PWideChar(DisplayableCaption), -1, font, @rect, nil, @rect, nil, nil);
          finally
            GdipDeleteFont(font);
          end;
        finally
          GdipDeleteFontFamily(ff);
        end;
      finally
        GdipDeleteGraphics(hgdip);
      end;
    finally
      DeleteDC(dc);
    end;
    FCaptionWidth := ceil(rect.Width);
    FCaptionHeight := ceil(rect.Height);
  end;
end;
//------------------------------------------------------------------------------
function TCustomSubitem.WindowProc(wnd: HWND; message: uint; wParam: WPARAM; lParam: LPARAM): LRESULT;
var
  pos: TSmallPoint;
  wpt: windows.TPoint;
  ShiftState: TShiftState;
begin
  try
      result := 0;
      pos := TSmallPoint(DWORD(lParam));
      ShiftState := [];
      if wParam and MK_SHIFT <> 0 then Include(ShiftState, ssShift);
      if wParam and MK_CONTROL <> 0 then Include(ShiftState, ssCtrl);

      if message = WM_LBUTTONDOWN then
      begin
            SetActiveWindow(FHWndParent);
            MouseDownPoint.x:= pos.x;
            MouseDownPoint.y:= pos.y;
            if HitTest(pos.x, pos.y) then MouseDown(mbLeft, ShiftState, pos.x, pos.y);
      end
      else if message = WM_RBUTTONDOWN then
      begin
            SetActiveWindow(FHWndParent);
            MouseDownPoint.x:= pos.x;
            MouseDownPoint.y:= pos.y;
            if HitTest(pos.x, pos.y) then MouseDown(mbRight, ShiftState, pos.x, pos.y);
      end
      else if message = WM_MBUTTONDOWN then
      begin
            SetActiveWindow(FHWndParent);
      end
      else if message = WM_LBUTTONUP then
      begin
            if HitTest(pos.x, pos.y) then MouseUp(mbLeft, ShiftState, pos.x, pos.y);
      end
      else if message = WM_RBUTTONUP then
      begin
            if HitTest(pos.x, pos.y) then MouseUp(mbRight, ShiftState, pos.x, pos.y);
      end
      else if message = WM_MOUSEMOVE then
      begin
            if not FLockDragging and (wParam and MK_LBUTTON <> 0) then
            begin
              if (abs(pos.x - MouseDownPoint.x) >= 4) or (abs(pos.y - MouseDownPoint.y) >= 4) then BeginDrag;
            end;
      end
      else if message = WM_COMMAND then
      begin
            WMCommand(wParam, lParam, result);
      end
      else if message = WM_TIMER then
      begin
            if (wParam = ID_TIMER_MOUSEHELD) and
              ItemViews.ConsumeItemTimer(ItemId, ID_TIMER_MOUSEHELD, GetTickCount64) then
            begin
              ItemViews.KillItemTimer(ItemId, ID_TIMER_MOUSEHELD);
              GetCursorPos(wpt);
              if WindowFromPoint(wpt) = FHWnd then MouseHeld(FMouseDownButton);
            end;
      end
      else if (message = WM_CLOSE) or (message = WM_QUIT) then exit;

  except
    on e: Exception do err('CustomSubitem.WindowProc[ Msg=0x' + inttohex(message, 8) + ' ]', e);
  end;

  result := DefWindowProc(wnd, message, wParam, lParam);
end;
//------------------------------------------------------------------------------
procedure TCustomSubitem.err(where: string; e: Exception);
begin
  if assigned(e) then
  begin
    AddLog(where + LineEnding + e.message);
  end else begin
    AddLog(where);
  end;
end;
//------------------------------------------------------------------------------
end.

