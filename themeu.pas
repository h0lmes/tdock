unit themeu;

interface

uses Windows, Classes, SysUtils, Forms, Dialogs, StdCtrls, IniFiles,
  ActiveX, declu, toolu, gfx, GDIPAPI;

const MAX_REGION_POINTS = 128;

type
  PLayerBackground = ^TLayerBackground;
  TLayerBackground = record
    ImageFile: string;
    Image: Pointer;
    W: uint;
    H: uint;
    Margins: Windows.TRect;
    StretchStyle: TStretchStyle;
  end;

  TLayerSeparator = record
    ImageFile: string;
    Image: Pointer;
    W: uint;
    H: uint;
    Margins: Windows.TRect;
  end;

  TLayerSimpleImage = record
    Image: Pointer;
    W: uint;
    H: uint;
  end;

  TLayerButton = record
    Image: Pointer;
    AttentionImage: Pointer;
    W: uint;
    H: uint;
    Margins: Windows.TRect;
    Area: Windows.TRect;
  end;

  { TDTheme }

  TDTheme = class
  private
    FSite: TBaseSite;
    FThemesFolder: string;
    FThemeName: string;
    FBlurRegion: string;
    FBlurRegionPoints: array [0..MAX_REGION_POINTS - 1] of windows.TPoint;
    FBlurRegionPointsCount: integer;
    FBlurRect: Windows.TRect;
    FBlurR: Windows.TSize;
    FItemsArea: Windows.TRect;
    FItemsArea2: Windows.TRect;
    FMargin: integer;
    FMargin2: integer;
    procedure SetBlurRegion(value: string);
    procedure SetItemsArea(value: windows.TRect);
    procedure SetSite(value: TBaseSite);
  public
    is_default: boolean;
    Background: TLayerBackground;
    Separator: TLayerSeparator;
    Indicator: TLayerSimpleImage;
    Button: TLayerButton;
    Stack: TLayerSimpleImage;
    Path: string;

    property BlurRegion: string read FBlurRegion write SetBlurRegion;
    property Site: TBaseSite read FSite write SetSite;
    property ItemsArea: windows.TRect read FItemsArea write SetItemsArea;
    property ItemsArea2: windows.TRect read FItemsArea2;
    property Margin: integer read FMargin;
    property Margin2: integer read FMargin2;
    property ThemesFolder: string read FThemesFolder;

    constructor Create(aTheme: string; aSite: TBaseSite);
    destructor Destroy; override;

    procedure Clear;
    procedure ClearGraphics;
    function Load: boolean;
    procedure ReloadGraphics;
    function Save: boolean;
    procedure ImageAdjustRotate(image: Pointer);
    procedure SetTheme(atheme: string);
    function CorrectMargins(margins: Windows.TRect): Windows.TRect;
    function CorrectSize(size: Windows.TSize): Windows.TSize;
    function CorrectCoords(coord: Windows.TPoint; W, H: integer): Windows.TPoint;
    procedure DrawBackground(hGDIPGraphics: Pointer; r: GDIPAPI.TRect; alpha: integer);
    procedure DrawIndicator(dst: Pointer; Left, Top, Size, Site: integer);
    function DrawButton(dst: Pointer; Left, Top, Size: integer; Attention: boolean): boolean;
    function GetBlurRgn(r: GDIPAPI.TRect): HRGN;
		function GetBlurRect(r: GDIPAPI.TRect): GDIPAPI.TRect;
    function BlurEnabled: boolean;

    procedure MakeDefaultTheme;
    procedure CheckExtractFileFromResource(ResourceName: PChar; Filename: string);
    procedure ExtractFileFromResource(ResourceName: PChar; Filename: string);
    procedure SearchThemes(ThemeName: string; lb: TListBox);
    procedure ThemesMenu(ThemeName: string; hMenu: THandle);
  end;

var theme: TDTheme;

implementation
//------------------------------------------------------------------------------
constructor TDTheme.Create(aTheme: string; aSite: TBaseSite);
begin
  FThemeName := aTheme;
  FThemesFolder := toolu.UnzipPath('%pp%\Themes\');
  FSite := aSite;
  Clear;
  ClearGraphics;
  CheckExtractFileFromResource('DEFAULT_BACKGROUND', UnzipPath('%pp%\themes\background.png'));
  CheckExtractFileFromResource('DEFAULT_INDICATOR', UnzipPath('%pp%\themes\indicator.png'));
end;
//------------------------------------------------------------------------------
procedure TDTheme.Clear;
begin
  Background.StretchStyle := ssStretch;
  Background.Margins := rect(0, 0, 0, 0);
  FItemsArea := rect(0, 0, 0, 0);
  FItemsArea2 := rect(5, 5, 5, 5);
  FMargin := 10;
  FMargin2 := 0;
  Separator.Margins := rect(0, 0, 0, 0);
  Button.Margins := rect(2, 2, 2, 2);
  Button.Area := rect(-2, -2, -2, -2);
end;
//------------------------------------------------------------------------------
procedure TDTheme.ClearGraphics;
begin
  if Indicator.image <> nil then
  begin
    try GdipDisposeImage(Indicator.image);
    except end;
    Indicator.image := nil;
  end;

  if Button.Image <> nil then
  begin
    try GdipDisposeImage(Button.Image);
    except end;
    Button.Image := nil;
  end;

  if Button.AttentionImage <> nil then
  begin
    try GdipDisposeImage(Button.AttentionImage);
    except end;
    Button.AttentionImage := nil;
  end;

  if Separator.image <> nil then
  begin
    try GdipDisposeImage(Separator.image);
    except end;
    Separator.image := nil;
  end;

  if Stack.image <> nil then
  begin
    try GdipDisposeImage(Stack.image);
    except end;
    Stack.image := nil;
  end;

  if Background.image <> nil then
  begin
    try GdipDisposeImage(Background.image);
    except end;
    Background.image := nil;
  end;
end;
//------------------------------------------------------------------------------
procedure TDTheme.SetTheme(aTheme: string);
begin
  FThemeName := aTheme;
  Load;
end;
//------------------------------------------------------------------------------
function TDTheme.Load: boolean;
var
  ini: TIniFile;
  section: string;
  ia: windows.TRect;
begin
  Result := false;
  is_default := false;

  Clear;

  // default theme //

  if not DirectoryExists(FThemesFolder + FThemeName + '\') then
  begin
    FThemeName := 'Aero';
    if not DirectoryExists(FThemesFolder + FThemeName + '\') then
    begin
      MakeDefaultTheme;
      Result := True;
      exit;
    end;
  end;

  // loading theme data //
  try
    Path := FThemesFolder + FThemeName + '\';

    // background //
    ini := TIniFile.Create(Path + 'background.ini');
    ini.CaseSensitive := false;
    section := 'Background';
    if ini.SectionExists('BackgroundBottom') then section := 'BackgroundBottom';
    //
    Background.ImageFile := Trim(ini.ReadString(section, 'Image', 'background.png'));
    // ObjectDock format //
    if ini.ValueExists(section, 'LeftWidth') then
    begin
      ia.Left :=   ini.ReadInteger(section, 'OutsideBorderLeft', 0);
      ia.Top :=    ini.ReadInteger(section, 'OutsideBorderTop', 0);
      ia.Right :=  ini.ReadInteger(section, 'OutsideBorderRight', 0);
      ia.Bottom := ini.ReadInteger(section, 'OutsideBorderBottom', 0);
      Background.Margins.Left :=   ini.ReadInteger(section, 'LeftWidth', 0);
      Background.Margins.Top :=    ini.ReadInteger(section, 'TopHeight', 0);
      Background.Margins.Right :=  ini.ReadInteger(section, 'RightWidth', 0);
      Background.Margins.Bottom := ini.ReadInteger(section, 'BottomHeight', 0);
    end;
    // RocketDock format //
    if ini.ValueExists(section, 'LeftMargin') then
    begin
      ia.Left :=   ini.ReadInteger(section, 'Outside-LeftMargin', 0);
      ia.Top :=    ini.ReadInteger(section, 'Outside-TopMargin', 0);
      ia.Right :=  ini.ReadInteger(section, 'Outside-RightMargin', 0);
      ia.Bottom := ini.ReadInteger(section, 'Outside-BottomMargin', 0);
      Background.Margins.Left :=   ini.ReadInteger(section, 'LeftMargin', 0);
      Background.Margins.Top :=    ini.ReadInteger(section, 'TopMargin', 0);
      Background.Margins.Right :=  ini.ReadInteger(section, 'RightMargin', 0);
      Background.Margins.Bottom := ini.ReadInteger(section, 'BottomMargin', 0);
    end;
    // Terry-specific keys //
    BlurRegion := ini.ReadString (section, 'BlurRegion', '');
    ini.Free;

    ItemsArea := ia;

    // separator //
    if FileExists(Path + 'separator.ini') then
    begin
      ini := TIniFile.Create(Path + 'separator.ini');
      section := 'Separator';
      if ini.SectionExists('SeparatorBottom') then section := 'SeparatorBottom';
      Separator.ImageFile := Trim(ini.ReadString(section, 'Image', 'separator.png'));
      if ini.ValueExists(section, 'LeftWidth') then Separator.Margins.Left := ini.ReadInteger(section, 'LeftWidth', 0);
      if ini.ValueExists(section, 'RightWidth') then Separator.Margins.Right := ini.ReadInteger(section, 'RightWidth', 0);
      if ini.ValueExists(section, 'TopHeight') then Separator.Margins.Top := ini.ReadInteger(section, 'TopHeight', 0);
      if ini.ValueExists(section, 'BottomHeight') then Separator.Margins.Bottom := ini.ReadInteger(section, 'BottomHeight', 0);
      if ini.ValueExists(section, 'LeftMargin') then Separator.Margins.Left := ini.ReadInteger(section, 'LeftMargin', 0);
      if ini.ValueExists(section, 'RightMargin') then Separator.Margins.Right := ini.ReadInteger(section, 'RightMargin', 0);
      if ini.ValueExists(section, 'TopMargin') then Separator.Margins.Top := ini.ReadInteger(section, 'TopMargin', 0);
      if ini.ValueExists(section, 'BottomMargin') then Separator.Margins.Bottom := ini.ReadInteger(section, 'BottomMargin', 0);
      ini.Free;
    end else begin
      Separator.ImageFile := 'separator.png';
      Separator.Margins := rect(0, 0, 0, 0);
    end;

    // button //
    if FileExists(Path + 'button.ini') then
    begin
      ini := TIniFile.Create(Path + 'button.ini');
      section := 'Button';
      Button.Margins.Left :=   ini.ReadInteger(section, 'LeftWidth', 2);
      Button.Margins.Right :=  ini.ReadInteger(section, 'RightWidth', 2);
      Button.Margins.Top :=    ini.ReadInteger(section, 'TopHeight', 2);
      Button.Margins.Bottom := ini.ReadInteger(section, 'BottomHeight', 2);
      Button.Area.Left :=   ini.ReadInteger(section, 'OutsideBorderLeft', -5);
      Button.Area.Top :=    ini.ReadInteger(section, 'OutsideBorderTop', -5);
      Button.Area.Right :=  ini.ReadInteger(section, 'OutsideBorderRight', -5);
      Button.Area.Bottom := ini.ReadInteger(section, 'OutsideBorderBottom', -5);
      ini.Free;
    end else begin
      Button.Margins := rect(2, 2, 2, 2);
      Button.Area := rect(-5, -5, -5, -5);
    end;

    ReloadGraphics;
    Result := True;
  except
    on e: Exception do raise Exception.Create('Error loading theme' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------
function TDTheme.Save: boolean;
var
  ini: TIniFile;
begin
  result := false;

  if not DirectoryExists(FThemesFolder) then CreateDirectory(PChar(FThemesFolder), nil);
  if FThemeName = '' then FThemeName := 'Aero';
  if not DirectoryExists(FThemesFolder + FThemeName + '\') then
    CreateDirectory(PChar(FThemesFolder + FThemeName + '\'), nil);

  try
    windows.DeleteFile(PChar(FThemesFolder + FThemeName + '\background.ini'));
    windows.DeleteFile(PChar(FThemesFolder + FThemeName + '\separator.ini'));

    // background //
    ini := TIniFile.Create(FThemesFolder + FThemeName + '\background.ini');
    ini.WriteString ('Background', 'Image',        Background.ImageFile);
    ini.WriteInteger('Background', 'OutsideBorderLeft',   FItemsArea.Left);
    ini.WriteInteger('Background', 'OutsideBorderTop',    FItemsArea.Top);
    ini.WriteInteger('Background', 'OutsideBorderRight',  FItemsArea.Right);
    ini.WriteInteger('Background', 'OutsideBorderBottom', FItemsArea.Bottom);
    ini.WriteInteger('Background', 'LeftWidth',    Background.Margins.Left);
    ini.WriteInteger('Background', 'TopHeight',    Background.Margins.Top);
    ini.WriteInteger('Background', 'RightWidth',   Background.Margins.Right);
    ini.WriteInteger('Background', 'BottomHeight', Background.Margins.Bottom);
    // terry-specific
    if BlurRegion <> '' then ini.WriteString ('Background', 'BlurRegion', BlurRegion);
    ini.Free;
    // separator //
    ini := TIniFile.Create(FThemesFolder + FThemeName + '\separator.ini');
    ini.WriteString ('Separator', 'Image',        Separator.ImageFile);
    ini.WriteInteger('Separator', 'LeftWidth',    Separator.Margins.Left);
    ini.WriteInteger('Separator', 'TopHeight',    Separator.Margins.Top);
    ini.WriteInteger('Separator', 'RightWidth',   Separator.Margins.Right);
    ini.WriteInteger('Separator', 'BottomHeight', Separator.Margins.Bottom);
    ini.Free;

    result := true;
  except
    on e: Exception do raise Exception.Create('Error saving theme' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------
procedure TDTheme.SetBlurRegion(value: string);
var
  idx: integer;
  str: string;
begin
  FBlurRegion := value;
  FBlurRegionPointsCount := 0;
  str := FBlurRegion;
  idx := 0;
  try
    while (str <> '') and (idx < 1024) do
    begin
      FBlurRegionPoints[idx].x := strtoint(trim( fetch(str, ',', true) ));
      FBlurRegionPoints[idx].y := strtoint(trim( fetch(str, ',', true) ));
      inc(idx);
    end;
  except
  end;
  FBlurRegionPointsCount := idx;

  if FBlurRegionPointsCount = 0 then
  begin
    FBlurRegionPointsCount := 2;
    FBlurRegionPoints[0].x := 0;
    FBlurRegionPoints[0].y := 0;
    FBlurRegionPoints[1].x := 0;
    FBlurRegionPoints[1].y := 0;
  end;

  if (FBlurRegionPointsCount = 2) or (FBlurRegionPointsCount = 3) then
  begin
    FBlurRect.Left := FBlurRegionPoints[0].x;
    FBlurRect.Top := FBlurRegionPoints[0].y;
    FBlurRect.Right := FBlurRegionPoints[1].x;
    FBlurRect.Bottom := FBlurRegionPoints[1].y;
    FBlurR.cx := 0;
    FBlurR.cy := 0;
    if FBlurRegionPointsCount = 3 then
    begin
      FBlurR.cx := FBlurRegionPoints[2].x;
      FBlurR.cy := FBlurRegionPoints[2].y;
    end;
  end;
end;
//------------------------------------------------------------------------------
procedure TDTheme.SetSite(value: TBaseSite);
begin
  FSite := value;
  ReloadGraphics;
end;
//------------------------------------------------------------------------------
procedure TDTheme.SetItemsArea(value: windows.TRect);
begin
  FItemsArea := value;
  FMargin2 := 0;
  if FItemsArea.Top < 0 then FMargin2 := -FItemsArea.Top;
end;
//------------------------------------------------------------------------------
procedure TDTheme.ReloadGraphics;
var
  img: Pointer;
begin
  ClearGraphics;

  try
    // background image //
    try
      if FileExists(Path + Background.ImageFile) then
        GdipLoadImageFromFile(PWideChar(WideString(Path + Background.ImageFile)), Background.Image);
      if Background.image = nil then
        GdipLoadImageFromFile(PWideChar(WideString(FThemesFolder + 'background.png')), Background.Image);
      if Background.image <> nil then
      begin
        ImageAdjustRotate(Background.Image);
        GdipGetImageWidth(Background.Image, Background.W);
        GdipGetImageHeight(Background.Image, Background.H);
        img := Background.Image;
        GdipCloneBitmapAreaI(0, 0, Background.W, Background.H, PixelFormat32bppPARGB, img, Background.Image);
        GdipDisposeImage(img);
      end;
    except
      on e: Exception do raise Exception.Create('Error loading background: ' + Path + Background.ImageFile + LineEnding + e.message);
    end;

    // separator image //
    try
      if FileExists(Path + Separator.ImageFile) then
        GdipLoadImageFromFile(PWideChar(WideString(Path + Separator.ImageFile)), Separator.Image);
      if Separator.Image <> nil then
      begin
        ImageAdjustRotate(Separator.Image);
        GdipGetImageWidth(Separator.Image, Separator.W);
        GdipGetImageHeight(Separator.Image, Separator.H);
      end;
    except
      on e: Exception do raise Exception.Create('Error loading separator: ' + Path + Separator.ImageFile + LineEnding + e.message);
    end;

    // stack default icon //
    try
      if FileExists(Path + 'stack.png') then GdipLoadImageFromFile(PWideChar(WideString(Path + 'stack.png')), Stack.Image);
      if Stack.image = nil then CreateDefaultStackImage(Stack.Image);
      GdipGetImageWidth(Stack.Image, Stack.W);
      GdipGetImageHeight(Stack.Image, Stack.H);
    except
      on e: Exception do raise Exception.Create('Error loading stack icon: ' + Path + 'stack.png' + LineEnding + e.message);
    end;

    // running indicator image //
    try
      if FileExists(Path + 'indicator.png') then
        GdipLoadImageFromFile(PWideChar(WideString(Path + 'indicator.png')), Indicator.Image);
      if Indicator.image = nil then
        GdipLoadImageFromFile(PWideChar(WideString(FThemesFolder + 'indicator.png')), Indicator.Image);
      if Indicator.Image <> nil then
      begin
        ImageAdjustRotate(Indicator.Image);
        GdipGetImageWidth(Indicator.Image, Indicator.W);
        GdipGetImageHeight(Indicator.Image, Indicator.H);
        img := Indicator.Image;
        GdipCloneBitmapAreaI(0, 0, Indicator.W, Indicator.H, PixelFormat32bppPARGB, img, Indicator.Image);
        GdipDisposeImage(img);
      end;
    except
      on e: Exception do raise Exception.Create('Error loading indicator: ' + Path + 'indicator.png' + LineEnding + e.message);
    end;

    // running button image //
    try
      if FileExists(Path + 'button.png') then
        GdipLoadImageFromFile(PWideChar(WideString(Path + 'button.png')), Button.Image);
      if assigned(Button.Image) then
      begin
        ImageAdjustRotate(Button.Image);
        GdipGetImageWidth(Button.Image, Button.W);
        GdipGetImageHeight(Button.Image, Button.H);
        img := Button.Image;
        GdipCloneBitmapAreaI(0, 0, Button.W, Button.H, PixelFormat32bppPARGB, img, Button.Image);
        GdipDisposeImage(img);
      end;
    except
      on e: Exception do raise Exception.Create('Error loading button: ' + Path + 'button.png' + LineEnding + e.message);
    end;

    // attention button image //
    try
      if FileExists(Path + 'attentionbutton.png') then
        GdipLoadImageFromFile(PWideChar(WideString(Path + 'attentionbutton.png')), Button.AttentionImage);
      if assigned(Button.AttentionImage) then
      begin
        ImageAdjustRotate(Button.AttentionImage);
        img := Button.AttentionImage;
        GdipCloneBitmapAreaI(0, 0, Button.W, Button.H, PixelFormat32bppPARGB, img, Button.AttentionImage);
        GdipDisposeImage(img);
      end;
    except
      on e: Exception do raise Exception.Create('Error loading button: ' + Path + 'attentionbutton.png' + LineEnding + e.message);
    end;

    img := nil;
  except
    on e: Exception do raise Exception.Create('Error loading theme files.' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------
procedure TDTheme.ImageAdjustRotate(image: Pointer);
begin
  if image <> nil then
  begin
    if Fsite = bsLeft then GdipImageRotateFlip(image, Rotate90FlipNone)
    else if Fsite = bsTop then GdipImageRotateFlip(image, Rotate180FlipX)
    else if Fsite = bsRight then GdipImageRotateFlip(image, Rotate270FlipNone);
  end;
end;
//------------------------------------------------------------------------------
function TDTheme.CorrectMargins(margins: Windows.TRect): Windows.TRect;
begin
  Result := margins;
  if Fsite = bsLeft then
  begin
    Result.Left := margins.Bottom;
    Result.Top := margins.Left;
    Result.Right := margins.Top;
    Result.Bottom := margins.Right;
  end
  else if Fsite = bsTop then
  begin
    Result.Top := margins.Bottom;
    Result.Bottom := margins.Top;
  end
  else if Fsite = bsRight then
  begin
    Result.Left := margins.Top;
    Result.Top := margins.Right;
    Result.Right := margins.Bottom;
    Result.Bottom := margins.Left;
  end;
end;
//------------------------------------------------------------------------------
function TDTheme.CorrectSize(size: Windows.TSize): Windows.TSize;
begin
  Result := size;
  if (Fsite = bsLeft) or (Fsite = bsRight) then
  begin
    Result.cx := size.cy;
    Result.cy := size.cx;
  end;
end;
//------------------------------------------------------------------------------
function TDTheme.CorrectCoords(coord: Windows.TPoint; W, H: integer): Windows.TPoint;
begin
  result.x := coord.x;
  result.y := coord.y;
  if Fsite = bsLeft then
  begin
    result.y := result.x;
    result.x := W - coord.y;
  end else
  if Fsite = bsTop then
  begin
    result.y := H - result.y;
  end else
  if Fsite = bsRight then
  begin
    result.x := result.y;
    result.y := H - coord.x;
  end;
end;
//------------------------------------------------------------------------------
procedure TDTheme.DrawBackground(hGDIPGraphics: Pointer; r: GDIPAPI.TRect; alpha: integer);
var
  marg, area: Windows.TRect;
begin
  marg := CorrectMargins(Background.Margins);
  area := CorrectMargins(FItemsArea);
  inc(marg.Left, area.Left);
  inc(marg.Top, area.Top);
  inc(marg.Right, area.Right);
  inc(marg.Bottom, area.Bottom);
  gfx.DrawEx(hGDIPGraphics, Background.Image, Background.W, Background.H,
    rect(r.x, r.y, r.Width, r.Height), marg, Background.StretchStyle, alpha);
end;
//------------------------------------------------------------------------------
procedure TDTheme.DrawIndicator(dst: Pointer; Left, Top, Size, Site: integer);
begin
  if assigned(Indicator.Image) then
  try
    if Site = 0 then
    begin
      Left -= Indicator.W div 2;
      if FItemsArea.Top < 0 then Left += FItemsArea.Top + FItemsArea2.Top;
      Top += (Size - Indicator.H) div 2;
    end
    else
    if Site = 1 then
    begin
      Left += (Size - Indicator.W) div 2;
      Top -= Indicator.H div 2;
      if FItemsArea.Top < 0 then Top += FItemsArea.Top + FItemsArea2.Top;
    end
    else
    if Site = 2 then
    begin
      Left += Size - Indicator.W div 2;
      if FItemsArea.Top < 0 then Left -= FItemsArea.Top + FItemsArea2.Top;
      Top += (Size - Indicator.H) div 2;
    end
    else
    if Site = 3 then
    begin
      Left += (Size - Indicator.W) div 2;
      Top += Size - Indicator.H div 2;
      if FItemsArea.Top < 0 then Top -= FItemsArea.Top + FItemsArea2.Top;
    end;

    GdipDrawImageRectRectI(dst, Indicator.Image, Left, Top, Indicator.W, Indicator.H,
      0, 0, Indicator.W, Indicator.H, UnitPixel, nil, nil, nil);
  except
    on e: Exception do raise Exception.Create('DrawIndicator' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------
function TDTheme.DrawButton(dst: Pointer; Left, Top, Size: integer; Attention: boolean): boolean;
var
  img: pointer;
  marg, area: Windows.TRect;
begin
  result := false;
  img := Button.Image;
  marg := CorrectMargins(Button.Margins);
  area := CorrectMargins(Button.Area);
  if Attention and assigned(Button.AttentionImage) then img := Button.AttentionImage;
  if assigned(img) then
  begin
    gfx.DrawEx(dst, img, Button.W, Button.H,
      rect(Left + area.Left, Top + area.Top, Size - area.Left - area.Right, Size - area.Top - area.Bottom),
      marg, ssStretch, 255);
    result := true;
  end;
end;
//------------------------------------------------------------------------------
function TDTheme.BlurEnabled: boolean;
begin
  result := FBlurRegionPointsCount > 1;
end;
//------------------------------------------------------------------------------
function TDTheme.GetBlurRgn(r: GDIPAPI.TRect): HRGN;
var
  bm: windows.TRect;
  ba: windows.TRect;
  br: windows.TSize;
  pts: array [0..MAX_REGION_POINTS - 1] of windows.TPoint;
  idx: integer;
begin
  result := 0;
  if not BlurEnabled then exit;

  if FBlurRegionPointsCount = 2 then
  begin
    ba := CorrectMargins(FBlurRect);
    result := CreateRectRgn(r.x + ba.Left, r.y + ba.Top, r.x + r.Width - ba.Right, r.y + r.Height - ba.Bottom);
  end else
  if FBlurRegionPointsCount = 3 then
  begin
    ba := CorrectMargins(FBlurRect);
    br := CorrectSize(FBlurR);
    result := CreateRoundRectRgn(r.x + ba.Left, r.y + ba.Top, r.x + r.Width - ba.Right, r.y + r.Height - ba.Bottom, br.cx, br.cy);
  end else
  begin
    bm := CorrectMargins(Background.Margins);
    ba := CorrectMargins(FItemsArea);
    inc(bm.Left, ba.Left);
    inc(bm.Top, ba.Top);
    inc(bm.Right, ba.Right);
    inc(bm.Bottom, ba.Bottom);
    idx := 0;
    while idx < FBlurRegionPointsCount do
    begin
      pts[idx] := CorrectCoords(FBlurRegionPoints[idx], Background.W, Background.H);

      if pts[idx].x <= bm.Left then pts[idx].x := r.x + pts[idx].x
      else
      if pts[idx].x >= Background.W - bm.Right then pts[idx].x := r.x + r.Width - (Background.W - pts[idx].x)
      else
        pts[idx].x := r.x + round((pts[idx].x - bm.Left) * (r.Width - bm.Left - bm.Right) / (Background.W - bm.Left - bm.Right)) + bm.Left;

      if pts[idx].y <= bm.Top then pts[idx].y := r.y + pts[idx].y
      else
      if pts[idx].y >= Background.H - bm.Bottom then pts[idx].y := r.y + r.Height - (Background.H - pts[idx].y)
      else
        pts[idx].y := r.y + round((pts[idx].y - bm.Top) * (r.Height - bm.Top - bm.Bottom) / (Background.H - bm.Top - bm.Bottom)) + bm.Top;

      inc(idx);
    end;
    result := CreatePolygonRgn(pts, FBlurRegionPointsCount, WINDING);
  end;
end;
//------------------------------------------------------------------------------
function TDTheme.GetBlurRect(r: GDIPAPI.TRect): GDIPAPI.TRect;
var
  ba: windows.TRect;
begin
  result := r;
  if BlurEnabled then
  begin
    ba := CorrectMargins(FBlurRect);
    result.x := r.x + ba.Left;
    result.y := r.y + ba.Top;
    result.width := r.Width - ba.Left - ba.Right;
    result.height := r.Height - ba.Top - ba.Bottom;
	end;
end;
//------------------------------------------------------------------------------
procedure TDTheme.MakeDefaultTheme;
begin
  is_default := True;

  Background.StretchStyle := ssStretch;
  Background.Margins := rect(0, 4, 0, 0);
  ItemsArea := rect(16, 11, 16, 3);
  BlurRegion := '';
  Separator.Margins := rect(0, 0, 0, 0);

  Path := '';
  ReloadGraphics;
end;
//------------------------------------------------------------------------------
procedure TDTheme.CheckExtractFileFromResource(ResourceName: PChar; filename: string);
begin
  if not FileExists(filename) then ExtractFileFromResource(ResourceName, filename);
end;
//------------------------------------------------------------------------------
procedure TDTheme.ExtractFileFromResource(ResourceName: PChar; filename: string);
var
  rs: TResourceStream;
  fs: TFileStream;
  irs: IStream;
  ifs: IStream;
  Read, written: QWord;
begin
  rs := TResourceStream.Create(hInstance, ResourceName, RT_RCDATA);
  fs := TFileStream.Create(filename, fmCreate);
  irs := TStreamAdapter.Create(rs, soReference) as IStream;
  ifs := TStreamAdapter.Create(fs, soReference) as IStream;
  irs.CopyTo(ifs, rs.Size, Read, written);
  if (Read <> written) or (Read <> rs.Size) then
    messagebox(application.mainform.handle, 'Error writing file from resource', 'Terry.Theme.ExtractFileFromResource', 0);
  rs.Free;
  fs.Free;
end;
//------------------------------------------------------------------------------
procedure TDTheme.SearchThemes(ThemeName: string; lb: TListBox);
var
  fhandle: THandle;
  f: TWin32FindData;
  idx: integer;
begin
  lb.items.BeginUpdate;
  lb.items.Clear;

  fhandle := FindFirstFile(PChar(FThemesFolder + '*.*'), f);
  if not (fhandle = THandle(-1)) then
    if ((f.dwFileAttributes and 16) = 16) then lb.items.add(AnsiToUTF8(f.cFileName));
  while FindNextFile(fhandle, f) do
    if ((f.dwFileAttributes and 16) = 16) then lb.items.add(AnsiToUTF8(f.cFileName));
  if not (fhandle = THandle(-1)) then Windows.FindClose(fhandle);

  idx := 0;
  while idx < lb.items.Count do
    if (lb.items.strings[idx] = '.') or (lb.items.strings[idx] = '..') or
      not FileExists(FThemesFolder + UTF8ToAnsi(lb.items.strings[idx]) + '\background.ini') then
      lb.items.Delete(idx)
    else
      Inc(idx);

  lb.ItemIndex := lb.items.indexof(AnsiToUTF8(ThemeName));
  lb.items.EndUpdate;
end;
//------------------------------------------------------------------------------
procedure TDTheme.ThemesMenu(ThemeName: string; hMenu: THandle);
  procedure AppendMI(name: string; var idx: integer);
  var
    flags: cardinal;
  begin
    if (name <> '.') and (name <> '..') then
      if FileExists(FThemesFolder + name + '\background.ini') then
      begin
        flags := MF_STRING;
        if name = ThemeName then flags += MF_CHECKED;
        AppendMenuW(hMenu, flags, idx, pwchar(WideString(name)));
        inc(idx);
      end;
  end;

var
  fhandle: THandle;
  f: TWin32FindData;
  idx: integer;
begin
  idx := 1;
  fhandle := FindFirstFile(PChar(FThemesFolder + '*.*'), f);
  if not (fhandle = THandle(-1)) then
    if ((f.dwFileAttributes and 16) = 16) then AppendMI(f.cFileName, idx);
  while FindNextFile(fhandle, f) do
    if ((f.dwFileAttributes and 16) = 16) then AppendMI(f.cFileName, idx);
  if not (fhandle = THandle(-1)) then Windows.FindClose(fhandle);
end;
//------------------------------------------------------------------------------
destructor TDTheme.Destroy;
begin
  Clear;
  ClearGraphics;
  inherited;
end;
//------------------------------------------------------------------------------
end.

