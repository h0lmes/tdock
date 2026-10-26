program terry;

{$MODE Delphi}

uses
  jwaWindows,
  Windows,
  Messages,
  Classes,
  SysUtils,
  Interfaces,
  interfacebase,
  Forms,
  Dialogs,
  ShellAPI,
  declu,
  DockH,
  frmmainu {frmterry},
  frmsetsu {frmsets},
  frmitemoptu {frmShortcutOptions},
  frmcmdu {frmcmd},
  frmthemeeditoru {frmLayersEditor},
  frmColorU {frmColor},
  frmDebugU {frmDebug},
  themeu, setsu, GDIPAPI, gfx, iconserviceu, toolu, itemmgru, customitemu, scitemu, sepitemu,
  plgitemu, stackitemu, customsubitemu, scsubitemu, hintu, droptgtu, shcontextu,
  notifieru, PIDL, dwm_unit, trayu, frmAddCommandU, frmstackpropu, stackmodeu,
  processhlp, taskitemu, frmhellou, frmtipu, multidocku, aeropeeku,
  shelltraywndu, MMDevApi_tlb, mixeru, networksu, customdrawitemu, frmrestoreu,
  iniproc, loggeru, UWP_TLB, pluginhostu, itemmodelu, itemhostu, shelltextu;

{$R *.res}

{$undef DEBUG_EXPORTS}
{$undef EXT_DEBUG}

//------------------------------------------------------------------------------
{$ifdef DEBUG_EXPORTS}
procedure inf(where, data: string);
begin
  AddLog(where + ':   ' + data);
end;
{$endif}
//------------------------------------------------------------------------------
function DockletIsVisible(id: HWND): bool; stdcall;
begin
  result := assigned(PluginHost) and PluginHost.Visible;
  {$ifdef DEBUG_EXPORTS} inf('DockletIsVisible', inttostr(id) + ', ' + inttostr(integer(result))); {$endif}
end;
//------------------------------------------------------------------------------
function DockletIsUndocked(id: HWND): bool; stdcall;
begin
  {$ifdef DEBUG_EXPORTS} inf('DockletIsUndocked', inttostr(id)); {$endif}
  result := false;
  try
    if assigned(PluginHost) then result := PluginHost.IsUndocked(id);
  except
    on e: Exception do if assigned(PluginHost) then PluginHost.ReportError('DockletIsUndocked', e);
  end;
end;
//------------------------------------------------------------------------------
function DockletGetRect(id: HWND; r: windows.PRect): bool; stdcall;
var
  tmp: windows.TRect;
begin
  {$ifdef DEBUG_EXPORTS} inf('DockletGetRect', inttostr(id)); {$endif}
  result := false;
  try
    if assigned(PluginHost) and (r <> nil) then
      begin
        result := PluginHost.GetItemRect(id, tmp);
        r.Left := tmp.left;
        r.Top := tmp.top;
        r.Right := tmp.right;
        r.Bottom := tmp.bottom;
      end;
  except
    on e: Exception do if assigned(PluginHost) then PluginHost.ReportError('DockletGetRect', e);
  end;
end;
//------------------------------------------------------------------------------
function DockletGetLabel(id: HWND; szCaption: pchar): integer; stdcall;
var
  capt: string;
begin
  {$ifdef DEBUG_EXPORTS} inf('DockletGetLabel', inttostr(id)); {$endif}
  result := 0;
  try
    if assigned(PluginHost) then
      begin
        capt := PluginHost.GetCaption(id);
        result := length(capt);
        if szCaption <> nil then StrLCopy(szCaption, pchar(capt), result);
        inc(result);
      end;
  except
    on e: Exception do if assigned(PluginHost) then PluginHost.ReportError('DockletGetLabel', e);
  end;
end;
//------------------------------------------------------------------------------
function DockletSetLabel(id: HWND; szCaption: pchar): integer; stdcall;
var
  caption: WideString;
  required: integer;
begin
  {$ifdef DEBUG_EXPORTS} inf('DockletSetLabel', inttostr(id) + ', ' + strpas(szCaption)); {$endif}
  result := 0;
  try
    if assigned(PluginHost) and (szCaption <> nil) then
      begin
        required := MultiByteToWideChar(CP_ACP, 0, szCaption, -1, nil, 0);
        if required = 0 then exit;
        SetLength(caption, required);
        if MultiByteToWideChar(CP_ACP, 0, szCaption, -1, PWideChar(caption), required) = 0 then exit;
        SetLength(caption, required - 1);
        result := PluginHost.SetCaption(id, caption) + 1;
      end;
  except
    on e: Exception do if assigned(PluginHost) then PluginHost.ReportError('DockletSetLabel', e);
  end;
end;
//------------------------------------------------------------------------------
function DockletLoadGDIPlusImage(szImage: pchar): Pointer; stdcall;
var
  imagefile: WideString;
begin
  result := nil;
  try
    if szImage <> nil then
    begin
      imagefile := UnzipPath(strpas(szImage));
      {$ifdef DEBUG_EXPORTS} inf('DockletLoadGDIPlusImage.szImage', strpas(szImage)); {$endif}
      GdipCreateBitmapFromFile(PWideChar(imagefile), result);
    end;
  except
    on e: Exception do if assigned(PluginHost) then PluginHost.ReportError('DockletLoadGDIPlusImage', e);
  end;
  {$ifdef DEBUG_EXPORTS} inf('DockletLoadGDIPlusImage', '0x' + inttohex(dword(result), 8)); {$endif}
end;
//------------------------------------------------------------------------------
procedure DockletSetImage(id: HWND; image: Pointer; AutoDelete: bool); stdcall;
begin
  {$ifdef DEBUG_EXPORTS} inf('DockletSetImage', inttostr(id) + ', 0x' + inttohex(dword(image), 8)); {$endif}
  try
    if assigned(PluginHost) then PluginHost.SetImage(id, image, AutoDelete);
  except
    on e: Exception do if assigned(PluginHost) then PluginHost.ReportError('DockletSetImage', e);
  end;
end;
//------------------------------------------------------------------------------
procedure DockletSetImageFile(id: HWND; szImage: pchar); stdcall;
begin
  {$ifdef DEBUG_EXPORTS} inf('DockletSetImageFile', inttostr(id) + ', ' + strpas(szImage)); {$endif}
  try
    if szImage <> nil then
      DockletSetImage(id, DockletLoadGDIPlusImage(szImage), true);
  except
    on e: Exception do if assigned(PluginHost) then PluginHost.ReportError('DockletSetImageFile', e);
  end;
end;
//------------------------------------------------------------------------------
procedure DockletSetImageOverlay(id: HWND; overlay: Pointer; AutoDelete: bool); stdcall;
begin
  {$ifdef DEBUG_EXPORTS} inf('DockletSetImageOverlay', inttostr(id) + ', 0x' + inttohex(dword(overlay), 8)); {$endif}
  try
    if assigned(PluginHost) then PluginHost.SetOverlay(id, overlay, AutoDelete);
  except
    on e: Exception do if assigned(PluginHost) then PluginHost.ReportError('DockletSetImageOverlay', e);
  end;
end;
//------------------------------------------------------------------------------
function DockletBrowseForImage(id: HWND; szImage: pchar; szRoot: pchar): bool; stdcall;
var
  sTemp: string;
  scope: TItemHostScope;
  imageDialog: TOpenDialog;
begin
  {$ifdef DEBUG_EXPORTS} inf('DockletBrowseForImage1', inttostr(id) + ', ' + strpas(szImage) + ', ' + strpas(szRoot)); {$endif}
  result:= false;
  try
    if (szImage = nil) or not assigned(PluginHost) then exit;
    if not PluginHost.BeginUiOperation(scope) then exit;
    try
      imageDialog := TOpenDialog.Create(nil);
      try
        if szRoot <> nil then sTemp:= strpas(szRoot)
        else sTemp:= IncludeTrailingPathDelimiter(ExtractFilePath(paramstr(0)));
        imageDialog.InitialDir := sTemp;
        if imageDialog.Execute then
        begin
          sTemp := imageDialog.FileName;
          StrLCopy(szImage, pchar(sTemp), MAX_PATH);
          result := true;
        end;
      finally imageDialog.Free; end;
    finally EndItemHostOperation(scope); end;
  except
    on e: Exception do if assigned(PluginHost) then PluginHost.ReportError('DockletBrowseForImage', e);
  end;
  {$ifdef DEBUG_EXPORTS} if result then inf('DockletBrowseForImage2', inttostr(id) + ', ' + strpas(szImage) + ', ' + strpas(szRoot)); {$endif}
end;
//------------------------------------------------------------------------------
procedure DockletLockMouseEffect(id: HWND; lock: bool); stdcall;
begin
  {$ifdef DEBUG_EXPORTS} inf('DockletLockMouseEffect', inttostr(id) + ', ' + inttostr(integer(lock))); {$endif}
  try
    if assigned(PluginHost) then PluginHost.LockMouseEffect(id, lock);
  except
    on e: Exception do if assigned(PluginHost) then PluginHost.ReportError('DockletLockMouseEffect', e);
  end;
end;
//------------------------------------------------------------------------------
procedure DockletDoAttensionAnimation(id: HWND); stdcall;
begin
  {$ifdef DEBUG_EXPORTS} inf('DockletDoAttensionAnimation', inttostr(id)); {$endif}
  try
    if assigned(PluginHost) then PluginHost.Animate(id);
  except
    on e: Exception do if assigned(PluginHost) then PluginHost.ReportError('DockletDoAttensionAnimation', e);
  end;
end;
//------------------------------------------------------------------------------
procedure DockletGetRelativeFolder(id: HWND; szFolder: pchar); stdcall;
var
  rel: string;
begin
  {$ifdef DEBUG_EXPORTS} inf('DockletGetRelativeFolder1', inttostr(id)); {$endif}
  try
    rel := '';
    if assigned(PluginHost) then rel := PluginHost.RelativeFolder(id);
    if assigned(szFolder) then StrLCopy(szFolder, pchar(rel), length(rel));
  except
    on e: Exception do if assigned(PluginHost) then PluginHost.ReportError('DockletGetRelativeFolder', e);
  end;
  {$ifdef DEBUG_EXPORTS} inf('DockletGetRelativeFolder2', inttostr(id) + ', ' + strpas(szFolder)); {$endif}
end;
//------------------------------------------------------------------------------
procedure DockletGetRootFolder(id: HWND; szFolder: pchar); stdcall;
var
  rel: string;
begin
  {$ifdef DEBUG_EXPORTS} inf('DockletGetRootFolder1', inttostr(id)); {$endif}
  try
    rel := '';
    if assigned(PluginHost) then rel := PluginHost.RootFolder;
    if assigned(szFolder) then StrLCopy(szFolder, pchar(rel), MAX_PATH);
  except
    on e: Exception do if assigned(PluginHost) then PluginHost.ReportError('DockletGetRootFolder', e);
  end;
  {$ifdef DEBUG_EXPORTS} inf('DockletGetRootFolder2', inttostr(id) + ', ' + strpas(szFolder)); {$endif}
end;
//------------------------------------------------------------------------------
function DockletQueryDockEdge(id: HWND): integer; stdcall;
begin
  result := 0;
  if assigned(PluginHost) then result := PluginHost.QueryDockEdge;
end;
//------------------------------------------------------------------------------
function DockletSetDockEdge(id: HWND; Edge: integer): integer; stdcall;
begin
  result := 0;
  if assigned(PluginHost) then result := PluginHost.SetDockEdge(Edge);
end;
//------------------------------------------------------------------------------
function DockletQueryDockAlign(id: HWND): integer; stdcall;
begin
  result := 1;
  if assigned(PluginHost) then result := PluginHost.QueryDockAlign;
end;
//------------------------------------------------------------------------------
function DockletSetDockAlign(id: HWND; Offset: integer): integer; stdcall;
begin
  result := 1;
  if assigned(PluginHost) then result := PluginHost.SetDockAlign(Offset);
end;
//------------------------------------------------------------------------------
function DockColorDialog(AColor: puint): bool; stdcall;
var scope: TItemHostScope; colorDialog: TColorDialog;
begin
  result := false;
  try
    if (AColor = nil) or not assigned(PluginHost) then exit;
    if not PluginHost.BeginUiOperation(scope) then exit;
    try
      colorDialog := TColorDialog.Create(nil);
      try
        colorDialog.Color := AColor^ and $FFFFFF;
        if colorDialog.Execute then
        begin
          AColor^ := colorDialog.Color;
          result := true;
        end;
      finally colorDialog.Free; end;
    finally EndItemHostOperation(scope); end;
  except
    on e: Exception do if assigned(PluginHost) then PluginHost.ReportError('DockColorDialog', e);
  end;
end;
//------------------------------------------------------------------------------
function DockGetRect: windows.TRect; stdcall;
begin
  result.Left := 0;
  result.Top := 0;
  result.Right := 0;
  result.Bottom := 0;
  if assigned(PluginHost) then result := PluginHost.DockRect;
end;
//------------------------------------------------------------------------------
procedure DockExecute(id: HWND; exename, params, dir: pchar; showcmd: integer); stdcall;
begin
  try
    if assigned(PluginHost) then PluginHost.Execute(id, exename, params, dir, showcmd);
  except
    on e: Exception do if assigned(PluginHost) then PluginHost.ReportError('DockExecute', e);
  end;
end;
//------------------------------------------------------------------------------
function DockAddMenu(hMenu: THandle): THandle; stdcall;
begin
  result := 0;
  try
    if assigned(PluginHost) then result := PluginHost.AddMenu(hMenu);
  except
    on e: Exception do if assigned(PluginHost) then PluginHost.ReportError('DockAddMenu', e);
  end;
end;
//------------------------------------------------------------------------------
procedure Undock(id: HWND); stdcall;
begin
  if assigned(PluginHost) then PluginHost.Undock(id);
end;
//------------------------------------------------------------------------------
procedure Dock(id: HWND); stdcall;
begin
  if assigned(PluginHost) then PluginHost.Dock(id);
end;
//------------------------------------------------------------------------------
function DockCreateItem(data: pchar): HWND; stdcall;
begin
  result := 0;
  try
    if assigned(PluginHost) then result := PluginHost.CreateItem(data);
  except
    on e: Exception do if assigned(PluginHost) then PluginHost.ReportError('DockCreateItem', e);
  end;
end;
//------------------------------------------------------------------------------
procedure DockDeleteItem(id: HWND); stdcall;
begin
  if assigned(PluginHost) then PluginHost.DeleteItem(id);
end;
//------------------------------------------------------------------------------
function DockAddProgram(data: pchar): THandle; stdcall;
begin
  try
    result := 0;
    if assigned(PluginHost) then PluginHost.AddProgram(strpas(data));
  except
    on e: Exception do if assigned(PluginHost) then PluginHost.ReportError('DockAddProgram', e);
  end;
end;
//------------------------------------------------------------------------------
procedure Notify(id: HWND; Message: PAnsiChar); stdcall;
begin
  if assigned(PluginHost) then PluginHost.Notify(WideString(strpas(Message)));
end;
//------------------------------------------------------------------------------
procedure ActivateHint(id: HWND; Caption: PWideChar; x, y: integer); stdcall;
begin
  if assigned(PluginHost) then PluginHost.ActivateHint(id, Caption, x, y);
end;
//------------------------------------------------------------------------------
procedure DeactivateHint(id: HWND); stdcall;
begin
  if assigned(PluginHost) then PluginHost.DeactivateHint(id);
end;
//------------------------------------------------------------------------------
procedure ExcludeFromPeek(id: HWND); stdcall;
begin
  if assigned(PluginHost) then PluginHost.ExcludeFromPeek(id);
end;
//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
function TDockApiVersion: Cardinal; stdcall;
begin
  result := 1;
end;

function TDockItemCreateV1(Data: PAnsiChar): TDockItemId; stdcall;
begin
  result := 0;
  if (Data = nil) or not assigned(PluginHost) then exit;
  try result := TDockItemId(PluginHost.CreateItemId(StrPas(Data)));
  except
    on E: Exception do if assigned(PluginHost) then PluginHost.ReportError('TDockItemCreateV1', E);
  end;
end;

function TDockItemInsertV1(Id: TDockItemId): TDockItemId; stdcall;
begin
  result := 0;
  if not assigned(PluginHost) then exit;
  try result := TDockItemId(PluginHost.InsertItemId(TItemId(Id)));
  except
    on E: Exception do if assigned(PluginHost) then PluginHost.ReportError('TDockItemInsertV1', E);
  end;
end;

function TDockItemDeleteV1(Id: TDockItemId): BOOL; stdcall;
begin
  result := false;
  if not assigned(PluginHost) then exit;
  try result := PluginHost.DeleteItemId(TItemId(Id));
  except
    on E: Exception do if assigned(PluginHost) then PluginHost.ReportError('TDockItemDeleteV1', E);
  end;
end;

function TDockItemGetWindowV1(Id: TDockItemId): HWND; stdcall;
begin
  result := 0;
  if not assigned(PluginHost) then exit;
  try result := PluginHost.WindowFromItemId(TItemId(Id));
  except
    on E: Exception do if assigned(PluginHost) then PluginHost.ReportError('TDockItemGetWindowV1', E);
  end;
end;

function TDockItemFromWindowV1(Window: HWND): TDockItemId; stdcall;
begin
  result := 0;
  if not assigned(PluginHost) then exit;
  try result := TDockItemId(PluginHost.ItemIdFromWindow(Window));
  except
    on E: Exception do if assigned(PluginHost) then PluginHost.ReportError('TDockItemFromWindowV1', E);
  end;
end;

function TDockItemGetCaptionV1(Id: TDockItemId; Buffer: PWideChar; Capacity: Cardinal): Cardinal; stdcall;
begin
  result := 0;
  if not assigned(PluginHost) then exit;
  try result := PluginHost.CopyCaptionById(TItemId(Id), Buffer, Capacity);
  except
    on E: Exception do if assigned(PluginHost) then PluginHost.ReportError('TDockItemGetCaptionV1', E);
  end;
end;

function TDockItemSetCaptionV1(Id: TDockItemId; Caption: PWideChar): BOOL; stdcall;
begin
  result := false;
  if (Caption = nil) or not assigned(PluginHost) then exit;
  try result := PluginHost.SetCaptionById(TItemId(Id), WideString(Caption));
  except
    on E: Exception do if assigned(PluginHost) then PluginHost.ReportError('TDockItemSetCaptionV1', E);
  end;
end;

function TDockItemSetImageV1(Id: TDockItemId; Image: Pointer; AutoDelete: BOOL): BOOL; stdcall;
begin
  result := false;
  if not assigned(PluginHost) then exit;
  try result := PluginHost.SetImageById(TItemId(Id), Image, AutoDelete);
  except
    on E: Exception do if assigned(PluginHost) then PluginHost.ReportError('TDockItemSetImageV1', E);
  end;
end;

function TDockItemSetOverlayV1(Id: TDockItemId; Image: Pointer; AutoDelete: BOOL): BOOL; stdcall;
begin
  result := false;
  if not assigned(PluginHost) then exit;
  try result := PluginHost.SetOverlayById(TItemId(Id), Image, AutoDelete);
  except
    on E: Exception do if assigned(PluginHost) then PluginHost.ReportError('TDockItemSetOverlayV1', E);
  end;
end;

function TDockItemDockV1(Id: TDockItemId): BOOL; stdcall;
begin
  result := false;
  if not assigned(PluginHost) then exit;
  try result := PluginHost.DockById(TItemId(Id));
  except
    on E: Exception do if assigned(PluginHost) then PluginHost.ReportError('TDockItemDockV1', E);
  end;
end;

function TDockItemUndockV1(Id: TDockItemId): BOOL; stdcall;
begin
  result := false;
  if not assigned(PluginHost) then exit;
  try result := PluginHost.UndockById(TItemId(Id));
  except
    on E: Exception do if assigned(PluginHost) then PluginHost.ReportError('TDockItemUndockV1', E);
  end;
end;

function TDockItemAnimateV1(Id: TDockItemId): BOOL; stdcall;
begin
  result := false;
  if not assigned(PluginHost) then exit;
  try result := PluginHost.AnimateById(TItemId(Id));
  except
    on E: Exception do if assigned(PluginHost) then PluginHost.ReportError('TDockItemAnimateV1', E);
  end;
end;

exports
  TDockApiVersion,
  TDockItemCreateV1,
  TDockItemInsertV1,
  TDockItemDeleteV1,
  TDockItemGetWindowV1,
  TDockItemFromWindowV1,
  TDockItemGetCaptionV1,
  TDockItemSetCaptionV1,
  TDockItemSetImageV1,
  TDockItemSetOverlayV1,
  TDockItemDockV1,
  TDockItemUndockV1,
  TDockItemAnimateV1,
  DockletIsVisible,
  DockletIsUndocked,
  DockletGetRect,
  DockletGetLabel,
  DockletSetLabel,
  DockletSetImage,
  DockletSetImageFile,
  DockletSetImageOverlay,
  DockletDoAttensionAnimation,
  DockletGetRootFolder,
  DockletGetRelativeFolder,
  DockletLoadGDIPlusImage,
  DockletBrowseForImage,
  DockletLockMouseEffect,
  DockletQueryDockEdge,
  DockletSetDockEdge,
  DockletQueryDockAlign,
  DockletSetDockAlign,
  DockGetRect,
  DockColorDialog,
  DockExecute,
  DockAddMenu,
  Undock,
  Dock,
  DockCreateItem,
  DockDeleteItem,
  DockAddProgram,
  Notify,
  ActivateHint,
  DeactivateHint,
  ExcludeFromPeek;
//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
function TDWindowProc(wnd: HWND; message: uint; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall;
begin
  result := DefWindowProc(wnd, message, wParam, lParam);
end;
//------------------------------------------------------------------------------
procedure RegisterWindowItemClass;
var
  wndClass: windows.TWndClass;
begin
  try
    wndClass.style          := CS_DBLCLKS;
    wndClass.lpfnWndProc    := @TDWindowProc;
    wndClass.cbClsExtra     := 0;
    wndClass.cbWndExtra     := 0;
    wndClass.hInstance      := hInstance;
    wndClass.hIcon          := 0;
    wndClass.hCursor        := LoadCursor(0, idc_Arrow);
    wndClass.hbrBackground  := 0;
    wndClass.lpszMenuName   := nil;
    wndClass.lpszClassName  := TDWCLASS;
    windows.RegisterClass(wndClass);
  except
    on e: Exception do if assigned(PluginHost) then PluginHost.ReportError('RegisterWindowItemClass', e);
  end;
end;
//------------------------------------------------------------------------------
function encodePath(path: string): string;
begin
  result := toolu.ReplaceEx(path, '\', '_');
  if length(result) > MAX_PATH - 1 - length(PROGRAM_GUID) - 7 then
     result := copy(result, length(result) - (MAX_PATH - 1 - length(PROGRAM_GUID) - 7), MAX_PATH);
end;
//------------------------------------------------------------------------------
var
  VerInfo: TOSVersioninfo;
  {$ifndef CPU64}
  IsWow64Process: function(Handle: THandle; var Res: boolean): boolean; stdcall;
  {$endif}
  idx: integer;
  setsFiles: TStrings;
  SetsFilename, ProgramPath: string;
  hMutex: THandle;
  h: THandle;
begin
  loggeru.SetLogFileName(ChangeFileExt(ParamStr(0), '.log'));
  AddLog('>>> TDock app start');

  //if FileExists('heap.trc') then DeleteFile('heap.trc');
  //SetHeapTraceOutput('heap.trc');

  toolu.ScalingFactor := 100;
  // os version
  VerInfo.dwOSVersionInfoSize := sizeof(TOSVersionInfo);
  GetVersionEx(@VerInfo);
  toolu.bIsWindowsVistaOrHigher := VerInfo.dwMajorVersion >= 6;
  toolu.bIsWindows10 := VerInfo.dwMajorVersion >= 10;
  gfx.bIsWindowsVistaOrHigher := toolu.bIsWindowsVistaOrHigher;
  {$ifdef EXT_DEBUG} AddLog('version'); {$endif}

  // multi-dock support //

  TMultiDock.CCreate();
  // read sets filename from params
  ProgramPath := IncludeTrailingPathDelimiter(ExtractFilePath(Paramstr(0)));
  SetsFilename := '';
  idx := 1;
  while idx <= ParamCount do
  begin
    if strlicomp(pchar(ParamStr(idx)), '-i', 2) = 0 then
      SetsFilename := ProgramPath + copy(ParamStr(idx), 3, MAX_PATH - 1);
    inc(idx);
  end;
  {$ifdef EXT_DEBUG} AddLog('MultiDock'); {$endif}

  // if it was not specified
  if SetsFilename = '' then
  begin
    // list all sets files in program folder
    setsFiles := TStringList.Create;
    searchfiles(ProgramPath, 'sets*.ini', setsFiles);
    qSortStrings(setsFiles);
    // take 1st one
    if setsFiles.Count > 0 then SetsFilename := ProgramPath + setsFiles.Strings[0];
    // or the default one
    if not FileExists(SetsFilename) then SetsFilename := ProgramPath + 'sets.ini';
    // run instances for all other files
    if setsFiles.Count > 1 then
    begin
      for idx := 1 to setsFiles.Count - 1 do docks.RunDock(setsFiles.Strings[idx]);
    end;
    setsFiles.free;
  end;
  {$ifdef EXT_DEBUG} AddLog('scan sets files'); {$endif}


  // check running instances //

  hMutex := CreateMutex(nil, false, pchar('Global\' + PROGRAM_GUID + encodePath(SetsFilename)));
  if GetLastError = ERROR_ALREADY_EXISTS then
  begin
    h := FindWindow('Window', PROGRAM_NAME);
    if IsWindow(h) then
    begin
      sendmessage(h, wm_user, wm_activate, 0);
      SetForegroundWindow(h);
    end;
    halt;
  end;
  {$ifdef EXT_DEBUG} AddLog('CreateMutex'); {$endif}

  // application //

  Application.Scaled:=True;
  Application.Initialize;
  {$ifdef EXT_DEBUG} AddLog('Application.Initialize'); {$endif}
  Application.Title := PROGRAM_TITLE;
  h := WidgetSet.AppHandle;
  SetWindowLongPtr(h, GWL_EXSTYLE, GetWindowLongPtr(h, GWL_EXSTYLE) or WS_EX_TOOLWINDOW);
  {$ifdef EXT_DEBUG} AddLog('SetWindowLongPtr appHandle'); {$endif}

  Application.ShowMainForm := false;
  Application.CreateForm(Tfrmmain, frmmain);
  {$ifdef EXT_DEBUG} AddLog('frmmain.Create'); {$endif}
  SetWindowLongPtr(frmmain.handle, GWL_EXSTYLE, GetWindowLongPtr(frmmain.handle, GWL_EXSTYLE) or WS_EX_LAYERED or WS_EX_TOOLWINDOW);
  frmmain.Caption := PROGRAM_NAME;
  {$ifdef EXT_DEBUG} AddLog('SetWindowLongPtr frmmain'); {$endif}

  RegisterWindowItemClass;
  {$ifdef EXT_DEBUG} AddLog('RegisterWindowItemClass'); {$endif}
  Notifier := TNotifier.Create;
  {$ifdef EXT_DEBUG} AddLog('TNotifier.Create'); {$endif}
  mixer := TMixer.Create;
  {$ifdef EXT_DEBUG} AddLog('TMixer.Create'); {$endif}
  // ProcessHelper (must be created before tray controller). Depends on DWM //
  ProcessHelper := TProcessHelper.Create;
  {$ifdef EXT_DEBUG} AddLog('TProcessHelper.Create'); {$endif}
  ShellTrayWndController := TShellTrayWndController.Create;
  {$ifdef EXT_DEBUG} AddLog('TShellTrayWndController.Create'); {$endif}

  frmmain.Init(SetsFilename);
  {$ifdef EXT_DEBUG} AddLog('frmmain.Init'); {$endif}
  Application.ShowMainForm := true;
  frmmain.ExecAutorun;

  Application.Run;

  CloseHandle(hMutex);
  TShellTrayWndController.Cleanup;
  TProcessHelper.Cleanup;
  TMixer.Cleanup;
  TNotifier.Cleanup;
  TMultiDock.CDestroy;
  AddLog('>>> End');
end.
