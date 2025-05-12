unit hintu;

interface

uses Windows, Messages, SysUtils, Forms, Math,
  declu, toolu, GDIPAPI, gfx, setsu, dockh;

const
  TDHINT_WCLASS = 'TDockHintWClass';

type
  THint = class
  private
    wndClass: TWndClass;
    FHWnd: THandle;
    FHWndOwner: THandle;
    FSite: TBaseSite;
    FActivating: boolean;
    FVisible: boolean;
    FCaption: WideString;
    FFont: TDFontData;
    FAlpha: integer;
    FAlphaTarget: integer;
    FX: integer;
    FY: integer;
    FW: integer;
    FH: integer;
    FXTarget: integer;
    FYTarget: integer;
    FWTarget: integer;
    FHTarget: integer;
    FBorder: integer;
    procedure err(where: string; e: Exception);
    procedure Paint;
  public
    constructor Create;
    destructor Destroy; override;
    function GetMonitorRect(monitor: integer): Windows.TRect;
    procedure ActivateHint(hwndOwner: HWND; ACaption: WideString; x, y: integer; monitor: THandle; ASite: TBaseSite);
    procedure DeactivateHint(hwndOwner: HWND);
    procedure DeactivateImmediate;
    procedure Timer;
  end;

implementation
//------------------------------------------------------------------------------
function WndProc(wnd: HWND; message: uint; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall;
var
  objHint: THint;
begin
  if message = WM_NCHITTEST then
  begin
    result := HTTRANSPARENT;
    exit;
  end
  else if (message = WM_TIMER) and (wParam = ID_TIMER) then
  begin
    objHint := THint(GetWindowLongPtr(wnd, GWL_USERDATA));
    if objHint is THint then objHint.Timer;
    exit;
  end;
  Result := DefWindowProc(wnd, message, wParam, lParam);
end;
//------------------------------------------------------------------------------
procedure THint.err(where: string; e: Exception);
begin
  if assigned(e) then dockh.notify(0, pchar(where + LineEnding + e.message))
  else dockh.notify(0, pchar(where));
end;
//------------------------------------------------------------------------------
constructor THint.Create;
begin
  StrCopy(@FFont.Name[0], PChar(GetFont));
  FFont.size := GetfontSize;
  FFont.color := $ffffffff;
  FAlpha := 0;
  FVisible := False;

  try
    wndClass.style          := 0;
    wndClass.lpfnWndProc    := @WndProc;
    wndClass.cbClsExtra     := 0;
    wndClass.cbWndExtra     := 0;
    wndClass.hInstance      := hInstance;
    wndClass.hIcon          := 0;
    wndClass.hCursor        := LoadCursor(0, IDC_ARROW);
    wndClass.hbrBackground  := 0;
    wndClass.lpszMenuName   := nil;
    wndClass.lpszClassName  := TDHINT_WCLASS;
    windows.RegisterClass(wndClass);
  except
    on e: Exception do
    begin
      err('Hint.Create.RegisterClass', e);
      exit;
    end;
  end;

  try
    FHWnd := CreateWindowEx(ws_ex_layered or ws_ex_toolwindow, TDHINT_WCLASS, nil, ws_popup, 0, 0, 0, 0, 0, 0, hInstance, nil);
    if IsWindow(FHWnd) then SetWindowLongPtr(FHWnd, GWL_USERDATA, PtrUInt(self))
    else err('Hint.Create.CreateWindowEx failed', nil);
  except
    on e: Exception do err('Hint.Create.CreateWindowEx', e);
  end;
end;
//------------------------------------------------------------------------------
destructor THint.Destroy;
begin
  DestroyWindow(FHWnd);
end;
//------------------------------------------------------------------------------
function THint.GetMonitorRect(monitor: integer): Windows.TRect;
begin
  result.Left := 0;
  result.Top := 0;
  result.Right := screen.Width;
  result.Bottom := screen.Height;
  if monitor >= screen.MonitorCount then monitor := screen.MonitorCount - 1;
  if monitor >= 0 then Result := screen.Monitors[monitor].WorkareaRect;
end;
//------------------------------------------------------------------------------
procedure THint.ActivateHint(hwndOwner: HWND; ACaption: WideString; x, y: integer; monitor: THandle; ASite: TBaseSite);
var
  wdc, dc: THandle;
  dst, font, family: Pointer;
  awidth, aheight: integer;
  rect: TRectF;
  workArea: Windows.TRect;
  monInfo: MONITORINFO;
begin
  if IsWindow(FHWnd) then
  try
    FActivating := True;
    try
      FHWndOwner := hwndOwner;
      FSite := ASite;
      FCaption := ACaption;
      CopyFontData(sets.container.Font, FFont);
      FBorder := 7;

      // measure string //
      wdc := GetDC(FHWnd);
      dc := CreateCompatibleDC(wdc);
      ReleaseDC(FHWnd, wdc);
      if dc = 0 then raise Exception.Create('Hint.ActivateHint.CreateCompatibleDC failed');
      GdipCreateFromHDC(dc, dst);
      GdipCreateFontFamilyFromName(PWideChar(WideString(PChar(@FFont.Name))), nil, family);
      GdipCreateFont(family, FFont.size, integer(FFont.bold) + integer(FFont.italic) * 2, 2, font);
      rect.x := 0;
      rect.y := 0;
      rect.Width := 0;
      rect.Height := 0;
      GdipMeasureString(dst, PWideChar(FCaption), -1, font, @rect, nil, @rect, nil, nil);
      GdipDeleteGraphics(dst);
      DeleteDC(dc);
      GdipDeleteFont(font);
      GdipDeleteFontFamily(family);

      // calc hint dimensions and position //
      aheight := round(rect.Height) + 2;
      awidth := round(rect.Width) + aheight div 2 + 1;
      awidth := max(awidth, aheight);

      if ASite = bsLeft then dec(y, aheight div 2)
      else if ASite = bsTop then dec(x, awidth div 2)
      else if ASite = bsRight then
      begin
        dec(y, aheight div 2);
        dec(x, awidth);
      end else
      begin
        dec(y, aheight);
        dec(x, awidth div 2);
      end;

      monInfo.cbSize := sizeof(MONITORINFO);
      GetMonitorInfoA(monitor, @monInfo);
      workArea := monInfo.rcWork;
      if x + awidth > workArea.right then x := workArea.right - awidth;
      if y + aheight > workArea.Bottom then y := workArea.Bottom - aheight;
      if x < workArea.left then x := workArea.left;
      if y < workArea.top then y := workArea.top;

      FAlphaTarget := 255;
      FXTarget := x;
      FYTarget := y;
      FWTarget := awidth;
      FHTarget := aheight;
      if not sets.container.HintEffects then
      begin
        FAlpha := 255;
        FX := x;
        FY := y;
        FW := awidth;
        FH := aheight;
      end else if not FVisible and (FAlpha = 0) then
      begin
        FAlpha := 0;
        FX := x;
        FY := y;
        FW := awidth;
        FH := aheight;
        {if (FSite = bsTop) or (FSite = bsBottom) then
        begin
          FW := 10;
          FX := FXTarget + (FWTarget - 10) div 2;
        end else begin
          FH := 10;
          FY := FYTarget + (FHTarget - 10) div 2;
        end;}
      end else begin
        if (ASite = bsTop) or (ASite = bsBottom) then
        begin
          FY := y;
          FH := aheight;
        end else begin
          FX := x;
          FW := awidth;
        end;
      end;
    except
      on e: Exception do
      begin
        err('Hint.ActivateHint.Precalc', e);
        FActivating := False;
        exit;
      end;
    end;

    try
      Paint;
      if not FVisible and sets.container.HintEffects then SetTimer(FHWnd, ID_TIMER, 10, nil);
      FVisible := True;
    except
      on e: Exception do
      begin
        err('Hint.ActivateHint.Fin', e);
        FActivating := False;
        exit;
      end;
    end;
  finally
    FActivating := False;
  end;
end;
//------------------------------------------------------------------------------
procedure THint.Paint;
var
  dst, font, family, brush, path: Pointer;
  rect: TRectF;
  bmp: _SimpleBitmap;
  points: array [0..3] of GDIPAPI.TPoint;
begin
    // background //
    try
      bmp.topleft.x := FX - FBorder;
      bmp.topleft.y := FY - FBorder;
      bmp.Width := FW + FBorder * 2;
      bmp.Height := FH + FBorder * 2;
      if not gfx.CreateBitmap(bmp, FHWnd) then exit;
      GdipCreateFromHDC(bmp.dc, dst);
      if not assigned(dst) then
      begin
        DeleteBitmap(bmp);
        exit;
      end;
      GdipGraphicsClear(dst, 0);
      GdipSetSmoothingMode(dst, SmoothingModeAntiAlias);
      GdipSetTextRenderingHint(dst, TextRenderingHintAntiAlias);
      GdipTranslateWorldTransform(dst, FBorder, FBorder, MatrixOrderPrepend);
      // compose path
      GdipCreatePath(FillModeWinding, path);
      points[0].x := 0;
      points[0].y := 0;
      points[1].x := FW;
      points[1].y := 0;
      points[2].x := FW;
      points[2].y := FH;
      points[3].x := 0;
      points[3].y := FH;
      GdipAddPathClosedCurve2I(path, points, 4, 15 / FW);
      // fill
      GdipCreateSolidFill($ff000000 + FFont.backcolor and $ffffff, brush);
      GdipFillPath(dst, brush, path);
      GdipDeleteBrush(brush);
      GdipDeletePath(path);
    except
      on e: Exception do raise Exception.Create('Hint.Paint.Background'#13 + e.message);
    end;

    // text //
    try
      GdipCreateFontFamilyFromName(PWideChar(WideString(PChar(@FFont.Name))), nil, family);
      GdipCreateFont(family, FFont.size, integer(FFont.bold) + integer(FFont.italic) * 2, 2, font);
      rect.Y := 1;
      rect.X := FH div 4 + 1;
      rect.Width := FW - 2;
      rect.Height := FH - 1;
      GdipCreateSolidFill(FFont.color, brush);
      GdipDrawString(dst, PWideChar(FCaption), -1, font, @rect, nil, brush);
      GdipDeleteBrush(brush);

      UpdateLWindow(FHWnd, bmp, FAlpha);
      SetWindowPos(FHWnd, hwnd_topmost, 0, 0, 0, 0, SWP_NOACTIVATE + SWP_NOMOVE + SWP_NOSIZE + SWP_SHOWWINDOW);

      GdipDeleteFont(font);
      GdipDeleteFontFamily(family);
      GdipDeleteGraphics(dst);
      DeleteBitmap(bmp);
    except
      on e: Exception do raise Exception.Create('Hint.Paint.Text'#13 + e.message);
    end;
end;
//------------------------------------------------------------------------------
procedure THint.Timer;
const
  STEP = 1;
  ITER = 4;
  ASTEP = 5;
  AITER = 3;
var
  delta: integer;
begin
  try
    if (not FVisible and (FAlpha > 0)) or (FVisible and (FAlpha < 255)) or (FXTarget <> FX) or (FYTarget <> FY) or (FWTarget <> FW) or (FHTarget <> FH) then
    begin
      delta := abs(255 - FAlpha) div AITER;
      if FVisible then FAlpha += ifthen(delta < ASTEP, ASTEP, delta)
      else FAlpha -= ifthen(delta < ASTEP, ASTEP, delta);
      if FAlpha < 0 then FAlpha := 0;
      if FAlpha > 255 then FAlpha := 255;

      delta := abs(FXTarget - FX) div ITER;
      if abs(FXTarget - FX) < STEP then FX := FXTarget
      else if FXTarget > FX then FX += ifthen(delta < STEP, STEP, delta)
      else if FXTarget < FX then FX -= ifthen(delta < STEP, STEP, delta);

      delta := abs(FYTarget - FY) div ITER;
      if abs(FYTarget - FY) < STEP then FY := FYTarget
      else if FYTarget > FY then FY += ifthen(delta < STEP, STEP, delta)
      else if FYTarget < FY then FY -= ifthen(delta < STEP, STEP, delta);

      delta := abs(FWTarget - FW) div ITER;
      if abs(FWTarget - FW) < STEP then FW := FWTarget
      else if FWTarget > FW then FW += ifthen(delta < STEP, STEP, delta)
      else if FWTarget < FW then FW -= ifthen(delta < STEP, STEP, delta);

      delta := abs(FHTarget - FH) div ITER;
      if abs(FHTarget - FH) < STEP then FH := FHTarget
      else if FHTarget > FH then FH += ifthen(delta < STEP, STEP, delta)
      else if FHTarget < FH then FH -= ifthen(delta < STEP, STEP, delta);

      Paint;

      if not FVisible and (FAlpha = 0) then
      begin
        KillTimer(FHWnd, ID_TIMER);
        ShowWindow(FHWnd, 0);
      end;
    end;
  except
    on e: Exception do err('Hint.Timer', e);
  end;
end;
//------------------------------------------------------------------------------
procedure THint.DeactivateHint(hwndOwner: HWND);
begin
  if hwndOwner = FHWndOwner then
  try
    FVisible := false;
    if sets.container.HintEffects then
    begin
      {if (FSite = bsTop) or (FSite = bsBottom) then
      begin
        FWTarget := 10;
        FXTarget := FX + (FW - 10) div 2;
      end else begin
        FHTarget := 10;
        FYTarget := FY + (FH - 10) div 2;
      end;}
    end else
    begin
      FAlpha := 0;
      KillTimer(FHWnd, ID_TIMER);
      ShowWindow(FHWnd, 0);
    end;
  except
    on e: Exception do err('Hint.DeactivateHint', e);
  end;
end;
//------------------------------------------------------------------------------
procedure THint.DeactivateImmediate;
begin
  try
    FVisible := false;
    FAlpha := 0;
    KillTimer(FHWnd, ID_TIMER);
    ShowWindow(FHWnd, 0);
  except
    on e: Exception do err('Hint.DeactivateImmediate', e);
  end;
end;
//------------------------------------------------------------------------------
end.

