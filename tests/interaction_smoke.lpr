program interaction_smoke;

{$mode delphi}

uses Interfaces, Windows, Messages, SysUtils, Classes, Controls, Forms, ActiveX, ShlObj, ComObj,
  declu, setsu, frmmainu, itemmgru, customitemu, stackitemu, scitemu,
  pluginhostu, shelltraywndu, notifieru, toolu, loggeru, win32hotkeyu, dropimportu;

type
  TObservedMain = class(Tfrmmain)
  public
    FullscreenObservations: Integer;
    function FullScreenAppActive: Boolean; override;
  end;
  TObservedStack = class(TStackItem)
  public
    Ticks: Integer;
    procedure Timer; override;
  end;
  TFailingDropBatch = class(TDropImportBatch)
  protected
    function GetCount: Integer; override;
  public
    FailCount: Boolean;
  end;

function TFailingDropBatch.GetCount: Integer;
begin
  if FailCount then raise Exception.Create('Controlled drop consumer failure');
  Result := inherited GetCount;
end;

procedure TObservedStack.Timer;
begin Inc(Ticks); inherited; end;

function TObservedMain.FullScreenAppActive: Boolean;
begin
  Inc(FullscreenObservations);
  Result := False;
end;

procedure ActivateHint(Id: THandle; Caption: PWideChar; X, Y: Integer); stdcall;
begin
  if Assigned(PluginHost) then PluginHost.ActivateHint(Id, Caption, X, Y);
end;
procedure DeactivateHint(Id: THandle); stdcall;
begin
  if Assigned(PluginHost) then PluginHost.DeactivateHint(Id);
end;
function DockGetRect: Windows.TRect; stdcall;
begin
  Result := Default(Windows.TRect);
  if Assigned(PluginHost) then Result := PluginHost.DockRect;
end;
procedure ExcludeFromPeek(Id: THandle); stdcall;
begin
  if Assigned(PluginHost) then PluginHost.ExcludeFromPeek(Id);
end;
procedure Notify(Id: THandle; Text: PChar); stdcall;
begin
  if Assigned(PluginHost) then PluginHost.Notify(WideString(StrPas(Text)));
end;

exports ActivateHint, DeactivateHint, DockGetRect, ExcludeFromPeek, Notify;

procedure Require(Value: Boolean; const Message: string);
begin
  if not Value then raise Exception.Create(Message);
end;
procedure Pump(Duration: QWord);
var Deadline: QWord;
begin
  Deadline := GetTickCount64 + Duration;
  repeat
    Application.ProcessMessages;
    Sleep(5);
  until GetTickCount64 >= Deadline;
end;
function OwnedWindow(const ClassName: PChar; Owner: HWND = 0): HWND;
var ProcessId: DWORD;
begin
  Result := 0;
  repeat
    Result := Windows.FindWindowEx(0, Result, ClassName, nil);
    if Result = 0 then Exit;
    Windows.GetWindowThreadProcessId(Result, @ProcessId);
    if (ProcessId = Windows.GetCurrentProcessId) and
      ((Owner = 0) or (Windows.GetWindow(Result, GW_OWNER) = Owner)) then Exit;
  until False;
end;

function NativeFileData(const Path: UnicodeString): IDataObject;
var Absolute, Child: PItemIDList; Parent: IShellFolder;
begin
  Absolute := nil;
  OleCheck(SHParseDisplayName(PWideChar(Path), nil, Absolute, 0, nil));
  try
    OleCheck(SHBindToParent(Absolute, IID_IShellFolder, @Parent, Child));
    OleCheck(Parent.GetUIObjectOf(0, 1, Child, IID_IDataObject, nil, Result));
  finally CoTaskMemFree(Absolute); end;
end;

procedure RunSmoke;
var Fixture: string; Lines: TStringList; Params: TDItemCreateParams;
  Stack: TObservedStack; HintWindow: HWND; DockRect: Windows.TRect;
  Point: Windows.TPoint; HeightBeforeZoom: Integer; Hotkey: TDockHotkeyBinding;
  Batch: TDropImportBatch; CopiedPath: UnicodeString; CopyHandle: THandle;
  CopyBytes: RawByteString; Written, Effect: DWORD; CountBefore: Integer;
  FailingBatch: TFailingDropBatch; FailureReturned: Boolean;
  NativeData: IDataObject;
begin
  ScalingFactor := 100;
  Application.Initialize;
  Application.ShowMainForm := False;
  Application.CreateForm(TObservedMain, frmmain);
  Windows.SetWindowLongPtr(frmmain.Handle, GWL_EXSTYLE,
    Windows.GetWindowLongPtr(frmmain.Handle, GWL_EXSTYLE) or WS_EX_LAYERED or WS_EX_TOOLWINDOW);
  frmmain.trayicon.Visible := False;
  ShellTrayWndController := TShellTrayWndController.Create;
  Notifier := TNotifier.Create;
  Fixture := ExtractFilePath(ParamStr(0)) + 'interaction.ini';
  ForceDirectories(ExtractFilePath(ParamStr(0)) + 'Themes');
  Lines := TStringList.Create;
  try
    Lines.Text := '[base]' + LineEnding +
      'Hello=0' + LineEnding + 'AutoHide=0' + LineEnding +
      'AutoHideOnFullScreenApp=0' + LineEnding + 'HideTaskBar=0' + LineEnding +
      'ReserveScreenEdge=0' + LineEnding + 'ShowRunningIndicator=0' + LineEnding +
      'Taskbar=0' + LineEnding + 'Blur=0' + LineEnding + 'ShowHint=1' + LineEnding +
      'HintEffects=0' + LineEnding + 'ZoomItems=1' + LineEnding +
      'ItemSize=48' + LineEnding + 'BigItemSize=96' + LineEnding +
      'ZoomTime=120' + LineEnding + 'StackOpenAnimation=1' + LineEnding +
      '[gfx]' + LineEnding + 'Blur=0' + LineEnding +
      '[Font]' + LineEnding + 'name=Segoe UI' + LineEnding + 'size=14' + LineEnding +
      'size2=14' + LineEnding + '[item1]' + LineEnding + 'class=separator' + LineEnding;
    Lines.SaveToFile(Fixture);
  finally Lines.Free; end;
  try
    frmmain.Init(Fixture);
    Require(TObservedMain(frmmain).FullscreenObservations > 0,
      'Startup did not seed fullscreen observation');
    Writeln('PASS initial fullscreen observation');
    Params := Default(TDItemCreateParams);
    Params.ItemSize := 48; Params.BigItemSize := 96;
    Params.ShowHint := True; Params.StackAnimationEnabled := True;
    Params.Font := sets.container.Font;
    Params.Parameter := TStackItem.Make('Interaction smoke stack');
    Stack := TObservedStack.Create(frmmain.Handle, Params);
    Require(frmmain.ItemMgr.AdoptItem(Stack, True) = Stack.Handle, 'Stack adoption failed');
    Stack.AddSubitem(TShortcutItem.Make('Smoke item', '', '', '', '', SW_SHOWNORMAL));
    Pump(150);
    Require(Stack.Ticks = 0, 'A stable item received idle frame callbacks');
    frmmain.ItemMgr.ItemCmd(Stack.Handle, icHover, 1);
    HintWindow := OwnedWindow('TDockHintWClass');
    Require(Assigned(frmmain.AHint) and IsWindowVisible(HintWindow), 'Hover hint did not become visible');
    frmmain.AHint.DeactivateImmediate;
    frmmain.SetParam(gpHintEffects, 1);
    frmmain.ItemMgr.ItemCmd(Stack.Handle, icHover, 0);
    frmmain.ItemMgr.ItemCmd(Stack.Handle, icHover, 1);
    Pump(150);
    Require(IsWindowVisible(HintWindow), 'Animated hover hint did not become visible');
    Writeln('PASS hover hint with effects off and on');
    Require(frmmain.BeginUserOperation, 'Stack operation was rejected');
    try Stack.MouseClick(mbLeft, [], 0, 0); finally frmmain.EndUserOperation; end;
    Pump(750);
    Require(Stack.Ticks > 0, 'Active stack animation did not receive frame callbacks');
    Require(IsWindowVisible(OwnedWindow('TDockSubItemWClass', Stack.Handle)), 'Animated stack did not open');
    Require(frmmain.BeginUserOperation, 'Stack close operation was rejected');
    try Stack.MouseClick(mbLeft, [], 0, 0); finally frmmain.EndUserOperation; end;
    Pump(750);
    Require(not IsWindowVisible(OwnedWindow('TDockSubItemWClass', Stack.Handle)), 'Animated stack did not close');
    Require(not frmmain.IsMouseEffectLocked, 'Stack animation retained the mouse lock');
    Writeln('PASS animated stack open and close');
    frmmain.ItemMgr.Undock(Stack.Handle);
    DockRect := frmmain.ItemMgr.Rect;
    Point.X := (DockRect.Left + DockRect.Right) div 2;
    Point.Y := (DockRect.Top + DockRect.Bottom) div 2;
    HeightBeforeZoom := frmmain.ItemMgr.LayoutSnapshot.HeightZoomed;
    frmmain.ItemMgr.WHMouseMove(Point);
    Require(frmmain.ItemMgr.InteractionSnapshot.Zooming, 'Zoom did not start');
    Pump(250);
    Require(frmmain.ItemMgr.LayoutSnapshot.HeightZoomed > HeightBeforeZoom,
      'Native dock timer did not advance zoom geometry');
    frmmain.ItemMgr.Dock(Stack.Handle);
    Writeln('PASS timer-driven zoom');
    frmmain.SetParam(gpGlobalHotkeyValue_Hide, VK_F24);
    frmmain.SetParam(gpGlobalHotkeyFlag_Hide, 1);
    Hotkey := frmmain.HotkeyBinding(0);
    Require(Hotkey.Registered, 'Native global hotkey registration failed');
    Windows.PostMessage(frmmain.Handle, WM_HOTKEY, Hotkey.NativeId, LPARAM(VK_F24) shl 16);
    Pump(100);
    Require(not IsWindowVisible(frmmain.Handle), 'Global hotkey did not hide the dock');
    Windows.PostMessage(frmmain.Handle, WM_HOTKEY, Hotkey.NativeId, LPARAM(VK_F24) shl 16);
    Pump(100);
    Require(IsWindowVisible(frmmain.Handle), 'Global hotkey did not restore the hidden dock');
    frmmain.SetParam(gpGlobalHotkeyFlag_Hide, 0);
    Writeln('PASS registered hotkey delivery while dock is hidden');
    frmmain.OnDragEnter(nil, 0);
    Require(frmmain.ItemMgr.InteractionSnapshot.DraggingFile, 'Drag feedback did not start');
    Effect := DROPEFFECT_COPY or DROPEFFECT_LINK;
    Require(frmmain.DropMgr.DragEnter(nil, 0, Point, Effect) = S_OK, 'Rejected entry failed');
    Require(Effect = DROPEFFECT_NONE, 'Unsupported entry advertised an effect');
    Require(not frmmain.ItemMgr.InteractionSnapshot.DraggingFile,
      'Unsupported entry retained earlier drag feedback');
    Writeln('PASS rejected entry clears existing drag feedback');
    FailingBatch := TFailingDropBatch.Create('');
    try
      FailingBatch.Expose;
      FailingBatch.FailCount := True;
      frmmain.OnDragEnter(nil, 0);
      FailureReturned := False;
      try frmmain.OnDrop(FailingBatch, 0);
      except
        on E: Exception do
          if E.Message = 'Controlled drop consumer failure' then FailureReturned := True
          else raise;
      end;
      Require(FailureReturned, 'The form concealed a drop consumer failure');
      Require(not frmmain.ItemMgr.InteractionSnapshot.DraggingFile,
        'Failed consumption retained drag feedback');
    finally FailingBatch.FailCount := False; FailingBatch.Free; end;
    Writeln('PASS form returns consumer failures after clearing drag feedback');
    Require(frmmain.DropMgr.ImportStorage = UTF8Decode(ExtractFilePath(Fixture)) + 'ImportedFiles',
      'Drop storage did not use the active settings directory');
    CountBefore := frmmain.ItemMgr.ItemCount;
    Batch := TDropImportBatch.Create(frmmain.DropMgr.ImportStorage);
    try
      CopiedPath := Batch.NewFile('smoke-copy.txt', CopyHandle);
      CopyBytes := 'persistent drag copy';
      try Require(WriteFile(CopyHandle, CopyBytes[1], Length(CopyBytes), Written, nil), 'Copy write failed');
      finally CloseHandle(CopyHandle); end;
      Batch.Add(UTF8Encode(CopiedPath)); Batch.Expose;
      frmmain.OnDragEnter(nil, 0);
      frmmain.OnDrop(Batch, 0);
      Require(not frmmain.ItemMgr.InteractionSnapshot.DraggingFile, 'Copied-file drop retained drag state');
      Require(Batch.AcceptedCount = 1, 'Real form did not acknowledge the copied file');
      Require(frmmain.ItemMgr.ItemCount = CountBefore + 1, 'Real form did not add the launcher');
    finally Batch.Free; end;
    Require(GetFileAttributesW(PWideChar(CopiedPath)) <> INVALID_FILE_ATTRIBUTES,
      'Accepted file disappeared after the drop callback');
    Writeln('PASS copied-file import through the real form');
    NativeData := NativeFileData(CopiedPath);
    try
      CountBefore := frmmain.ItemMgr.ItemCount;
      Effect := DROPEFFECT_COPY or DROPEFFECT_LINK;
      Require(frmmain.DropMgr.DragEnter(NativeData, 0, Classes.Point(0, 0), Effect) = S_OK,
        'Native Shell entry failed');
      Require(Effect = DROPEFFECT_COPY, 'Native Shell entry did not negotiate COPY');
      Effect := DROPEFFECT_COPY or DROPEFFECT_LINK;
      Require(frmmain.DropMgr.Drop(NativeData, 0, Classes.Point(0, 0), Effect) = S_OK,
        'Native Shell transfer failed');
      Require(Effect = DROPEFFECT_COPY, 'Native Shell completion did not report COPY');
      Require(frmmain.ItemMgr.ItemCount = CountBefore + 1, 'Native Shell transfer lost its launcher');
      Require(not frmmain.ItemMgr.InteractionSnapshot.DraggingFile,
        'Native Shell completion retained drag feedback');
    finally NativeData := nil; end;
    Writeln('PASS native Shell data object through real form import and feedback');
    Batch := TDropImportBatch.Create('');
    try
      Batch.Add('https://example.invalid/smoke'); Batch.Expose;
      CountBefore := Stack.ItemCount;
      frmmain.OnDragEnter(nil, Stack.Handle);
      frmmain.OnDrop(Batch, Stack.Handle);
      Require(not frmmain.ItemMgr.InteractionSnapshot.DraggingFile, 'Stack drop retained drag state');
      Require(Batch.AcceptedCount = 1, 'Real form did not acknowledge the stack target');
      Require(Stack.ItemCount = CountBefore + 1, 'Real form did not insert the stack target');
    finally Batch.Free; end;
    Writeln('PASS URL import into a stack through the real form');
  finally
    frmmain.CloseProgram;
    Pump(50);
    TShellTrayWndController.Cleanup;
    TNotifier.Cleanup;
  end;
end;

begin
  loggeru.SetLogFileName(ChangeFileExt(ParamStr(0), '.log'));
  try RunSmoke;
  except
    on E: Exception do
    begin Writeln('FAIL ', E.Message); Halt(1); end;
  end;
end.
