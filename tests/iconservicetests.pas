unit iconservicetests;
{$mode delphi}

interface

uses Windows, SysUtils, Classes, ActiveX, ComObj, ShlObj, GDIPAPI,
  iconserviceu, fpcunit, testregistry, PIDL, Forms, frmitemoptu;

type
  TIconServiceTests = class(TTestCase)
  private
    FImage: Pointer;
    FWidth, FHeight: UINT;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure ApplicationIDUsesRequestedShellIcon;
    procedure FactoryPreservesAlphaAndReleasesBitmap;
    procedure FailedFactoryReleasesPartialBitmap;
    procedure MissingTargetHonorsDefaultPolicy;
    procedure PIDLRemainsOwnedByCaller;
    procedure SerializedPIDLUsesFactory;
    procedure ShellNameUsesFactory;
    procedure RequestedSizeFitsWholeImage;
    procedure IndependentResultsSurviveReplacement;
    procedure CustomPNGHasPriorityAndKeepsAspect;
    procedure IndexedResourceLoadsWithoutFactory;
    procedure BorrowedWindowIconSurvivesLoading;
    procedure NativeFileLoadsWithoutTestFactory;
    procedure RepeatedLoadsReleaseNativeHandles;
    procedure CalculatorPropertiesUsesSharedLoader;
    procedure PIDLPropertiesUsesSharedLoader;
    procedure PackageArtworkReplacesPaddedTile;
    procedure PackagePIDLUsesUnplatedArtwork;
    procedure TaskImageFallsBackToWindow;
    procedure AsyncTaskImageKeepsFilePreference;
    procedure AsyncTaskImageReplacesSmallFileIcon;
    procedure NonAppIDUsesAppsFolderIcon;
    procedure AppsFolderPrefixesUseCanonicalIconName;
    procedure OrdinaryBangTargetsDoNotUseAppsFolder;
  end;

implementation

uses asyncwindowiconu;

type
  TTestFactory = class(TInterfacedObject, IShellItemImageFactory)
    function GetImage(Size: Windows.TSize; Flags: UINT; out Bitmap: HBITMAP): HRESULT; stdcall;
  end;

var
  FactoryCalls, ImageCalls: Integer;
  RequestedName: UnicodeString;
  RequestedSize: Windows.TSize;
  RequestedFlags: UINT;
  ReturnedBitmap: HBITMAP;
  RequestedPIDL: PItemIDList;
  FactoryFails: Boolean;
  FactoryWidth, FactoryHeight: Integer;
  PackageLogo: UnicodeString;

function TTestFactory.GetImage(Size: Windows.TSize; Flags: UINT;
  out Bitmap: HBITMAP): HRESULT;
var Info: BITMAPINFO; Pixels: PCardinal; I: Integer;
begin
  Inc(ImageCalls);
  RequestedSize := Size;
  RequestedFlags := Flags;
  if FactoryWidth > 0 then Size.cx := FactoryWidth;
  if FactoryHeight > 0 then Size.cy := FactoryHeight;
  FillChar(Info, SizeOf(Info), 0);
  Info.bmiHeader.biSize := SizeOf(Info.bmiHeader);
  Info.bmiHeader.biWidth := Size.cx;
  Info.bmiHeader.biHeight := -Size.cy;
  Info.bmiHeader.biPlanes := 1;
  Info.bmiHeader.biBitCount := 32;
  Info.bmiHeader.biCompression := BI_RGB;
  Bitmap := CreateDIBSection(0, Info, DIB_RGB_COLORS, Pointer(Pixels), 0, 0);
  if Bitmap = 0 then Exit(E_OUTOFMEMORY);
  ReturnedBitmap := Bitmap;
  for I := 0 to Size.cx * Size.cy - 1 do Pixels[I] := $FFFFAA00;
  Pixels[0] := 0;
  Pixels[1] := $80804000;
  if FactoryFails then Result := E_FAIL else Result := S_OK;
end;

function ResolveFactory(const Name: UnicodeString; IDList: PItemIDList;
  out Factory: IShellItemImageFactory): HRESULT;
begin
  Inc(FactoryCalls);
  RequestedName := Name;
  RequestedPIDL := IDList;
  Factory := TTestFactory.Create;
  Result := S_OK;
end;

function ResolvePackageArtwork(const Name: UnicodeString; IDList: PItemIDList;
  out LogoPath: UnicodeString): Boolean;
begin
  LogoPath := PackageLogo;
  Result := LogoPath <> '';
end;

procedure TIconServiceTests.SetUp;
begin
  OleCheck(OleInitialize(nil));
  FImage := nil;
  PackageLogo := '';
  ResolvePackageArtworkForTests := ResolvePackageArtwork;
  FactoryCalls := 0;
  ImageCalls := 0;
  ReturnedBitmap := 0;
  RequestedName := '';
  RequestedPIDL := nil;
  FactoryFails := False;
  FactoryWidth := 0;
  FactoryHeight := 0;
  ResolveIconFactoryForTests := ResolveFactory;
end;

procedure TIconServiceTests.TearDown;
begin
  ResolveIconFactoryForTests := nil;
  ResolvePackageArtworkForTests := nil;
  if FImage <> nil then GdipDisposeImage(FImage);
  OleUninitialize;
end;

procedure TIconServiceTests.ApplicationIDUsesRequestedShellIcon;
const AppID = 'Microsoft.WindowsCalculator_8wekyb3d8bbwe!App';
begin
  LoadTargetImage(AppID, 128, True, True, FImage, FWidth, FHeight);
  AssertEquals('Application icons must use the Shell image factory', 1, FactoryCalls);
  AssertEquals('Application IDs need AppsFolder', 'shell:AppsFolder\' + AppID, UTF8Encode(RequestedName));
  AssertEquals('The Shell request must use the display size', 128, RequestedSize.cx);
  AssertEquals('The Shell request must use the display size', 128, RequestedSize.cy);
  AssertTrue('The caller must receive an image', FImage <> nil);
end;

procedure TIconServiceTests.NonAppIDUsesAppsFolderIcon;
const AppID = 'TDOCK.Test_8wekyb3d8bbwe!Main';
begin
  LoadTargetImage(AppID, 64, True, False, FImage, FWidth, FHeight);
  AssertEquals(1, FactoryCalls);
  AssertEquals('shell:AppsFolder\' + AppID, UTF8Encode(RequestedName));
  AssertTrue(FImage <> nil);
end;

procedure TIconServiceTests.AppsFolderPrefixesUseCanonicalIconName;
const
  AppID = 'TDOCK.Test_8wekyb3d8bbwe!Main';
  AppsGUID = '{4234d49b-0245-4df3-b780-3893943456e1}';
begin
  LoadTargetImage('ShElL:ApPsFoLdEr\' + AppID, 64, True, False, FImage, FWidth, FHeight);
  AssertEquals('shell:AppsFolder\' + AppID, UTF8Encode(RequestedName));
  LoadTargetImage('shell:::' + AppsGUID + '\' + AppID, 64, True, False, FImage, FWidth, FHeight);
  AssertEquals('shell:AppsFolder\' + AppID, UTF8Encode(RequestedName));
  LoadTargetImage('::' + AppsGUID + '\' + AppID, 64, True, False, FImage, FWidth, FHeight);
  AssertEquals('shell:AppsFolder\' + AppID, UTF8Encode(RequestedName));
  AssertEquals(3, FactoryCalls);
end;

procedure TIconServiceTests.OrdinaryBangTargetsDoNotUseAppsFolder;
begin
  LoadTargetImage('custom:!App', 64, True, False, FImage, FWidth, FHeight);
  LoadTargetImage('https://example.invalid/!App', 64, True, False, FImage, FWidth, FHeight);
  LoadTargetImage('C:\TDOCK.Missing!App', 64, True, False, FImage, FWidth, FHeight);
  LoadTargetImage('Example!App', 64, True, False, FImage, FWidth, FHeight);
  AssertEquals('Ordinary targets must not receive an AppsFolder prefix', 0, FactoryCalls);
end;

procedure TIconServiceTests.FactoryPreservesAlphaAndReleasesBitmap;
var Pixel: ARGB; Native: Windows.BITMAP;
begin
  LoadTargetImage('TDOCK.Test_8wekyb3d8bbwe!App', 64, True, False, FImage, FWidth, FHeight);
  AssertEquals('Icons only', SIIGBF_ICONONLY or SIIGBF_BIGGERSIZEOK, RequestedFlags);
  AssertEquals('The loader must not request a tile background', 0,
    RequestedFlags and SIIGBF_ICONBACKGROUND);
  AssertEquals('Transparent pixels must remain transparent', Ord(Ok),
    Ord(GdipBitmapGetPixel(FImage, 0, 0, Pixel)));
  AssertEquals('Alpha must survive the native copy', Cardinal(0), Pixel);
  GdipBitmapGetPixel(FImage, 1, 0, Pixel);
  AssertEquals('Partial alpha must survive the native copy', Cardinal(128), Pixel shr 24);
  GdipBitmapGetPixel(FImage, 32, 32, Pixel);
  AssertEquals('The image must retain its color', Cardinal($FFFFAA00), Pixel);
  AssertEquals('The native bitmap must be released', 0,
    GetObject(ReturnedBitmap, SizeOf(Native), @Native));
end;

procedure TIconServiceTests.FailedFactoryReleasesPartialBitmap;
var Native: Windows.BITMAP;
begin
  FactoryFails := True;
  LoadTargetImage('shell:TDOCK_MISSING_ICON_00000', 64, True, False, FImage, FWidth, FHeight);
  AssertEquals('Partial native output must be released', 0,
    GetObject(ReturnedBitmap, SizeOf(Native), @Native));
  AssertTrue('Failure without a default must return nil', FImage = nil);
  AssertEquals('Failed width must be zero', 0, FWidth);
  AssertEquals('Failed height must be zero', 0, FHeight);
end;

procedure TIconServiceTests.MissingTargetHonorsDefaultPolicy;
begin
  LoadTargetImage('TDOCK_MISSING_ICON_00000.exe', 48, True, False, FImage, FWidth, FHeight);
  AssertTrue('Missing files must return nil without a default', FImage = nil);
  LoadTargetImage('TDOCK_MISSING_ICON_00000.exe', 48, True, True, FImage, FWidth, FHeight);
  AssertTrue('The default must supply an owned image', FImage <> nil);
  AssertEquals('The default must fit the requested size', 48, FWidth);
end;

function FixturePIDL: PItemIDList;
begin
  Result := nil;
  OleCheck(SHParseDisplayName(PWideChar(UnicodeString(GetEnvironmentVariable('SystemRoot') +
    '\System32\notepad.exe')), nil, Result, 0, nil));
end;

procedure TIconServiceTests.PIDLRemainsOwnedByCaller;
var IDList: PItemIDList; Saved: string;
begin
  IDList := FixturePIDL;
  try
    Saved := PIDL_ToString(IDList);
    LoadImageFromPIDL(IDList, 64, True, False, FImage, FWidth, FHeight);
    AssertTrue('The factory must receive the supplied PIDL', RequestedPIDL = IDList);
    AssertEquals('The input PIDL must remain readable', Saved, PIDL_ToString(IDList));
  finally PIDL_Free(IDList); end;
end;

procedure TIconServiceTests.SerializedPIDLUsesFactory;
var IDList: PItemIDList; Saved: string;
begin
  IDList := FixturePIDL;
  try Saved := PIDL_ToString(IDList); finally PIDL_Free(IDList); end;
  LoadTargetImage(Saved, 96, True, False, FImage, FWidth, FHeight);
  AssertEquals('Serialized PIDLs need the same factory', 1, FactoryCalls);
  AssertTrue('The service must decode the PIDL', RequestedPIDL <> nil);
  AssertTrue('The caller must receive an independent image', FImage <> nil);
end;

procedure TIconServiceTests.ShellNameUsesFactory;
const Name = 'shell:AppsFolder\TDOCK.Test_8wekyb3d8bbwe!App';
begin
  LoadTargetImage(Name, 80, True, False, FImage, FWidth, FHeight);
  AssertEquals('Shell names must remain unchanged', Name, UTF8Encode(RequestedName));
  LoadTargetImage('::{20D04FE0-3AEA-1069-A2D8-08002B30309D}', 80,
    True, False, FImage, FWidth, FHeight);
  AssertEquals('Namespace objects need the shared factory', 2, FactoryCalls);
end;

procedure TIconServiceTests.RequestedSizeFitsWholeImage;
begin
  FactoryWidth := 256;
  FactoryHeight := 128;
  LoadTargetImage('TDOCK.Test_8wekyb3d8bbwe!App', 64, True, False, FImage, FWidth, FHeight);
  AssertEquals('The whole image must fit without cropping', 64, FWidth);
  AssertEquals('The loader must preserve aspect ratio', 32, FHeight);
end;

procedure TIconServiceTests.IndependentResultsSurviveReplacement;
var Other: Pointer; W, H: UINT; Pixel: ARGB;
begin
  Other := nil;
  LoadTargetImage('TDOCK.Test_8wekyb3d8bbwe!App', 48, True, False, FImage, FWidth, FHeight);
  LoadTargetImage('TDOCK.Test_8wekyb3d8bbwe!App', 48, True, False, Other, W, H);
  try
    LoadTargetImage('TDOCK.Test_8wekyb3d8bbwe!App', 24, True, False, FImage, FWidth, FHeight);
    AssertEquals('Replacing one result must preserve another', Ord(Ok),
      Ord(GdipBitmapGetPixel(Other, 10, 10, Pixel)));
    AssertEquals('Each caller must own its pixels', Cardinal($FFFFAA00), Pixel);
  finally GdipDisposeImage(Other); end;
end;

procedure TIconServiceTests.CustomPNGHasPriorityAndKeepsAspect;
const PNGEncoder: TGUID = '{557CF406-1A04-11D3-9A73-0000F81EF32E}';
var Source: Pointer; Name: UnicodeString;
begin
  Name := UnicodeString(ExtractFilePath(ParamStr(0)) + 'override.png');
  Source := nil;
  AssertEquals('Create bitmap fixture', Ord(Ok),
    Ord(GdipCreateBitmapFromScan0(80, 40, 0, PixelFormat32bppPARGB, nil, Source)));
  try AssertEquals('Create PNG fixture', Ord(Ok), Ord(GdipSaveImageToFile(Source, PWideChar(Name), @PNGEncoder, nil)));
  finally GdipDisposeImage(Source); end;
  try
    LoadShortcutImage('TDOCK.Test_8wekyb3d8bbwe!App', Name, 64, True, False, FImage, FWidth, FHeight);
    AssertEquals('Custom PNGs must bypass Shell extraction', 0, FactoryCalls);
    AssertEquals('The PNG must fit', 64, FWidth);
    AssertEquals('The PNG must retain its aspect ratio', 32, FHeight);
  finally
    if FImage <> nil then GdipDisposeImage(FImage);
    FImage := nil;
    DeleteFileW(PWideChar(Name));
  end;
end;

procedure TIconServiceTests.IndexedResourceLoadsWithoutFactory;
begin
  LoadImage(UnicodeString(GetEnvironmentVariable('SystemRoot') +
    '\System32\shell32.dll,3'), 48, True, False, FImage, FWidth, FHeight);
  AssertTrue('Indexed resources must still load', FImage <> nil);
  AssertEquals('Explicit resource indices must bypass the factory', 0, FactoryCalls);
end;

function WaitForWindowIcon(Owner: HWND): Boolean;
var Started: QWord; Message: TMsg;
begin
  Started := GetTickCount64;
  Result := False;
  repeat
    while PeekMessage(Message, 0, 0, 0, PM_REMOVE) do
      if (Message.hwnd = Owner) and (Message.message = WINDOW_ICON_READY_MESSAGE) then Result := True
      else DispatchMessage(Message);
    if not Result then Sleep(1);
  until Result or (GetTickCount64 - Started > 1000);
end;

procedure TIconServiceTests.BorrowedWindowIconSurvivesLoading;
var Window: HWND; Icon: HICON; Info: ICONINFO;
begin
  Window := CreateWindowExW(0, 'STATIC', 'icon fixture', 0, 0, 0, 1, 1, 0, 0, HInstance, nil);
  AssertTrue('Create a native fixture window', Window <> 0);
  Icon := CopyIcon(LoadIcon(0, IDI_APPLICATION));
  try
    SendMessage(Window, WM_SETICON, ICON_BIG, Icon);
    LoadImageFromHWndAsync(Window, Window, 1, 64, True, False, FImage, FWidth, FHeight);
    AssertTrue('The window icon must become ready', WaitForWindowIcon(Window));
    AssertEquals('The window icon path must retain its source code', 2,
      LoadImageFromHWndAsync(Window, Window, 1, 64, True, False, FImage, FWidth, FHeight));
    AssertTrue('The result must contain an image', FImage <> nil);
    AssertTrue('The loader must preserve the borrowed icon', GetIconInfo(Icon, Info));
    DeleteObject(Info.hbmColor);
    DeleteObject(Info.hbmMask);
  finally
    UnsubscribeWindowIcons(Window);
    DestroyWindow(Window);
    DestroyIcon(Icon);
  end;
end;

procedure TIconServiceTests.NativeFileLoadsWithoutTestFactory;
begin
  ResolveIconFactoryForTests := nil;
  LoadImage(UnicodeString(GetEnvironmentVariable('SystemRoot') +
    '\System32\notepad.exe'), 96, True, False, FImage, FWidth, FHeight);
  AssertTrue('Native file extraction must load', FImage <> nil);
  AssertEquals('Native output must fit the display size', 96, FWidth);
end;

function GetGuiResources(Process: THandle; Flags: DWORD): DWORD; stdcall;
  external 'user32.dll' name 'GetGuiResources';

procedure TIconServiceTests.RepeatedLoadsReleaseNativeHandles;
var I: Integer; BeforeCount: DWORD;
begin
  LoadTargetImage('TDOCK.Test_8wekyb3d8bbwe!App', 64, True, False, FImage, FWidth, FHeight);
  BeforeCount := GetGuiResources(GetCurrentProcess, 0);
  for I := 1 to 100 do
    LoadTargetImage('TDOCK.Test_8wekyb3d8bbwe!App', 64, True, False, FImage, FWidth, FHeight);
  AssertEquals('Repeated loads must not retain GDI handles', BeforeCount,
    GetGuiResources(GetCurrentProcess, 0));
end;

procedure TIconServiceTests.CalculatorPropertiesUsesSharedLoader;
var Form: TfrmItemProp; Action: TCloseAction;
begin
  Form := TfrmItemProp.Create(nil);
  try
    Form.edCmd.Text := 'Microsoft.WindowsCalculator_8wekyb3d8bbwe!App';
    AssertEquals('Properties must resolve Calculator through AppsFolder',
      'shell:AppsFolder\Microsoft.WindowsCalculator_8wekyb3d8bbwe!App', UTF8Encode(RequestedName));
    AssertEquals('Properties must request a 128-pixel icon', 128, RequestedSize.cx);
    AssertTrue('Properties must load the icon', ImageCalls > 0);
  finally
    Form.FormClose(nil, Action);
    Form.Free;
  end;
end;

procedure TIconServiceTests.PIDLPropertiesUsesSharedLoader;
var Form: TfrmItemProp; Action: TCloseAction; IDList: PItemIDList; Saved: string;
begin
  IDList := FixturePIDL;
  try Saved := PIDL_ToString(IDList); finally PIDL_Free(IDList); end;
  Form := TfrmItemProp.Create(nil);
  try
    Form.edCmd.Text := Saved;
    AssertTrue('Properties must decode the PIDL through the shared loader', RequestedPIDL <> nil);
    AssertEquals('Properties must request the same display size', 128, RequestedSize.cx);
    AssertTrue('Properties must load the icon', ImageCalls > 0);
  finally
    Form.FormClose(nil, Action);
    Form.Free;
  end;
end;

procedure CheckPackageArtwork(Test: TIconServiceTests; AsPIDL: Boolean);
const PNGEncoder: TGUID = '{557CF406-1A04-11D3-9A73-0000F81EF32E}';
var Name: UnicodeString; Bitmap, Graphics: Pointer; IDList: PItemIDList; Pixel: ARGB;
  procedure WriteAsset(const Suffix: UnicodeString; Size: Integer; Color: ARGB);
  begin
    Name := ChangeFileExt(PackageLogo, '') + Suffix + '.png';
    Bitmap := nil;
    Graphics := nil;
    Test.AssertEquals('Create artwork fixture', Ord(Ok),
      Ord(GdipCreateBitmapFromScan0(Size, Size, 0, PixelFormat32bppPARGB, nil, Bitmap)));
    try
      GdipGetImageGraphicsContext(Bitmap, Graphics);
      GdipGraphicsClear(Graphics, Color);
      GdipDeleteGraphics(Graphics);
      GdipBitmapSetPixel(Bitmap, 0, 0, 0);
      Test.AssertEquals('Save artwork fixture', Ord(Ok),
        Ord(GdipSaveImageToFile(Bitmap, PWideChar(Name), @PNGEncoder, nil)));
    finally GdipDisposeImage(Bitmap); end;
  end;
begin
  PackageLogo := UnicodeString(ExtractFilePath(ParamStr(0)) + 'package-logo.png');
  WriteAsset('.targetsize-32_altform-unplated', 32, $FFFF0000);
  WriteAsset('.targetsize-256_altform-unplated', 256, $FF00FF00);
  WriteAsset('.targetsize-256_altform-unplated_contrast-white', 256, $FFFFFFFF);
  IDList := nil;
  try
    if AsPIDL then
    begin
      IDList := FixturePIDL;
      LoadImageFromPIDL(IDList, 128, True, False, Test.FImage, Test.FWidth, Test.FHeight);
    end
    else LoadTargetImage('TDOCK.Test_8wekyb3d8bbwe!App', 128, True, False,
      Test.FImage, Test.FWidth, Test.FHeight);
    Test.AssertEquals('Package artwork must replace the padded Shell tile', 0, FactoryCalls);
    Test.AssertEquals('Artwork must use the display size', 128, Test.FWidth);
    GdipBitmapGetPixel(Test.FImage, 64, 64, Pixel);
    Test.AssertEquals('Choose sufficient resolution and skip contrast variants', Cardinal($FF00FF00), Pixel);
    GdipBitmapGetPixel(Test.FImage, 0, 0, Pixel);
    Test.AssertTrue('The artwork must preserve transparent edges', (Pixel shr 24) < 255);
  finally
    PIDL_Free(IDList);
    if Test.FImage <> nil then GdipDisposeImage(Test.FImage);
    Test.FImage := nil;
    DeleteFileW(PWideChar(ChangeFileExt(PackageLogo, '') + '.targetsize-32_altform-unplated.png'));
    DeleteFileW(PWideChar(ChangeFileExt(PackageLogo, '') + '.targetsize-256_altform-unplated.png'));
    DeleteFileW(PWideChar(ChangeFileExt(PackageLogo, '') + '.targetsize-256_altform-unplated_contrast-white.png'));
  end;
end;

procedure TIconServiceTests.PackageArtworkReplacesPaddedTile;
begin CheckPackageArtwork(Self, False); end;

procedure TIconServiceTests.PackagePIDLUsesUnplatedArtwork;
begin CheckPackageArtwork(Self, True); end;

procedure TIconServiceTests.TaskImageFallsBackToWindow;
var Window: HWND; Icon: HICON;
begin
  Window := CreateWindowExW(0, 'STATIC', 'task icon fixture', 0, 0, 0, 1, 1,
    0, 0, HInstance, nil);
  AssertTrue('Create the task fixture window', Window <> 0);
  Icon := CopyIcon(LoadIcon(0, IDI_APPLICATION));
  try
    SendMessage(Window, WM_SETICON, ICON_BIG, Icon);
    LoadAppImageAsync('TDOCK_MISSING_ICON_00000.exe', Window, Window, 1, 64,
      False, False, FImage, FWidth, FHeight);
    AssertTrue('The task window icon must become ready', WaitForWindowIcon(Window));
    AssertEquals('Missing file icons must fall back to the window', 2,
      LoadAppImageAsync('TDOCK_MISSING_ICON_00000.exe', Window, Window, 1, 64,
        False, False, FImage, FWidth, FHeight));
    AssertTrue('Window fallback must supply an image', FImage <> nil);
  finally
    UnsubscribeWindowIcons(Window);
    DestroyWindow(Window);
    DestroyIcon(Icon);
  end;
end;

procedure TIconServiceTests.AsyncTaskImageKeepsFilePreference;
begin
  AssertEquals('Large file icons must retain priority in the UI loader', 1,
    LoadAppImageAsync(GetEnvironmentVariable('SystemRoot') + '\System32\notepad.exe',
      0, 0, 1, 64, False, False, FImage, FWidth, FHeight));
  AssertEquals('The UI loader must retain the shared factory', 1, FactoryCalls);
  AssertEquals('The UI file icon must retain its dimensions', 64, FWidth);
end;
procedure TIconServiceTests.AsyncTaskImageReplacesSmallFileIcon;
var Window, Owner: HWND; Icon: HICON;
begin
  Window := CreateWindowExW(0, 'STATIC', 'target', 0, 0, 0, 1, 1, 0, 0, HInstance, nil);
  Owner := CreateWindowExW(0, 'STATIC', 'owner', 0, 0, 0, 1, 1, 0, 0, HInstance, nil);
  Icon := CopyIcon(LoadIcon(0, IDI_APPLICATION));
  try
    SendMessage(Window, WM_SETICON, ICON_BIG, Icon);
    FactoryWidth := 16; FactoryHeight := 16;
    AssertEquals('The first request must retain the small file fallback', 1,
      LoadAppImageAsync(GetEnvironmentVariable('SystemRoot') + '\System32\notepad.exe',
        Window, Owner, 33, 64, False, False, FImage, FWidth, FHeight));
    AssertTrue('The small file fallback must subscribe for a window icon', WaitForWindowIcon(Owner));
    AssertEquals('The larger cached window icon must replace the small file icon', 2,
      LoadAppImageAsync(GetEnvironmentVariable('SystemRoot') + '\System32\notepad.exe',
        Window, Owner, 33, 64, False, False, FImage, FWidth, FHeight));
    AssertTrue('The selected window icon must exceed the file icon', FWidth > 16);
  finally
    UnsubscribeWindowIcons(Owner);
    DestroyWindow(Window);
    DestroyWindow(Owner);
    DestroyIcon(Icon);
  end;
end;
initialization
  RegisterTest(TIconServiceTests);
end.
