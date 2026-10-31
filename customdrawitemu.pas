unit customdrawitemu;

{$t+}

interface

uses Windows, Messages, SysUtils, Controls, Classes, ShellAPI, Math,
  declu, dockh, GDIPAPI, gfx, customitemu, themeu, animationcurveu;

type
  TOnBeforeDraw = procedure of object;
  TOnAfterDraw = procedure of object;
  TOnDrawOverlay = procedure(graphics: Pointer; x, y, size: integer) of object;
  PItemPositionBatch = ^HDWP;

  { TCustomDrawItem }

  TCustomDrawItem = class(TCustomItem)
  private
    FPositionBatch: PItemPositionBatch;
    function TryMoveDrawWindow(var Batch: HDWP; X, Y: integer; Flags: UINT): boolean;
  protected
    FDrawSurface: _SimpleBitmap;
    FDrawSurfaceValid: boolean;
    FNativePresentationValid: boolean;
    FRunning: boolean;
    OnBeforeDraw: TOnBeforeDraw;
    OnAfterDraw: TOnAfterDraw;
    OnDrawOverlay: TOnDrawOverlay;
    function CreateDrawSurface(var Bitmap: _SimpleBitmap): boolean; virtual;
    function CreateDrawGraphics(DC: HDC): Pointer; virtual;
    function PaintDrawImage(Graphics, Attributes: Pointer; X, Y, Size: integer): boolean; virtual;
    function PresentDrawSurface(const Bitmap: _SimpleBitmap; Alpha: integer): boolean; virtual;
    function MoveDrawWindow(var Batch: HDWP; X, Y: integer; Flags: UINT): boolean; virtual;
    procedure DrawNumberOverlay(dst: pointer; x, y, size, number: integer);
  public
    property Running: boolean read FRunning;
    constructor Create(wndParent: HWND; var AParams: TDItemCreateParams); override;
    destructor Destroy; override;
    procedure InvalidateNativePresentation;
    procedure DrawInPositionBatch(Ax, Ay, ASize: integer; AForce: boolean;
      var Batch: HDWP; AShowItem: UINT);
    procedure Draw(Ax, Ay, ASize: integer; AForce: boolean; wpi: HDWP; AShowItem: uint); override;
  end;

implementation
//------------------------------------------------------------------------------
constructor TCustomDrawItem.Create(wndParent: HWND; var AParams: TDItemCreateParams);
begin
  inherited;
  FRunning := false;
end;
//------------------------------------------------------------------------------
destructor TCustomDrawItem.Destroy;
begin
  if FDrawSurfaceValid then DeleteBitmap(FDrawSurface);
  inherited;
end;
//------------------------------------------------------------------------------
function TCustomDrawItem.CreateDrawSurface(var Bitmap: _SimpleBitmap): boolean;
begin Result := CreateBitmap(Bitmap, FHWnd); end;
function TCustomDrawItem.CreateDrawGraphics(DC: HDC): Pointer;
begin
  Result := nil;
  GdipCreateFromHDC(DC, Result);
end;
function TCustomDrawItem.PaintDrawImage(Graphics, Attributes: Pointer; X, Y, Size: integer): boolean;
begin
  if not Assigned(FImage) then exit(true);
  Result := GdipDrawImageRectRectI(Graphics, FImage, X, Y, Size, Size,
    0, 0, FIW, FIH, UnitPixel, Attributes, nil, nil) = Ok;
end;
function TCustomDrawItem.PresentDrawSurface(const Bitmap: _SimpleBitmap; Alpha: integer): boolean;
begin Result := TryUpdateLWindow(FHWnd, Bitmap, Alpha); end;
function TCustomDrawItem.MoveDrawWindow(var Batch: HDWP; X, Y: integer; Flags: UINT): boolean;
begin
  if Batch <> 0 then
  begin
    Batch := DeferWindowPos(Batch, FHWnd, 0, X, Y, 0, 0, Flags);
    Result := Batch <> 0;
  end
  else Result := SetWindowPos(FHWnd, 0, X, Y, 0, 0, Flags);
end;
function TCustomDrawItem.TryMoveDrawWindow(var Batch: HDWP; X, Y: integer; Flags: UINT): boolean;
begin
  if FPositionBatch <> nil then Batch := FPositionBatch^;
  try Result := MoveDrawWindow(Batch, X, Y, Flags);
  finally
    if FPositionBatch <> nil then FPositionBatch^ := Batch;
  end;
end;
procedure TCustomDrawItem.InvalidateNativePresentation;
begin
  FNativePresentationValid := false;
  if FFreed then exit;
  FFrameRedraw := true;
  FFrameForce := true;
end;
procedure TCustomDrawItem.DrawInPositionBatch(Ax, Ay, ASize: integer; AForce: boolean;
  var Batch: HDWP; AShowItem: UINT);
var PreviousBatch: PItemPositionBatch;
begin
  PreviousBatch := FPositionBatch;
  FPositionBatch := @Batch;
  try Draw(Ax, Ay, ASize, AForce, Batch, AShowItem);
  finally FPositionBatch := PreviousBatch; end;
end;
//------------------------------------------------------------------------------
// set position, size, repaint window //
procedure TCustomDrawItem.Draw(Ax, Ay, ASize: integer; AForce: boolean; wpi: HDWP; AShowItem: uint);
var
  bmp: _SimpleBitmap;
  dst, hattr, brush: Pointer;
  bitmapX, bitmapY: integer; // coord of image within window
  screenX, screenY: integer; // coord of window
  ItemRect: windows.TRect;
  animX, animY, animSize: integer;
  button: boolean;
  motion: TClickAnimationValues;
  drawAttempted, drawComplete: boolean;
begin
  bmp := Default(_SimpleBitmap);
  dst := nil;
  hattr := nil;
  brush := nil;
  drawAttempted := false;
  drawComplete := false;
  try
  try
    AForce := AForce or FFrameForce or
      (not FNativePresentationValid and (AShowItem and SWP_HIDEWINDOW = 0));
    if FFreed or not FEnabled or FUpdating or (FUndocked and not AForce)
       or ((FX = Ax) and (FY = Ay) and (FSize = ASize) and (FShowItem = AShowItem) and not AForce and not need_dock) then exit;
    drawAttempted := true;

    // OnBeforeDraw
    if assigned(OnBeforeDraw) then OnBeforeDraw;
    if FFreed then exit;

    animX := 0;
    animY := 0;
    animSize := 0;
    motion := ClickAnimationValues(FItemAnimationType, FAnimationProgress, FBorder, FItemSize);

    // set position //
    try
      ItemRect := GetRectFromSize(ASize);
      FX := Ax;
      FY := Ay;
      FShowItem := AShowItem;
      if need_dock then
      begin
        Ax := FDockingX;
        Ay := FDockingY;
      end;
      screenX := Ax - ItemRect.Left;
      screenY := Ay - ItemRect.Top;

      // bounce animation //
      if FAnimationProgress > 0 then
        if (FItemAnimationType >= 2) and (FItemAnimationType <= 4) then
        begin
          animX := Round(motion.Bounce);
          if (FSite = 0) or (FSite = 2) then dec(screenY, animX);
        end;

      if (FSize = ASize) and not AForce then
      begin
        if not TryMoveDrawWindow(wpi, screenX, screenY,
          swp_nosize + swp_noactivate + swp_noreposition + swp_nozorder + FShowItem) then exit;
        UpdateHint(screenX, screenY);
        drawComplete := true;
        FFrameRedraw := false;
        FFrameForce := false;
        // OnAfterDraw
        if assigned(OnAfterDraw) then OnAfterDraw;
        exit;
      end else begin
        if FShowItem and SWP_HIDEWINDOW <> 0 then
        begin
          if not TryMoveDrawWindow(wpi, screenX, screenY,
            swp_nosize + swp_noactivate + swp_noreposition + swp_nozorder + FShowItem) then exit;
        end
        else if wpi > 0 then
          if not TryMoveDrawWindow(wpi, 0, 0,
            swp_nomove + swp_nosize + swp_noactivate + swp_nozorder + swp_noreposition + FShowItem) then exit;
      end;

      FSize := ASize;
      if FShowItem and SWP_HIDEWINDOW <> 0 then
      begin
        FNativePresentationValid := false;
        drawComplete := true;
        FFrameRedraw := false;
        FFrameForce := false;
        exit;
      end;
      UpdateHint(screenX, screenY);
    except
      on e: Exception do raise Exception.Create('SetPosition ' + LineEnding + e.message);
    end;

    // init bitmap //
    try
      bmp.topleft.x := screenX;
      bmp.topleft.y := screenY;
      bmp.width := FSize + ItemRect.Left * 2;
      bmp.height := FSize + ItemRect.Top * 2;
      if FDrawSurfaceValid and ((FDrawSurface.width <> bmp.width) or
        (FDrawSurface.height <> bmp.height)) then
      begin
        DeleteBitmap(FDrawSurface);
        FDrawSurfaceValid := false;
      end;
      if not FDrawSurfaceValid then
      begin
        FDrawSurface := bmp;
        FDrawSurfaceValid := CreateDrawSurface(FDrawSurface);
        if not FDrawSurfaceValid then exit;
      end;
      bmp := FDrawSurface;
      bmp.topleft := Point(screenX, screenY);
      FillChar(bmp.BufferBits^, bmp.width * bmp.height * 4, 0);
      dst := CreateDrawGraphics(bmp.dc);
      if not assigned(dst) then exit;
      GdipCreateSolidFill(ITEM_BACKGROUND, brush);
      if (FSite = 1) or (FSite = 3) then
        GdipFillRectangleI(dst, brush, ItemRect.Left - FItemSpacing div 2, ItemRect.Top - 1, ItemRect.Right - ItemRect.Left + FItemSpacing, ItemRect.Bottom - ItemRect.Top + 1)
      else
        GdipFillRectangleI(dst, brush, ItemRect.Left - 1, ItemRect.Top - FItemSpacing div 2, ItemRect.Right - ItemRect.Left + 1, ItemRect.Bottom - ItemRect.Top + FItemSpacing);
      GdipDeleteBrush(brush);
      brush := nil;
      GdipSetInterpolationMode(dst, InterpolationModeHighQualityBicubic);

      // draw the button
      button := false;
      if FRunning then button := theme.DrawButton(dst, ItemRect.Left, ItemRect.Top, FSize, FAttention);
      FNCHitTestNC := button;

      bitmapX := 0;
      bitmapY := 0;

      if FAnimationProgress > 0 then
      begin
        // rotate //
        if FItemAnimationType = 1 then
        begin
          dec(bitmapX, ItemRect.Left);
          dec(bitmapY, ItemRect.Top);
          dec(bitmapX, FSize div 2);
          dec(bitmapY, FSize div 2);
          GdipTranslateWorldTransform(dst, -bitmapX, -bitmapY, MatrixOrderPrepend);
          GdipRotateWorldTransform(dst, motion.Rotation, MatrixOrderPrepend);
        end;
        // bounce //
        if (FItemAnimationType >= 2) and (FItemAnimationType <= 4) then
        begin
          animX := Round(motion.Bounce);
          if FSite = 1 then inc(bitmapY, animX)
          else if FSite = 3 then dec(bitmapY, animX);
        end;
        // quake //
        if FItemAnimationType = 5 then
        begin
          animX := Round(motion.OffsetX);
          animY := Round(motion.OffsetY);
          inc(bitmapX, animX);
          inc(bitmapY, animY);
        end;
        // swing //
        if FItemAnimationType = 6 then
        begin
          dec(bitmapX, ItemRect.Left);
          dec(bitmapY, ItemRect.Top);
          dec(bitmapX, FSize div 2);
          dec(bitmapY, FSize div 2);
          GdipTranslateWorldTransform(dst, -bitmapX, -bitmapY, MatrixOrderPrepend);
          GdipRotateWorldTransform(dst, motion.Rotation, MatrixOrderPrepend);
        end;
        // vibrate //
        if FItemAnimationType = 7 then
        begin
          animSize := Round(motion.SizeDelta);
          dec(bitmapX, animSize div 2);
          dec(bitmapY, animSize div 2);
        end;
        // zoom //
        if FItemAnimationType = 8 then
        begin
          animSize := Round(motion.SizeDelta);
          dec(bitmapX, animSize div 2);
          dec(bitmapY, animSize div 2);
        end;
      end;

      inc(bitmapX, ItemRect.Left);
      inc(bitmapY, ItemRect.Top);
    except
      on e: Exception do raise Exception.Create('InitBitmap ' + LineEnding + e.message);
    end;

    // draw icon //
    CreateColorAttributes(FColorData, FSelected, hattr);
    if not PaintDrawImage(dst, hattr, bitmapX, bitmapY, FSize + animSize) then exit;
    if hattr <> nil then GdipDisposeImageAttributes(hattr);
    hattr := nil;

    // OnDrawOverlay
    if assigned(OnDrawOverlay) then OnDrawOverlay(dst, bitmapX, bitmapY, FSize + animSize);

    // reset the transform we might have set for animation
    if FAnimationProgress > 0 then GdipResetWorldTransform(dst);

    if not button and not FUndocked then
    begin
      if FReflection then
        BitmapReflection(bmp, ItemRect.Left, ItemRect.Top, FSize, FReflectionSize, FSite);

      if FRunning then
        theme.DrawIndicator(dst, ItemRect.Left, ItemRect.Top, FSize, FSite);
    end;

    if not PresentDrawSurface(bmp, ifthen(FUndocked, 127, 255)) then exit;
    drawComplete := true;
    FNativePresentationValid := true;
    FFrameRedraw := false;
    FFrameForce := false;
    // OnAfterDraw
    if assigned(OnAfterDraw) then OnAfterDraw;
  finally
    if hattr <> nil then GdipDisposeImageAttributes(hattr);
    if brush <> nil then GdipDeleteBrush(brush);
    DeleteGraphics(dst);
    if drawAttempted and not drawComplete and not FFreed then
      InvalidateNativePresentation;
  end;
  except
    on e: Exception do raise Exception.Create('CustomDrawItem.Draw(' + FCaption + ') ' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------
procedure TCustomDrawItem.DrawNumberOverlay(dst: pointer; x, y, size, number: integer);
var
  brush, family, hfont, format, path: Pointer;
  tmpItemSize: integer;
  rect: GDIPAPI.TRectF;
begin
  GdipSetSmoothingMode(dst, SmoothingModeAntiAlias);
  GdipSetTextRenderingHint(dst, TextRenderingHintAntiAlias);
  // background
  tmpItemSize := max(FItemSize, 40);
  if number > 99 then rect.Width := round(tmpItemSize * 9 / 12)
  else if number > 9 then rect.Width := round(tmpItemSize * 7 / 12)
  else rect.Width := round(tmpItemSize * 5 / 12);
  rect.Height := round(tmpItemSize * 5 / 12);
  rect.X := x + Size - rect.Width + 5;
  rect.Y := y - 5;
  GdipCreatePath(FillModeWinding, path);
  AddPathRoundRect(path, rect, rect.Height / 2);
  GdipCreateSolidFill($ffff0000, brush); // red indicator background
  GdipFillPath(dst, brush, path);
  GdipDeleteBrush(brush);
  GdipDeletePath(path);
  // number
  GdipCreateFontFamilyFromName(PWideChar(WideString(PChar(@FFont.Name))), nil, family);
  GdipCreateFont(family, tmpItemSize * 5 div 16, 1, 2, hfont);
  GdipCreateSolidFill($ffffffff, brush);
  GdipCreateStringFormat(0, 0, format);
  GdipSetStringFormatAlign(format, StringAlignmentCenter);
  GdipSetStringFormatLineAlign(format, StringAlignmentCenter);
  GdipDrawString(dst, PWideChar(WideString(inttostr(number))), -1, hfont, @rect, format, brush);
  GdipDeleteStringFormat(format);
  GdipDeleteBrush(brush);
  GdipDeleteFont(hfont);
  GdipDeleteFontFamily(family);
end;
//------------------------------------------------------------------------------
end.

