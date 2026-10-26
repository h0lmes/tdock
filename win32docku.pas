unit win32docku;

{$mode delphi}

interface

uses Windows, Messages;

const
  DOCK_OBSERVATION_MESSAGE = WM_APP + $317;
  DOCK_OBSERVATION_TIMER = 15;

type
  TDockWindowObservation = record
    ForegroundChanged, WindowsChanged, TasksChanged: Boolean;
    Window: HWND;
  end;
  TDockCloseAction = procedure of object;
  TDockWindowAdapter = class
  private
    FWindow: HWND;
    FPreviousProc: Pointer;
    FPreviousUserData: PtrInt;
    FInstalled, FMouseRegistered: Boolean;
    FShellMessage: UINT;
    FTaskbarMessage: UINT;
    FShellRegistered: Boolean;
    FObserverHooks: array[0..1] of THandle;
    FObservationPosted: Boolean;
    FPendingObservation: TDockWindowObservation;
  public
    constructor Create(Window: HWND);
    destructor Destroy; override;
    procedure Install(Instance: TObject; WindowProc: Pointer);
    function RegisterMouse: Boolean;
    procedure Stop;
    function CallPrevious(const Message: TMessage): LRESULT;
    function TakeObservation: TDockWindowObservation;
    property ShellMessage: UINT read FShellMessage;
    property TaskbarMessage: UINT read FTaskbarMessage;
  end;

function IsDockCloseCommand(Parameter: WPARAM): Boolean;
function DispatchDockCloseCommand(Parameter: WPARAM; CloseAction: TDockCloseAction): Boolean;
function IsForegroundShellEvent(Event: WPARAM): Boolean;
function WindowEventChangesTasks(Event: DWORD): Boolean;

implementation

uses jwaWindows, declu;

var Observers: array of TDockWindowAdapter;

function IsForegroundShellEvent(Event: WPARAM): Boolean;
begin Result := (Event = HSHELL_WINDOWACTIVATED) or (Event = $8004); end;

function WindowEventChangesTasks(Event: DWORD): Boolean;
begin
  Result := (Event = EVENT_OBJECT_CREATE) or (Event = EVENT_OBJECT_DESTROY) or
    (Event = EVENT_OBJECT_SHOW) or (Event = EVENT_OBJECT_HIDE) or
    (Event = EVENT_OBJECT_NAMECHANGE) or (Event = EVENT_OBJECT_LOCATIONCHANGE) or
    (Event = $8017) or (Event = $8018);
end;

procedure DockWinEvent(Hook: HWINEVENTHOOK; Event: DWORD; Window: HWND;
  ObjectId, ChildId: LONG; EventThread, EventTime: DWORD); stdcall;
var Index: Integer; Observer: TDockWindowAdapter;
begin
  if (Window = 0) or (ChildId <> 0) then Exit;
  if (Event <> EVENT_SYSTEM_FOREGROUND) and (ObjectId <> 0) then Exit;
  if not ((Event = EVENT_SYSTEM_FOREGROUND) or (Event = EVENT_OBJECT_CREATE) or
    (Event = EVENT_OBJECT_DESTROY) or (Event = EVENT_OBJECT_SHOW) or
    (Event = EVENT_OBJECT_HIDE) or (Event = EVENT_OBJECT_LOCATIONCHANGE) or
    (Event = EVENT_OBJECT_REORDER) or (Event = EVENT_OBJECT_NAMECHANGE) or
    (Event = $8017) or (Event = $8018)) then Exit;
  for Index := 0 to High(Observers) do
  begin
    Observer := Observers[Index];
    if (Observer.FObserverHooks[0] <> Hook) and (Observer.FObserverHooks[1] <> Hook) then Continue;
    Observer.FPendingObservation.Window := Window;
    Observer.FPendingObservation.WindowsChanged := True;
    if Event = EVENT_SYSTEM_FOREGROUND then Observer.FPendingObservation.ForegroundChanged := True;
    if WindowEventChangesTasks(Event) then
      Observer.FPendingObservation.TasksChanged := True;
    if not Observer.FObservationPosted then
    begin
      Observer.FObservationPosted := True;
      if not Windows.PostMessage(Observer.FWindow, DOCK_OBSERVATION_MESSAGE, 0, 0) then
        Observer.FObservationPosted := False;
    end;
    Exit;
  end;
end;

function IsDockCloseCommand(Parameter: WPARAM): Boolean;
begin Result := (Parameter and $FFFF) = IDM_QUIT; end;
function DispatchDockCloseCommand(Parameter: WPARAM; CloseAction: TDockCloseAction): Boolean;
begin
  Result := IsDockCloseCommand(Parameter);
  if Result and Assigned(CloseAction) then CloseAction;
end;

constructor TDockWindowAdapter.Create(Window: HWND);
begin inherited Create; FWindow := Window; end;

destructor TDockWindowAdapter.Destroy;
begin Stop; inherited Destroy; end;

procedure TDockWindowAdapter.Install(Instance: TObject; WindowProc: Pointer);
begin
  if FInstalled then Exit;
  // JEDI Ptr helpers use 32-bit APIs in this compiler.
  // Use the native Windows functions for every pointer value.
  FPreviousUserData := Windows.GetWindowLongPtr(FWindow, GWL_USERDATA);
  FPreviousProc := Pointer(Windows.GetWindowLongPtr(FWindow, GWL_WNDPROC));
  Windows.SetWindowLongPtr(FWindow, GWL_USERDATA, PtrUInt(Instance));
  Windows.SetWindowLongPtr(FWindow, GWL_WNDPROC, PtrInt(WindowProc));
  FShellMessage := RegisterWindowMessage('SHELLHOOK');
  FTaskbarMessage := RegisterWindowMessage('TaskbarCreated');
  FShellRegistered := RegisterShellHookWindow(FWindow);
  SetLength(Observers, Length(Observers) + 1);
  Observers[High(Observers)] := Self;
  FObserverHooks[0] := SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND,
    0, DockWinEvent, 0, 0, WINEVENT_OUTOFCONTEXT or WINEVENT_SKIPOWNPROCESS);
  FObserverHooks[1] := SetWinEventHook(EVENT_OBJECT_CREATE, $8018,
    0, DockWinEvent, 0, 0, WINEVENT_OUTOFCONTEXT or WINEVENT_SKIPOWNPROCESS);
  FInstalled := True;
end;

function TDockWindowAdapter.RegisterMouse: Boolean;
var Device: RAWINPUTDEVICE;
begin
  Device := Default(RAWINPUTDEVICE);
  Device.usUsagePage := 1;
  Device.usUsage := 2;
  Device.dwFlags := RIDEV_INPUTSINK;
  Device.hwndTarget := FWindow;
  Result := RegisterRawInputDevices(@Device, 1, SizeOf(Device));
  FMouseRegistered := Result;
end;

procedure TDockWindowAdapter.Stop;
var Device: RAWINPUTDEVICE; Timer, Index, Next: Integer;
begin
  if not FInstalled and not FMouseRegistered then Exit;
  for Timer := ID_TIMER to DOCK_OBSERVATION_TIMER do KillTimer(FWindow, Timer);
  if FMouseRegistered then
  begin
    Device := Default(RAWINPUTDEVICE);
    Device.usUsagePage := 1;
    Device.usUsage := 2;
    Device.dwFlags := RIDEV_REMOVE;
    RegisterRawInputDevices(@Device, 1, SizeOf(Device));
    FMouseRegistered := False;
  end;
  if FInstalled then
  begin
    for Index := High(Observers) downto 0 do
      if Observers[Index] = Self then
      begin
        for Next := Index to High(Observers) - 1 do Observers[Next] := Observers[Next + 1];
        SetLength(Observers, Length(Observers) - 1);
      end;
    for Index := 0 to High(FObserverHooks) do
      if FObserverHooks[Index] <> 0 then
      begin
        UnhookWinEvent(FObserverHooks[Index]);
        FObserverHooks[Index] := 0;
      end;
    FObservationPosted := False;
    FPendingObservation := Default(TDockWindowObservation);
    if FShellRegistered then DeregisterShellHookWindow(FWindow);
    FShellRegistered := False;
    Windows.SetWindowLongPtr(FWindow, GWL_WNDPROC, PtrInt(FPreviousProc));
    Windows.SetWindowLongPtr(FWindow, GWL_USERDATA, FPreviousUserData);
    FInstalled := False;
  end;
end;

function TDockWindowAdapter.TakeObservation: TDockWindowObservation;
begin
  Result := FPendingObservation;
  FPendingObservation := Default(TDockWindowObservation);
  FObservationPosted := False;
end;

function TDockWindowAdapter.CallPrevious(const Message: TMessage): LRESULT;
begin
  if FPreviousProc <> nil then
    Result := Windows.CallWindowProc(FPreviousProc, FWindow, Message.Msg, Message.WParam, Message.LParam)
  else Result := Windows.DefWindowProc(FWindow, Message.Msg, Message.WParam, Message.LParam);
end;

end.
