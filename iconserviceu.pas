unit iconserviceu;

{$mode delphi}

interface

uses Windows, SysUtils, ShellAPI, ShlObj, ActiveX, GDIPAPI;

const
  IID_IShellItemImageFactory: TGUID = '{bcc18b79-ba16-442f-80c4-8a59c30c463b}';
  SIIGBF_BIGGERSIZEOK = $1;
  SIIGBF_ICONONLY = $4;
  SIIGBF_ICONBACKGROUND = $80;

type
  IShellItemImageFactory = interface(IUnknown)
    ['{bcc18b79-ba16-442f-80c4-8a59c30c463b}']
    function GetImage(Size: SIZE; Flags: UINT; out Bitmap: HBITMAP): HRESULT; stdcall;
  end;

function SHCreateItemFromParsingName(Name: PCWSTR; Bind: IBindCtx;
  const IID: TGUID; out Factory: IShellItemImageFactory): HRESULT; stdcall;
  external 'shell32.dll' name 'SHCreateItemFromParsingName';

// Inputs remain borrowed. Each result belongs to its caller.
procedure LoadImageFromPIDL(pidl: PItemIDList; MaxSize: Integer;
  exact, default: Boolean; var image: Pointer; var srcwidth, srcheight: UINT);
procedure LoadImageFromShellItem(Name: WideString; MaxSize: Integer;
  Exact, AllowDefault: Boolean; var Image: Pointer; var Width, Height: UINT);
// These UI loaders never send foreign window messages.
function LoadImageFromHWndAsync(AppWindow, Owner: THandle; Generation: WPARAM;
  MaxSize: Integer; Exact, AllowDefault: Boolean; var Image: Pointer;
  var Width, Height: UINT): Integer;
function LoadAppImageAsync(AppFile: string; AppWindow, Owner: THandle;
  Generation: WPARAM; MaxSize: Integer; Exact, AllowDefault: Boolean;
  var Image: Pointer; var Width, Height: UINT): Integer;
procedure LoadImage(ImageFile: WideString; MaxSize: Integer;
  Exact, AllowDefault: Boolean; var Image: Pointer; var Width, Height: UINT);

// Each loader replaces image with an independent, caller-owned GDI+ bitmap.
// The caller releases the returned bitmap with GdipDisposeImage.
procedure LoadTargetImage(const Target: UnicodeString; MaxSize: Integer;
  Exact, AllowDefault: Boolean; var Image: Pointer; var Width, Height: UINT);
procedure LoadShortcutImage(const Target, OverrideImage: UnicodeString; MaxSize: Integer;
  Exact, AllowDefault: Boolean; var Image: Pointer; var Width, Height: UINT);

{$ifdef ICONSERVICE_TESTS}
type
  TResolveIconFactory = function(const Name: UnicodeString; IDList: PItemIDList;
    out Factory: IShellItemImageFactory): HRESULT;
  TResolvePackageArtwork = function(const Name: UnicodeString; IDList: PItemIDList;
    out LogoPath: UnicodeString): Boolean;
var ResolvePackageArtworkForTests: TResolvePackageArtwork = nil;
    ResolveIconFactoryForTests: TResolveIconFactory = nil;
{$endif}

implementation

uses gfx, PIDL, shelltextu, asyncwindowiconu;

function SHCreateItemFromIDList(IDList: PItemIDList; const IID: TGUID;
  out Factory: IShellItemImageFactory): HRESULT; stdcall;
  external 'shell32.dll' name 'SHCreateItemFromIDList';

function SHGetPropertyStoreFromParsingName(Name: PWideChar; Bind: IBindCtx;
  Flags: DWORD; const IID: TGUID; out Store: IPropertyStore): HRESULT; stdcall;
  external 'shell32.dll' name 'SHGetPropertyStoreFromParsingName';
function SHGetPropertyStoreFromIDList(IDList: PItemIDList; Flags: DWORD;
  const IID: TGUID; out Store: IPropertyStore): HRESULT; stdcall;
  external 'shell32.dll' name 'SHGetPropertyStoreFromIDList';
function PSGetPropertyKeyFromName(Name: PWideChar; out Key: PROPERTYKEY): HRESULT; stdcall;
  external 'propsys.dll' name 'PSGetPropertyKeyFromName';
function ClearIconProperty(var Value: PROPVARIANT): HRESULT; stdcall;
  external 'ole32.dll' name 'PropVariantClear';
function SHLoadIndirectString(Source, Buffer: PWideChar; Count: UINT;
  Reserved: Pointer): HRESULT; stdcall;
  external 'shlwapi.dll' name 'SHLoadIndirectString';

function PropertyString(const Store: IPropertyStore; const Name: UnicodeString): UnicodeString;
var Key: PROPERTYKEY; Value: PROPVARIANT;
begin
  Result := '';
  if Failed(PSGetPropertyKeyFromName(PWideChar(Name), Key)) then Exit;
  FillChar(Value, SizeOf(Value), 0);
  try
    if Succeeded(Store.GetValue(@Key, Value)) and (Value.vt = VT_LPWSTR) and
      (Value.pwszVal <> nil) then Result := Value.pwszVal;
  finally ClearIconProperty(Value); end;
end;

function PackageLogoPath(const Name: UnicodeString; IDList: PItemIDList): UnicodeString;
const IID_PropertyStore: TGUID = '{886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99}';
var Store: IPropertyStore; Status: HRESULT;
  Root, Logo, Indirect: UnicodeString; Buffer: array[0..32767] of WideChar;
begin
  Result := '';
  {$ifdef ICONSERVICE_TESTS}
  if Assigned(ResolvePackageArtworkForTests) then
  begin
    if not ResolvePackageArtworkForTests(Name, IDList, Result) then Result := '';
    Exit;
  end;
  {$endif}
  Store := nil;
  if IDList <> nil then
    Status := SHGetPropertyStoreFromIDList(IDList, 0, IID_PropertyStore, Store)
  else Status := SHGetPropertyStoreFromParsingName(PWideChar(Name), nil, 0,
    IID_PropertyStore, Store);
  if Failed(Status) or (Store = nil) then Exit;
  Root := PropertyString(Store, 'System.AppUserModel.PackageInstallPath');
  Logo := PropertyString(Store, 'System.Tile.SmallLogoPath');
  if (Root = '') or (Logo = '') then Exit;
  if Pos('ms-resource:', LowerCase(Logo)) = 1 then
  begin
    Indirect := '@{' + PropertyString(Store, 'System.AppUserModel.PackageFullName') + '?' + Logo + '}';
    FillChar(Buffer, SizeOf(Buffer), 0);
    if Succeeded(SHLoadIndirectString(PWideChar(Indirect), @Buffer[0], Length(Buffer), nil)) then
      Result := PWideChar(@Buffer[0]);
  end
  else if (Pos(':', Logo) > 0) or (Copy(Logo, 1, 2) = '\\') then Result := Logo
  else Result := IncludeTrailingPathDelimiter(Root) + Logo;
end;

// Prefer unplated artwork, then the closest source at least as large as requested.
// Microsoft documents these qualifiers in the Windows app icon construction guide.
function PackageImage(const Name: UnicodeString; IDList: PItemIDList; MaxSize: Integer): Pointer;
var Logo, Stem, Ext, Folder, Qualifiers, FileName: UnicodeString;
  Found: WIN32_FIND_DATAW; Search: THandle;
  BestRank, BestDistance: Integer;
  procedure Consider(const Path: UnicodeString; Rank: Integer);
  var Candidate: Pointer; W, H: UINT; Size, Distance: Integer;
  begin
    Candidate := nil;
    if GdipCreateBitmapFromFile(PWideChar(Path), Candidate) <> Ok then Exit;
    try
      if (GdipGetImageWidth(Candidate, W) <> Ok) or
         (GdipGetImageHeight(Candidate, H) <> Ok) or (W = 0) or (H = 0) then Exit;
      Size := W;
      if H > W then Size := H;
      if Size >= MaxSize then Distance := Size - MaxSize
      else Distance := 1000000 + MaxSize - Size;
      if (Rank < BestRank) or ((Rank = BestRank) and (Distance < BestDistance)) then
      begin
        if Result <> nil then GdipDisposeImage(Result);
        Result := Candidate;
        Candidate := nil;
        BestRank := Rank;
        BestDistance := Distance;
      end;
    finally
      if Candidate <> nil then GdipDisposeImage(Candidate);
    end;
  end;
begin
  Result := nil;
  if MaxSize <= 0 then Exit;
  Logo := PackageLogoPath(Name, IDList);
  if Logo = '' then Exit;
  BestRank := MaxInt;
  BestDistance := MaxInt;
  Consider(Logo, 3);
  Ext := ExtractFileExt(Logo);
  Stem := Copy(Logo, 1, Length(Logo) - Length(Ext));
  Folder := ExtractFilePath(Logo);
  Search := FindFirstFileW(PWideChar(Stem + '.*' + Ext), Found);
  if Search = INVALID_HANDLE_VALUE then Exit;
  try
    repeat
      if (Found.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY) <> 0 then Continue;
      FileName := PWideChar(@Found.cFileName[0]);
      Qualifiers := LowerCase(Copy(FileName, Length(ExtractFileName(Stem)) + 1, MaxInt));
      if (Pos('contrast-', Qualifiers) > 0) or (Pos('theme-', Qualifiers) > 0) then Continue;
      if Pos('altform-', Qualifiers) > 0 then
      begin
        if Pos('altform-unplated', Qualifiers) = 0 then Continue;
        Consider(Folder + FileName, 0);
      end
      else if Pos('targetsize-', Qualifiers) > 0 then Consider(Folder + FileName, 1)
      else if Pos('scale-', Qualifiers) > 0 then Consider(Folder + FileName, 2);
    until not FindNextFileW(Search, Found);
  finally Windows.FindClose(Search); end;
end;

procedure ResetImage(var Image: Pointer; var Width, Height: UINT);
begin
  if Image <> nil then GdipDisposeImage(Image);
  Image := nil;
  Width := 0;
  Height := 0;
end;

// Copy pixels into GDI+ storage before releasing the Shell bitmap.
// GdipCreateBitmapFromHBITMAP discards the alpha channel.
function CopyShellBitmap(Bitmap: HBITMAP): Pointer;
var
  Native: Windows.BITMAP;
  Info: BITMAPINFO;
  Data: TBitmapData;
  Pixels: array of Cardinal;
  DC: HDC;
  W, H, Y, I: Integer;
  Row: PByte;
begin
  Result := nil;
  if GetObject(Bitmap, SizeOf(Native), @Native) = 0 then Exit;
  W := Native.bmWidth;
  H := Abs(Native.bmHeight);
  if (W <= 0) or (H <= 0) or (Int64(W) * H > MaxInt div 4) then Exit;
  SetLength(Pixels, W * H);
  FillChar(Info, SizeOf(Info), 0);
  Info.bmiHeader.biSize := SizeOf(Info.bmiHeader);
  Info.bmiHeader.biWidth := W;
  Info.bmiHeader.biHeight := -H;
  Info.bmiHeader.biPlanes := 1;
  Info.bmiHeader.biBitCount := 32;
  Info.bmiHeader.biCompression := BI_RGB;
  DC := GetDC(0);
  if DC = 0 then Exit;
  try
    if GetDIBits(DC, Bitmap, 0, H, @Pixels[0], Info, DIB_RGB_COLORS) <> H then Exit;
  finally
    ReleaseDC(0, DC);
  end;
  if Native.bmBitsPixel < 32 then
    for I := 0 to High(Pixels) do Pixels[I] := Pixels[I] or $FF000000;
  if GdipCreateBitmapFromScan0(W, H, 0, PixelFormat32bppPARGB, nil, Result) <> Ok then Exit(nil);
  FillChar(Data, SizeOf(Data), 0);
  if GdipBitmapLockBits(Result, nil, ImageLockModeWrite, PixelFormat32bppPARGB, @Data) <> Ok then
  begin
    GdipDisposeImage(Result);
    Exit(nil);
  end;
  try
    for Y := 0 to H - 1 do
    begin
      if Data.Stride >= 0 then Row := PByte(PtrUInt(Data.Scan0) + PtrUInt(Y) * PtrUInt(Data.Stride))
      else Row := PByte(PtrUInt(Data.Scan0) - PtrUInt(Y) * PtrUInt(-Data.Stride));
      Move(Pixels[Y * W], Row^, W * 4);
    end;
  finally
    GdipBitmapUnlockBits(Result, @Data);
  end;
end;

// Fit the whole image. Exact requests also enlarge smaller sources.
procedure FitImage(var Image: Pointer; MaxSize: Integer; Exact: Boolean;
  var Width, Height: UINT);
var W, H: UINT; NW, NH: Integer; Scale: Double;
  Dest, Graphics: Pointer;
begin
  Width := 0;
  Height := 0;
  if Image = nil then Exit;
  if (GdipGetImageWidth(Image, W) <> Ok) or
     (GdipGetImageHeight(Image, H) <> Ok) or (W = 0) or (H = 0) then
  begin
    ResetImage(Image, Width, Height);
    Exit;
  end;
  Width := W;
  Height := H;
  if (MaxSize <= 0) or ((not Exact) and (W <= UINT(MaxSize)) and (H <= UINT(MaxSize))) then Exit;
  if W > H then Scale := MaxSize / W else Scale := MaxSize / H;
  NW := Round(W * Scale);
  NH := Round(H * Scale);
  if NW < 1 then NW := 1;
  if NH < 1 then NH := 1;
  if (NW = Integer(W)) and (NH = Integer(H)) then Exit;
  Dest := nil;
  Graphics := nil;
  if GdipCreateBitmapFromScan0(NW, NH, 0, PixelFormat32bppPARGB, nil, Dest) <> Ok then Exit;
  try
    if GdipGetImageGraphicsContext(Dest, Graphics) <> Ok then Exit;
    GdipGraphicsClear(Graphics, 0);
    GdipSetInterpolationMode(Graphics, InterpolationModeHighQualityBicubic);
    if GdipDrawImageRectRectI(Graphics, Image, 0, 0, NW, NH, 0, 0, W, H,
      UnitPixel, nil, nil, nil) <> Ok then Exit;
    GdipDisposeImage(Image);
    Image := Dest;
    Dest := nil;
    Width := NW;
    Height := NH;
  finally
    if Graphics <> nil then GdipDeleteGraphics(Graphics);
    if Dest <> nil then GdipDisposeImage(Dest);
  end;
end;

function FactoryImage(const Name: UnicodeString; IDList: PItemIDList;
  MaxSize: Integer): Pointer;
var Factory: IShellItemImageFactory; Status: HRESULT;
  Size: Windows.TSize; Bitmap: HBITMAP;
begin
  Result := nil;
  if MaxSize <= 0 then Exit;
  Factory := nil;
  Bitmap := 0;
  {$ifdef ICONSERVICE_TESTS}
  if Assigned(ResolveIconFactoryForTests) then
    Status := ResolveIconFactoryForTests(Name, IDList, Factory)
  else
  {$endif}
  if IDList <> nil then
    Status := SHCreateItemFromIDList(IDList, IID_IShellItemImageFactory, Factory)
  else Status := SHCreateItemFromParsingName(PWideChar(Name), nil,
    IID_IShellItemImageFactory, Factory);
  if Failed(Status) or (Factory = nil) then Exit;
  Size.cx := MaxSize;
  Size.cy := MaxSize;
  try
    // Do not request a registered tile background.
    Status := Factory.GetImage(Size, SIIGBF_ICONONLY or SIIGBF_BIGGERSIZEOK, Bitmap);
    if Succeeded(Status) and (Bitmap <> 0) then Result := CopyShellBitmap(Bitmap);
  finally
    if Bitmap <> 0 then DeleteObject(Bitmap);
  end;
end;

function LegacyShellIcon(const Name: UnicodeString; IDList: PItemIDList;
  MaxSize: Integer): HICON;
var Info: TSHFileInfoW; Flags: UINT; Source: PWideChar;
begin
  FillChar(Info, SizeOf(Info), 0);
  Flags := SHGFI_ICON;
  if MaxSize <= 16 then Flags := Flags or SHGFI_SMALLICON;
  Source := PWideChar(Name);
  if IDList <> nil then
  begin
    Flags := Flags or SHGFI_PIDL;
    Source := PWideChar(IDList);
  end;
  if SHGetFileInfoW(Source, 0, Info, SizeOf(Info), Flags) = 0 then
  begin
    if Info.hIcon <> 0 then DestroyIcon(Info.hIcon);
    Exit(0);
  end;
  Result := Info.hIcon;
end;

procedure ShellImage(const Name: UnicodeString; IDList: PItemIDList;
  MaxSize: Integer; Exact, AllowDefault: Boolean; var Image: Pointer;
  var Width, Height: UINT);
var Icon: HICON;
begin
  ResetImage(Image, Width, Height);
  if (Name <> '') or (IDList <> nil) then
  begin
    Image := PackageImage(Name, IDList, MaxSize);
    if Image = nil then Image := FactoryImage(Name, IDList, MaxSize);
    if Image = nil then
    begin
      Icon := LegacyShellIcon(Name, IDList, MaxSize);
      if Icon <> 0 then
      try Image := IconToGDIPBitmap(Icon);
      finally DestroyIcon(Icon); end;
    end;
  end;
  if (Image = nil) and AllowDefault then CreateDefaultImage(Image);
  FitImage(Image, MaxSize, Exact, Width, Height);
end;

procedure LoadImageFromPIDL(pidl: PItemIDList; MaxSize: Integer;
  exact, default: Boolean; var image: Pointer; var srcwidth, srcheight: UINT);
begin
  // The input PIDL remains owned by the caller.
  ShellImage('', pidl, MaxSize, exact, default, image, srcwidth, srcheight);
end;

procedure LoadImageFromShellItem(Name: WideString; MaxSize: Integer;
  Exact, AllowDefault: Boolean; var Image: Pointer; var Width, Height: UINT);
begin
  ShellImage(name, nil, MaxSize, exact, AllowDefault, image, Width, Height);
end;

procedure LoadImage(ImageFile: WideString; MaxSize: Integer;
  Exact, AllowDefault: Boolean; var Image: Pointer; var Width, Height: UINT);
var Index, Comma: Integer; LargeIcon, SmallIcon: HICON; Ext: WideString;
begin
  ResetImage(image, Width, Height);
  Index := 0;
  Comma := Length(imagefile);
  while (Comma > 0) and (imagefile[Comma] <> ',') do Dec(Comma);
  if (Comma > 0) and TryStrToInt(string(Copy(imagefile, Comma + 1, MaxInt)), Index) then
    SetLength(imagefile, Comma - 1);
  if ShellPathExists(imagefile) then
  begin
    Ext := LowerCase(ExtractFileExt(imagefile));
    if (Ext = '.png') or (Ext = '.gif') then
    begin
      if GdipCreateBitmapFromFile(PWideChar(imagefile), image) <> Ok then image := nil;
    end
    else if Index <> 0 then
    begin
      LargeIcon := 0;
      SmallIcon := 0;
      try
        ExtractIconExW(PWideChar(imagefile), Index, LargeIcon, SmallIcon, 1);
        if LargeIcon <> 0 then image := IconToGDIPBitmap(LargeIcon)
        else if SmallIcon <> 0 then image := IconToGDIPBitmap(SmallIcon);
      finally
        if LargeIcon <> 0 then DestroyIcon(LargeIcon);
        if SmallIcon <> 0 then DestroyIcon(SmallIcon);
      end;
    end
    else image := FactoryImage(imagefile, nil, MaxSize);
    if (image = nil) and (Index = 0) then
    begin
      LargeIcon := LegacyShellIcon(imagefile, nil, MaxSize);
      if LargeIcon <> 0 then
      try image := IconToGDIPBitmap(LargeIcon);
      finally DestroyIcon(LargeIcon); end;
    end;
  end;
  if (image = nil) and AllowDefault then CreateDefaultImage(image);
  FitImage(image, MaxSize, exact, Width, Height);
end;

procedure LoadTargetImage(const Target: UnicodeString; MaxSize: Integer;
  Exact, AllowDefault: Boolean; var Image: Pointer; var Width, Height: UINT);
var IDList: PItemIDList; AppID: UnicodeString;
begin
  if IsPIDLString(UTF8Encode(Target)) then
  begin
    IDList := PIDL_FromString(UTF8Encode(Target));
    try LoadImageFromPIDL(IDList, MaxSize, Exact, AllowDefault, Image, Width, Height);
    finally PIDL_Free(IDList); end;
  end
  else if TryNormalizeAppTarget(Target, AppID) then
    LoadImageFromShellItem(APPS_FOLDER_PREFIX + AppID,
      MaxSize, Exact, AllowDefault, Image, Width, Height)
  else if (Pos('shell:', LowerCase(Target)) = 1) or (Pos('::', Target) = 1) then
    LoadImageFromShellItem(Target, MaxSize, Exact, AllowDefault, Image, Width, Height)
  else LoadImage(Target, MaxSize, Exact, AllowDefault, Image, Width, Height);
end;

procedure LoadShortcutImage(const Target, OverrideImage: UnicodeString; MaxSize: Integer;
  Exact, AllowDefault: Boolean; var Image: Pointer; var Width, Height: UINT);
begin
  if OverrideImage <> '' then
    LoadImage(OverrideImage, MaxSize, Exact, AllowDefault, Image, Width, Height)
  else LoadTargetImage(Target, MaxSize, Exact, AllowDefault, Image, Width, Height);
end;

function LoadImageFromHWndAsync(AppWindow, Owner: THandle; Generation: WPARAM;
  MaxSize: Integer; Exact, AllowDefault: Boolean; var Image: Pointer;
  var Width, Height: UINT): Integer;
var Icon: HICON; Service: TWindowIconService;
begin
  ResetImage(Image, Width, Height);
  Result := 0;
  Service := WindowIconService;
  Icon := 0;
  if Service <> nil then Icon := Service.Request(AppWindow, Owner, Generation, MaxSize);
  if Icon <> 0 then
  try
    Image := IconToGDIPBitmap(Icon);
    Result := 2;
  finally DestroyIcon(Icon); end;
  if (Image = nil) and AllowDefault then
  begin
    Image := IconToGDIPBitmap(LoadIcon(0, IDI_APPLICATION));
    Result := 6;
  end;
  FitImage(Image, MaxSize, Exact, Width, Height);
  if Image = nil then Result := 0;
end;

function LoadAppImageAsync(AppFile: string; AppWindow, Owner: THandle;
  Generation: WPARAM; MaxSize: Integer; Exact, AllowDefault: Boolean;
  var Image: Pointer; var Width, Height: UINT): Integer;
var FileImage, WindowImage: Pointer; FW, FH, WW, WH: UINT; Method: Integer;
begin
  ResetImage(Image, Width, Height);
  FileImage := nil;
  WindowImage := nil;
  FW := 0; FH := 0; WW := 0; WH := 0;
  Result := 0;
  try
    LoadImage(UnicodeString(AppFile), MaxSize, False, False, FileImage, FW, FH);
    Method := 0;
    if FW <= 32 then
      Method := LoadImageFromHWndAsync(AppWindow, Owner, Generation, MaxSize,
        False, False, WindowImage, WW, WH);
    if (WindowImage <> nil) and (WW > FW) then
    begin
      Image := WindowImage;
      WindowImage := nil;
      Result := Method;
    end
    else if FileImage <> nil then
    begin
      Image := FileImage;
      FileImage := nil;
      Result := 1;
    end;
    if (Image = nil) and AllowDefault then
    begin
      Image := IconToGDIPBitmap(LoadIcon(0, IDI_APPLICATION));
      Result := 6;
    end;
    FitImage(Image, MaxSize, Exact, Width, Height);
  finally
    if FileImage <> nil then GdipDisposeImage(FileImage);
    if WindowImage <> nil then GdipDisposeImage(WindowImage);
  end;
end;

end.
