unit asyncwindowicontests;
{$mode delphi}
interface
uses Windows, Classes, SysUtils, fpcunit, testregistry, GDIPAPI, iconserviceu,
  asyncwindowiconu, taskitemu, aeropeeku, declu, gfx;
type
  TTaskIconProbe = class(TTaskItem)
  public
    procedure Bind(Window: HWND);
    function ImagePixel: Cardinal;
  end;
  TPeekIconProbe = class(TAeroPeekWindow)
  protected
    procedure Paint; override;
  public
    Paints: Integer;
    procedure BindWithFallback(Window: HWND);
    procedure Refresh;
    function ImagePixel: Cardinal;
  end;
  TAsyncWindowIconTests = class(TTestCase)
  published
    procedure StrictTimeoutBoundsResponsiveSlowWindow;
    procedure RequestReturnsBeforeForeignWindowResponds;
    procedure ReadyMessageArrivesWhileUITimersContinue;
    procedure PostedCompletionDoesNotHideDueNativeTimer;
    procedure DuplicateRequestsShareOneWindowQuery;
    procedure FailedQueriesStayCachedUntilInvalidated;
    procedure QueueAndCacheRemainBounded;
    procedure UnsubscribeCancelsPendingWork;
    procedure DestroyedOwnerAndObsoleteGenerationRejectResults;
    procedure DestroyedTargetRejectsResults;
    procedure ShutdownCancelsSlowQueries;
    procedure FailedQueriesRetryAfterTTL;
    procedure UILoaderReturnsFallbackBeforeSlowWindow;
    procedure UILoaderReplacesExistingFallbackWithOwnedPixels;
    procedure TaskItemReturnsBeforeSlowWindow;
    procedure TaskItemReceivesReadyImage;
    procedure PreviewReplacesExistingFallback;
    procedure RebindingOwnerReleasesObsoleteQueuedWindows;
    procedure SubscriptionCountRemainsBounded;
    procedure TaskNativeReplacementKeepsCurrentSubscription;
    procedure IconCopiesReleaseNativeHandles;
    procedure ChangedWindowIdentityRejectsSameHandleResults;
    procedure StampFailureKeepsReadableClassIcon;
  end;
implementation
var FixtureWindow: HWND; FixtureReady: THandle; FixtureDelay: DWORD;
  FixtureIcon: HICON; FixtureCalls: LongInt;
function FixtureProc(Wnd: HWND; Msg: UINT; W: WPARAM; L: LPARAM): LRESULT; stdcall;
begin
  if Msg = WM_GETICON then
  begin
    InterlockedIncrement(FixtureCalls);
    Sleep(FixtureDelay);
    Exit(LRESULT(FixtureIcon));
  end;
  Result := DefWindowProc(Wnd, Msg, W, L);
end;
function FixtureThread(Arg: Pointer): DWORD; stdcall;
var WC: TWndClassW; Msg: TMsg;
begin
  FillChar(WC, SizeOf(WC), 0);
  WC.lpfnWndProc := @FixtureProc;
  WC.hInstance := HInstance;
  WC.lpszClassName := 'tdock.async.icon.fixture';
  RegisterClassW(WC);
  FixtureWindow := CreateWindowExW(0, WC.lpszClassName, 'fixture', 0,
    0, 0, 1, 1, 0, 0, HInstance, nil);
  SetEvent(FixtureReady);
  while GetMessage(Msg, 0, 0, 0) do DispatchMessage(Msg);
  DestroyWindow(FixtureWindow);
  Result := 0;
end;
procedure StartFixture(Delay: DWORD; out Thread: THandle; out ThreadId: DWORD);
begin
  FixtureDelay := Delay;
  FixtureCalls := 0;
  FixtureIcon := CopyIcon(LoadIcon(0, IDI_APPLICATION));
  FixtureReady := CreateEvent(nil, True, False, nil);
  Thread := CreateThread(nil, 0, @FixtureThread, nil, 0, ThreadId);
  if WaitForSingleObject(FixtureReady, 2000) <> WAIT_OBJECT_0 then
    raise Exception.Create('The fixture thread did not start');
end;
procedure StopFixture(Thread: THandle; ThreadId: DWORD);
begin
  PostThreadMessage(ThreadId, WM_QUIT, 0, 0);
  WaitForSingleObject(Thread, 3000);
  CloseHandle(Thread);
  CloseHandle(FixtureReady);
  DestroyIcon(FixtureIcon);
end;
procedure TAsyncWindowIconTests.StrictTimeoutBoundsResponsiveSlowWindow;
var Thread: THandle; ThreadId: DWORD; Started, Elapsed: QWord;
  Image: Pointer; W, H: UINT;
begin
  StartFixture(180, Thread, ThreadId);
  Image := nil;
  try
    Started := GetTickCount64;
    LoadImageFromHWnd(FixtureWindow, 64, True, False, Image, W, H, 20);
    Elapsed := GetTickCount64 - Started;
    AssertTrue('A responsive slow window must respect the query timeout', Elapsed < 130);
  finally
    if Image <> nil then GdipDisposeImage(Image);
    StopFixture(Thread, ThreadId);
  end;
end;
procedure TAsyncWindowIconTests.RequestReturnsBeforeForeignWindowResponds;
var Thread: THandle; ThreadId: DWORD; Started, Elapsed: QWord;
  Service: TWindowIconService; Icon: HICON; Owner: HWND;
begin
  StartFixture(180, Thread, ThreadId);
  Service := TWindowIconService.Create;
  Owner := CreateWindowExW(0, 'STATIC', 'icon owner', 0, 0, 0, 1, 1, 0, 0, HInstance, nil);
  try
    Started := GetTickCount64;
    Icon := Service.Request(FixtureWindow, Owner, 1, 64);
    Elapsed := GetTickCount64 - Started;
    if Icon <> 0 then DestroyIcon(Icon);
    AssertTrue('UI requests must return before the slow window responds', Elapsed < 60);
  finally
    Service.Free;
    DestroyWindow(Owner);
    StopFixture(Thread, ThreadId);
  end;
end;
function WaitReady(Owner: HWND; Timeout: DWORD; out Message: TMsg;
  out TimerMessages: Integer): Boolean;
var Started: QWord; Current: TMsg;
begin
  TimerMessages := 0;
  Started := GetTickCount64;
  repeat
    while PeekMessage(Current, 0, 0, 0, PM_REMOVE) do
    begin
      if (Current.hwnd = Owner) and (Current.message = WINDOW_ICON_READY_MESSAGE) then
      begin
        Message := Current;
        // Posted completion can precede a native timer that is already due.
        while PeekMessage(Current, Owner, WM_TIMER, WM_TIMER, PM_REMOVE) do
        begin
          Inc(TimerMessages);
          TranslateMessage(Current);
          DispatchMessage(Current);
        end;
        Exit(True);
      end;
      if (Current.hwnd = Owner) and (Current.message = WM_TIMER) then Inc(TimerMessages);
      TranslateMessage(Current);
      DispatchMessage(Current);
    end;
    Sleep(1);
  until GetTickCount64 - Started >= Timeout;
  Result := False;
end;
procedure TAsyncWindowIconTests.PostedCompletionDoesNotHideDueNativeTimer;
var Owner: HWND; Message: TMsg; Timers: Integer;
begin
  Owner := CreateWindowExW(0, 'STATIC', 'owner', 0, 0, 0, 1, 1, 0, 0, HInstance, nil);
  AssertTrue('Create the timer observation owner', Owner <> 0);
  try
    AssertTrue('Start a real native timer', SetTimer(Owner, 1, 1, nil) <> 0);
    Sleep(30);
    AssertTrue('Post the higher-priority completion message',
      PostMessage(Owner, WINDOW_ICON_READY_MESSAGE, 71, 0));
    AssertTrue('The observer must retain the completion message', WaitReady(Owner, 100, Message, Timers));
    AssertEquals('The completion payload must remain unchanged', QWord(71), QWord(Message.wParam));
    AssertTrue('Posted completion must not hide a due native timer', Timers > 0);
  finally
    KillTimer(Owner, 1);
    DestroyWindow(Owner);
  end;
end;
procedure TAsyncWindowIconTests.ReadyMessageArrivesWhileUITimersContinue;
var Thread: THandle; ThreadId: DWORD; Service: TWindowIconService;
  Owner: HWND; Icon: HICON; Message: TMsg; Timers: Integer; Info: ICONINFO;
begin
  StartFixture(20, Thread, ThreadId);
  Service := TWindowIconService.Create;
  Owner := CreateWindowExW(0, 'STATIC', 'owner', 0, 0, 0, 1, 1, 0, 0, HInstance, nil);
  SetTimer(Owner, 1, 1, nil);
  try
    Icon := Service.Request(FixtureWindow, Owner, 55, 64);
    if Icon <> 0 then DestroyIcon(Icon);
    AssertTrue('The worker must notify its live owner', WaitReady(Owner, 1000, Message, Timers));
    AssertTrue('The UI timer must progress during the icon query', Timers > 0);
    AssertEquals('The message must retain the owner generation', QWord(55), QWord(Message.wParam));
    AssertTrue('The live result must validate', Service.AcceptNotification(FixtureWindow, Owner, 55));
    Icon := Service.Request(FixtureWindow, Owner, 55, 64);
    AssertTrue('The result must contain an owned icon', Icon <> 0);
    DestroyIcon(Icon);
    AssertTrue('The borrowed source must survive the returned copy', GetIconInfo(FixtureIcon, Info));
    DeleteObject(Info.hbmColor);
    DeleteObject(Info.hbmMask);
  finally
    Service.Free;
    KillTimer(Owner, 1);
    DestroyWindow(Owner);
    StopFixture(Thread, ThreadId);
  end;
end;
procedure TAsyncWindowIconTests.DuplicateRequestsShareOneWindowQuery;
var Thread: THandle; ThreadId: DWORD; Service: TWindowIconService;
  Owner: HWND; Icon: HICON; Message: TMsg; Timers, I: Integer;
begin
  StartFixture(15, Thread, ThreadId);
  Service := TWindowIconService.Create;
  Owner := CreateWindowExW(0, 'STATIC', 'owner', 0, 0, 0, 1, 1, 0, 0, HInstance, nil);
  try
    for I := 1 to 100 do
    begin
      Icon := Service.Request(FixtureWindow, Owner, 12, 64);
      if Icon <> 0 then DestroyIcon(Icon);
    end;
    AssertTrue('The coalesced query must complete', WaitReady(Owner, 1000, Message, Timers));
    AssertEquals('Duplicate requests must share one foreign message', 1, FixtureCalls);
    AssertFalse('Duplicate requests must not post duplicate results',
      WaitReady(Owner, 50, Message, Timers));
  finally
    Service.Free;
    DestroyWindow(Owner);
    StopFixture(Thread, ThreadId);
  end;
end;
procedure TAsyncWindowIconTests.FailedQueriesStayCachedUntilInvalidated;
var Thread: THandle; ThreadId: DWORD; Service: TWindowIconService;
  Owner: HWND; Icon: HICON; Message: TMsg; Timers, Calls: Integer;
begin
  StartFixture(0, Thread, ThreadId);
  DestroyIcon(FixtureIcon);
  FixtureIcon := 0;
  Service := TWindowIconService.Create;
  Owner := CreateWindowExW(0, 'STATIC', 'owner', 0, 0, 0, 1, 1, 0, 0, HInstance, nil);
  try
    Service.Request(FixtureWindow, Owner, 12, 64);
    AssertTrue('Failures must complete', WaitReady(Owner, 1000, Message, Timers));
    Calls := FixtureCalls;
    Icon := Service.Request(FixtureWindow, Owner, 12, 64);
    if Icon <> 0 then DestroyIcon(Icon);
    AssertFalse('Cached failures must suppress immediate retries', WaitReady(Owner, 50, Message, Timers));
    AssertEquals('Cached failures must suppress foreign messages', Calls, FixtureCalls);
    Service.Invalidate(FixtureWindow);
    Service.Request(FixtureWindow, Owner, 12, 64);
    AssertTrue('Invalidation must allow a new request', WaitReady(Owner, 1000, Message, Timers));
    AssertTrue('Invalidation must repeat the foreign query', FixtureCalls > Calls);
  finally
    Service.Free;
    DestroyWindow(Owner);
    StopFixture(Thread, ThreadId);
  end;
end;
procedure TAsyncWindowIconTests.QueueAndCacheRemainBounded;
var Service: TWindowIconService; Owner: HWND; Windows: array[0..95] of HWND;
  I, Pending, Cached, Subscriptions: Integer;
begin
  Service := TWindowIconService.Create;
  Owner := CreateWindowExW(0, 'STATIC', 'owner', 0, 0, 0, 1, 1, 0, 0, HInstance, nil);
  FillChar(Windows, SizeOf(Windows), 0);
  try
    for I := 0 to High(Windows) do
    begin
      Windows[I] := CreateWindowExW(0, 'STATIC', 'target', 0, 0, 0, 1, 1, 0, 0, HInstance, nil);
      Service.Request(Windows[I], Owner, 3, 64);
    end;
    Service.Counts(Pending, Cached, Subscriptions);
    AssertTrue('The pending queue must remain bounded', Pending <= WINDOW_ICON_CACHE_LIMIT);
    AssertTrue('The icon cache must remain bounded', Cached <= WINDOW_ICON_CACHE_LIMIT);
    AssertTrue('Subscriptions must remain bounded', Subscriptions <= WINDOW_ICON_SUBSCRIPTION_LIMIT);
  finally
    Service.Free;
    for I := 0 to High(Windows) do if Windows[I] <> 0 then DestroyWindow(Windows[I]);
    DestroyWindow(Owner);
  end;
end;
procedure TAsyncWindowIconTests.UnsubscribeCancelsPendingWork;
var Service: TWindowIconService; Owner: HWND; Target: HWND;
  Pending, Cached, Subscriptions, Timers: Integer; Message: TMsg;
begin
  Service := TWindowIconService.Create;
  Owner := CreateWindowExW(0, 'STATIC', 'owner', 0, 0, 0, 1, 1, 0, 0, HInstance, nil);
  Target := CreateWindowExW(0, 'STATIC', 'target', 0, 0, 0, 1, 1, 0, 0, HInstance, nil);
  try
    Service.Request(Target, Owner, 1, 64);
    Service.Unsubscribe(Owner);
    Service.Counts(Pending, Cached, Subscriptions);
    AssertEquals('Unsubscribe must cancel unnecessary queued queries', 0, Pending);
    AssertEquals('Unsubscribe must release owner subscriptions', 0, Subscriptions);
    AssertFalse('An unsubscribed owner must receive no result', WaitReady(Owner, 60, Message, Timers));
  finally
    Service.Free;
    DestroyWindow(Target);
    DestroyWindow(Owner);
  end;
end;
procedure TAsyncWindowIconTests.DestroyedOwnerAndObsoleteGenerationRejectResults;
var Thread: THandle; ThreadId: DWORD; Service: TWindowIconService;
  Owner: HWND; Message: TMsg; Timers: Integer;
begin
  StartFixture(15, Thread, ThreadId);
  Service := TWindowIconService.Create;
  Owner := CreateWindowExW(0, 'STATIC', 'owner', 0, 0, 0, 1, 1, 0, 0, HInstance, nil);
  try
    Service.Request(FixtureWindow, Owner, 1, 64);
    Service.Request(FixtureWindow, Owner, 2, 64);
    AssertTrue('The current subscription must complete', WaitReady(Owner, 1000, Message, Timers));
    AssertFalse('Old generations must be rejected', Service.AcceptNotification(FixtureWindow, Owner, 1));
    AssertTrue('Current generations must validate', Service.AcceptNotification(FixtureWindow, Owner, 2));
    DestroyWindow(Owner);
    AssertFalse('Destroyed owners must be rejected', Service.AcceptNotification(FixtureWindow, Owner, 2));
    Owner := 0;
  finally
    Service.Free;
    if Owner <> 0 then DestroyWindow(Owner);
    StopFixture(Thread, ThreadId);
  end;
end;
procedure TAsyncWindowIconTests.DestroyedTargetRejectsResults;
var Service: TWindowIconService; Owner, Target: HWND; Message: TMsg; Timers: Integer;
begin
  Service := TWindowIconService.Create;
  Owner := CreateWindowExW(0, 'STATIC', 'owner', 0, 0, 0, 1, 1, 0, 0, HInstance, nil);
  Target := CreateWindowExW(0, 'STATIC', 'target', 0, 0, 0, 1, 1, 0, 0, HInstance, nil);
  try
    Service.Request(Target, Owner, 1, 64);
    AssertTrue('The target must complete', WaitReady(Owner, 1000, Message, Timers));
    DestroyWindow(Target);
    AssertFalse('Destroyed targets must invalidate cached results', Service.AcceptNotification(Target, Owner, 1));
    Target := 0;
  finally
    Service.Free;
    if Target <> 0 then DestroyWindow(Target);
    DestroyWindow(Owner);
  end;
end;
procedure TAsyncWindowIconTests.ShutdownCancelsSlowQueries;
var Thread: THandle; ThreadId: DWORD; Service: TWindowIconService;
  Owner: HWND; Started: QWord;
begin
  StartFixture(800, Thread, ThreadId);
  Service := TWindowIconService.Create;
  Owner := CreateWindowExW(0, 'STATIC', 'owner', 0, 0, 0, 1, 1, 0, 0, HInstance, nil);
  try
    Service.Request(FixtureWindow, Owner, 1, 64);
    Started := GetTickCount64;
    while (FixtureCalls = 0) and (GetTickCount64 - Started < 500) do Sleep(1);
    AssertTrue('The slow foreign query must start', FixtureCalls > 0);
    Started := GetTickCount64;
    FreeAndNil(Service);
    AssertTrue('Shutdown must not wait for the foreign window', GetTickCount64 - Started < 150);
  finally
    Service.Free;
    DestroyWindow(Owner);
    StopFixture(Thread, ThreadId);
  end;
end;
procedure TAsyncWindowIconTests.FailedQueriesRetryAfterTTL;
var Thread: THandle; ThreadId: DWORD; Service: TWindowIconService;
  Owner: HWND; Message: TMsg; Timers, Calls: Integer;
begin
  StartFixture(0, Thread, ThreadId);
  DestroyIcon(FixtureIcon); FixtureIcon := 0;
  Service := TWindowIconService.Create;
  Owner := CreateWindowExW(0, 'STATIC', 'owner', 0, 0, 0, 1, 1, 0, 0, HInstance, nil);
  try
    Service.Request(FixtureWindow, Owner, 12, 64);
    AssertTrue('The initial failure must complete', WaitReady(Owner, 1000, Message, Timers));
    Calls := FixtureCalls;
    Sleep(WINDOW_ICON_FAILURE_TTL + 10);
    Service.Request(FixtureWindow, Owner, 12, 64);
    AssertTrue('Expired failures must retry', WaitReady(Owner, 1000, Message, Timers));
    AssertTrue('Expired failures must repeat the query', FixtureCalls > Calls);
  finally
    Service.Free;
    DestroyWindow(Owner);
    StopFixture(Thread, ThreadId);
  end;
end;
procedure TAsyncWindowIconTests.UILoaderReturnsFallbackBeforeSlowWindow;
var Thread: THandle; ThreadId: DWORD; Owner: HWND;
  Image: Pointer; W, H: UINT; Started: QWord;
begin
  StartFixture(180, Thread, ThreadId);
  Owner := CreateWindowExW(0, 'STATIC', 'owner', 0, 0, 0, 1, 1, 0, 0, HInstance, nil);
  Image := nil;
  try
    Started := GetTickCount64;
    LoadImageFromHWndAsync(FixtureWindow, Owner, 44, 32, True, True, Image, W, H);
    AssertTrue('The UI loader must not wait for a foreign icon', GetTickCount64 - Started < 60);
    AssertTrue('The first UI load must provide a fallback', Image <> nil);
    AssertEquals('The fallback must fit the requested size', 32, W);
  finally
    WindowIconService.Unsubscribe(Owner);
    if Image <> nil then GdipDisposeImage(Image);
    DestroyWindow(Owner);
    StopFixture(Thread, ThreadId);
  end;
end;
procedure TAsyncWindowIconTests.UILoaderReplacesExistingFallbackWithOwnedPixels;
var Thread: THandle; ThreadId: DWORD; Owner: HWND; Message: TMsg;
  Image: Pointer; W, H: UINT; I, Timers: Integer; Pixel: ARGB;
  Pixels: array[0..1023] of Cardinal; Mask: array[0..127] of Byte;
begin
  StartFixture(15, Thread, ThreadId);
  DestroyIcon(FixtureIcon);
  for I := 0 to High(Pixels) do Pixels[I] := $FF00FF00;
  FillChar(Mask, SizeOf(Mask), 0);
  FixtureIcon := CreateIcon(HInstance, 32, 32, 1, 32, @Mask[0], @Pixels[0]);
  Owner := CreateWindowExW(0, 'STATIC', 'owner', 0, 0, 0, 1, 1, 0, 0, HInstance, nil);
  Image := nil;
  try
    LoadImageFromHWndAsync(FixtureWindow, Owner, 45, 32, True, True, Image, W, H);
    AssertTrue('The first UI image must exist', Image <> nil);
    AssertTrue('The UI loader must subscribe for later updates', WaitReady(Owner, 1000, Message, Timers));
    AssertTrue('The owner must accept the current binding',
      WindowIconService.AcceptNotification(FixtureWindow, Owner, 45));
    LoadImageFromHWndAsync(FixtureWindow, Owner, 45, 32, True, True, Image, W, H);
    GdipBitmapGetPixel(Image, 16, 16, Pixel);
    AssertEquals('The cached window pixels must replace the existing fallback', Cardinal($FF00FF00), Pixel);
    StopFixture(Thread, ThreadId); Thread := 0;
    GdipBitmapGetPixel(Image, 16, 16, Pixel);
    AssertEquals('The UI bitmap must own independent pixels', Cardinal($FF00FF00), Pixel);
  finally
    WindowIconService.Unsubscribe(Owner);
    if Image <> nil then GdipDisposeImage(Image);
    DestroyWindow(Owner);
    if Thread <> 0 then StopFixture(Thread, ThreadId);
  end;
end;
procedure TTaskIconProbe.Bind(Window: HWND);
begin
  FExecutable := 'TDOCK_ASYNC_MISSING_ICON.exe';
  FAppList.Clear;
  FAppList.Add(Pointer(Window));
  UpdateImage;
end;
function TTaskIconProbe.ImagePixel: Cardinal;
begin
  Result := 0;
  if FImage <> nil then GdipBitmapGetPixel(FImage, FIW div 2, FIH div 2, Result);
end;
procedure TPeekIconProbe.Paint;
begin Inc(Paints); end;
procedure TPeekIconProbe.BindWithFallback(Window: HWND);
begin
  FActive := True;
  FActivating := True;
  FCompositionEnabled := True;
  FWorkArea := Default(Windows.TRect);
  FWorkArea.Right := 1920;
  FWorkArea.Bottom := 1080;
  FTaskThumbSize := 100;
  FIconSize := 16;
  FItemCount := 1;
  SetLength(items, 1);
  items[0].hwnd := Window;
  LoadImageFromHWndAsync(0, 0, 0, 16, True, True,
    items[0].image, items[0].iw, items[0].ih);
end;
procedure TPeekIconProbe.Refresh;
begin UpdateTitles; end;
function TPeekIconProbe.ImagePixel: Cardinal;
begin
  Result := 0;
  if items[0].image <> nil then
    GdipBitmapGetPixel(items[0].image, items[0].iw div 2, items[0].ih div 2, Result);
end;
procedure GreenFixtureIcon;
var I: Integer; Pixels: array[0..1023] of Cardinal; Mask: array[0..127] of Byte;
begin
  DestroyIcon(FixtureIcon);
  for I := 0 to High(Pixels) do Pixels[I] := $FF00FF00;
  FillChar(Mask, SizeOf(Mask), 0);
  FixtureIcon := CreateIcon(HInstance, 32, 32, 1, 32, @Mask[0], @Pixels[0]);
end;
procedure TAsyncWindowIconTests.TaskItemReturnsBeforeSlowWindow;
var Thread: THandle; ThreadId: DWORD; Task: TTaskIconProbe;
  Params: TDItemCreateParams; Started: QWord;
begin
  StartFixture(180, Thread, ThreadId);
  Params := Default(TDItemCreateParams);
  Params.ItemSize := 32; Params.BigItemSize := 32;
  Task := TTaskIconProbe.Create(0, Params);
  try
    Started := GetTickCount64;
    Task.Bind(FixtureWindow);
    AssertTrue('Task icons must not block the UI', GetTickCount64 - Started < 60);
  finally
    Task.Free;
    StopFixture(Thread, ThreadId);
  end;
end;
procedure TAsyncWindowIconTests.TaskItemReceivesReadyImage;
var Thread: THandle; ThreadId: DWORD; Task: TTaskIconProbe;
  Params: TDItemCreateParams; Message: TMsg; Timers: Integer;
begin
  StartFixture(15, Thread, ThreadId);
  GreenFixtureIcon;
  Params := Default(TDItemCreateParams);
  Params.ItemSize := 32; Params.BigItemSize := 32;
  Task := TTaskIconProbe.Create(0, Params);
  try
    Task.Bind(FixtureWindow);
    AssertTrue('Task icons must subscribe for ready results', WaitReady(Task.Handle, 1000, Message, Timers));
    DispatchMessage(Message);
    AssertEquals('The task owner must install the ready icon', Cardinal($FF00FF00), Task.ImagePixel);
  finally
    Task.Free;
    StopFixture(Thread, ThreadId);
  end;
end;
procedure TAsyncWindowIconTests.PreviewReplacesExistingFallback;
var Thread: THandle; ThreadId: DWORD; Peek: TPeekIconProbe;
  Message: TMsg; Timers: Integer;
begin
  StartFixture(15, Thread, ThreadId);
  GreenFixtureIcon;
  Peek := TPeekIconProbe.Create;
  try
    Peek.BindWithFallback(FixtureWindow);
    AssertTrue('The initial fallback must differ from the window image', Peek.ImagePixel <> $FF00FF00);
    Peek.Refresh;
    AssertTrue('Preview fallback images must subscribe for updates', WaitReady(Peek.Handle, 1000, Message, Timers));
    DispatchMessage(Message);
    AssertEquals('The preview owner must replace its nonempty fallback', Cardinal($FF00FF00), Peek.ImagePixel);
    AssertTrue('The preview must repaint after the ready result', Peek.Paints > 0);
  finally
    Peek.Free;
    StopFixture(Thread, ThreadId);
  end;
end;
procedure TAsyncWindowIconTests.RebindingOwnerReleasesObsoleteQueuedWindows;
var Service: TWindowIconService; Owner: HWND; Windows: array[0..64] of HWND;
  I, Pending, Cached, Subscriptions: Integer;
begin
  Service := TWindowIconService.Create;
  Owner := CreateWindowExW(0, 'STATIC', 'owner', 0, 0, 0, 1, 1, 0, 0, HInstance, nil);
  FillChar(Windows, SizeOf(Windows), 0);
  try
    for I := 0 to High(Windows) do
    begin
      Windows[I] := CreateWindowExW(0, 'STATIC', 'target', 0, 0, 0, 1, 1, 0, 0, HInstance, nil);
      if I < High(Windows) then Service.Request(Windows[I], Owner, 1, 64);
    end;
    Service.Request(Windows[High(Windows)], Owner, 2, 64);
    Service.Counts(Pending, Cached, Subscriptions);
    AssertEquals('A new binding must release obsolete subscriptions', 1, Subscriptions);
    AssertTrue('A new binding must cancel obsolete pending requests', Pending <= 1);
  finally
    Service.Free;
    for I := 0 to High(Windows) do if Windows[I] <> 0 then DestroyWindow(Windows[I]);
    DestroyWindow(Owner);
  end;
end;
procedure TAsyncWindowIconTests.SubscriptionCountRemainsBounded;
var Service: TWindowIconService; Target: HWND; Owners: array[0..269] of HWND;
  I, Pending, Cached, Subscriptions: Integer;
begin
  Service := TWindowIconService.Create;
  Target := CreateWindowExW(0, 'STATIC', 'target', 0, 0, 0, 1, 1, 0, 0, HInstance, nil);
  FillChar(Owners, SizeOf(Owners), 0);
  try
    for I := 0 to High(Owners) do
    begin
      Owners[I] := CreateWindowExW(0, 'STATIC', 'owner', 0, 0, 0, 1, 1, 0, 0, HInstance, nil);
      Service.Request(Target, Owners[I], 1, 64);
    end;
    Service.Counts(Pending, Cached, Subscriptions);
    AssertEquals('The service must cap live subscriptions', WINDOW_ICON_SUBSCRIPTION_LIMIT, Subscriptions);
    AssertTrue('Many owners must share one pending request', Pending <= 1);
    AssertEquals('Many owners must share one cache entry', 1, Cached);
  finally
    Service.Free;
    for I := 0 to High(Owners) do if Owners[I] <> 0 then DestroyWindow(Owners[I]);
    DestroyWindow(Target);
  end;
end;
procedure TAsyncWindowIconTests.TaskNativeReplacementKeepsCurrentSubscription;
var Thread: THandle; ThreadId: DWORD; Task: TTaskIconProbe;
  Params: TDItemCreateParams; Message: TMsg; Timers: Integer; OldOwner: HWND;
begin
  StartFixture(15, Thread, ThreadId);
  GreenFixtureIcon;
  Params := Default(TDItemCreateParams);
  Params.ItemSize := 32; Params.BigItemSize := 32;
  Task := TTaskIconProbe.Create(0, Params);
  try
    Task.Bind(FixtureWindow);
    OldOwner := Task.Handle;
    Task.RecreateWindow;
    AssertTrue('Native replacement must create a new owner', Task.Handle <> OldOwner);
    AssertFalse('The old native owner must reject results',
      WindowIconService.AcceptNotification(FixtureWindow, OldOwner, 1));
    if Task.ImagePixel <> $FF00FF00 then
    begin
      AssertTrue('The replacement owner must receive its ready result', WaitReady(Task.Handle, 1000, Message, Timers));
      DispatchMessage(Message);
    end;
    AssertEquals('The replacement owner must install ready pixels', Cardinal($FF00FF00), Task.ImagePixel);
  finally
    Task.Free;
    StopFixture(Thread, ThreadId);
  end;
end;
function NativeGuiResources(Process: THandle; Flags: DWORD): DWORD; stdcall;
  external 'user32.dll' name 'GetGuiResources';
procedure TAsyncWindowIconTests.IconCopiesReleaseNativeHandles;
var Thread: THandle; ThreadId: DWORD; Service: TWindowIconService;
  Owner: HWND; Message: TMsg; Timers, I: Integer; Icon: HICON;
  BeforeGDI, BeforeUSER: DWORD;
begin
  StartFixture(0, Thread, ThreadId);
  Owner := CreateWindowExW(0, 'STATIC', 'owner', 0, 0, 0, 1, 1, 0, 0, HInstance, nil);
  Service := TWindowIconService.Create;
  try
    Service.Request(FixtureWindow, Owner, 1, 64);
    AssertTrue('The cache must warm before handle measurement', WaitReady(Owner, 1000, Message, Timers));
    BeforeGDI := NativeGuiResources(GetCurrentProcess, 0);
    BeforeUSER := NativeGuiResources(GetCurrentProcess, 1);
    for I := 1 to 200 do
    begin
      Icon := Service.Request(FixtureWindow, Owner, 1, 64);
      AssertTrue('Each cache hit must supply an owned icon', Icon <> 0);
      DestroyIcon(Icon);
    end;
    AssertEquals('Owned copies must not retain GDI handles', BeforeGDI, NativeGuiResources(GetCurrentProcess, 0));
    AssertEquals('Owned copies must not retain USER handles', BeforeUSER, NativeGuiResources(GetCurrentProcess, 1));
  finally
    Service.Free;
    DestroyWindow(Owner);
    StopFixture(Thread, ThreadId);
  end;
end;
function CaptureIdentityProperty(Wnd: HWND; Name: PWideChar; Data: THandle;
  Context: ULONG_PTR): Integer; stdcall;
var Value: UnicodeString;
begin
  Result := 1;
  if PtrUInt(Name) <= $FFFF then Exit;
  Value := Name;
  if (Pos('tdock.asyncicon.', Value) = 1) and (Pos('.owner', Value) = 0) then
  begin
    PUnicodeString(Context)^ := Value;
    Result := 0;
  end;
end;
function EnumerateIconProperties(Wnd: HWND; Callback: Pointer; Context: ULONG_PTR): Integer; stdcall;
  external 'user32.dll' name 'EnumPropsExW';
procedure TAsyncWindowIconTests.ChangedWindowIdentityRejectsSameHandleResults;
var Thread: THandle; ThreadId, OriginalPID, OriginalTID, CurrentPID: DWORD;
  Owner: HWND; Service: TWindowIconService; Name: UnicodeString;
  Message: TMsg; Timers: Integer;
begin
  StartFixture(0, Thread, ThreadId);
  Owner := CreateWindowExW(0, 'STATIC', 'owner', 0, 0, 0, 1, 1, 0, 0, HInstance, nil);
  Service := TWindowIconService.Create;
  try
    OriginalTID := GetWindowThreadProcessId(FixtureWindow, @OriginalPID);
    Service.Request(FixtureWindow, Owner, 1, 64);
    AssertTrue('The original identity must complete', WaitReady(Owner, 1000, Message, Timers));
    EnumerateIconProperties(FixtureWindow, @CaptureIdentityProperty, ULONG_PTR(@Name));
    AssertTrue('The service must register a window identity', Name <> '');
    AssertTrue('Replace the identity without changing the handle',
      SetPropW(FixtureWindow, PWideChar(Name), NextWindowIconGeneration));
    AssertEquals('The thread ID remains unchanged', OriginalTID,
      GetWindowThreadProcessId(FixtureWindow, @CurrentPID));
    AssertEquals('The process ID remains unchanged', OriginalPID, CurrentPID);
    AssertFalse('Changed identities must reject results despite matching HWND/PID/TID',
      Service.AcceptNotification(FixtureWindow, Owner, 1));
  finally
    Service.Free;
    if Name <> '' then RemovePropW(FixtureWindow, PWideChar(Name));
    DestroyWindow(Owner);
    StopFixture(Thread, ThreadId);
  end;
end;
function RefuseWindowStamp(Window: HWND; Name: PWideChar; Stamp: THandle): BOOL;
begin Result := False; end;
procedure TAsyncWindowIconTests.StampFailureKeepsReadableClassIcon;
var Thread: THandle; ThreadId: DWORD; Service: TWindowIconService;
  Owner: HWND; Icon: HICON; Info: ICONINFO; Pending, Cached, Subscriptions: Integer;
begin
  StartFixture(800, Thread, ThreadId);
  Owner := CreateWindowExW(0, 'STATIC', 'owner', 0, 0, 0, 1, 1, 0, 0, HInstance, nil);
  Service := TWindowIconService.Create;
  Windows.SetClassLongPtr(FixtureWindow, GCL_HICON, LONG_PTR(FixtureIcon));
  WindowIconStampForTests := RefuseWindowStamp;
  try
    Icon := Service.Request(FixtureWindow, Owner, 7, 64);
    AssertTrue('Denied identity stamping must retain readable class icons', Icon <> 0);
    DestroyIcon(Icon);
    Windows.SetClassLongPtr(FixtureWindow, GCL_HICON, 0);
    Windows.SetClassLongPtr(FixtureWindow, GCL_HICONSM, LONG_PTR(FixtureIcon));
    Icon := Service.Request(FixtureWindow, Owner, 7, 64);
    AssertTrue('Large requests must also use a readable small class icon', Icon <> 0);
    DestroyIcon(Icon);
    Icon := Service.Request(FixtureWindow, Owner, 7, 16);
    AssertTrue('Small requests must retain their readable class icon', Icon <> 0);
    DestroyIcon(Icon);
    AssertEquals('Unstamped windows must receive no foreign icon messages', 0, FixtureCalls);
    AssertTrue('The readable class icon must remain borrowed', GetIconInfo(FixtureIcon, Info));
    DeleteObject(Info.hbmColor);
    DeleteObject(Info.hbmMask);
    Service.Counts(Pending, Cached, Subscriptions);
    AssertEquals('Unstamped windows must not retain stale cache entries', 0, Cached);
    AssertEquals('Unstamped windows must not queue notifications', 0, Subscriptions);
  finally
    WindowIconStampForTests := nil;
    Windows.SetClassLongPtr(FixtureWindow, GCL_HICON, 0);
    Windows.SetClassLongPtr(FixtureWindow, GCL_HICONSM, 0);
    Service.Free;
    DestroyWindow(Owner);
    StopFixture(Thread, ThreadId);
  end;
end;
initialization
  RegisterTest(TAsyncWindowIconTests);
end.
