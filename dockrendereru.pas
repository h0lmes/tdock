unit dockrendereru;

{$mode delphi}

interface

uses Windows, SysUtils, GDIPAPI, gfx, themeu, docklayoutu;

type
  TDockRenderer = class
  private
    FWindow, FBlurWindow: HWND;
    FBlurActive: Boolean;
    FOldBaseWindowRect, FOldBaseImageRect: GDIPAPI.TRect;
    FOldDraggingFile: Boolean;
  protected
    function DrawBackground(const Layout: TDockLayoutSnapshot; Theme: TDTheme;
      Alpha: Integer): Boolean; virtual;
  public
    constructor Create(Window: HWND);
    destructor Destroy; override;
    procedure CreateBlur;
    procedure DestroyBlur;
    procedure Paint(const Layout: TDockLayoutSnapshot; Theme: TDTheme;
      Alpha, Flags: Integer; BlurEnabled: Boolean);
    procedure UpdateBlur(const Layout: TDockLayoutSnapshot; Theme: TDTheme; BlurEnabled: Boolean);
    property BlurWindow: HWND read FBlurWindow;
  end;

implementation

uses declu, dwm_unit;

constructor TDockRenderer.Create(Window: HWND);
begin inherited Create; FWindow := Window; end;

destructor TDockRenderer.Destroy;
begin DestroyBlur; inherited Destroy; end;

procedure TDockRenderer.CreateBlur;
begin
  if FBlurWindow = 0 then
  try
    FBlurWindow := CreateWindowEx(WS_EX_LAYERED + WS_EX_TOOLWINDOW, TDWCLASS,
      'BlurWindow', WS_POPUP, -100, -100, 10, 10, 0, 0, hInstance, nil);
    dwm.ExcludeFromPeek(FBlurWindow);
    SetWindowLongPtr(FWindow, GWL_HWNDPARENT, FBlurWindow); // attach main window
    SetWindowPos(FBlurWindow, FWindow, 0, 0, 0, 0, SWP_NO_FLAGS);
  except
    on e: Exception do raise Exception.Create('Base.CreateBlur' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------
procedure TDockRenderer.DestroyBlur;
begin
  if FBlurWindow = 0 then Exit;
  try
    SetWindowLongPtr(FWindow, GWL_HWNDPARENT, 0); // detach main window
    if IsWindow(FBlurWindow) then DestroyWindow(FBlurWindow);
    FBlurWindow := 0;
  except
    on e: Exception do raise Exception.Create('Base.DestroyBlur' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------

function SameRect(const A, B: GDIPAPI.TRect): Boolean;
begin
  Result := (A.X = B.X) and (A.Y = B.Y) and
    (A.Width = B.Width) and (A.Height = B.Height);
end;

procedure TDockRenderer.Paint(const Layout: TDockLayoutSnapshot; Theme: TDTheme;
  Alpha, Flags: Integer; BlurEnabled: Boolean);
var Changed: Boolean;
begin
  Changed := ((Flags and 1) <> 0) or
    (Layout.DraggingFile <> FOldDraggingFile) or
    not SameRect(Layout.BaseImageRect, FOldBaseImageRect) or
    not SameRect(Layout.BaseWindowRect, FOldBaseWindowRect);
  if not Changed then Exit;
  if DrawBackground(Layout, Theme, Alpha) then
  begin
    FOldBaseImageRect := Layout.BaseImageRect;
    FOldBaseWindowRect := Layout.BaseWindowRect;
    FOldDraggingFile := Layout.DraggingFile;
    UpdateBlur(Layout, Theme, BlurEnabled);
  end;
end;

function TDockRenderer.DrawBackground(const Layout: TDockLayoutSnapshot; Theme: TDTheme;
  Alpha: Integer): Boolean;
var Bitmap: gfx._SimpleBitmap; Graphics: Pointer;
  Source: Windows.TPoint; Size: Windows.TSize; Blend: TBlendFunction;
begin
  Result := False;
  if Theme = nil then Exit;
  Bitmap := Default(gfx._SimpleBitmap);
  Graphics := nil;
  Bitmap.TopLeft.X := Layout.BaseWindowRect.X;
  Bitmap.TopLeft.Y := Layout.BaseWindowRect.Y;
  Bitmap.Width := Layout.BaseWindowRect.Width;
  Bitmap.Height := Layout.BaseWindowRect.Height;
  try
    if not CreateBitmap(Bitmap, FWindow) then Exit;
    Graphics := gfx.CreateGraphics(Bitmap.DC);
    if Graphics = nil then Exit;
    GdipSetCompositingMode(Graphics, CompositingModeSourceOver);
    GdipSetCompositingQuality(Graphics, CompositingQualityHighSpeed);
    GdipSetSmoothingMode(Graphics, SmoothingModeHighSpeed);
    GdipSetPixelOffsetMode(Graphics, PixelOffsetModeHighSpeed);
    GdipSetInterpolationMode(Graphics, InterpolationModeHighQualityBicubic);
    if Layout.DraggingFile then GdipGraphicsClear(Graphics, ITEM_BACKGROUND);
    Theme.DrawBackground(Graphics, Layout.BaseImageRect, Alpha);
    Source.X := 0;
    Source.Y := 0;
    Size.cx := Bitmap.Width;
    Size.cy := Bitmap.Height;
    Blend := Default(TBlendFunction);
    Blend.BlendOp := AC_SRC_OVER;
    Blend.SourceConstantAlpha := 255;
    Blend.AlphaFormat := AC_SRC_ALPHA;
    Result := UpdateLayeredWindow(FWindow, 0, @Bitmap.TopLeft, @Size,
      Bitmap.DC, @Source, $1fffffff, @Blend, ULW_ALPHA);
  finally
    if Graphics <> nil then gfx.DeleteGraphics(Graphics);
    gfx.DeleteBitmap(Bitmap);
  end;
end;

procedure TDockRenderer.UpdateBlur(const Layout: TDockLayoutSnapshot; Theme: TDTheme;
  BlurEnabled: Boolean);
var Bitmap: _SimpleBitmap; Graphics: Pointer; Rect: GDIPAPI.TRect;
begin
  if Assigned(Theme) and BlurEnabled and Theme.BlurEnabled and
    IsWindow(FBlurWindow) and IsWindowVisible(FWindow) then
  begin
    Bitmap := Default(_SimpleBitmap);
    Graphics := nil;
    Rect := Theme.GetBlurRect(Layout.BaseImageRect);
    Bitmap.TopLeft.X := Rect.X + Layout.BaseWindowRect.X;
    Bitmap.TopLeft.Y := Rect.Y + Layout.BaseWindowRect.Y;
    Bitmap.Width := Rect.Width;
    Bitmap.Height := Rect.Height;
    try
      if not CreateBitmap(Bitmap, FBlurWindow) then Exit;
      GdipCreateFromHDC(Bitmap.DC, Graphics);
      if Graphics = nil then Exit;
      UpdateLWindow(FBlurWindow, Bitmap, 255);
      SetWindowPos(FBlurWindow, 0, 0, 0, 0, 0, SWP_NO_FLAGS + SWP_NOZORDER + SWP_SHOWWINDOW);
      DWM.EnableBlurBehindWindow(FBlurWindow, 0);
      FBlurActive := True;
    finally
      if Graphics <> nil then DeleteGraphics(Graphics);
      DeleteBitmap(Bitmap);
    end;
  end
  else if FBlurActive then
  begin
    FBlurActive := False;
    DWM.DisableBlurBehindWindow(FBlurWindow);
    SetWindowPos(FBlurWindow, FWindow, 0, 0, 0, 0, SWP_NO_FLAGS + SWP_HIDEWINDOW);
  end;
end;

end.
