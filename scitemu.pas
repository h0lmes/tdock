unit scitemu;

{$t+}

interface
uses Windows, Messages, SysUtils, Controls, Classes, Math, ShellAPI, ComObj, ShlObj,
  GDIPAPI, gfx, iconserviceu, PIDL, ShContextU,
  declu, dockh, customitemu, customdrawitemu,
  toolu, processhlp, aeropeeku, mixeru, networksu, iniproc, loggeru, itemserializationu, shelltextu;

type

  { TShortcutItem }

  TShortcutItem = class(TCustomDrawItem)
  private
    procedure ApplyData(const Data: TShortcutDtoV1);
    function CaptureData: TShortcutDtoV1;
  private
    FCommand: string;
    FParams: string;
    FDir: string;
    FImageFile: string;
    FImageFile2: string;
    FShowCmd: integer;
    FHide: boolean;
    //
    FUseShellContextMenus: boolean;
    FTaskLivePreviews: boolean;
    FTaskThumbSize: integer;
    FTaskGrouping: boolean;
    FTaskSystemMenus: boolean; // use old-style system menus instead of AeroPeekWindow
    FAeroPeekEnabled: boolean; // allow to use AeroPeek or not
    FIsExecutable: boolean;
    FExecutable: WideString;
    FIsPackagedApp: boolean;
    FIsPIDL: boolean;
    FPIDL: PItemIDList;
    FLastMouseUp: PtrUInt;
    FAppList: TFPList;
    FFlashedWindow: THandle;
    FAeroPeekWindowActive: boolean;
    FDynObject: boolean;
    FDynObjectRecycleBin: boolean;
    FDynObjectState: integer;
    procedure CheckWindowActivated;
    procedure FromIni(IniFile, IniSection: string);
    procedure FromString(value: string);
    procedure LoadImageI;
    procedure UpdateRunning;
    procedure LoadDynObjectImage(imagefile: string; MaxSize: integer; exact, default: boolean; var image: pointer; var srcwidth, srcheight: uint);
    procedure CheckIfDynObject;
    procedure DynObjectUpdate;
    procedure AfterDraw;
    procedure DrawOverlay(dst: pointer; x, y, size: integer);
    procedure BeforeMouseHover(AHover: boolean);
    procedure MouseHover(AHover: boolean);
    procedure Exec(action: TExecuteAction);
    function ActivateProcessMainWindow(group: boolean): boolean;
    procedure BeforeUndock;
    function ContextMenu(pt: Windows.TPoint): boolean;
    procedure ClosePeekWindow(Timeout: cardinal = 0);
    procedure ShowPeekWindow(Timeout: cardinal = 0);
    procedure UpdatePeekWindow;
  protected
    // Returns an owned Shell item. The caller must free it with PIDL_Free.
    function ParseAppShellItem(const ParsingName: UnicodeString): PItemIDList; virtual;
  public
    property Command: string read FCommand write FCommand;
    property Params: string read FParams write FParams;
    property Dir: string read FDir write FDir;
    property ImageFile: string read FImageFile write FImageFile;
    property ImageFile2: string read FImageFile2 write FImageFile2;
    property ShowCmd: integer read FShowCmd write FShowCmd;
    property Hide: boolean read FHide write FHide;

    constructor Create(AWndParent: HWND; var AParams: TDItemCreateParams); override;
    destructor Destroy; override;
    procedure Update;
    function ToString: string; override;
    procedure MouseClick(button: TMouseButton; shift: TShiftState; x, y: integer); override;
    procedure MouseHeld(button: TMouseButton); override;
    procedure WndMessage(var msg: TMessage); override;
    procedure WMCommand(wParam: WPARAM; lParam: LPARAM; var Result: LRESULT); override;
    function cmd(id: TDParam; param: PtrInt): PtrInt; override;
    procedure Timer; override;
    procedure Configure; override;
    function CanOpenFolder: boolean; override;
    procedure OpenFolder; override;
    function Executable: string; override;
    function DropFile(wnd: HWND; pt: windows.TPoint; filename: string): boolean; override;
    procedure Save(ini, section: string); override;
    procedure PrepareDeletion; override;
    procedure ForegroundChanged(wnd: HWND); override;
    //
    class function Make(ACaption: WideString = '';
      ACommand: string = ''; AParams: string = ''; ADir: string = ''; AImage: string = '';
      AShowCmd: integer = 1; AColorData: integer = DEF_COLOR_DATA; AHide: boolean = false): string;
    class function MakeFromFilename(value: string): string;
  end;

implementation
uses frmitemoptu, itemviewu, itemhostu;

//------------------------------------------------------------------------------
constructor TShortcutItem.Create(AWndParent: HWND; var AParams: TDItemCreateParams);
begin
  inherited;
  FUseShellContextMenus := AParams.UseShellContextMenus;
  FAeroPeekEnabled      := AParams.AeroPeekEnabled;
  FTaskGrouping         := AParams.TaskGrouping;
  FTaskLivePreviews     := AParams.TaskLivePreviews;
  FTaskThumbSize        := AParams.TaskThumbSize;
  FTaskSystemMenus      := AParams.TaskSystemMenus;
  FLastMouseUp          := 0;
  FCommand              := '';
  FParams               := '';
  FDir                  := '';
  FImageFile            := '';
  FImageFile2           := '';
  FShowCmd              := 0;
  FHide                 := false;
  FRunning              := false;
  FAeroPeekWindowActive := false;
  OnBeforeMouseHover    := BeforeMouseHover;
  OnMouseHover          := MouseHover;
  OnBeforeUndock        := BeforeUndock;
  OnAfterDraw           := AfterDraw;
  OnDrawOverlay         := DrawOverlay;
  FAppList              := TFPList.Create;

  if AParams.IniFile <> '' then FromIni(AParams.IniFile, AParams.IniSection)
  else FromString(Aparams.Parameter);
end;
//------------------------------------------------------------------------------
destructor TShortcutItem.Destroy;
begin
  FFreed := true;
  ItemViews.KillItemTimer(ItemId, ID_TIMER_UPDATE_SHORTCUT);
  if FAeroPeekWindowActive then TAeroPeekWindow.Close(0);
  try if assigned(FImage) then GdipDisposeImage(FImage);
  except end;
  try if FIsPIDL then PIDL_Free(FPIDL);
  except end;
  FAppList.free;
  inherited;
end;
//------------------------------------------------------------------------------
procedure TShortcutItem.ApplyData(const Data: TShortcutDtoV1);
begin
  Caption := Data.Caption;
  FCommand := Data.Command;
  FParams := Data.Params;
  FDir := Data.Directory;
  FImageFile2 := cutafter(Data.Image, ';');
  FImageFile := cut(Data.Image, ';');
  FHide := Data.Hide;
  FColorData := Data.ColorData;
  FShowCmd := Data.ShowCmd;
end;

function TShortcutItem.CaptureData: TShortcutDtoV1;
begin
  Result := DefaultShortcutDto;
  Result.Caption := FCaption;
  Result.Command := FCommand;
  Result.Params := FParams;
  Result.Directory := FDir;
  Result.Image := FImageFile;
  if FImageFile2 <> '' then Result.Image := Result.Image + ';' + FImageFile2;
  Result.Hide := FHide;
  Result.ColorData := FColorData;
  Result.ShowCmd := FShowCmd;
end;

procedure TShortcutItem.FromIni(IniFile, IniSection: string);
begin
  if FFreed or (IniFile = '') or (IniSection = '') then Exit;
  ApplyData(ReadShortcutIni(IniFile, IniSection));
  Update;
end;
//------------------------------------------------------------------------------
procedure TShortcutItem.FromString(value: string);
begin
  if FFreed then Exit;
  ApplyData(ReadShortcutText(value));
  Update;
end;
//------------------------------------------------------------------------------
function TShortcutItem.ParseAppShellItem(const ParsingName: UnicodeString): PItemIDList;
begin
  Result := nil;
  if SHParseDisplayName(PWideChar(ParsingName), nil, Result, 0, nil) <> S_OK then
    PIDL_Free(Result);
end;

procedure TShortcutItem.Update;
var
  pidFolder: PItemIDList;
  csidl: integer;
  ParsingName: UnicodeString;
  //
  ext, params, dir, icon: string;
  AppID: UnicodeString;
begin
  if FFreed or FUpdating then exit;

  try
    try
      FUpdating := true;

      FIsExecutable := false;
      FExecutable := '';
      FIsPIDL := false;
      PIDL_Free(FPIDL);

      FIsPackagedApp := TryNormalizeAppTarget(UTF8Decode(UnzipPath(FCommand)), AppID);
      if FIsPackagedApp then
      begin
          if FCaption = '?' then
          begin
            pidFolder := ParseAppShellItem(APPS_FOLDER_PREFIX + AppID);
            if assigned(pidFolder) then
            try
              FCaption := ShellUTF16(PIDL_GetDisplayName3(pidFolder));
            finally
              PIDL_Free(pidFolder);
            end;
          end;
      end
      else
      begin
          // if FCommand is a CSIDL convert it to GUID or path //
          csidl := CSIDL_ToInt(FCommand);
          if csidl > -1 then
          begin
            OleCheck(SHGetSpecialFolderLocation(0, csidl or CSIDL_FLAG_NO_ALIAS, pidFolder));
            if PIDL_GetDisplayNameText(nil, pidFolder, SHGDN_FORPARSING, ParsingName) then FCommand := ShellUTF8(ParsingName);
            PIDL_Free(pidFolder);
            if FileExists(FCommand) or DirectoryExists(FCommand) then FCommand := ZipPath(FCommand)
            else FCaption := '::::'; // assuming this is a PIDL
          end;

          // create PIDL from GUID //
          if IsPIDLString(FCommand) then FPIDL := PIDL_FromString(FCommand);
          if not assigned(FPIDL) then
            if not FileExists(toolu.UnzipPath(FCommand)) then
              if IsShellName(ShellUTF16(FCommand)) then FPIDL := PIDL_ParseTarget(ShellUTF16(FCommand));

          FIsPIDL := assigned(FPIDL);
          if FIsPIDL and (FCaption = '::::') then FCaption := ShellUTF16(PIDL_GetDisplayName3(FPIDL));

          // check if this is the shortcut to an executable file
          if not FIsPIDL then
          begin
            FExecutable := ShellUTF16(toolu.UnzipPath(FCommand));
            ext := ExtractFileExt(FExecutable);
            if SameText(ext, '.appref-ms') then ResolveAppref(FHWnd, FExecutable);
            if SameText(ext, '.lnk') then ResolveLNK(FHWnd, FExecutable, params, dir, icon);
            ext := ExtractFileExt(FExecutable);
            FIsExecutable := SameText(ext, '.exe');
            if not ShellPathExists(FExecutable) and not FIsExecutable then FExecutable := '';
          end;
      end;

      // check if this is a dynamic state object //
      CheckIfDynObject;

      // load appropriate image //
      LoadImageI;
    finally
      FUpdating:= false;
    end;

    Redraw;
  except
    on e: Exception do raise Exception.Create('ShortcutItem.Update ' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------
procedure TShortcutItem.LoadImageI;
begin
  if FDynObjectRecycleBin and (FImageFile <> '') then
  begin
    if FDynObjectState = 0 then
      LoadImage(ShellUTF16(UnzipPath(FImageFile)), FBigItemSize, false, true, FImage, FIW, FIH)
    else
      LoadImage(ShellUTF16(UnzipPath(FImageFile2)), FBigItemSize, false, true, FImage, FIW, FIH);
  end
  else if FDynObject then
    LoadDynObjectImage(FImageFile, FBigItemSize, false, true, FImage, FIW, FIH)
  else
    LoadShortcutImage(ShellUTF16(UnzipPath(FCommand)), ShellUTF16(UnzipPath(FImageFile)),
      FBigItemSize, false, true, FImage, FIW, FIH);
end;
//--------------------------------------------------------------------------------------------------
procedure TShortcutItem.LoadDynObjectImage(imagefile: string; MaxSize: integer; exact, default: boolean; var image: pointer; var srcwidth, srcheight: uint);
begin
  try
    if pos('{LANGID}', imagefile) > 0 then
    begin
      imagefile := ReplaceEx(imagefile, '{LANGID}', GetLangIDString(FDynObjectState));
      LoadImage(ShellUTF16(UnzipPath(imagefile)), MaxSize, exact, default, image, srcwidth, srcheight);
      Caption := GetLangIDName(FDynObjectState);
    end;
    if pos('{VOLUME}', imagefile) > 0 then
    begin
      imagefile := ReplaceEx(imagefile, '{VOLUME}', Mixer.StateString);
      LoadImage(ShellUTF16(UnzipPath(imagefile)), MaxSize, exact, default, image, srcwidth, srcheight);
      Caption := Mixer.Description;
    end;
    if pos('{NETWORK}', imagefile) > 0 then
    begin
      imagefile := ReplaceEx(imagefile, '{NETWORK}', TNetworks.CStateString);
      LoadImage(ShellUTF16(UnzipPath(imagefile)), MaxSize, exact, default, image, srcwidth, srcheight);
      Caption := TNetworks.CDescription;
    end;
  except
    on e: Exception do raise Exception.Create('LoadDynObjectImage ' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------
procedure TShortcutItem.CheckIfDynObject;
var
  pidFolder: PItemIDList;
begin
  if FFreed then exit;
  ItemViews.KillItemTimer(ItemId, ID_TIMER_UPDATE_SHORTCUT);

  FDynObjectState := 0;
  FDynObject := (pos('{LANGID}', FImageFile) > 0) or (pos('{VOLUME}', FImageFile) > 0) or (pos('{NETWORK}', FImageFile) > 0);
  FDynObjectRecycleBin := false;
  if FIsPIDL then
  begin
    OleCheck(SHGetSpecialFolderLocation(0, CSIDL_BITBUCKET or CSIDL_FLAG_NO_ALIAS, pidFolder));
    FDynObjectRecycleBin := PIDL_GetDisplayName2(pidFolder) = FCommand;
    PIDL_Free(pidFolder);
  end;

  if FDynObject or FDynObjectRecycleBin then DynObjectUpdate;

  // setup update timer
  if FDynObject then ItemViews.SetItemTimer(ItemId, ID_TIMER_UPDATE_SHORTCUT, 500)
  else
  if FDynObjectRecycleBin then ItemViews.SetItemTimer(ItemId, ID_TIMER_UPDATE_SHORTCUT, 1000);
end;
//------------------------------------------------------------------------------
procedure TShortcutItem.DynObjectUpdate;
var
  newDynObjectState: integer = 0;
begin
  if FFreed then exit;

  // if this is a dynamic object
  if FDynObject then
  begin
    if pos('{LANGID}', FImageFile) > 0 then newDynObjectState := GetLangID;
    if pos('{VOLUME}', FImageFile) > 0 then newDynObjectState := TMixer.CUpdate;
    if pos('{NETWORK}', FImageFile) > 0 then newDynObjectState := TNetworks.CUpdate;
  end
  // if this is a Recycle Bin
  else if FDynObjectRecycleBin then newDynObjectState := GetRecycleBinState;

  // if 'state' changed
  if FDynObjectState <> newDynObjectState then
  begin
    FDynObjectState := newDynObjectState;
    LoadImageI;
    Redraw;
  end;
end;
//------------------------------------------------------------------------------
function TShortcutItem.cmd(id: TDParam; param: PtrInt): PtrInt;
var
  temp: uint;
  idx: integer;
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
          if temp <> FIW then LoadImageI;
        end;
      gpShowRunningIndicator:
        if FRunning and not boolean(param) then
        begin
          FRunning := false;
          Redraw;
        end;
      gpAeroPeekEnabled:      FAeroPeekEnabled := boolean(param);
      gpTaskLivePreviews:     FTaskLivePreviews := boolean(param);
      gpTaskThumbSize:        FTaskThumbSize := param;
      gpTaskGrouping:         FTaskGrouping := boolean(param);
      gpTaskSystemMenus:      FTaskSystemMenus := boolean(param);
      gpUseShellContextMenus: FUseShellContextMenus := boolean(param);
      gpSite:                 if FRunning then Redraw;
      tcThemeChanged:         if FRunning then Redraw;
      tcDebugInfo:
        if FAppList.Count > 0 then // log every window info
        begin
          AddLog('---------- ShortcutItem.WindowsInfo');
          AddLog('Caption = ' + Caption);
          for idx := 0 to FAppList.Count - 1 do LogWindow(THandle(FAppList.Items[idx]));
        end;

      // commands //
      icFree:
        if (param = 0) and (FDynObject or FDynObjectRecycleBin) then CheckIfDynObject;
      icUpdateRunning: UpdateRunning;
      icDragEnter:
        begin
          FDropIndicator := DII_RUN;
          Redraw;
          result := FDropIndicator;
        end;
      icDragLeave:
        begin
          FDropIndicator := DII_NONE;
          Redraw;
        end;

      icFlashTaskWindow:
        if FAppList.IndexOf(pointer(param)) >= 0 then
        begin
          FFlashedWindow := param;
          Animate;
          Attention(true);
          ItemViews.SetItemTimer(ItemId, ID_TIMER_WINDOWACTIVATED, 1000);
        end;
    end;

  except
    on e: Exception do raise Exception.Create('ShortcutItem.Cmd ' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------
procedure TShortcutItem.UpdateRunning;
var
  aRunning: boolean;
  appCount: integer;
begin
  if FIsExecutable then
  begin
    appCount := FAppList.Count;
    ProcessHelper.GetProcessWindows(FExecutable, FAppList);
    aRunning := FAppList.Count > 0;
    if (aRunning <> FRunning) or (appCount <> FAppList.Count) then
    begin
      FRunning := aRunning;
      Redraw;
    end;
  end;
end;
//------------------------------------------------------------------------------
// Draw routines ---------------------------------------------------------------
procedure TShortcutItem.AfterDraw;
begin
  if FAeroPeekWindowActive then UpdatePeekWindow;
end;
//------------------------------------------------------------------------------
procedure TShortcutItem.DrawOverlay(dst: pointer; x, y, size: integer);
begin
  if assigned(FAppList) then
    if FAppList.Count > 1 then DrawNumberOverlay(dst, x, y, size, FAppList.Count);
  DrawItemIndicator(dst, FDropIndicator, x, y, size, size);
end;
// Draw routines ---------------------------------------------------------------
//------------------------------------------------------------------------------
procedure TShortcutItem.Timer;
begin
  try
    inherited;
    if FFreed or FUpdating then exit;

  except
    on e: Exception do raise Exception.Create('ShortcutItem.Timer ' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------
procedure TShortcutItem.Configure;
begin
  TfrmItemProp.Open(Handle);
end;
//------------------------------------------------------------------------------
function TShortcutItem.ToString: string;
begin
  Result := WriteShortcutText(CaptureData);
end;
//------------------------------------------------------------------------------
procedure TShortcutItem.MouseClick(button: TMouseButton; shift: TShiftState; x, y: integer);
var
  pt: windows.TPoint;
  tickCount, elapsed: QWord;
begin
  tickCount := gettickcount64;
  elapsed := tickCount - FLastMouseUp;

  if button = mbLeft then
  begin
    if elapsed > FLaunchInterval then
    begin
      if ssAlt in shift then Exec(eaGroup)
      else
      if ssCtrl in shift then Exec(eaRun)
      else
        Exec(eaDefault);
    end;
    FLastMouseUp := tickCount;
  end;

  if button = mbRight then
  begin
    ClosePeekWindow;
    windows.GetCursorPos(pt);
    ContextMenu(pt);
  end;
end;
//------------------------------------------------------------------------------
procedure TShortcutItem.Exec(action: TExecuteAction);
  procedure Run;
  begin
    if FHide then dockh.DockExecute(FHWnd, '/hide', '', '', 0) else DockletDoAttensionAnimation(FHWnd);
    DockExecute(FHWnd, pchar(FCommand), pchar(FParams), pchar(FDir), FShowCmd);
  end;
begin
  if FIsPIDL then Run
  else
  begin
      if FActivateRunning and not (action = eaRun) then
      begin
          if FHide then DockExecute(FHWnd, '/hide', '', '', 0);
          if not ActivateProcessMainWindow(action = eaGroup) then Run;
      end
      else Run;
  end;
end;
//------------------------------------------------------------------------------
function TShortcutItem.ActivateProcessMainWindow(group: boolean): boolean;
begin
  result := false;
  if not FIsExecutable then exit;

  ProcessHelper.EnumAppWindows;
  ProcessHelper.GetProcessWindows(FExecutable, FAppList);
  if FAppList.Count = 1 then
  begin
    result := true;
    ItemViews.KillItemTimer(ItemId, ID_TIMER_OPEN);
    ProcessHelper.ActivateWindow(THandle(FAppList.First), FAttention);
  end else
  if FAppList.Count > 1 then
  begin
    result := true;
    if group then
      ProcessHelper.ActivateWindowList(FAppList)
		else if FTaskSystemMenus then
    begin
      ProcessHelper.ActivateProcessMainWindow(FExecutable, Handle, GetScreenRect, FSite);
    end else begin
      if not TAeroPeekWindow.IsActive then ShowPeekWindow;
    end;
	end;
end;
//------------------------------------------------------------------------------
procedure TShortcutItem.MouseHeld(button: TMouseButton);
begin
  inherited;
  if button = mbRight then Configure;
end;
//------------------------------------------------------------------------------
procedure TShortcutItem.BeforeUndock;
begin
  ClosePeekWindow;
end;
//------------------------------------------------------------------------------
function TShortcutItem.ContextMenu(pt: Windows.TPoint): boolean;
var
  filename: string;
  msg: TMessage;
  mii: MENUITEMINFO;
begin
  result := false;

  FHMenu := CreatePopupMenu;
  if FDynObjectRecycleBin and (FDynObjectState > 0) then
    AppendMenuW(FHMenu, MF_STRING, $f005, pwchar(UTF8Decode(XEmptyBin)));
  AppendMenuW(FHMenu, MF_STRING, $f001, pwchar(UTF8Decode(XConfigureIcon)));
  AppendMenuW(FHMenu, MF_STRING, $f003, pwchar(UTF8Decode(XCopy)));
  if CanOpenFolder then
    AppendMenuW(FHMenu, MF_STRING, $f002, pwchar(UTF8Decode(XOpenFolderOf) + ' "' + Caption + '"'));
  AppendMenuW(FHMenu, MF_SEPARATOR, 0, '-');
  AppendMenuW(FHMenu, MF_STRING, $f004, pwchar(UTF8Decode(XDeleteIcon)));

  AppendMenuW(FHMenu, MF_SEPARATOR, 0, '-');
  if FRunning then
  begin
    AppendMenuW(FHMenu, MF_STRING + ifthen(FIsExecutable, 0, MF_DISABLED), $f008, pwchar(UTF8Decode(XKillProcess)));
    AppendMenuW(FHMenu, MF_SEPARATOR, 0, '-');
    if FAppList.Count < 2 then
      AppendMenuW(FHMenu, MF_STRING, $f007, pwchar(UTF8Decode(XCloseWindow)))
    else begin
      AppendMenuW(FHMenu, MF_STRING, $f007, pwchar(UTF8Decode(XCloseAllWindows)));
      AppendMenuW(FHMenu, MF_STRING, $f009, pwchar(UTF8Decode(XMinimizeRestoreAllWindows)));
    end;
  end;
  AppendMenuW(FHMenu, MF_STRING, $f006, pwchar(UTF8Decode(XRun)));
  mii.cbSize := sizeof(MENUITEMINFO);
  mii.fMask := MIIM_STATE;
  mii.fState := MFS_DEFAULT;
  SetMenuItemInfo(FHMenu, $f006, false, @mii);
  LME(true);

  // if shell context menu is enabled //
  if FUseShellContextMenus and ((FCommand <> '') or FIsPIDL) then
  begin
    if FIsPIDL then result := shcontextu.ShContextMenu(FHWnd, pt, FPIDL, FHMenu)
    else
    begin
      filename := toolu.UnzipPath(FCommand);
      if fileexists(filename) or directoryexists(filename) then result := shcontextu.ShContextMenu(FHWnd, pt, filename, FHMenu);
    end;
  end;

  // else, if it is disabled //
  if not result then msg.WParam := WPARAM(TrackPopupMenuEx(FHMenu, TPM_RETURNCMD, pt.x, pt.y, FHWnd, nil));
  WMCommand(msg.wParam, msg.lParam, msg.Result);
  Result := True;
end;
//------------------------------------------------------------------------------
procedure TShortcutItem.WMCommand(wParam: WPARAM; lParam: LPARAM; var Result: LRESULT);
var
  idx: integer;
begin
  result := 0;
  LME(false);
  DestroyMenu(FHMenu);
  FHMenu := 0;
  case wParam of // f001 to f020
    $f001: Configure;
    $f002: OpenFolder;
    $f003: toolu.SetClipboard(ToString);
    $f004: Delete;
    $f005: DockExecute(FHWnd, pchar('/emptybin'), nil, nil, 1);
    $f006: Exec(eaRun);
    $f007:
      if FAppList.Count > 0 then
      begin
        for idx := FAppList.Count - 1 downto 0 do
          ProcessHelper.CloseWindow(THandle(FAppList.Items[idx]));
      end;
    $f008: ProcessHelper.Kill(FExecutable);
    $f009: ProcessHelper.ActivateWindowList(FAppList);
  end;
end;
//------------------------------------------------------------------------------
procedure TShortcutItem.WndMessage(var msg: TMessage);
begin
  if not FFreed then
    with msg do
    begin
        Result := 0;

        // WM_ACTIVATEAPP
        if (msg = WM_ACTIVATEAPP) and (wParam = 0) then ClosePeekWindow;

        // WM_TIMER
        if msg = WM_TIMER then
        begin
          // open AeroPeekWindow
          if (wParam = ID_TIMER_OPEN) and
            ItemViews.ConsumeItemTimer(ItemId, ID_TIMER_OPEN, ClockNow) then ShowPeekWindow;
          // check if should cancel attention
          if (wParam = ID_TIMER_WINDOWACTIVATED) and
            ItemViews.ConsumeItemTimer(ItemId, ID_TIMER_WINDOWACTIVATED, ClockNow) then CheckWindowActivated;
          // update bitbucket
          if (wParam = ID_TIMER_UPDATE_SHORTCUT) and
            ItemViews.ConsumeItemTimer(ItemId, ID_TIMER_UPDATE_SHORTCUT, ClockNow) then
            if FDynObject or FDynObjectRecycleBin then DynObjectUpdate;
        end;
    end;
end;
//------------------------------------------------------------------------------
procedure TShortcutItem.BeforeMouseHover(AHover: boolean);
begin
  FHideHint := TAeroPeekWindow.IsActive and (FAppList.Count > 0);
end;
//------------------------------------------------------------------------------
procedure TShortcutItem.MouseHover(AHover: boolean);
begin
  if (FAppList.Count > 0) and not FTaskSystemMenus then
    if AHover then
    begin
      if TAeroPeekWindow.IsActive then
      begin
        if TAeroPeekWindow.ActivatedBy(FHWnd) then ShowPeekWindow else ShowPeekWindow(100);
      end
      else ShowPeekWindow(800);
    end else begin
      ClosePeekWindow(800);
    end;
end;
//------------------------------------------------------------------------------
procedure TShortcutItem.ShowPeekWindow(Timeout: cardinal = 0);
var
  pt: windows.TPoint;
begin
  if Timeout > 0 then
  begin
    ItemViews.SetItemTimer(ItemId, ID_TIMER_OPEN, Timeout);
    exit;
  end;

  ItemViews.KillItemTimer(ItemId, ID_TIMER_OPEN);

  pt := GetScreenRect.TopLeft;
  if (FSite = 1) or (FSite = 3) then inc(pt.x, FSize div 2);
  if (FSite = 0) or (FSite = 2) then inc(pt.y, FSize div 2);
  if FSite = 0 then inc(pt.x, FSize);
  if FSite = 1 then inc(pt.y, FSize);
  case FSite of
    0: inc(pt.x, 5);
    1: inc(pt.y, 5);
    2: dec(pt.x, 5);
    3: dec(pt.y, 5);
  end;
  FHideHint := true;
  UpdateHint;
  TAeroPeekWindow.Open(FHWnd, FAppList, FFlashedWindow, pt.x, pt.y, FSite, FTaskThumbSize, FTaskLivePreviews, FAeroPeekEnabled);
  FAeroPeekWindowActive := true;
end;
//------------------------------------------------------------------------------
procedure TShortcutItem.PrepareDeletion;
begin
  try
    if TAeroPeekWindow.ActivatedBy(FHWnd) then TAeroPeekWindow.Close(0);
    FAeroPeekWindowActive := false;
    FHideHint := false;
  finally
    inherited;
  end;
end;

procedure TShortcutItem.ClosePeekWindow(Timeout: cardinal = 0);
begin
  ItemViews.KillItemTimer(ItemId, ID_TIMER_OPEN);
  if FHideHint then
  begin
    FHideHint := false;
    UpdateHint;
  end;
  if FAeroPeekWindowActive then
  begin
    FAeroPeekWindowActive := false;
    TAeroPeekWindow.Close(Timeout);
  end;
end;
//------------------------------------------------------------------------------
procedure TShortcutItem.UpdatePeekWindow;
var
  pt: windows.TPoint;
begin
  pt := GetScreenRect.TopLeft;
  if (FSite = 1) or (FSite = 3) then inc(pt.x, FSize div 2);
  if (FSite = 0) or (FSite = 2) then inc(pt.y, FSize div 2);
  if FSite = 0 then inc(pt.x, FSize);
  if FSite = 1 then inc(pt.y, FSize);
  case FSite of
    0: inc(pt.x, 5);
    1: inc(pt.y, 5);
    2: dec(pt.x, 5);
    3: dec(pt.y, 5);
  end;
  TAeroPeekWindow.SetPosition(pt.x, pt.y);
end;
//------------------------------------------------------------------------------
procedure TShortcutItem.CheckWindowActivated;
begin
  ForegroundChanged(GetForegroundWindow);
end;

procedure TShortcutItem.ForegroundChanged(wnd: HWND);
begin
  if FFreed then exit;
  if FAttention then
  begin
    if FAppList.IndexOf(pointer(wnd)) >= 0 then
    begin
      FFlashedWindow := 0;
      Attention(false);
      ItemViews.KillItemTimer(ItemId, ID_TIMER_WINDOWACTIVATED);
    end;
  end
  else ItemViews.KillItemTimer(ItemId, ID_TIMER_WINDOWACTIVATED);
end;
//------------------------------------------------------------------------------
function TShortcutItem.CanOpenFolder: boolean;
var
  strFile: string;
begin
  strFile := toolu.UnzipPath(FCommand);
  result := fileexists(strFile) or directoryexists(strFile);
end;
//------------------------------------------------------------------------------
procedure TShortcutItem.OpenFolder;
var
  strFile: string;
begin
  strFile := ExtractFilePath(toolu.UnzipPath(FCommand));
  DockExecute(FHWnd, pchar(strFile), nil, nil, sw_shownormal);
end;
//------------------------------------------------------------------------------
function TShortcutItem.Executable: string;
begin
  result := ShellUTF8(FExecutable);
end;
//------------------------------------------------------------------------------
function TShortcutItem.DropFile(wnd: HWND; pt: windows.TPoint; filename: string): boolean;
var
  ext: string;
begin
  result := not FFreed;
  if result then
  begin
    ext := LowerCase(ExtractFileExt(filename));
    if (ext = '.png') or (ext = '.ico') then
    begin
      FImageFile := toolu.ZipPath(filename);
      FColorData := DEF_COLOR_DATA;
      Update;
    end
    else
    begin
      Result := ItemHostOpenDocument(FHWndParent, FHWnd, FCommand, FParams, FDir, filename, FShowCmd);
    end;
  end;
end;
//------------------------------------------------------------------------------
procedure TShortcutItem.Save(ini, section: string);
begin
  if (ini = '') or (section = '') then Exit;
  WriteShortcutIni(ini, section, CaptureData, not FDynObject);
end;
//------------------------------------------------------------------------------
class function TShortcutItem.Make(ACaption: WideString = '';
  ACommand: string = ''; AParams: string = ''; ADir: string = ''; AImage: string = '';
  AShowCmd: integer = 1; AColorData: integer = DEF_COLOR_DATA; AHide: boolean = false): string;
var Data: TShortcutDtoV1;
begin
  Data := DefaultShortcutDto;
  Data.Caption := ACaption;
  Data.Command := ACommand;
  Data.Params := AParams;
  Data.Directory := ADir;
  Data.Image := AImage;
  Data.ShowCmd := AShowCmd;
  Data.ColorData := AColorData;
  Data.Hide := AHide;
  Result := WriteShortcutText(Data);
end;
//------------------------------------------------------------------------------
class function TShortcutItem.MakeFromFilename(value: string): string;
var
  Caption: WideString;
  Dir: string = '';
begin
  if IsPackagedApp(value) then
  begin
    result := Make('?', value, '', '', '', 1);
  end
  else
  if IsShellName(ShellUTF16(value)) or IsPIDLString(value) then
  begin
    result := Make('::::', value, '', '', '', 1);
  end
  else
  begin
    if DirectoryExists(value) then
      Caption  := ShellUTF16(value)
    else
      Caption  := ShellUTF16(ChangeFileExt(ExtractFilename(value), ''));
    if LowerCase(ExtractFileExt(value)) = '.exe' then Dir := ZipPath(ExcludeTrailingPathDelimiter(ExtractFilePath(value)));
    result := Make(Caption, ZipPath(value), '', Dir, '', 1);
  end;
end;
//------------------------------------------------------------------------------
end.
 
