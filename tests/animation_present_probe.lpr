program animation_present_probe;

{$mode delphi}

uses Interfaces, Windows, Messages, SysUtils, Classes, Math, Controls,
  declu, GDIPAPI, gfx, themeu, customitemu, customdrawitemu, animationclocku,
  framepaceru, displayclocku, iconserviceu, asyncwindowiconu;

const
  FrameCount = 240;
  ProbeItemSize = 96;
  ProbeNoActivate = $08000000;
  ProbeTitle = 'TDock animation verification';

type
  TTimerControlClock = class(TDisplayClock)
  protected
    function OpenDisplay(const Device: string; out Adapter, SourceId: Cardinal): Boolean; override;
  public
    function ReadPhase(out PhaseMs, PeriodMs: Double): Boolean; override;
  end;
  TTimerControlPacer = class(TFramePacer)
  protected
    function CreateDisplayClock: TDisplayClock; override;
  end;
  TPresentationProbe = class(TCustomDrawItem)
  private
    FSequence: Cardinal;
    FStressWindow: HWND;
    FStressGeneration: WPARAM;
    FStressImage: Pointer;
    FStressWidth, FStressHeight: UINT;
    FCurrentGraphics: Pointer;
    procedure DrawMarker(Graphics: Pointer; X, Y, Size: integer);
  protected
    function CreateDrawGraphics(DC: HDC): Pointer; override;
    function PresentDrawSurface(const Bitmap: _SimpleBitmap; Alpha: integer): boolean; override;
  public
    constructor Create;
    destructor Destroy; override;
    procedure WndMessage(var Message: TMessage); override;
    procedure WMCommand(WParam: WPARAM; LParam: LPARAM; var Result: LRESULT); override;
    function ToString: string; override;
    procedure Save(Ini, Section: string); override;
    procedure BindStressWindow(Window: HWND);
    procedure ReloadStressIcon;
    procedure Submit(Sequence: Cardinal; X, Y: integer;
      out SampleQpc, SubmitQpc: Int64);
  end;

var
  StressWindow: HWND;
  StressReady, StressThread: THandle;
  StressThreadId: DWORD;
  StressIconQueries: LongInt;
  FlushControl: Boolean;
  GdiFlushControl: Boolean;

function ProbeDwmFlush: HRESULT; stdcall; external 'dwmapi.dll' name 'DwmFlush';

function TTimerControlClock.OpenDisplay(const Device: string;
  out Adapter, SourceId: Cardinal): Boolean;
begin Adapter := 0; SourceId := 0; Result := False; end;
function TTimerControlClock.ReadPhase(out PhaseMs, PeriodMs: Double): Boolean;
begin Result := False; end;
function TTimerControlPacer.CreateDisplayClock: TDisplayClock;
begin Result := TTimerControlClock.Create; end;

function TPresentationProbe.CreateDrawGraphics(DC: HDC): Pointer;
begin Result := inherited; FCurrentGraphics := Result; end;
function TPresentationProbe.PresentDrawSurface(const Bitmap: _SimpleBitmap;
  Alpha: integer): boolean;
begin
  if GdiFlushControl then
  begin
    if GdipFlush(FCurrentGraphics, FlushIntentionSync) <> Ok then
      raise Exception.Create('Flush frame graphics failed');
    GdiFlush;
  end;
  Result := inherited;
end;

procedure Require(Value: boolean; const Message: string);
begin
  if not Value then raise Exception.Create(Message);
end;

procedure CheckGraphics(Status: GpStatus; const Operation: string);
begin
  if Status <> Ok then
    raise Exception.CreateFmt('%s failed with GDI+ status %d', [Operation, Ord(Status)]);
end;

procedure ActivateHint(Id: THandle; Caption: PWideChar; X, Y: integer); stdcall;
begin end;
procedure DeactivateHint(Id: THandle); stdcall;
begin end;
procedure ExcludeFromPeek(Id: THandle); stdcall;
begin end;
procedure Notify(Id: THandle; Text: PChar); stdcall;
begin end;
function DockGetRect: Windows.TRect; stdcall;
begin Result := Default(Windows.TRect); end;
procedure DockletLockMouseEffect(Id: HWND; Lock: BOOL); stdcall;
begin end;

exports ActivateHint, DeactivateHint, ExcludeFromPeek, Notify, DockGetRect,
  DockletLockMouseEffect;

constructor TPresentationProbe.Create;
var Params: TDItemCreateParams; Graphics, Brush: Pointer;
begin
  Params := Default(TDItemCreateParams);
  Params.ItemSize := ProbeItemSize;
  Params.BigItemSize := ProbeItemSize;
  Params.AnimationType := 1;
  Params.Site := 3;
  inherited Create(0, Params);
  FStressGeneration := NextWindowIconGeneration;
  OnDrawOverlay := DrawMarker;
  FIW := ProbeItemSize;
  FIH := ProbeItemSize;
  Graphics := nil;
  Brush := nil;
  CheckGraphics(GdipCreateBitmapFromScan0(FIW, FIH, 0, PixelFormat32bppARGB,
    nil, FImage), 'Create seed bitmap');
  try
    CheckGraphics(GdipGetImageGraphicsContext(FImage, Graphics), 'Create seed graphics');
    CheckGraphics(GdipGraphicsClear(Graphics, $FF173B70), 'Clear seed bitmap');
    CheckGraphics(GdipCreateSolidFill($FFFFB52E, Brush), 'Create seed brush');
    CheckGraphics(GdipFillRectangleI(Graphics, Brush, 12, 12, 60, 20), 'Paint seed rectangle');
    CheckGraphics(GdipFillEllipseI(Graphics, Brush, 46, 46, 36, 36), 'Paint seed circle');
  finally
    if Brush <> nil then GdipDeleteBrush(Brush);
    if Graphics <> nil then GdipDeleteGraphics(Graphics);
  end;
  Require(SetWindowTextW(Handle, ProbeTitle), 'Cannot set the verification title');
  Windows.SetWindowLongPtr(Handle, GWL_EXSTYLE,
    Windows.GetWindowLongPtr(Handle, GWL_EXSTYLE) or WS_EX_TRANSPARENT or
    WS_EX_TOOLWINDOW or ProbeNoActivate);
end;

destructor TPresentationProbe.Destroy;
begin
  UnsubscribeWindowIcons(Handle);
  if FStressImage <> nil then GdipDisposeImage(FStressImage);
  FStressImage := nil;
  if FImage <> nil then GdipDisposeImage(FImage);
  FImage := nil;
  inherited;
end;

procedure TPresentationProbe.DrawMarker(Graphics: Pointer; X, Y, Size: integer);
var Black, White, Green: Pointer; BitIndex: integer; Brush: Pointer;
begin
  Black := nil;
  White := nil;
  Green := nil;
  try
    CheckGraphics(GdipResetWorldTransform(Graphics), 'Reset marker transform');
    CheckGraphics(GdipSetSmoothingMode(Graphics, SmoothingModeNone), 'Set marker smoothing');
    CheckGraphics(GdipCreateSolidFill($FF000000, Black), 'Create black marker brush');
    CheckGraphics(GdipCreateSolidFill($FFFFFFFF, White), 'Create white marker brush');
    CheckGraphics(GdipCreateSolidFill($FF00FF00, Green), 'Create green guard brush');
    CheckGraphics(GdipFillRectangleI(Graphics, Black, 0, 0, 104, 16), 'Clear marker pixels');
    CheckGraphics(GdipFillRectangleI(Graphics, Green, 0, 0, 4, 4), 'Paint marker guard');
    for BitIndex := 0 to 23 do
    begin
      Brush := Black;
      if FSequence and (Cardinal(1) shl BitIndex) <> 0 then Brush := White;
      CheckGraphics(GdipFillRectangleI(Graphics, Brush, 4 + BitIndex * 4, 4, 4, 8),
        'Paint marker bit');
    end;
  finally
    if Green <> nil then GdipDeleteBrush(Green);
    if White <> nil then GdipDeleteBrush(White);
    if Black <> nil then GdipDeleteBrush(Black);
  end;
end;

procedure TPresentationProbe.WndMessage(var Message: TMessage);
begin
  Message.Result := 0;
  if (Message.Msg = WINDOW_ICON_READY_MESSAGE) and (FStressWindow <> 0) and
    (WindowIconService <> nil) and
    WindowIconService.AcceptNotification(HWND(Message.LParam), Handle, Message.WParam) then
    ReloadStressIcon;
end;

procedure TPresentationProbe.WMCommand(WParam: WPARAM; LParam: LPARAM; var Result: LRESULT);
begin Result := 0; end;
function TPresentationProbe.ToString: string;
begin Result := ''; end;
procedure TPresentationProbe.Save(Ini, Section: string);
begin end;

procedure TPresentationProbe.BindStressWindow(Window: HWND);
begin FStressWindow := Window; end;

procedure TPresentationProbe.ReloadStressIcon;
begin
  if FStressWindow <> 0 then
    LoadImageFromHWndAsync(FStressWindow, Handle, FStressGeneration, ProbeItemSize,
      True, True, FStressImage, FStressWidth, FStressHeight);
end;

procedure TPresentationProbe.Submit(Sequence: Cardinal; X, Y: integer;
  out SampleQpc, SubmitQpc: Int64);
begin
  FSequence := Sequence;
  BeginAnimationFrame;
  try
    QueryPerformanceCounter(SampleQpc);
    BeginMotionFrame;
    try
      if not FIconAnimationActive then Animate;
      Timer;
    finally EndMotionFrame; end;
    TakeFrameDrawForce;
    Draw(X, Y, ProbeItemSize, True, 0, SWP_SHOWWINDOW);
    if FlushControl then ProbeDwmFlush;
    QueryPerformanceCounter(SubmitQpc);
    Require(not FrameRedrawPending, 'The native frame submission failed');
  finally EndAnimationFrame; end;
end;

function SlowIconProc(Window: HWND; Message: UINT; WParam: WPARAM;
  LParam: LPARAM): LRESULT; stdcall;
begin
  if Message = WM_GETICON then
  begin
    InterlockedIncrement(StressIconQueries);
    Sleep(250);
    Exit(LRESULT(LoadIcon(0, IDI_APPLICATION)));
  end;
  Result := DefWindowProcW(Window, Message, WParam, LParam);
end;

function SlowIconThread(Parameter: Pointer): DWORD; stdcall;
var WindowClass: TWndClassW; Message: TMsg;
begin
  FillChar(WindowClass, SizeOf(WindowClass), 0);
  WindowClass.lpfnWndProc := @SlowIconProc;
  WindowClass.hInstance := HInstance;
  WindowClass.lpszClassName := 'TDockPresentationSlowIcon';
  RegisterClassW(WindowClass);
  StressWindow := CreateWindowExW(WS_EX_TOOLWINDOW or ProbeNoActivate,
    WindowClass.lpszClassName, 'TDock hidden icon fixture', WS_POPUP,
    -20000, -20000, 1, 1, 0, 0, HInstance, nil);
  SetEvent(StressReady);
  if StressWindow <> 0 then
  begin
    while GetMessage(Message, 0, 0, 0) do DispatchMessage(Message);
    DestroyWindow(StressWindow);
    StressWindow := 0;
  end;
  Result := 0;
end;

procedure StartStressWindow;
begin
  StressReady := CreateEvent(nil, True, False, nil);
  if StressReady = 0 then RaiseLastOSError;
  StressThread := CreateThread(nil, 0, @SlowIconThread, nil, 0, StressThreadId);
  if StressThread = 0 then RaiseLastOSError;
  Require(WaitForSingleObject(StressReady, 3000) = WAIT_OBJECT_0,
    'The slow icon fixture did not start');
  Require(StressWindow <> 0, 'The slow icon fixture window failed');
end;

procedure StopStressWindow;
begin
  if StressThread <> 0 then
  begin
    PostThreadMessage(StressThreadId, WM_QUIT, 0, 0);
    Require(WaitForSingleObject(StressThread, 3000) = WAIT_OBJECT_0,
      'The slow icon fixture did not stop');
    CloseHandle(StressThread);
    StressThread := 0;
  end;
  if StressReady <> 0 then CloseHandle(StressReady);
  StressReady := 0;
end;

procedure PumpMessages;
var Message: TMsg;
begin
  while PeekMessage(Message, 0, 0, 0, PM_REMOVE) do
  begin
    TranslateMessage(Message);
    DispatchMessage(Message);
  end;
end;

procedure SetNativeDpiContext;
type TSetDpiContext = function(Context: Pointer): Pointer; stdcall;
var SetContext: TSetDpiContext;
begin
  SetContext := TSetDpiContext(GetProcAddress(GetModuleHandle('user32.dll'),
    'SetThreadDpiAwarenessContext'));
  if Assigned(SetContext) then SetContext(Pointer(PtrInt(-4)));
end;

function ClockName(Source: TDisplayClockSource): string;
begin
  case Source of
    dcsVerticalBlank: Result := 'vertical_blank';
    dcsDwmTiming: Result := 'dwm_timing';
    else Result := 'timer';
  end;
end;

procedure RunProbe;
var RequestedHz: Double; ReadyFile, SubmittedFile: string; Stress: boolean;
  Item: TPresentationProbe; Pacer: TFramePacer; FixtureTheme: TDTheme;
  Csv: TStringList; Message: TMsg; Sequence: Cardinal;
  WorkArea, FixedRect, ActualRect: Windows.TRect;
  ItemX, ItemY: integer; Started, Deadline: QWord;
  SampleQpc, SubmitQpc: Int64;
begin
  Require((ParamCount = 3) or (ParamCount = 4),
    'Use requestedHz readyFile submittedCsv [stress]');
  RequestedHz := StrToFloat(ParamStr(1));
  Require((RequestedHz >= 1) and (RequestedHz <= 1000), 'Invalid requested refresh rate');
  ReadyFile := ExpandFileName(ParamStr(2));
  SubmittedFile := ExpandFileName(ParamStr(3));
  Stress := (ParamCount = 4) and SameText(ParamStr(4), 'stress');
  FlushControl := (ParamCount = 4) and SameText(ParamStr(4), 'flush');
  GdiFlushControl := (ParamCount = 4) and SameText(ParamStr(4), 'gdi');
  if ParamCount = 4 then Require(Stress or FlushControl or GdiFlushControl or SameText(ParamStr(4), 'timer'),
    'The optional argument must be stress, flush, gdi, or timer');
  Item := nil;
  Pacer := nil;
  FixtureTheme := nil;
  Csv := TStringList.Create;
  try
    SetNativeDpiContext;
    FixtureTheme := TDTheme(TDTheme.NewInstance);
    theme := FixtureTheme;
    Item := TPresentationProbe.Create;
    Require(SystemParametersInfo(SPI_GETWORKAREA, 0, @WorkArea, 0),
      'Cannot read the desktop work area');
    ItemX := WorkArea.Left + 80 + MIN_BORDER;
    ItemY := WorkArea.Top + 80 + MIN_BORDER;
    Item.Draw(ItemX, ItemY, ProbeItemSize, True, 0, SWP_SHOWWINDOW);
    Require(not Item.FrameRedrawPending, 'The initial native frame failed');
    Require(SetWindowPos(Item.Handle, HWND_TOPMOST, 0, 0, 0, 0,
      SWP_NOMOVE or SWP_NOSIZE or SWP_NOACTIVATE or SWP_SHOWWINDOW),
      'Cannot show the verification window');
    Require(GetWindowRect(Item.Handle, FixedRect), 'Cannot read the verification rectangle');
    Require((FixedRect.Right - FixedRect.Left >= 104) and
      (FixedRect.Bottom - FixedRect.Top >= 16), 'The marker surface is too small');
    if (ParamCount = 4) and SameText(ParamStr(4), 'timer') then
      Pacer := TTimerControlPacer.Create(Item.Handle, DOCK_FRAME_MESSAGE)
    else Pacer := TFramePacer.Create(Item.Handle, DOCK_FRAME_MESSAGE);
    Pacer.SetMonitorForWindow(Item.Handle);
    Pacer.SetRefreshRate(RequestedHz);
    if Stress then
    begin
      StartStressWindow;
      Item.BindStressWindow(StressWindow);
    end;
    Started := GetTickCount64;
    while not FileExists(ReadyFile) do
    begin
      Require(GetTickCount64 - Started < 15000, 'The desktop capture handshake timed out');
      PumpMessages;
      MsgWaitForMultipleObjects(0, nil, False, 10, QS_ALLINPUT);
    end;
    Csv.Add('sequence,sample_qpc,submit_qpc,requested_hz,effective_hz,display_hz,clock_source');
    Sequence := 0;
    Started := GetTickCount64;
    Pacer.SetActive(True);
    while Sequence < FrameCount do
    begin
      Require(GetTickCount64 - Started < 15000, 'The presentation probe timed out');
      if PeekMessage(Message, 0, 0, 0, PM_REMOVE) then
      begin
        if (Message.hwnd = Item.Handle) and (Message.message = DOCK_FRAME_MESSAGE) then
        begin
          if not Pacer.ConsumeMessage(Message.wParam) then Continue;
          Inc(Sequence);
          Item.Submit(Sequence, ItemX, ItemY, SampleQpc, SubmitQpc);
          Require(GetWindowRect(Item.Handle, ActualRect) and
            EqualRect(FixedRect, ActualRect), 'The verification window moved or changed size');
          Csv.Add(Format('%d,%d,%d,%.3f,%.3f,%.3f,%s',
            [Sequence, SampleQpc, SubmitQpc, RequestedHz, Pacer.EffectiveRefreshRate,
              Pacer.DisplayRefreshRate, ClockName(Pacer.ClockSource)]));
          if Stress and (Sequence mod 8 = 0) then Item.ReloadStressIcon;
        end
        else
        begin
          TranslateMessage(Message);
          DispatchMessage(Message);
        end;
      end
      else MsgWaitForMultipleObjects(0, nil, False, 100, QS_ALLINPUT);
    end;
    Pacer.SetActive(False);
    Deadline := GetTickCount64 + 250;
    while GetTickCount64 < Deadline do
    begin
      PumpMessages;
      MsgWaitForMultipleObjects(0, nil, False, 10, QS_ALLINPUT);
    end;
    Csv.SaveToFile(SubmittedFile);
    Writeln('submitted_frames=', Sequence, ',requested_hz=', RequestedHz:0:3,
      ',effective_hz=', Pacer.EffectiveRefreshRate:0:3,
      ',display_hz=', Pacer.DisplayRefreshRate:0:3,
      ',clock_source=', ClockName(Pacer.ClockSource),
      ',stress_icon_queries=', StressIconQueries);
  finally
    Pacer.Free;
    ShutdownWindowIconService;
    StopStressWindow;
    Item.Free;
    theme := nil;
    FixtureTheme.Free;
    Csv.Free;
  end;
end;

begin
  DefaultFormatSettings.DecimalSeparator := '.';
  try
    RunProbe;
  except
    on E: Exception do
    begin
      Writeln(StdErr, E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
