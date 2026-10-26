unit stackitemu;

{$t+}

interface
uses Windows, Messages, SysUtils, Controls, Classes, ShellAPI, ComObj, ShlObj,
  Math, GDIPAPI, PIDL, dwm_unit, iniproc, gfx, iconserviceu, declu, toolu,
  stackmodeu, customdrawitemu, customsubitemu, scsubitemu, itemmodelu, itemserializationu, docktimingu;

const
  MAX_SUBITEMS = STACK_CHILD_LIMIT;
  STATE_PROGRESS_MIN = 0.0;
  STATE_PROGRESS_MAX = 1.0;
  DEF_ANIM_SPEED = 8;
  MID_ANIM_SPEED = 4;
  DEF_DISTORT = 1;
  DEF_STACK_PREVIEW = 1;

type
  TStackState = (stsClosed, stsOpening, stsOpen, stsClosing);

  PCSIBucket = ^TCSIBucket;
  TCSIBucket = record
    x: integer;
    y: integer;
    s: integer;
    alpha: integer;
    angle: single;
    hint_align: integer;
    hint_alpha: integer;
    draw: boolean;
    ItemId: TItemId;
    function GetItem: TCustomSubitem;
    function GetWindow: HWND;
    property item: TCustomSubitem read GetItem;
    property wnd: HWND read GetWindow;
  end;

  PSISubitemData = ^TSISubitemData;
  TSISubitemData = record
    Data: string;
    Name: string;
  end;

  { TStackItem }

  TStackItem = class(TCustomDrawItem)
  private
    procedure ApplyData(const Data: TStackDtoV1);
    function CaptureData: TStackDtoV1;
    function AddSubitemData(const Data: string; out AddedId: TItemId): boolean;
  {$ifdef ANIMATION_TIMING_TESTS}protected{$else}private{$endif}
    FImageFile: string;
    FSpecialFolder: string;
    FMode: integer;
    FOffset: integer;
    FAnimationSpeed: integer;
    FDistort: integer;
    FPreview: integer; // 0 - none, 1 - four, 2 - nine
    FShowBackground: boolean;
    FSorted: boolean;
    //
    FUseShellContextMenus: boolean;
    items: array of TCSIBucket; // using a dynamic array. static causes obscure error while deleting stackitem
    FChildren: TItemStore;
    FItemCount: integer;
    FState: TStackState;
    FStateProgress: extended;
    FStackAnimation: TScalarAnimation;
    FOpenAnimation: boolean;
    FDragOver: boolean;
    FPreviewImage: pointer;
    FPreviewImageW: uint;
    FPreviewImageH: uint;
    FWindowCount: integer;
    procedure BeforeDraw;
    procedure DrawOverlay(dst: pointer; x, y, size: integer);
    procedure Exec;
    function ContextMenu(pt: Windows.TPoint): boolean;
    procedure OnDragEnter;
    procedure OnDragOver;
    procedure OnDragLeave;
    function DropFileI(filename: string): boolean;
    // items handling //
    procedure UpdateSpecialFolder;
    procedure AddSpecialFolder(csidl: integer);
    procedure SortItems;
    procedure UpdatePreview;
    function MakeICP: TDItemCreateParams;
    procedure CheckDeleteSubitems;
    procedure DeleteSubitems;
    procedure FreeSubitem(Item: TCustomSubitem);
    procedure ChildRemoved(Id: TItemId);
    procedure SubitemSwap(index1, index2: integer);
    procedure CopyCSIBucket(pFrom, pTo: PCSIBucket);
    function ItemIndex(wnd: HWND): integer;
    procedure AllSubitemsCmd(id: TDParam; param: PtrInt);
    procedure OpenStack;
    procedure CloseStack(immediate: boolean = false);
    procedure DoStateProgress;
    procedure StartStackAnimation(Target: Double);
    procedure ShowAllItems(flag: boolean);
    procedure ShowStackState;
  protected
    function AnimationNow: QWord; virtual;
    function CreateSubitem: TCustomSubitem; virtual;
  public
    property ItemCount: integer read FItemCount;
    property ImageFile: string read FImageFile write FImageFile;
    property SpecialFolder: string read FSpecialFolder write FSpecialFolder;
    property Mode: integer read FMode write FMode;
    property Offset: integer read FOffset write FOffset;
    property AnimationSpeed: integer read FAnimationSpeed write FAnimationSpeed;
    property Distort: integer read FDistort write FDistort;
    property Preview: integer read FPreview write FPreview;
    property ShowBackground: boolean read FShowBackground write FShowBackground;
    property Sorted: boolean read FSorted write FSorted;
    //
    function ToStringFullCopy: string;
    //
    constructor Create(wndParent: HWND; var AParams: TDItemCreateParams); override;
    destructor Destroy; override;
    function ChildStore: TItemStore; override;
    procedure PrepareDeletion; override;
    procedure Init; override;
    procedure FromIni(IniFile, IniSection: string);
    procedure FromString(value: string);
    procedure Update;
    procedure SetFont(var Value: TDFontData); override;
    function ToString: string; override;
    procedure MouseClick(button: TMouseButton; shift: TShiftState; x, y: integer); override;
    procedure MouseHeld(button: TMouseButton); override;
    procedure WndMessage(var msg: TMessage); override;
    procedure WMCommand(wParam: WPARAM; lParam: LPARAM; var Result: LRESULT); override;
    function cmd(id: TDParam; param: PtrInt): PtrInt; override;
    procedure Timer; override;
    function NeedsFrame: boolean; override;
    procedure Configure; override;
    function DropFile(wnd: HWND; pt: windows.TPoint; filename: string): boolean; override;
    procedure Save(ini, section: string); override;
    //
    procedure AddSubitemDefault;
    function AddSubitem(data: string): boolean;
    function AddSubitems(Data: TStrings): boolean;
    function GetSubitemCaption(index: integer): WideString;
    function SubitemToString(index: integer): string;
    procedure DeleteSubitem(index: integer);
    procedure SubitemMoveUp(index: integer);
    procedure SubitemMoveDown(index: integer);
    procedure SubitemConfigure(index: integer);
    //
    class function Make(ACaption: WideString = ''; AImage: string = ''; ASpecialFolder: string = '';
      color_data: integer = DEF_COLOR_DATA; AMode: integer = 0;
      AOffset: integer = 0; AAnimationSpeed: integer = DEF_ANIM_SPEED;
      ADistort: integer = DEF_DISTORT; APreview: integer = DEF_STACK_PREVIEW;
      AShowBackground: boolean = false;
      ASorted: boolean = false): string;
  end;

implementation
uses themeu, frmstackpropu, itemregistryu, loggeru, itemviewu, shelltextu;
function TStackItem.AnimationNow: QWord;
begin Result := GetTickCount64; end;
//------------------------------------------------------------------------------
function TCSIBucket.GetItem: TCustomSubitem;
begin
  Result := TCustomSubitem(FindItemModel(ItemId));
end;
//------------------------------------------------------------------------------
function TCSIBucket.GetWindow: HWND;
begin
  Result := ItemViews.HandleOf(ItemId);
end;
//------------------------------------------------------------------------------
constructor TStackItem.Create(wndParent: HWND; var AParams: TDItemCreateParams);
begin
  inherited;
  FUseShellContextMenus := AParams.UseShellContextMenus;
  FOpenAnimation := AParams.StackAnimationEnabled;
  OnBeforeDraw := BeforeDraw;
  OnDrawOverlay := DrawOverlay;

  if AParams.IniFile <> '' then FromIni(AParams.IniFile, AParams.IniSection)
  else FromString(Aparams.Parameter);
end;
//------------------------------------------------------------------------------
procedure TStackItem.Init;
begin
  inherited;
  FImageFile := '';
  FChildren := TItemStore.Create;
  FChildren.OnRemoved := ChildRemoved;
  FItemCount := 0;
  SetLength(items, MAX_SUBITEMS);
  FState := stsClosed;
  FStateProgress := STATE_PROGRESS_MIN;
  FMode := 0;
  FOffset := 0;
  FAnimationSpeed := DEF_ANIM_SPEED;
  FOpenAnimation := true;
  FDistort := DEF_DISTORT;
  FDragOver := false;
  FSpecialFolder := '';
  FPreview := DEF_STACK_PREVIEW;
  FPreviewImage := nil;
  FShowBackground := false;
  FWindowCount := 0;
end;
//------------------------------------------------------------------------------
destructor TStackItem.Destroy;
begin
  FFreed := true;
  try GdipDisposeImage(FImage);
  except end;
  try if FPreviewImage <> nil then GdipDisposeImage(FPreviewImage);
  except end;
  try
    DeleteSubitems;
  finally
    try FreeAndNil(FChildren);
    finally inherited; end;
  end;
end;
//------------------------------------------------------------------------------
function TStackItem.ChildStore: TItemStore;
begin
  Result := FChildren;
end;
//------------------------------------------------------------------------------
function TStackItem.CreateSubitem: TCustomSubitem;
begin
  Result := TShortcutSubitem.Create(FHWnd, MakeICP);
end;
//------------------------------------------------------------------------------
procedure TStackItem.PrepareDeletion;
var wasOpen: boolean; children: TItemIds; index: integer;
begin
  wasOpen := FState <> stsClosed;
  FState := stsClosed;
  FStateProgress := STATE_PROGRESS_MIN;
  FHideHint := false;
  FDragOver := false;
  FDropIndicator := 0;
  ItemViews.KillItemTimer(ItemId, ID_TIMER_OPEN);
  ItemViews.KillItemTimer(ItemId, ID_TIMER_CLOSE);
  try
    children := FChildren.Snapshot;
    for index := 0 to High(children) do
      ItemViews.KillItemTimer(children[index], ID_TIMER_MOUSEHELD);
    if FItemCount > 0 then ShowAllItems(false);
  finally
    try if wasOpen then LME(false);
    finally inherited; end;
  end;
end;
//------------------------------------------------------------------------------
procedure TStackItem.ApplyData(const Data: TStackDtoV1);
begin
  Caption := Data.Caption;
  FImageFile := Data.Image;
  FSpecialFolder := Data.SpecialFolder;
  FColorData := Data.ColorData;
  FMode := Data.Mode;
  FOffset := Data.Offset;
  FAnimationSpeed := Data.AnimationSpeed;
  FDistort := Data.Distort;
  FPreview := Data.Preview;
  FShowBackground := Data.Background;
  FSorted := Data.Sorted;
end;

function TStackItem.CaptureData: TStackDtoV1;
begin
  Result := DefaultStackDto;
  Result.Caption := Caption;
  Result.Image := FImageFile;
  Result.SpecialFolder := FSpecialFolder;
  Result.ColorData := FColorData;
  Result.Mode := FMode;
  Result.Offset := FOffset;
  Result.AnimationSpeed := FAnimationSpeed;
  Result.Distort := FDistort;
  Result.Preview := FPreview;
  Result.Background := FShowBackground;
  Result.Sorted := FSorted;
end;

procedure TStackItem.FromIni(IniFile, IniSection: string);
var Children: TStringList;
begin
  if FFreed or (IniFile = '') or (IniSection = '') then Exit;
  Children := ReadStackChildren(IniFile, IniSection, '');
  FUpdating := True;
  try
    ApplyData(ReadStackIni(IniFile, IniSection));
    if not AddSubitems(Children) then raise ERangeError.Create('Cannot add stack children');
    UpdateSpecialFolder;
  finally FUpdating := False; Children.Free; end;
  Update;
end;
//------------------------------------------------------------------------------
procedure TStackItem.FromString(value: string);
var Children: TStringList;
begin
  if FFreed then Exit;
  Children := ReadStackChildren('', '', value);
  FUpdating := True;
  try
    ApplyData(ReadStackText(value));
    if not AddSubitems(Children) then raise ERangeError.Create('Cannot add stack children');
    UpdateSpecialFolder;
  finally FUpdating := False; Children.Free; end;
  Update;
end;
//------------------------------------------------------------------------------
procedure TStackItem.Update;
var Data: TStackDtoV1;
begin
  if FFreed or FUpdating then exit;
  Data := CaptureData;
  NormalizeStackDto(Data);
  ApplyData(Data);

  try
    try
      FUpdating := true;
      // load images from files //
      LoadImage(ShellUTF16(UnzipPath(FImageFile)), FBigItemSize, false, false, FImage, FIW, FIH);
      // default stack image //
      if FImage = nil then
      begin
        FImage := theme.Stack.Image;
        DownscaleImage(Fimage, FBigItemSize, false, FIW, FIH, false);
      end;
    finally
      FUpdating:= false;
    end;

    if FSorted then SortItems;
    UpdatePreview;
  except
    on e: Exception do raise Exception.Create('StackItem.UpdateItemInternal ' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------
function TStackItem.cmd(id: TDParam; param: PtrInt): PtrInt;
var
  b: boolean;
  temp: uint;
  idx, windowCount: integer;
begin
  try
    result := inherited cmd(id, param);

    case id of
      // parameters //
      gpBigItemSize:
        begin
          if FBigItemSize <= 96 then temp := 96
          else if FBigItemSize <= 128 then temp := 128
          else if FBigItemSize <= 160 then temp := 160
          else if FBigItemSize <= 192 then temp := 192
          else if FBigItemSize <= 256 then temp := 256;
          if temp <> FIW then Update;
        end;
      gpShowRunningIndicator:
        begin
          if FRunning and not boolean(param) then
          begin
            FRunning := false;
            Redraw;
          end;
        end;
      gpUseShellContextMenus: FUseShellContextMenus := boolean(param);
      gpStackAnimationEnabled: FOpenAnimation := param <> 0;
      gpSite:
        begin
          if FRunning then Redraw;
          CloseStack;
        end;
      tcThemeChanged:
        begin
          Update; // in order to update default stack image //
          if FRunning then Redraw;
        end;

      // commands //

      icUpdateRunning:
        begin
          windowCount := 0;
          idx := 0;
          while idx < FItemCount do
          begin
            items[idx].item.cmd(icUpdateRunning, 0);
            inc(windowCount, items[idx].item.WindowCount);
            inc(idx);
          end;
          if windowCount <> FWindowCount then
          begin
            FWindowCount := windowCount;
            FRunning := windowCount > 0;
            Redraw;
          end;
        end;
      icDragEnter:
        begin
          OnDragEnter;
          result := FDropIndicator;
        end;
      icDragOver: OnDragOver;
      icDragLeave: OnDragLeave;
      icVisible: if not boolean(param) then CloseStack(true);
      icIsItem:
        begin
          result := 0;
          if (FItemCount > 0) and (FState = stsOpen) then
          begin
            for idx := 0 to FItemCount - 1 do
              if items[idx].wnd = THandle(param) then result := FHWnd;
          end;
        end;
    end;

    b := (id = gpItemSize) or (id = gpUseShellContextMenus) or (id = gpSite) or (id = gpShowHint) or
      (id = gpShowRunningIndicator) or (id = gpLaunchInterval) or (id = gpActivateRunning) or (id = gpLockDragging) or (id = tcThemeChanged);
    if (FItemCount > 0) and b then
    begin
      for idx := 0 to FItemCount - 1 do items[idx].item.cmd(id, param);
    end;

  except
    on e: Exception do raise Exception.Create('StackItem.Cmd ' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------
procedure TStackItem.SetFont(var Value: TDFontData);
var
  idx: integer;
begin
  inherited;

  if FItemCount > 0 then
  begin
    for idx := 0 to FItemCount - 1 do items[idx].item.SetFont(FFont);
  end;
end;
//------------------------------------------------------------------------------
// Draw routines ---------------------------------------------------------------
procedure TStackItem.BeforeDraw;
begin
  if FState = stsOpen then DoStateProgress;
end;
//------------------------------------------------------------------------------
procedure TStackItem.DrawOverlay(dst: pointer; x, y, size: integer);
begin
  if assigned(FPreviewImage) and (FState = stsClosed) then
    GdipDrawImageRectRectI(dst, FPreviewImage, x, y, size, size, 0, 0, FPreviewImageW, FPreviewImageH, UnitPixel, nil, nil, nil);
  if FWindowCount > 0 then DrawNumberOverlay(dst, x, y, size, FWindowCount);
  DrawItemIndicator(dst, FDropIndicator, x, y, size, size);
end;
// Draw routines ---------------------------------------------------------------
//------------------------------------------------------------------------------
procedure TStackItem.Timer;
begin
  inherited;
  if not FFreed and not FUpdating then
    if (FState = stsOpening) or (FState = stsClosing) then DoStateProgress;
end;
function TStackItem.NeedsFrame: boolean;
begin
  Result := inherited NeedsFrame or (FState in [stsOpening, stsClosing]);
end;
//------------------------------------------------------------------------------
procedure TStackItem.Configure;
begin
  TfrmStackProp.Open(Handle);
end;
//------------------------------------------------------------------------------
function TStackItem.ToString: string;
begin
  Result := WriteStackText(CaptureData);
end;
//------------------------------------------------------------------------------
function TStackItem.ToStringFullCopy: string;
var
  idx: integer;
begin
  result := ToString;
  if (FItemCount > 0) and (FSpecialFolder = '') then
  begin
    for idx := 0 to FItemCount - 1 do
      result := result + #10 + items[idx].item.ToString;
  end;
end;
//------------------------------------------------------------------------------
procedure TStackItem.MouseClick(button: TMouseButton; shift: TShiftState; x, y: integer);
var
  pt: windows.TPoint;
begin
  if button = mbLeft then Exec;

  if button = mbRight then
  begin
    CloseStack;
    windows.GetCursorPos(pt);
    ContextMenu(pt);
  end;
end;
//------------------------------------------------------------------------------
procedure TStackItem.MouseHeld(button: TMouseButton);
begin
  CloseStack;
  inherited;
  if button = mbRight then Configure;
end;
//------------------------------------------------------------------------------
function TStackItem.ContextMenu(pt: Windows.TPoint): boolean;
  function IsValidShortcutString(str: string): boolean;
  begin
    Result := False;
    if Trim(str) = '' then Exit;
    try
      ReadShortcutText(str);
      Result := True;
    except on EConvertError do Result := False; end;
  end;

var
  msg: TMessage;
begin
  result := false;

  FHMenu := CreatePopupMenu;
  AppendMenuW(FHMenu, MF_STRING, $f001, pwchar(UTF8Decode(XConfigureIcon)));
  AppendMenuW(FHMenu, MF_STRING, $f003, pwchar(UTF8Decode(XCopy)));
  if IsValidShortcutString(GetClipboard) then AppendMenuW(FHMenu, MF_STRING, $f005, pwchar(UTF8Decode(XPaste)));
  AppendMenuW(FHMenu, MF_SEPARATOR, 0, '-');
  AppendMenuW(FHMenu, MF_STRING, $f004, pwchar(UTF8Decode(XDeleteIcon)));

  LME(true);
  msg.WParam := WPARAM(TrackPopupMenuEx(FHMenu, TPM_RETURNCMD, pt.x, pt.y, FHWnd, nil));
  WMCommand(msg.wParam, msg.lParam, msg.Result);
  Result := True;
end;
//------------------------------------------------------------------------------
procedure TStackItem.WMCommand(wParam: WPARAM; lParam: LPARAM; var Result: LRESULT);
begin
  result := 0;
  LME(false);
  DestroyMenu(FHMenu);
  FHMenu := 0;
  case wParam of // f001 to f020
    $f001: Configure;
    $f002: ; // open folder
    $f003: toolu.SetClipboard(ToStringFullCopy);
    $f004: Delete;
    $f005: AddSubitem(GetClipboard);
  end;
end;
//------------------------------------------------------------------------------
procedure TStackItem.WndMessage(var msg: TMessage);
var
  idx: integer;
  found: boolean;
begin
  if FFreed then exit;

  with msg do
  begin
      Result := 0;

      // WM_ACTIVATEAPP
      if (Msg = WM_ACTIVATEAPP) and (wParam = 0) then CloseStack;

      // WM_ACTIVATE
      if (Msg = WM_ACTIVATE) and (wParam and $f = 0) then
      begin
        found := false;
        if FItemCount > 0 then
          for idx := 0 to FItemCount - 1 do
            if items[idx].wnd = THandle(lParam) then found := true;
        if not found then CloseStack;
      end;

      // WM_TIMER (OPEN)
      if (Msg = WM_TIMER) and (wParam = ID_TIMER_OPEN) then
      begin
        if not ItemViews.ConsumeItemTimer(ItemId, ID_TIMER_OPEN, GetTickCount64) then exit;
        ItemViews.KillItemTimer(ItemId, ID_TIMER_OPEN);
        OpenStack;
      end;

      // WM_TIMER (CLOSE)
      if (Msg = WM_TIMER) and (wParam = ID_TIMER_CLOSE) then
      begin
        if not ItemViews.ConsumeItemTimer(ItemId, ID_TIMER_CLOSE, GetTickCount64) then exit;
        ItemViews.KillItemTimer(ItemId, ID_TIMER_CLOSE);
        CloseStack;
      end;

      // WM_APP_UPDATE_PREVIEW private message //
      if (Msg = WM_APP_UPDATE_PREVIEW) and not FUpdating then UpdatePreview;
  end;
end;
//------------------------------------------------------------------------------
procedure TStackItem.Exec;
begin
  if (FState = stsClosed) or (FState = stsClosing) then OpenStack else CloseStack;
end;
//------------------------------------------------------------------------------
procedure TStackItem.OnDragEnter;
begin
  if not FFreed then
  try
    FDropIndicator := DII_ADD;
    FDragOver := true;
    ItemViews.KillItemTimer(ItemId, ID_TIMER_CLOSE);
    ItemViews.SetItemTimer(ItemId, ID_TIMER_OPEN, 1000);
    Redraw;
  except
    on e: Exception do raise Exception.Create('StackItem.OnDragEnter ' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------
procedure TStackItem.OnDragOver;
begin
end;
//------------------------------------------------------------------------------
procedure TStackItem.OnDragLeave;
begin
  if not FFreed then
  try
    cmd(icSelect, 0);
    FDropIndicator := 0;
    FDragOver := false;
    ItemViews.KillItemTimer(ItemId, ID_TIMER_OPEN);
    ItemViews.SetItemTimer(ItemId, ID_TIMER_CLOSE, 1000);
    Redraw;
  except
    on e: Exception do raise Exception.Create('StackItem.OnDragLeave ' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------
function TStackItem.DropFile(wnd: HWND; pt: windows.TPoint; filename: string): boolean;
var
  index: integer;
begin
  result := not FFreed;
  if result then
  begin
    if wnd = FHWnd then Result := DropFileI(filename)
    else
    begin
      index := ItemIndex(wnd);
      if index <> NOT_AN_ITEM then Result := items[index].item.DropFile(pt, filename)
      else Result := False;
    end;
  end;
end;
//------------------------------------------------------------------------------
function TStackItem.DropFileI(filename: string): boolean;
var
  ext: string;
begin
  Result := False;
  // update icon //
  ext := LowerCase(ExtractFileExt(filename));
  if (ext = '.png') or (ext = '.ico') then
  begin
    FImageFile := toolu.ZipPath(filename);
    FColorData := DEF_COLOR_DATA;
    Update;
    Result := True;
    exit;
  end;

  if FSpecialFolder <> '' then
  begin
    // TODO: IFileOperation. No definition in ShlObj for IFileOperation
    exit;
  end;

  Result := AddSubitem(TShortcutSubitem.MakeFromFilename(filename));
end;
//------------------------------------------------------------------------------
procedure TStackItem.Save(ini, section: string);
var Index: integer;
begin
  if (ini = '') or (section = '') then Exit;
  WriteStackIni(ini, section, CaptureData);
  if FSpecialFolder = '' then
    for Index := 0 to FItemCount - 1 do
      WriteIniStringW(ShellUTF16(ini), ShellUTF16(section), 'subitem' + IntToStr(Index + 1), ShellUTF16(items[Index].item.ToString));
end;
//------------------------------------------------------------------------------
procedure TStackItem.UpdateSpecialFolder;
var
  csidl: integer;
begin
  if FSpecialFolder <> '' then
  begin
      csidl := CSIDL_ToInt(FSpecialFolder);
      if csidl > -1 then
      begin
        DeleteSubitems;
        FCaption := '::::';
        AddSpecialFolder(csidl);
        if csidl = CSIDL_DESKTOPDIRECTORY then AddSpecialFolder(CSIDL_COMMON_DESKTOPDIRECTORY);
        if csidl = CSIDL_PERSONAL then AddSpecialFolder(CSIDL_COMMON_DOCUMENTS);
        UpdatePreview;
      end else begin
        FSpecialFolder := '';
      end;
  end;
end;
//------------------------------------------------------------------------------
procedure TStackItem.AddSpecialFolder(csidl: integer);
var
  psfDesktop: IShellFolder;
  psfFolder: IShellFolder;
  pidFolder: PITEMIDLIST;
  pidChild: PITEMIDLIST;
  pidAbsolute: PItemIdList;
  pEnumList: IEnumIDList;
  celtFetched: ULONG;
  strItemData: string;
begin
  if FFreed then exit;

  try
    OleCheck(SHGetDesktopFolder(psfDesktop));
    OleCheck(SHGetSpecialFolderLocation(0, csidl or CSIDL_FLAG_NO_ALIAS, pidFolder));
    OleCheck(psfDesktop.BindToObject(pidFolder, nil, IID_IShellFolder, psfFolder));
    OleCheck(psfFolder.EnumObjects(0, SHCONTF_NONFOLDERS or SHCONTF_FOLDERS, pEnumList));

    if FCaption = '::::' then
    begin
      FCaption := ShellUTF16(PIDL_GetDisplayName3(pidFolder));
    end;

    while pEnumList.Next(1, pidChild, celtFetched) = NOERROR do
    begin
      pidAbsolute := PIDL_GetAbsolute(pidFolder, pidChild);
      try
        strItemData := TShortcutSubitem.MakeFromFilename(PIDL_GetDisplayName2(pidAbsolute));
        AddSubitem(strItemData);
      finally PIDL_Free(pidAbsolute); PIDL_Free(pidChild); end;
    end;

    PIDL_Free(pidFolder);
  except
    on e: Exception do raise Exception.Create('StackItem.AddSpecialFolder ' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------
procedure TStackItem.SortItems;
  procedure sort(low, high: integer);
  var
    l, r: integer;
    median, temp: string;
  begin
    l := low;
    r := high;
    median := AnsiUpperCase(GetSubitemCaption((l + r) div 2));
    repeat
      while AnsiUpperCase(GetSubitemCaption(l)) < median do inc(l);
      while AnsiUpperCase(GetSubitemCaption(r)) > median do dec(r);
      if l <= r then
      begin
        SubitemSwap(l, r);
        inc(l);
        dec(r);
      end;
    until l > r;

    if low < r then sort(low, r);
    if l < high then sort(l, high);
  end;
begin
  if FItemCount > 0 then sort(0, FItemCount - 1);
end;
//------------------------------------------------------------------------------
procedure TStackItem.UpdatePreview;
var
  i, border, itemSize, viewItemCount: integer;
  g: Pointer;
begin
  if FFreed or FUpdating then exit;

  try
    try if FPreviewImage <> nil then GdipDisposeImage(FPreviewImage);
    except end;
    FPreviewImage := nil;

    if (FPreview > 0) and (FItemCount > 0) then
    begin
      viewItemCount := Math.Min(FItemCount, 4);
      if FPreview = 2 then viewItemCount := Math.Min(FItemCount, 9);

	    border := round(FBigItemSize / 8);
	    itemSize := (FBigItemSize - border * 2);
	    if viewItemCount > 4 then itemSize := round(itemSize / 3)
	    else
	    if viewItemCount > 1 then itemSize := round(itemSize / 2);

      FPreviewImageW := FBigItemSize and $fff;
      FPreviewImageH := FBigItemSize and $fff;
      GdipCreateBitmapFromScan0(FPreviewImageW, FPreviewImageH, 0, PixelFormat32bppPARGB, nil, FPreviewImage);
      GdipGetImageGraphicsContext(FPreviewImage, g);
      GdipSetInterpolationMode(g, InterpolationModeHighQualityBicubic);
      GdipSetPixelOffsetMode(g, PixelOffsetModeHighQuality);
      if viewItemCount = 1 then
         items[0].item.DrawPreview(g, border, border, itemSize - 2)
      else
      if (viewItemCount >= 2) and (viewItemCount <= 4) then
      begin
        for i := 0 to viewItemCount - 1 do
          items[i].item.DrawPreview(g, border + (itemSize + 1) * (i mod 2), border + (itemSize + 1) * (i div 2), itemSize - 2);
      end
      else
      if viewItemCount >= 5 then
      begin
        for i := 0 to viewItemCount - 1 do
          items[i].item.DrawPreview(g, border + (itemSize + 1) * (i mod 3), border + (itemSize + 1) * (i div 3), itemSize - 2);
      end;
      GdipDeleteGraphics(g);
    end;

    Redraw;
  except
    on e: Exception do raise Exception.Create('StackItem.UpdatePreview ' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------
function TStackItem.MakeICP: TDItemCreateParams;
begin
  Result := Default(TDItemCreateParams);
  result.ItemSize := FItemSize;
  result.BigItemSize := FItemSize;
  result.LaunchInterval := FLaunchInterval;
  result.ActivateRunning := FActivateRunning;
  result.UseShellContextMenus := FUseShellContextMenus;
  result.Site := FSite;
  result.Reflection := false;
  result.ReflectionSize := 0;
  result.ShowHint := FShowHint;
  result.AnimationType := 0;
  result.LockDragging := FLockDragging;
  CopyFontData(FFont, result.Font);
end;
//------------------------------------------------------------------------------
function TStackItem.AddSubitem(data: string): boolean;
var AddedId: TItemId;
begin
  Result := AddSubitemData(Data, AddedId);
end;
//------------------------------------------------------------------------------
function TStackItem.AddSubitems(Data: TStrings): boolean;
var Added: TItemIds; AddedId, ParentId: TItemId; Index, Count: integer;
  WasUpdating: boolean; Child: TItemModel;
begin
  Result := False;
  if FFreed or (State in [imsDeleted, imsRetiring]) or not Pin then Exit;
  ParentId := ItemId;
  try
    if Data.Count > MAX_SUBITEMS - FItemCount then Exit;
    for Index := 0 to Data.Count - 1 do ReadShortcutText(Data[Index]);
    WasUpdating := FUpdating;
    FUpdating := True;
    Count := 0;
    SetLength(Added, Data.Count);
    try
      for Index := 0 to Data.Count - 1 do
      begin
        if not AddSubitemData(Data[Index], AddedId) then Exit;
        Added[Count] := AddedId;
        Inc(Count);
      end;
      Result := True;
    finally
      if not Result then
        for Index := Count - 1 downto 0 do
        begin
          Child := FChildren.Find(Added[Index]);
          if Child is TCustomSubitem then FreeSubitem(TCustomSubitem(Child));
        end;
      FUpdating := WasUpdating;
      if not FFreed then UpdatePreview;
    end;
  finally ReleaseItemModel(ParentId); end;
end;
//------------------------------------------------------------------------------
function TStackItem.AddSubitemData(const Data: string; out AddedId: TItemId): boolean;
var
  upd: boolean;
  child: TCustomSubitem;
  parentId: TItemId;
begin
  Result := False;
  AddedId := NO_ITEM_ID;
  if FFreed or (State in [imsDeleted, imsRetiring]) or not Pin then exit;
  parentId := ItemId;
  try
    try
      if FItemCount >= MAX_SUBITEMS then exit;
      upd := FUpdating;
      child := nil;
      FChildren.BeginCreation;
      try
        FUpdating := true;
        child := CreateSubitem;
        if child = nil then raise EOutOfMemory.Create('Cannot create subitem');
        if child.Freed or (child.Handle = 0) then
          raise EOSError.Create('Cannot create subitem window');
        if not FChildren.Add(child) then raise Exception.Create('Cannot own subitem');
        child.ParentItemId := ItemId;
        child.FromString(data);
        if not FFreed and not (State in [imsDeleted, imsRetiring]) and
          not child.Freed and not (child.State in [imsDeleted, imsRetiring]) and
          (child.Handle <> 0) and FChildren.Contains(child.ItemId) and
          (FItemCount < MAX_SUBITEMS) then
        begin
          items[FItemCount] := Default(TCSIBucket);
          items[FItemCount].ItemId := child.ItemId;
          child.State := imsActive;
          inc(FItemCount);
          AddedId := child.ItemId;
          Result := True;
          child := nil;
        end;
      finally
        try FreeSubitem(child);
        finally
          FUpdating := upd;
          FChildren.EndCreation;
        end;
      end;

      UpdatePreview;
    except
      on e: Exception do raise Exception.Create('StackItem.AddSubitem ' + LineEnding + e.message);
    end;
  finally
    ReleaseItemModel(parentId);
  end;
end;
//------------------------------------------------------------------------------
procedure TStackItem.CheckDeleteSubitems;
var
  idx: integer;
begin
  if FFreed then exit;

  if FItemCount > 0 then
  try
    idx := 0;
    while idx < FItemCount do
    begin
      if items[idx].item.QueryDelete then DeleteSubitem(idx) else inc(idx);
    end;
  except
    on e: Exception do raise Exception.Create('StackItem.CheckDeleteSubitems ' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------
procedure TStackItem.DeleteSubitem(index: integer);
var Item: TCustomSubitem;
begin
  if (index >= 0) and (index < FItemCount) then
  try
    Item := items[index].item;
    FreeSubitem(Item);
  except
    on e: Exception do raise Exception.Create('StackItem.DeleteSubitem ' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------
procedure TStackItem.FreeSubitem(Item: TCustomSubitem);
begin
  if Item = nil then exit;
  Item.Freed := true;
  try Item.Free;
  except
    on E: Exception do
      try AddLog('StackItem.FreeSubitem' + LineEnding + E.Message); except end;
  end;
end;
//------------------------------------------------------------------------------
procedure TStackItem.ChildRemoved(Id: TItemId);
var index, next: integer;
begin
  for index := 0 to FItemCount - 1 do
    if items[index].ItemId = Id then
    begin
      for next := index to FItemCount - 2 do
        CopyCSIBucket(@items[next + 1], @items[next]);
      dec(FItemCount);
      items[FItemCount] := Default(TCSIBucket);
      if FFreed or FUpdating then exit;
      try
        if FItemCount = 0 then PrepareDeletion;
        UpdatePreview;
      except on E: Exception do
        try AddLog('StackItem.ChildRemoved' + LineEnding + E.Message); except end;
      end;
      exit;
    end;
end;
//------------------------------------------------------------------------------
procedure TStackItem.DeleteSubitems;
var
  idx: integer;
  pending: TItemIds;
begin
  if FChildren <> nil then
  try
    pending := FChildren.Snapshot;
    for idx := 0 to FItemCount - 1 do items[idx] := Default(TCSIBucket);
    FItemCount := 0;
    for idx := 0 to High(pending) do
      FreeSubitem(TCustomSubitem(FChildren.Find(pending[idx])));

    if not FFreed then UpdatePreview;
  except
    on e: Exception do raise Exception.Create('StackItem.DeleteSubitems ' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------
procedure TStackItem.AddSubitemDefault;
begin
  AddSubitem(TShortcutSubitem.Make('New item'));
end;
//------------------------------------------------------------------------------
function TStackItem.GetSubitemCaption(index: integer): WideString;
begin
  result := '';
  if (index >= 0) and (index < FItemCount) then
  try
    result := items[index].item.Caption;
  except
    on e: Exception do raise Exception.Create('StackItem.GetSubitemCaption ' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------
function TStackItem.SubitemToString(index: integer): string;
begin
  result := '';
  if (index >= 0) and (index < FItemCount) then
  try
    result := items[index].item.ToString;
  except
    on e: Exception do raise Exception.Create('StackItem.SubitemToString ' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------
procedure TStackItem.SubitemMoveUp(index: integer);
begin
  try
    SubitemSwap(index - 1, index);
  except
    on e: Exception do raise Exception.Create('StackItem.SubitemMoveUp ' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------
procedure TStackItem.SubitemMoveDown(index: integer);
begin
  try
    SubitemSwap(index + 1, index);
  except
    on e: Exception do raise Exception.Create('StackItem.SubitemMoveDown ' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------
procedure TStackItem.SubitemSwap(index1, index2: integer);
var
  csib: TCSIBucket;
begin
  if (index1 >= 0) and (index1 < FItemCount) and (index2 >= 0) and (index2 < FItemCount) and (index1 <> index2) then
  try
    CopyCSIBucket(@items[index1], @csib);
    CopyCSIBucket(@items[index2], @items[index1]);
    CopyCSIBucket(@csib, @items[index2]);
  except
    on e: Exception do raise Exception.Create('StackItem.SubitemSwap ' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------
procedure TStackItem.SubitemConfigure(index: integer);
begin
  if (index >= 0) and (index < FItemCount) then
  try
    items[index].item.Configure;
  except
    on e: Exception do raise Exception.Create('StackItem.SubitemConfigure ' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------
procedure TStackItem.CopyCSIBucket(pFrom, pTo: PCSIBucket);
begin
  pTo^.ItemId := pFrom^.ItemId;
end;
//------------------------------------------------------------------------------
function TStackItem.ItemIndex(wnd: HWND): integer;
var
  idx: integer;
  Id: TItemId;
begin
  try
    result := NOT_AN_ITEM;
    if (wnd = 0) or (FItemCount <= 0) then exit;
    Id := ItemViews.ItemIdOf(wnd);
    if Id = NO_ITEM_ID then exit;
    for idx := 0 to FItemCount - 1 do
    begin
      if items[idx].ItemId = Id then
      begin
        result := idx;
        break;
      end;
    end;
  except
    on e: Exception do raise Exception.Create('StackItem.ItemIndex ' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------
procedure TStackItem.AllSubitemsCmd(id: TDParam; param: PtrInt);
var
  idx: integer;
begin
  if FFreed then exit;

  if FItemCount > 0 then
  try
    for idx := 0 to FItemCount - 1 do items[idx].item.cmd(id, param);
  except
    on e: Exception do raise Exception.Create('StackItem.CheckDeleteSubitems ' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------
procedure TStackItem.OpenStack;
var acquireLock: boolean;
begin
  if not FFreed and (FItemCount > 0) and ((FState = stsClosed) or (FState = stsClosing)) then
  begin
    acquireLock := FState = stsClosed;
    StartStackAnimation(1);
    FState := stsOpening; // further progress is being done by timer //
    FHideHint := true;
    Redraw;
    if not FOpenAnimation then
    begin
      FStateProgress := 1;
      FState := stsOpen;
      ShowStackState;
      ShowAllItems(true);
    end;
    if acquireLock then LME(true);
  end;
end;
//------------------------------------------------------------------------------
procedure TStackItem.CloseStack(immediate: boolean = false);
begin
  if not FFreed and (FItemCount > 0) and ((FState = stsOpen) or (FState = stsOpening)
    or (immediate and (FState = stsClosing))) then
  begin
    cmd(icSelect, 0);
    StartStackAnimation(0);
    FState := stsClosing;  // further progress is being done by timer //
    if immediate or not FOpenAnimation then
    begin
      FStateProgress := 0;
      FState := stsClosed;
      ShowStackState;
      LME(false);
      FHideHint := false;
      Redraw;
      ShowAllItems(false);
      CheckDeleteSubitems;
		end;
	end;
end;
//------------------------------------------------------------------------------
procedure TStackItem.DoStateProgress;
var
  showItems: boolean;
begin
  if FState = stsOpen then
  begin
      FStateProgress := 1;
      ShowStackState;
  end
  else
  if (FState = stsOpening) and (FStateProgress < 1) then
  begin
      showItems := FStateProgress = 0;

      FStateProgress := FStackAnimation.ValueAt(AnimationNow);
      if not FOpenAnimation then FStateProgress := 1;
      if FStateProgress >= 1 then
      begin
        FStateProgress := 1;
        FState := stsOpen;
      end;
      ShowStackState;

      if showItems then ShowAllItems(true);
  end
  else
  if FState = stsClosing then
  begin
      FStateProgress := FStackAnimation.ValueAt(AnimationNow);
      if not FOpenAnimation then FStateProgress := 0;

      if FStateProgress <= 0 then
      begin
        FStateProgress := 0;
        FState := stsClosed;
        LME(false);
        FHideHint := false;
        CheckDeleteSubitems;
        Redraw;
      end;

      if FState = stsClosed then
      begin
        ShowAllItems(false);
      end else begin
        ShowStackState;
      end;
  end;
end;
procedure TStackItem.StartStackAnimation(Target: Double);
var step: extended; duration, now: QWord;
begin
  now := AnimationNow;
  if FState in [stsOpening, stsClosing] then FStateProgress := FStackAnimation.ValueAt(now);
  step := mc.GetStep(FMode, FItemCount);
  if FAnimationSpeed > MID_ANIM_SPEED then step := step * (1 + (FAnimationSpeed - MID_ANIM_SPEED) * 0.5);
  if FAnimationSpeed < MID_ANIM_SPEED then step := step * (1 - (MID_ANIM_SPEED - FAnimationSpeed) * 0.15);
  if step <= 0 then step := 0.01;
  duration := Max(1, Round(Abs(Target - FStateProgress) * 10 / step));
  FStackAnimation.StartValue := FStateProgress;
  FStackAnimation.TargetValue := FStateProgress;
  FStackAnimation.DurationMs := 0;
  FStackAnimation.Retarget(now, Target, duration);
end;
//------------------------------------------------------------------------------
procedure TStackItem.ShowAllItems(flag: boolean);
var
  idx: integer;
  wpi: HDWP;
  swp: uint;
begin
  swp := SWP_SHOWWINDOW;
  if not flag then swp := SWP_HIDEWINDOW;

  wpi := BeginDeferWindowPos(FItemCount);
  for idx := 0 to FItemCount - 1 do
  begin
    if wpi = 0 then Break;
    wpi := DeferWindowPos(wpi, items[idx].wnd, FHWnd, 0, 0, 0, 0, swp_nomove +
      swp_nosize + swp_noactivate + swp_noreposition + swp);
  end;
  if wpi <> 0 then
    if not EndDeferWindowPos(wpi) then wpi := 0;
  if wpi = 0 then
    for idx := 0 to FItemCount - 1 do
      SetWindowPos(items[idx].wnd, FHWnd, 0, 0, 0, 0, swp_nomove +
        swp_nosize + swp_noactivate + swp_noreposition + swp);

  if not flag then
  begin
    for idx := 0 to FItemCount - 1 do items[idx].item.HideItem;
  end;
end;
//------------------------------------------------------------------------------
procedure TStackItem.ShowStackState;
var
  idx: integer;
  wr: windows.TRect;
  xyaa: TStackItemData;
begin
  if FItemCount = 0 then
  begin
    FState := stsClosed;
    exit;
  end;

  // calc base point (center of icon) //
  wr := ScreenRect;
  wr.left += FSize div 2;
  wr.top += FSize div 2;

  // get item params //
  for idx := 0 to FItemCount - 1 do
  begin
    xyaa := mc.GetItemData(FMode, (FState = stsOpening) or (FState = stsOpen), FShowHint, FStateProgress,
      idx, FItemCount, FSite, FItemSize, FOffset + (FSize - FItemSize) div 2, FDistort);
    items[idx].draw := true;
    items[idx].x := wr.left + xyaa.x;
    items[idx].y := wr.top + xyaa.y;
    items[idx].s := xyaa.s;
    items[idx].alpha := xyaa.alpha;
    items[idx].angle := xyaa.angle;
    items[idx].hint_align := xyaa.hint_align;
    items[idx].hint_alpha := xyaa.hint_alpha;
  end;

  // draw items //
  for idx := 0 to FItemCount - 1 do
  begin
    if items[idx].draw then items[idx].item.Draw(items[idx].x, items[idx].y, items[idx].s,
      items[idx].alpha, items[idx].angle, items[idx].hint_align, items[idx].hint_alpha, FShowBackground, false);
  end;
end;
//------------------------------------------------------------------------------
//
//
//
//
//
//
//
//------------------------------------------------------------------------------
class function TStackItem.Make(ACaption: WideString = ''; AImage: string = ''; ASpecialFolder: string = '';
      color_data: integer = DEF_COLOR_DATA; AMode: integer = 0;
      AOffset: integer = 0; AAnimationSpeed: integer = DEF_ANIM_SPEED;
      ADistort: integer = DEF_DISTORT; APreview: integer = DEF_STACK_PREVIEW;
      AShowBackground: boolean = false;
      ASorted: boolean = false): string;
var Data: TStackDtoV1;
begin
  Data := DefaultStackDto;
  Data.Caption := ACaption;
  Data.Image := AImage;
  Data.SpecialFolder := ASpecialFolder;
  Data.ColorData := color_data;
  Data.Mode := AMode;
  Data.Offset := AOffset;
  Data.AnimationSpeed := AAnimationSpeed;
  Data.Distort := ADistort;
  Data.Preview := APreview;
  Data.Background := AShowBackground;
  Data.Sorted := ASorted;
  Result := WriteStackText(Data);
end;
//------------------------------------------------------------------------------
end.
