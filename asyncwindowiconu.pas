unit asyncwindowiconu;
{$mode delphi}
interface
uses Windows, Classes, SyncObjs;
const
  WINDOW_ICON_READY_MESSAGE = WM_APP + $319;
  WINDOW_ICON_CACHE_LIMIT = 64;
  WINDOW_ICON_SUBSCRIPTION_LIMIT = 256;
  WINDOW_ICON_QUERY_TIMEOUT = 40;
  WINDOW_ICON_FAILURE_TTL = 500;
type
  TWindowIconEntry = record
    Window: HWND;
    ProcessId, ThreadId: DWORD;
    Stamp: THandle;
    Big: Boolean;
    Pending, Busy, Ready: Boolean;
    Revision: WPARAM;
    Icon: HICON;
    CompletedAt, UsedAt: QWord;
  end;
  TWindowIconSubscription = record
    Owner, Window: HWND;
    OwnerStamp, WindowStamp: THandle;
    Generation, LastNotified: WPARAM;
    Big: Boolean;
  end;
  TWindowIconService = class
  private
    FLock: TCriticalSection;
    FWake, FStop: THandle;
    FThread: TThread;
    FPropertyName, FOwnerPropertyName: UnicodeString;
    FEntries: array[0..WINDOW_ICON_CACHE_LIMIT - 1] of TWindowIconEntry;
    FSubscriptions: array[0..WINDOW_ICON_SUBSCRIPTION_LIMIT - 1] of TWindowIconSubscription;
    function Valid(const Entry: TWindowIconEntry): Boolean;
    function LiveOwner(const Subscription: TWindowIconSubscription): Boolean;
    function HasSubscribers(const Entry: TWindowIconEntry): Boolean;
    procedure DropSubscription(Index: Integer);
    procedure Prune(Owner: HWND; Generation: WPARAM; KeepWindow: HWND; KeepBig: Boolean);
    function Subscribe(Index: Integer; Owner: HWND; Generation: WPARAM): Boolean;
    procedure Notify(const Entry: TWindowIconEntry);
    procedure ClearEntry(Index: Integer);
    function Query(const Entry: TWindowIconEntry): HICON;
    procedure Run;
  public
    constructor Create;
    destructor Destroy; override;
    // The UI owns each returned icon and releases it with DestroyIcon.
    function Request(Window, Owner: HWND; Generation: WPARAM; MaxSize: Integer): HICON;
    procedure Unsubscribe(Owner: HWND);
    procedure Invalidate(Window: HWND);
    function AcceptNotification(Window, Owner: HWND; Generation: WPARAM): Boolean;
    procedure Counts(out Pending, Cached, Subscriptions: Integer);
  end;
function WindowIconService: TWindowIconService;
function NextWindowIconGeneration: WPARAM;
procedure ShutdownWindowIconService;
procedure UnsubscribeWindowIcons(Owner: HWND);
{$ifdef WINDOW_ICON_TESTS}
type TWindowIconStamp = function(Window: HWND; Name: PWideChar; Stamp: THandle): BOOL;
var WindowIconStampForTests: TWindowIconStamp = nil;
{$endif}
implementation
uses SysUtils;
type
  TWindowIconThread = class(TThread)
  private
    FService: TWindowIconService;
  protected
    procedure Execute; override;
  public
    constructor Create(Service: TWindowIconService);
  end;
var IconGeneration: LongInt; SharedService: TWindowIconService; ServiceStopped: Boolean;
function NextWindowIconGeneration: WPARAM;
var Value: LongInt;
begin
  repeat Value := InterlockedIncrement(IconGeneration); until Value <> 0;
  Result := WPARAM(LongWord(Value));
end;
function StampWindow(Window: HWND; Name: PWideChar; Stamp: THandle): BOOL;
begin
  {$ifdef WINDOW_ICON_TESTS}
  if Assigned(WindowIconStampForTests) then Exit(WindowIconStampForTests(Window, Name, Stamp));
  {$endif}
  Result := SetPropW(Window, Name, Stamp);
end;
function CopyCurrentClassIcon(Window: HWND; Big: Boolean): HICON;
var Source: HICON; Kind: Integer; PID, TID, CurrentPID: DWORD;
begin
  Result := 0;
  PID := 0;
  TID := GetWindowThreadProcessId(Window, @PID);
  if TID = 0 then Exit;
  Kind := GCL_HICON;
  if not Big then Kind := GCL_HICONSM;
  Source := HICON(Windows.GetClassLongPtr(Window, Kind));
  if Source = 0 then
  begin
    if Big then Kind := GCL_HICONSM else Kind := GCL_HICON;
    Source := HICON(Windows.GetClassLongPtr(Window, Kind));
  end;
  if Source = 0 then Exit;
  Result := CopyIcon(Source);
  CurrentPID := 0;
  if (GetWindowThreadProcessId(Window, @CurrentPID) <> TID) or (PID <> CurrentPID) or
    (HICON(Windows.GetClassLongPtr(Window, Kind)) <> Source) then
  begin
    if Result <> 0 then DestroyIcon(Result);
    Result := 0;
  end;
end;
function WindowIconService: TWindowIconService;
begin
  if not ServiceStopped and (SharedService = nil) then SharedService := TWindowIconService.Create;
  Result := SharedService;
end;
procedure ShutdownWindowIconService;
begin
  ServiceStopped := True;
  FreeAndNil(SharedService);
end;
procedure UnsubscribeWindowIcons(Owner: HWND);
begin
  if (SharedService <> nil) and (Owner <> 0) then SharedService.Unsubscribe(Owner);
end;
constructor TWindowIconThread.Create(Service: TWindowIconService);
begin
  inherited Create(True);
  FService := Service;
  FreeOnTerminate := False;
  Start;
end;
procedure TWindowIconThread.Execute;
begin FService.Run; end;
constructor TWindowIconService.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FPropertyName := UnicodeString('tdock.asyncicon.' + IntToHex(GetCurrentProcessId, 8) + '.' +
    IntToHex(NextWindowIconGeneration, 8));
  FOwnerPropertyName := FPropertyName + '.owner';
  FWake := CreateEvent(nil, False, False, nil);
  FStop := CreateEvent(nil, True, False, nil);
  if (FWake = 0) or (FStop = 0) then RaiseLastOSError;
  FThread := TWindowIconThread.Create(Self);
end;
destructor TWindowIconService.Destroy;
var I: Integer;
begin
  if FStop <> 0 then SetEvent(FStop);
  if FWake <> 0 then SetEvent(FWake);
  if FThread <> nil then
  begin
    FThread.WaitFor;
    FreeAndNil(FThread);
  end;
  for I := 0 to High(FSubscriptions) do
    if LiveOwner(FSubscriptions[I]) then
      RemovePropW(FSubscriptions[I].Owner, PWideChar(FOwnerPropertyName));
  for I := 0 to High(FEntries) do ClearEntry(I);
  if FWake <> 0 then CloseHandle(FWake);
  if FStop <> 0 then CloseHandle(FStop);
  FreeAndNil(FLock);
  inherited;
end;
function TWindowIconService.HasSubscribers(const Entry: TWindowIconEntry): Boolean;
var I: Integer;
begin
  for I := 0 to High(FSubscriptions) do
    if (FSubscriptions[I].Window = Entry.Window) and
      (FSubscriptions[I].WindowStamp = Entry.Stamp) and
      (FSubscriptions[I].Big = Entry.Big) and LiveOwner(FSubscriptions[I]) then Exit(True);
  Result := False;
end;
function TWindowIconService.LiveOwner(const Subscription: TWindowIconSubscription): Boolean;
begin
  Result := (Subscription.Owner <> 0) and (Subscription.OwnerStamp <> 0) and
    (GetPropW(Subscription.Owner, PWideChar(FOwnerPropertyName)) = Subscription.OwnerStamp);
end;
function TWindowIconService.Subscribe(Index: Integer; Owner: HWND; Generation: WPARAM): Boolean;
var I, Slot: Integer; Stamp: THandle;
begin
  Result := False;
  Slot := -1;
  for I := 0 to High(FSubscriptions) do
  begin
    if (FSubscriptions[I].Owner = Owner) and
      (FSubscriptions[I].Generation = Generation) and
      (FSubscriptions[I].Window = FEntries[Index].Window) and
      (FSubscriptions[I].WindowStamp = FEntries[Index].Stamp) and
      (FSubscriptions[I].Big = FEntries[Index].Big) then Exit(True);
    if FSubscriptions[I].Owner = 0 then Slot := I;
  end;
  if Slot < 0 then Exit;
  Stamp := GetPropW(Owner, PWideChar(FOwnerPropertyName));
  if Stamp = 0 then
  begin
    Stamp := NextWindowIconGeneration;
    if not SetPropW(Owner, PWideChar(FOwnerPropertyName), Stamp) then Exit;
  end;
  FSubscriptions[Slot].Owner := Owner;
  FSubscriptions[Slot].OwnerStamp := Stamp;
  FSubscriptions[Slot].Window := FEntries[Index].Window;
  FSubscriptions[Slot].WindowStamp := FEntries[Index].Stamp;
  FSubscriptions[Slot].Big := FEntries[Index].Big;
  FSubscriptions[Slot].Generation := Generation;
  if FEntries[Index].Ready then FSubscriptions[Slot].LastNotified := FEntries[Index].Revision;
  Result := True;
end;
procedure TWindowIconService.DropSubscription(Index: Integer);
var Owner: HWND; Stamp: THandle; I: Integer;
begin
  Owner := FSubscriptions[Index].Owner;
  Stamp := FSubscriptions[Index].OwnerStamp;
  FSubscriptions[Index] := Default(TWindowIconSubscription);
  if Owner = 0 then Exit;
  for I := 0 to High(FSubscriptions) do
    if FSubscriptions[I].Owner = Owner then Exit;
  if GetPropW(Owner, PWideChar(FOwnerPropertyName)) = Stamp then
    RemovePropW(Owner, PWideChar(FOwnerPropertyName));
end;
procedure TWindowIconService.Prune(Owner: HWND; Generation: WPARAM; KeepWindow: HWND; KeepBig: Boolean);
var I: Integer;
begin
  for I := 0 to High(FSubscriptions) do
    if not LiveOwner(FSubscriptions[I]) or
      ((FSubscriptions[I].Owner = Owner) and (FSubscriptions[I].Generation <> Generation)) then
      DropSubscription(I);
  for I := 0 to High(FEntries) do
    if (FEntries[I].Pending or FEntries[I].Busy) and
      not ((FEntries[I].Window = KeepWindow) and (FEntries[I].Big = KeepBig)) and
      not HasSubscribers(FEntries[I]) then
    begin
      FEntries[I].Pending := False;
      FEntries[I].Busy := False;
      FEntries[I].Revision := NextWindowIconGeneration;
    end;
end;
procedure TWindowIconService.Notify(const Entry: TWindowIconEntry);
var I: Integer;
begin
  for I := 0 to High(FSubscriptions) do
    if (FSubscriptions[I].Window = Entry.Window) and
      (FSubscriptions[I].WindowStamp = Entry.Stamp) and
      (FSubscriptions[I].Big = Entry.Big) and LiveOwner(FSubscriptions[I]) and
      (FSubscriptions[I].LastNotified <> Entry.Revision) then
      if PostMessage(FSubscriptions[I].Owner, WINDOW_ICON_READY_MESSAGE,
        FSubscriptions[I].Generation, LPARAM(Entry.Window)) then
        FSubscriptions[I].LastNotified := Entry.Revision;
end;
function TWindowIconService.Valid(const Entry: TWindowIconEntry): Boolean;
var ProcessId, ThreadId: DWORD;
begin
  ProcessId := 0;
  ThreadId := GetWindowThreadProcessId(Entry.Window, @ProcessId);
  Result := (ThreadId <> 0) and (ThreadId = Entry.ThreadId) and
    (ProcessId = Entry.ProcessId) and (Entry.Stamp <> 0) and
    (GetPropW(Entry.Window, PWideChar(FPropertyName)) = Entry.Stamp);
end;
procedure TWindowIconService.ClearEntry(Index: Integer);
var I: Integer; Shared: Boolean;
begin
  if FEntries[Index].Icon <> 0 then DestroyIcon(FEntries[Index].Icon);
  for I := 0 to High(FSubscriptions) do
    if (FSubscriptions[I].Window = FEntries[Index].Window) and
      (FSubscriptions[I].WindowStamp = FEntries[Index].Stamp) and
      (FSubscriptions[I].Big = FEntries[Index].Big) then
      DropSubscription(I);
  Shared := False;
  for I := 0 to High(FEntries) do
    if (I <> Index) and (FEntries[I].Window = FEntries[Index].Window) and
      (FEntries[I].Stamp = FEntries[Index].Stamp) then Shared := True;
  if not Shared and Valid(FEntries[Index]) then
    RemovePropW(FEntries[Index].Window, PWideChar(FPropertyName));
  FEntries[Index] := Default(TWindowIconEntry);
end;
function TWindowIconService.Query(const Entry: TWindowIconEntry): HICON;
const IconKinds: array[0..2] of WPARAM = (ICON_BIG, 2, ICON_SMALL);
var I, First: Integer; Borrowed: DWORD_PTR;
begin
  Result := 0;
  if not Valid(Entry) then Exit;
  First := 0;
  if not Entry.Big then First := 1;
  for I := First to High(IconKinds) do
  begin
    if WaitForSingleObject(FStop, 0) <> WAIT_TIMEOUT then Exit;
    Borrowed := 0;
    if SendMessageTimeout(Entry.Window, WM_GETICON, IconKinds[I], 0,
      SMTO_ABORTIFHUNG or SMTO_BLOCK or $20, WINDOW_ICON_QUERY_TIMEOUT, Borrowed) = 0 then Break;
    if Borrowed <> 0 then
    begin
      if Valid(Entry) then Result := CopyIcon(HICON(Borrowed));
      Exit;
    end;
  end;
  if Valid(Entry) then Result := CopyIcon(HICON(Windows.GetClassLongPtr(Entry.Window, GCL_HICON)));
end;
procedure TWindowIconService.Run;
var I, Selected: Integer; Entry: TWindowIconEntry; Icon: HICON;
begin
  while WaitForSingleObject(FStop, 0) = WAIT_TIMEOUT do
  begin
    Selected := -1;
    FLock.Acquire;
    try
      for I := 0 to High(FEntries) do
        if FEntries[I].Pending then
        begin
          Selected := I;
          FEntries[I].Pending := False;
          FEntries[I].Busy := True;
          Entry := FEntries[I];
          Break;
        end;
    finally FLock.Release; end;
    if Selected < 0 then
    begin
      WaitForSingleObject(FWake, INFINITE);
      Continue;
    end;
    Icon := Query(Entry);
    FLock.Acquire;
    try
      if FEntries[Selected].Revision = Entry.Revision then
      begin
        FEntries[Selected].Busy := False;
        if Valid(Entry) and HasSubscribers(Entry) and
          (WaitForSingleObject(FStop, 0) = WAIT_TIMEOUT) then
        begin
          if FEntries[Selected].Icon <> 0 then DestroyIcon(FEntries[Selected].Icon);
          FEntries[Selected].Icon := Icon;
          Icon := 0;
          FEntries[Selected].Ready := True;
          FEntries[Selected].CompletedAt := GetTickCount64;
          Notify(FEntries[Selected]);
        end;
      end;
    finally
      FLock.Release;
      if Icon <> 0 then DestroyIcon(Icon);
    end;
  end;
end;
function TWindowIconService.Request(Window, Owner: HWND; Generation: WPARAM;
  MaxSize: Integer): HICON;
var I, Index, Oldest: Integer; ThreadId, ProcessId: DWORD; Now, TTL: QWord;
  Stamp: THandle;
begin
  Result := 0;
  ProcessId := 0;
  ThreadId := GetWindowThreadProcessId(Window, @ProcessId);
  if (ThreadId = 0) or not IsWindow(Owner) then Exit;
  FLock.Acquire;
  try
    if WaitForSingleObject(FStop, 0) <> WAIT_TIMEOUT then Exit;
    Prune(Owner, Generation, Window, MaxSize > 16);
    Index := -1;
    Oldest := -1;
    for I := 0 to High(FEntries) do
    begin
      if (FEntries[I].Window = Window) and (FEntries[I].Big = (MaxSize > 16)) and
        Valid(FEntries[I]) then Index := I;
      if not FEntries[I].Busy and not FEntries[I].Pending and
        ((Oldest < 0) or (FEntries[I].UsedAt < FEntries[Oldest].UsedAt)) then Oldest := I;
    end;
    if Index < 0 then
    begin
      if Oldest < 0 then Exit;
      Index := Oldest;
      ClearEntry(Index);
      Stamp := GetPropW(Window, PWideChar(FPropertyName));
      if Stamp = 0 then
      begin
        Stamp := NextWindowIconGeneration;
        // A destroyed window loses this property, even if Windows reuses its handle.
        if not StampWindow(Window, PWideChar(FPropertyName), Stamp) then
        begin
          // UIPI can deny properties while permitting a class icon read.
          // Copy current class pixels without foreign messages or retained identity.
          Result := CopyCurrentClassIcon(Window, MaxSize > 16);
          Exit;
        end;
      end;
      FEntries[Index].Window := Window;
      FEntries[Index].ProcessId := ProcessId;
      FEntries[Index].ThreadId := ThreadId;
      FEntries[Index].Stamp := Stamp;
      FEntries[Index].Big := MaxSize > 16;
      FEntries[Index].Revision := NextWindowIconGeneration;
    end;
    if not Subscribe(Index, Owner, Generation) then Exit;
    Now := GetTickCount64;
    FEntries[Index].UsedAt := Now;
    if FEntries[Index].Icon <> 0 then Result := CopyIcon(FEntries[Index].Icon);
    TTL := 5000;
    if FEntries[Index].Icon = 0 then TTL := WINDOW_ICON_FAILURE_TTL;
    if not FEntries[Index].Busy and not FEntries[Index].Pending and
      (not FEntries[Index].Ready or (Now - FEntries[Index].CompletedAt >= TTL)) then
    begin
      FEntries[Index].Revision := NextWindowIconGeneration;
      FEntries[Index].Pending := True;
      SetEvent(FWake);
    end;
  finally FLock.Release; end;
end;
procedure TWindowIconService.Unsubscribe(Owner: HWND);
var I: Integer; Message: TMsg;
begin
  FLock.Acquire;
  try
    for I := 0 to High(FSubscriptions) do
      if FSubscriptions[I].Owner = Owner then
        DropSubscription(I);
    RemovePropW(Owner, PWideChar(FOwnerPropertyName));
    for I := 0 to High(FEntries) do
      if (FEntries[I].Pending or FEntries[I].Busy) and not HasSubscribers(FEntries[I]) then
      begin
        FEntries[I].Pending := False;
        FEntries[I].Busy := False;
        FEntries[I].Revision := NextWindowIconGeneration;
      end;
    while PeekMessage(Message, Owner, WINDOW_ICON_READY_MESSAGE, WINDOW_ICON_READY_MESSAGE, PM_REMOVE) do;
  finally FLock.Release; end;
end;
procedure TWindowIconService.Invalidate(Window: HWND);
var I: Integer;
begin
  FLock.Acquire;
  try
    for I := 0 to High(FEntries) do
      if FEntries[I].Window = Window then
      begin
        FEntries[I].Revision := NextWindowIconGeneration;
        FEntries[I].Ready := False;
        FEntries[I].Pending := False;
        FEntries[I].Busy := False;
        if FEntries[I].Icon <> 0 then DestroyIcon(FEntries[I].Icon);
        FEntries[I].Icon := 0;
      end;
  finally FLock.Release; end;
end;
function TWindowIconService.AcceptNotification(Window, Owner: HWND; Generation: WPARAM): Boolean;
var I, J: Integer;
begin
  Result := False;
  FLock.Acquire;
  try
    for I := 0 to High(FSubscriptions) do
      if (FSubscriptions[I].Owner = Owner) and
        (FSubscriptions[I].Window = Window) and
        (FSubscriptions[I].Generation = Generation) and LiveOwner(FSubscriptions[I]) then
        for J := 0 to High(FEntries) do
          if (FEntries[J].Window = Window) and
            (FEntries[J].Stamp = FSubscriptions[I].WindowStamp) and
            (FEntries[J].Big = FSubscriptions[I].Big) and
            FEntries[J].Ready and Valid(FEntries[J]) then Exit(True);
  finally FLock.Release; end;
end;
procedure TWindowIconService.Counts(out Pending, Cached, Subscriptions: Integer);
var I: Integer;
begin
  Pending := 0; Cached := 0; Subscriptions := 0;
  FLock.Acquire;
  try
    for I := 0 to High(FEntries) do
    begin
      if FEntries[I].Pending or FEntries[I].Busy then Inc(Pending);
      if FEntries[I].Window <> 0 then Inc(Cached);
    end;
    for I := 0 to High(FSubscriptions) do
      if FSubscriptions[I].Owner <> 0 then Inc(Subscriptions);
  finally FLock.Release; end;
end;
finalization
  ShutdownWindowIconService;
end.
