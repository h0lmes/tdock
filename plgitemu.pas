unit plgitemu;

interface
uses Windows, Messages, SysUtils, Controls, Classes, Dialogs, GDIPAPI,
  gfx, math, dynlibs, declu, DockH, customitemu, customdrawitemu, toolu, iniproc, itemserializationu;

type

  { TPluginItem }

  TPluginItem = class(TCustomDrawItem)
  protected
    lpData: Pointer;
    MouseDownPoint: windows.TPoint;
    AutoDeleteImage: boolean;
    AutoDeleteOverlay: boolean;
    FImage2: Pointer;
    FIW2: cardinal;
    FIH2: cardinal;
    hwnd2: HWND; // to speed up gdiplus drawing //
    FPluginFile: string;
    FIniFile: string;
    FIniSection: string;
    // plugin lib vars
    hLib: THandle;
    OnCreate: _OnCreate;
    OnSave: _OnSave;
    OnDestroy: _OnDestroy;
    OnLeftButtonClick: _OnLeftButtonClick;
    OnLeftButtonHeld: _OnLeftButtonHeld;
    OnDoubleClick: _OnDoubleClick;
    OnRightButtonClick: _OnRightButtonClick;
    OnConfigure: _OnConfigure;
    OnWndMessage: _OnProcessMessage;
    function ContextMenu(pt: Windows.TPoint): boolean;
    procedure LoadPlugin; virtual;
    function OpenPluginLibrary(const Filename: string): THandle; virtual;
    function CreatePluginData(Ini, Section: PChar): Pointer; virtual;
    procedure DestroyPluginData; virtual;
    function CopyPluginImage(Image: Pointer; AutoDelete: boolean;
      var ImageWidth, ImageHeight: UINT): Pointer; virtual;
    procedure ReleasePluginImage(Image: Pointer); virtual;
    procedure ReplacePluginImage(var CurrentImage: Pointer; var Owned: boolean;
      Source: Pointer; AutoDelete: boolean; var ImageWidth, ImageHeight: UINT);
    procedure DrawOverlay(dst: pointer; x, y, size: integer);
  public
    property Filename: string read FPluginFile;
    constructor Create(wndParent: HWND; var AParams: TDItemCreateParams); override;
    destructor Destroy; override;
    procedure FromIni(IniFile, IniSection: string);
    procedure FromString(value: string);
    procedure UpdateImage(AImage: Pointer; AutoDelete: boolean);
    procedure UpdateOverlay(AOverlay: Pointer; AutoDelete: boolean);
    procedure CallCreate;
    function ToString: string; override;
    function DblClick(button: TMouseButton; shift: TShiftState; x, y: integer): boolean; override;
    procedure MouseDown(button: TMouseButton; shift: TShiftState; x, y: integer); override;
    procedure MouseClick(button: TMouseButton; shift: TShiftState; x, y: integer); override;
    procedure MouseHeld(button: TMouseButton); override;
    procedure WndMessage(var msg: TMessage); override;
    procedure WMCommand(wParam: WPARAM; lParam: LPARAM; var Result: LRESULT); override;
    procedure Timer; override;
    procedure Configure; override;
    procedure Save(ini, section: string); override;
    procedure RecreateWindow; override;
    //
    class function Make(AFile: string): string;
  end;

procedure CopyPluginArgument(const Value: string; Destination: PChar; Capacity: SizeInt);

implementation

uses itemhostu, itemmodelu, itemviewu, loggeru;

type
  TPluginCallbackScope = record
    HostScope: TItemHostScope;
    ItemId: TItemId;
    Pinned: boolean;
  end;

procedure ReleasePluginModel(Id: TItemId);
begin
  try ReleaseItemModel(Id);
  except on E: Exception do
    try AddLog('PluginItem.DeferredDestroy' + LineEnding + E.Message); except end;
  end;
end;

function BeginPluginCallback(Item: TPluginItem; parent: HWND): TPluginCallbackScope;
var model: TItemModel;
begin
  result := Default(TPluginCallbackScope);
  result.ItemId := Item.ItemId;
  result.Pinned := AcquireItemModel(result.ItemId, model);
  try
    result.HostScope := BeginItemHostOperation(parent);
  except
    if result.Pinned then ReleasePluginModel(result.ItemId);
    raise;
  end;
end;

procedure EndPluginCallback(var Scope: TPluginCallbackScope);
begin
  try
    if Scope.Pinned then
    begin
      Scope.Pinned := false;
      ReleasePluginModel(Scope.ItemId);
    end;
  finally
    EndItemHostOperation(Scope.HostScope);
  end;
end;

procedure CopyPluginArgument(const Value: string; Destination: PChar; Capacity: SizeInt);
begin
  if (Destination = nil) or (Capacity <= 0) then exit;
  StrLCopy(Destination, PChar(Value), Capacity - 1);
end;

function TPluginItem.OpenPluginLibrary(const Filename: string): THandle;
begin
  result := LoadLibrary(Filename);
end;

procedure TPluginItem.RecreateWindow;
begin
  raise Exception.Create('Plugin windows must retain their native handle');
end;

function TPluginItem.CreatePluginData(Ini, Section: PChar): Pointer;
begin
  result := OnCreate(FHWnd, hLib, Ini, Section);
end;

procedure TPluginItem.DestroyPluginData;
begin
  if assigned(OnDestroy) then OnDestroy(lpData, FHWnd);
end;

function TPluginItem.CopyPluginImage(Image: Pointer; AutoDelete: boolean;
  var ImageWidth, ImageHeight: UINT): Pointer;
begin
  result := Image;
  DownscaleImage(result, FBigItemSize, false, ImageWidth, ImageHeight, AutoDelete);
end;

procedure TPluginItem.ReleasePluginImage(Image: Pointer);
begin
  if assigned(Image) then GdipDisposeImage(Image);
end;

procedure TPluginItem.ReplacePluginImage(var CurrentImage: Pointer; var Owned: boolean;
  Source: Pointer; AutoDelete: boolean; var ImageWidth, ImageHeight: UINT);
var newImage: Pointer; newWidth, newHeight: UINT;
begin
  newImage := CopyPluginImage(Source, AutoDelete, newWidth, newHeight);
  try
    if Owned then ReleasePluginImage(CurrentImage);
  except end;
  CurrentImage := newImage;
  Owned := assigned(newImage);
  ImageWidth := newWidth;
  ImageHeight := newHeight;
end;
//------------------------------------------------------------------------------
constructor TPluginItem.Create(wndParent: HWND; var AParams: TDItemCreateParams);
begin
  FFreed := true;
  inherited;
  FNeedMouseWheel := true;
  OnDrawOverlay := DrawOverlay;

  AutoDeleteImage := true;
  FImage := nil;
  AutoDeleteOverlay := true;
  FImage2 := nil;

  lpData := nil;

  // window to speed up drawing //
  hwnd2 := ItemViews.CreateAuxiliaryWindow(Self, TDITEM_WCLASS,
    WS_EX_LAYERED or WS_EX_TOOLWINDOW or WS_EX_NOACTIVATE);

  if AParams.IniFile <> '' then FromIni(AParams.IniFile, AParams.IniSection)
  else FromString(Aparams.Parameter);
end;
//------------------------------------------------------------------------------
procedure TPluginItem.FromIni(IniFile, IniSection: string);
begin
  FIniFile := IniFile;
  FIniSection := IniSection;
  if (length(IniFile) > 0) and (length(IniSection) > 0) then
  begin
    FPluginFile := toolu.UnzipPath(ReadIniStringW(FIniFile, FIniSection, 'file', ''));
    LoadPlugin;
  end;
end;
//------------------------------------------------------------------------------
procedure TPluginItem.FromString(value: string);
var Fields: TStringList;
begin
  FIniFile := '';
  FIniSection := '';
  Fields := ParseLegacyItemText(value);
  try FPluginFile := toolu.UnzipPath(Fields.Values['file']);
  finally Fields.Free; end;
  LoadPlugin;
end;
//------------------------------------------------------------------------------
procedure TPluginItem.LoadPlugin;
var previousDirectory: string;
begin
  previousDirectory := GetCurrentDir;
  try
    try
      FFreed := true;
      SetCurrentDir(ExtractFilePath(FPluginFile));
      hLib := OpenPluginLibrary(FPluginFile);
      if hLib = 0 then
      begin
        MessageBox(FHWnd, pchar('LoadLibrary(' + FPluginFile + ') failed'), 'CreatePlugin', 0);
        exit;
      end;
      @OnCreate           := GetProcAddress(hLib, 'OnCreate');
      @OnSave             := GetProcAddress(hLib, 'OnSave');
      @OnDestroy          := GetProcAddress(hLib, 'OnDestroy');
      @OnLeftButtonClick  := GetProcAddress(hLib, 'OnLeftButtonClick');
      @OnDoubleClick      := GetProcAddress(hLib, 'OnDoubleClick');
      @OnRightButtonClick := GetProcAddress(hLib, 'OnRightButtonClick');
      @OnConfigure        := GetProcAddress(hLib, 'OnConfigure');
      @OnWndMessage       := GetProcAddress(hLib, 'OnProcessMessage');
      if not assigned(OnCreate) then
      begin
        MessageBox(FHWnd, pchar('OnCreate(' + FPluginFile + ') is NULL'), 'CreatePlugin', 0);
        exit;
      end;
      FFreed := false;
    except
      on e: Exception do raise Exception.Create('PluginItem.LoadPlugin ' + LineEnding + e.message);
    end;
  finally
    SetCurrentDir(previousDirectory);
  end;
end;
//------------------------------------------------------------------------------
procedure TPluginItem.CallCreate;
var
  szIni, szIniGroup: array [0..MAX_PATH] of char;
  scope: TPluginCallbackScope;
begin
  if not FFreed and not assigned(lpData) then
  begin
    scope := BeginPluginCallback(Self, FHWndParent);
    try
      try
        if (FIniFile <> '') and (FIniSection <> '') then
        begin
          CopyPluginArgument(FIniFile, @szIni, SizeOf(szIni));
          CopyPluginArgument(FIniSection, @szIniGroup, SizeOf(szIniGroup));
          lpData := CreatePluginData(@szIni, @szIniGroup);
        end
        else lpData := CreatePluginData(nil, nil);
      except
        on e: Exception do raise Exception.Create('PluginItem.CallCreate(' + FIniFile + ', ' + FIniSection + ') ' + LineEnding + e.message);
      end;
    finally
      EndPluginCallback(scope);
    end;
  end;
end;
//------------------------------------------------------------------------------
destructor TPluginItem.Destroy;
var scope: TPluginCallbackScope;
begin
  try
    scope := BeginPluginCallback(Self, FHWndParent);
    try
      try
        DestroyPluginData;
      except
        on e: Exception do raise Exception.Create('PluginItem.OnDestroy ' + LineEnding + e.message);
      end;
    finally
      EndPluginCallback(scope);
    end;
  finally
    lpData := nil;
    try if AutoDeleteImage then ReleasePluginImage(FImage);
    except end;
    FImage := nil;
    try if AutoDeleteOverlay then ReleasePluginImage(FImage2);
    except end;
    FImage2 := nil;
    try ItemViews.DestroyWindow(hwnd2, ItemId);
    except end;
    hwnd2 := 0;
    // Plugins can retain native callbacks. Keep DLLs loaded until process exit.
    inherited;
  end;
end;
//------------------------------------------------------------------------------
procedure TPluginItem.UpdateImage(AImage: Pointer; AutoDelete: boolean);
begin
  if not FFreed then
  begin
    ReplacePluginImage(FImage, AutoDeleteImage, AImage, AutoDelete, FIW, FIH);
    if not FUndocked then Redraw;
  end;
end;
//------------------------------------------------------------------------------
procedure TPluginItem.UpdateOverlay(AOverlay: Pointer; AutoDelete: boolean);
begin
  if not FFreed then
  begin
    ReplacePluginImage(FImage2, AutoDeleteOverlay, AOverlay, AutoDelete, FIW2, FIH2);
    if not FUndocked then Redraw;
  end;
end;
//------------------------------------------------------------------------------
// Draw routines ---------------------------------------------------------------
procedure TPluginItem.DrawOverlay(dst: pointer; x, y, size: integer);
begin
  if assigned(FImage2) then GdipDrawImageRectRectI(dst, FImage2, x, y, size, size, 0, 0, FIW2, FIH2, UnitPixel, nil, nil, nil);
end;
// Draw routines ---------------------------------------------------------------
//------------------------------------------------------------------------------
procedure TPluginItem.Timer;
begin
  try
    inherited;
    if FFreed or FUpdating then exit;

  except
    on e: Exception do raise Exception.Create('PluginItem.Timer ' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------
procedure TPluginItem.Configure;
var scope: TPluginCallbackScope;
begin
  scope := BeginPluginCallback(Self, FHWndParent);
  try
    if assigned(OnConfigure) then OnConfigure(lpData);
  finally
    EndPluginCallback(scope);
  end;
end;
//------------------------------------------------------------------------------
function TPluginItem.ToString: string;
begin
  result := '';
  if not FFreed then
  begin
    result := result + '';
    result := 'class="plugin";' + LegacyItemField('file', toolu.ZipPath(FPluginFile)) +
      LegacyItemField('caption', FCaption);
  end;
end;
//------------------------------------------------------------------------------
function TPluginItem.DblClick(button: TMouseButton; shift: TShiftState; x, y: integer): boolean;
var
  sz: windows.TSize;
  scope: TPluginCallbackScope;
begin
  scope := BeginPluginCallback(Self, FHWndParent);
  try
    result := inherited DblClick(button, shift, x, y);
    if not FFreed then
    begin
      sz.cx := FSize;
      sz.cy := FSize;
      MouseDownPoint := point(x - Rect.Left, y - Rect.Top);
      if assigned(OnDoubleClick) then OnDoubleClick(lpData, @MouseDownPoint, @sz);
    end;
  finally
    EndPluginCallback(scope);
  end;
end;
//------------------------------------------------------------------------------
procedure TPluginItem.MouseDown(button: TMouseButton; shift: TShiftState; x, y: integer);
var scope: TPluginCallbackScope;
begin
  scope := BeginPluginCallback(Self, FHWndParent);
  try
    inherited;
    if not FFreed then MouseDownPoint := point(x - Rect.Left, y - Rect.Top);
  finally
    EndPluginCallback(scope);
  end;
end;
//------------------------------------------------------------------------------
procedure TPluginItem.MouseClick(button: TMouseButton; shift: TShiftState; x, y: integer);
var
  pt: windows.TPoint;
  sz: windows.TSize;
  result: boolean;
  scope: TPluginCallbackScope;
begin
  scope := BeginPluginCallback(Self, FHWndParent);
  try
    pt := point(x - Rect.Left, y - Rect.Top);
    sz.cx := FSize;
    sz.cy := FSize;

    if button = mbLeft then
      if assigned(OnLeftButtonClick) then OnLeftButtonClick(lpData, @pt, @sz);

    if button = mbRight then
    begin
      result := false;
      if assigned(OnRightButtonClick) then result := OnRightButtonClick(lpData, @pt, @sz);
      if not result then Configure;
    end;
  finally
    EndPluginCallback(scope);
  end;
end;
//------------------------------------------------------------------------------
procedure TPluginItem.MouseHeld(button: TMouseButton);
var
  pt: windows.TPoint;
  sz: windows.TSize;
  result: boolean;
  scope: TPluginCallbackScope;
begin
  scope := BeginPluginCallback(Self, FHWndParent);
  try
    inherited;
    if button = mbRight then
    begin
      result := false;
      if assigned(OnLeftButtonHeld) then
      begin
        pt := point(MouseDownPoint.x - Rect.Left, MouseDownPoint.y - Rect.Top);
        sz.cx := FSize;
        sz.cy := FSize;
        result := OnLeftButtonHeld(lpData, @pt, @sz);
      end;
      if not result then Configure;
    end;
  finally
    EndPluginCallback(scope);
  end;
end;
//------------------------------------------------------------------------------
function TPluginItem.ContextMenu(pt: Windows.TPoint): boolean;
var
  msg: TMessage;
  scope: TPluginCallbackScope;
begin
  scope := BeginPluginCallback(Self, FHWndParent);
  try
    result := false;

    FHMenu := CreatePopupMenu;
    AppendMenuW(FHMenu, MF_STRING, $f001, pwchar(UTF8Decode(XConfigureIcon)));
    if CanOpenFolder then AppendMenuW(FHMenu, MF_STRING, $f002, pwchar(UTF8Decode(XOpenFolderOf) + ' "' + Caption + '"'));
    AppendMenuW(FHMenu, MF_STRING, $f003, pwchar(UTF8Decode(XCopy)));
    AppendMenuW(FHMenu, MF_SEPARATOR, 0, '-');
    AppendMenuW(FHMenu, MF_STRING, $f004, pwchar(UTF8Decode(XDeleteIcon)));
    dockh.DockAddMenu(FHMenu);
    LME(true);

    // else, if it is disabled //
    msg.WParam := WPARAM(TrackPopupMenuEx(FHMenu, TPM_RETURNCMD, pt.x, pt.y, FHWnd, nil));
    WMCommand(msg.wParam, msg.lParam, msg.Result);
    Result := True;
  finally
    EndPluginCallback(scope);
  end;
end;
//------------------------------------------------------------------------------
procedure TPluginItem.WMCommand(wParam: WPARAM; lParam: LPARAM; var Result: LRESULT);
var scope: TPluginCallbackScope;
begin
  scope := BeginPluginCallback(Self, FHWndParent);
  try
    result := 0;
    LME(false);
    DestroyMenu(FHMenu);
    FHMenu := 0;
    case wParam of
      $f001: Configure;
      $f002: OpenFolder;
      $f003: toolu.SetClipboard(ToString);
      $f004: Delete;
    end;
  finally
    EndPluginCallback(scope);
  end;
end;
//------------------------------------------------------------------------------
procedure TPluginItem.WndMessage(var msg: TMessage);
var scope: TPluginCallbackScope;
begin
  msg.Result := 0;
  if not FFreed and assigned(OnWndMessage) then
  begin
    scope := BeginPluginCallback(Self, FHWndParent);
    try
      with msg do
        OnWndMessage(lpData, FHWnd, Msg, wParam, lParam);
    finally
      EndPluginCallback(scope);
    end;
  end;
end;
//------------------------------------------------------------------------------
procedure TPluginItem.Save(ini, section: string);
var scope: TPluginCallbackScope;
begin
  if (ini = '') or (section = '') then exit;
  scope := BeginPluginCallback(Self, FHWndParent);
  try
    try
      ClearIniSectionW(ini, section);
      WriteIniStringW(ini, section, 'class', 'plugin');
      WriteIniStringW(ini, section, 'file', toolu.ZipPath(FPluginFile));
      if assigned(OnSave) then OnSave(lpData, pchar(ini), pchar(section), false);
    except
      on E: Exception do raise Exception.Create('PluginItem.Save ' + LineEnding + 'Plugin DLL: ' + FPluginFile + LineEnding + e.message);
    end;
  finally
    EndPluginCallback(scope);
  end;
end;
//------------------------------------------------------------------------------
//
//
//
//
//
//------------------------------------------------------------------------------
class function TPluginItem.Make(AFile: string): string;
begin
  result := 'class="plugin";';
  if AFile <> '' then result := result + LegacyItemField('file', AFile);
end;
//------------------------------------------------------------------------------
end.
