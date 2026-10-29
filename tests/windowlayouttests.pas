unit windowlayouttests;

{$mode delphi}

interface

uses Windows, SysUtils, Types, Classes, fpcunit, testregistry, appwindowsu, windowlayoutu;

type
  TFakeLayoutWindow = record
    Handle: HWND;
    Generation: Integer;
    Eligible, CaptureFails, ApplyFails, RaiseOnApply, CloseOnApply, RaiseOnCapture: Boolean;
    Title, CaptureReason, ApplyReason: string;
    Placement: TWindowPlacement;
  end;
  TFakeWindowLayouts = class(TWindowLayoutService)
  public
    Windows: array of TFakeLayoutWindow;
    Displays: TLayoutDisplays;
    Applied: TWindowLayoutEntries;
    Released: Integer;
    ListFails, ReenterOnCapture: Boolean;
    DisplayReads, FailDisplayRead, ChangeDisplayRead: Integer;
    ReentryStatus: TWindowLayoutStatus;
    constructor Create;
    procedure AddWindow(Handle: HWND; ShowCommand: UINT = SW_SHOWNORMAL);
  protected
    function ReadWindows(out Handles: TApplicationWindows): Boolean; override;
    function ReadDisplays(out Snapshot: TLayoutDisplays): Boolean; override;
    function DescribeWindow(Window: HWND): string; override;
    function CaptureWindow(Window: HWND; out Entry: TWindowLayoutEntry; out Reason: string): Boolean; override;
    function MatchesWindow(const Entry: TWindowLayoutEntry): Boolean; override;
    function EligibleWindow(Window: HWND): Boolean; override;
    function ApplyWindow(const Entry: TWindowLayoutEntry; out Reason: string): Boolean; override;
    procedure ReleaseWindow(const Entry: TWindowLayoutEntry); override;
  end;
  TNativeLayoutProbe = class(TWindowLayoutService)
  public
    AllowHidden: Boolean;
    function Capture(Window: HWND; out Entry: TWindowLayoutEntry): Boolean;
    function Matches(const Entry: TWindowLayoutEntry): Boolean;
    function CaptureFailure(Window: HWND): string;
    function Description(Window: HWND): string;
    function Apply(const Entry: TWindowLayoutEntry): Boolean;
    procedure Release(const Entry: TWindowLayoutEntry);
    function Displays(out Snapshot: TLayoutDisplays): Boolean;
  protected
    function EligibleWindow(Window: HWND): Boolean; override;
  end;
  TWindowLayoutTests = class(TTestCase)
  private
    Layout: TFakeWindowLayouts;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure RestoreBeforeSaveDoesNothing;
    procedure RestoresSavedStatesAndNegativeCoordinates;
    procedure SkipsClosedHiddenAndNewWindows;
    procedure SkipsReusedWindowHandles;
    procedure RestoreRetainsSnapshot;
    procedure SaveReplacesPreviousSnapshot;
    procedure FailedSaveRetainsPreviousSnapshot;
    procedure PartialSaveReportsFailures;
    procedure EmptySaveReplacesPreviousSnapshot;
    procedure ReadFailureDoesNotMoveWindows;
    procedure DisplayChangesBlockRestore;
    procedure MonitorEnumerationOrderDoesNotMatter;
    procedure DisplayChangeDuringSaveRetainsPreviousSnapshot;
    procedure DisplayReadFailureDuringSaveRetainsPreviousSnapshot;
    procedure RestoreContinuesAfterWindowFailure;
    procedure WindowClosingDuringRestoreCountsAsSkipped;
    procedure ReentrantSaveCannotReplaceSnapshot;
    procedure NewServiceStartsWithoutSnapshot;
    procedure NativeMarkerDetectsWindowReplacement;
    procedure NativeReleaseRemovesOnlyItsOwnMarker;
    procedure NativePlacementRestoresHiddenFixtureGeometry;
    procedure NativeDisplaySnapshotIsStable;
    procedure NativeStatesRoundTripOnIsolatedDesktop;
    procedure ExistingFilterRejectsHiddenAndToolWindows;
    procedure ApplicationEnumerationDoesNotExposeHiddenFixture;
    procedure MessagesReportResults;
    procedure SaveFailuresIncludeWindowAndReason;
    procedure CaptureExceptionsIncludeWindowAndReason;
    procedure RestoreFailuresIncludeCurrentTitleAndReason;
    procedure MissingReasonsRemainExplicit;
    procedure FailureDetailsStayOnOneLine;
    procedure NativeCaptureReportsInvalidHandle;
    procedure NativeDescriptionsPreserveUnicode;
  end;

implementation

type
  TIsolatedLayoutThread = class(TThread)
  public
    Failure: string;
  protected
    procedure Execute; override;
  end;

procedure TIsolatedLayoutThread.Execute;
var Desktop, OriginalDesktop: HDESK; Id: TGUID; Name: UnicodeString;
  Windows: array[0..3] of HWND; Service: TWindowLayoutService;
  Outcome: TWindowLayoutResult; Before, After, NewWindowBounds: TRect; I: Integer;

  procedure Require(Condition: Boolean; const Message: string);
  begin
    if not Condition then raise Exception.Create(Message + ' (Win32: ' + IntToStr(GetLastError) + ')');
  end;

  function EqualBounds(const A, B: TRect): Boolean;
  begin
    Result := (A.Left = B.Left) and (A.Top = B.Top) and
      (A.Right = B.Right) and (A.Bottom = B.Bottom);
  end;

begin
  Desktop := 0;
  Service := nil;
  FillChar(Windows, SizeOf(Windows), 0);
  OriginalDesktop := GetThreadDesktop(GetCurrentThreadId);
  try
    try
      Require(CreateGUID(Id) = S_OK, 'Create a desktop identifier');
      Name := 'TDockLayoutTest' + UnicodeString(GUIDToString(Id));
      Desktop := CreateDesktopW(PWideChar(Name), nil, nil, 0, GENERIC_ALL, nil);
      Require(Desktop <> 0, 'Create an isolated desktop');
      Require(SetThreadDesktop(Desktop), 'Select the isolated desktop');
      for I := 0 to 2 do
      begin
        Windows[I] := CreateWindowExW(WS_EX_APPWINDOW, 'STATIC', 'TDock layout fixture',
          WS_OVERLAPPEDWINDOW, 80 + I * 40, 100 + I * 30, 400, 300, 0, 0, HInstance, nil);
        Require(Windows[I] <> 0, 'Create an application fixture');
        ShowWindow(Windows[I], SW_SHOWNOACTIVATE);
      end;
      ShowWindow(Windows[1], SW_SHOWMAXIMIZED);
      ShowWindow(Windows[1], SW_MINIMIZE);
      ShowWindow(Windows[2], SW_SHOWMAXIMIZED);
      Require(GetWindowRect(Windows[0], Before), 'Read the normal window rectangle');
      Service := TWindowLayoutService.Create;
      Outcome := Service.Save;
      Require((Outcome.Status = wlsSaved) and (Outcome.Saved = 3) and
        (Outcome.Failed = 0), 'Save all three native window states');
      for I := 0 to 2 do
      begin
        ShowWindow(Windows[I], SW_RESTORE);
        Require(SetWindowPos(Windows[I], 0, 250, 180, 500, 350,
          SWP_NOZORDER or SWP_NOACTIVATE), 'Disturb a fixture');
      end;
      Windows[3] := CreateWindowExW(WS_EX_APPWINDOW, 'STATIC', 'New window',
        WS_OVERLAPPEDWINDOW, 300, 200, 400, 300, 0, 0, HInstance, nil);
      Require(Windows[3] <> 0, 'Create a new application fixture');
      ShowWindow(Windows[3], SW_SHOWNOACTIVATE);
      Require(GetWindowRect(Windows[3], NewWindowBounds), 'Read the new window rectangle');
      Outcome := Service.Restore;
      Require((Outcome.Status = wlsRestored) and (Outcome.Restored = 3) and
        (Outcome.Failed = 0), 'Restore the saved native windows');
      Require(GetWindowRect(Windows[0], After) and EqualBounds(Before, After),
        'Restore the normal window position and size');
      Require(IsIconic(Windows[1]), 'Restore the minimized state');
      Require(IsZoomed(Windows[2]), 'Restore the maximized state');
      Require(GetWindowRect(Windows[3], After) and EqualBounds(NewWindowBounds, After),
        'Leave the new window unchanged');
      ShowWindow(Windows[1], SW_RESTORE);
      Require(IsZoomed(Windows[1]), 'Keep the minimized window restoration to maximized');
      Outcome := Service.Restore;
      Require((Outcome.Restored = 3) and IsIconic(Windows[1]), 'Restore the same snapshot twice');
    finally
      Service.Free;
      for I := 0 to 3 do
        if Windows[I] <> 0 then DestroyWindow(Windows[I]);
      if Desktop <> 0 then
      begin
        SetThreadDesktop(OriginalDesktop);
        CloseDesktop(Desktop);
      end;
    end;
  except
    on E: Exception do Failure := E.ClassName + ': ' + E.Message;
  end;
end;

constructor TFakeWindowLayouts.Create;
begin
  inherited Create;
  SetLength(Displays, 2);
  Displays[0].Device := 'LEFT';
  Displays[0].Bounds := Types.Rect(-1920, 0, 0, 1080);
  Displays[0].WorkArea := Types.Rect(-1920, 0, 0, 1040);
  Displays[0].Scale := 100;
  Displays[1].Device := 'MAIN';
  Displays[1].Bounds := Types.Rect(0, 0, 2560, 1440);
  Displays[1].WorkArea := Types.Rect(0, 0, 2560, 1400);
  Displays[1].Primary := True;
  Displays[1].Scale := 150;
end;

procedure TFakeWindowLayouts.AddWindow(Handle: HWND; ShowCommand: UINT);
var N: Integer;
begin
  N := Length(Windows);
  SetLength(Windows, N + 1);
  Windows[N].Handle := Handle;
  Windows[N].Generation := 1;
  Windows[N].Eligible := True;
  Windows[N].Title := 'Window ' + IntToStr(Handle);
  Windows[N].CaptureReason := 'Cannot mark window identity: access denied (Windows error 5).';
  Windows[N].ApplyReason := 'Cannot restore window placement (Windows error 1400).';
  Windows[N].Placement.length := SizeOf(TWindowPlacement);
  Windows[N].Placement.showCmd := ShowCommand;
  Windows[N].Placement.rcNormalPosition := Types.Rect(-1800, 100, -1000, 700);
end;

function TFakeWindowLayouts.ReadWindows(out Handles: TApplicationWindows): Boolean;
var I, N: Integer;
begin
  Handles := nil;
  Result := not ListFails;
  if not Result then Exit;
  for I := 0 to High(Windows) do
    if (Windows[I].Generation > 0) and Windows[I].Eligible then
    begin
      N := Length(Handles);
      SetLength(Handles, N + 1);
      Handles[N] := Windows[I].Handle;
    end;
end;

function TFakeWindowLayouts.ReadDisplays(out Snapshot: TLayoutDisplays): Boolean;
begin
  Inc(DisplayReads);
  Result := DisplayReads <> FailDisplayRead;
  Snapshot := Copy(Displays);
  if DisplayReads = ChangeDisplayRead then Inc(Snapshot[0].Bounds.Right);
end;

function TFakeWindowLayouts.CaptureWindow(Window: HWND;
  out Entry: TWindowLayoutEntry; out Reason: string): Boolean;
var I: Integer; Outcome: TWindowLayoutResult;
begin
  if ReenterOnCapture then
  begin
    Outcome := Save;
    ReentryStatus := Outcome.Status;
  end;
  Entry := Default(TWindowLayoutEntry);
  for I := 0 to High(Windows) do
    if Windows[I].Handle = Window then
    begin
      if Windows[I].RaiseOnCapture then raise Exception.Create(Windows[I].CaptureReason);
      Result := not Windows[I].CaptureFails;
      if not Result then
      begin Reason := Windows[I].CaptureReason; Exit; end;
      Entry.Window := Window;
      Entry.Marker := UnicodeString(IntToStr(Windows[I].Generation));
      Entry.Placement := Windows[I].Placement;
      Exit;
    end;
  Result := False;
end;

function TFakeWindowLayouts.MatchesWindow(const Entry: TWindowLayoutEntry): Boolean;
var I: Integer;
begin
  Result := False;
  for I := 0 to High(Windows) do
    if Windows[I].Handle = Entry.Window then
      Exit((Windows[I].Generation > 0) and
        (Entry.Marker = UnicodeString(IntToStr(Windows[I].Generation))));
end;

function TFakeWindowLayouts.EligibleWindow(Window: HWND): Boolean;
var I: Integer;
begin
  Result := False;
  for I := 0 to High(Windows) do
    if Windows[I].Handle = Window then Exit(Windows[I].Eligible);
end;

function TFakeWindowLayouts.ApplyWindow(const Entry: TWindowLayoutEntry; out Reason: string): Boolean;
var I, N: Integer;
begin
  Result := False;
  for I := 0 to High(Windows) do
    if Windows[I].Handle = Entry.Window then
    begin
      if Windows[I].RaiseOnApply then raise Exception.Create('Window rejected placement');
      if Windows[I].CloseOnApply then
      begin Windows[I].Generation := 0; Exit; end;
      if Windows[I].ApplyFails then begin Reason := Windows[I].ApplyReason; Exit; end;
      N := Length(Applied);
      SetLength(Applied, N + 1);
      Applied[N] := Entry;
      Windows[I].Placement := Entry.Placement;
      Exit(True);
    end;
end;

procedure TFakeWindowLayouts.ReleaseWindow(const Entry: TWindowLayoutEntry);
begin
  if Entry.Marker <> '' then Inc(Released);
end;

function TNativeLayoutProbe.Capture(Window: HWND; out Entry: TWindowLayoutEntry): Boolean;
var Reason: string;
begin Result := CaptureWindow(Window, Entry, Reason); end;
function TNativeLayoutProbe.Matches(const Entry: TWindowLayoutEntry): Boolean;
begin Result := MatchesWindow(Entry); end;
function TNativeLayoutProbe.Apply(const Entry: TWindowLayoutEntry): Boolean;
var Reason: string;
begin Result := ApplyWindow(Entry, Reason); end;
procedure TNativeLayoutProbe.Release(const Entry: TWindowLayoutEntry);
begin ReleaseWindow(Entry); end;
function TNativeLayoutProbe.Displays(out Snapshot: TLayoutDisplays): Boolean;
begin Result := ReadDisplays(Snapshot); end;
function TNativeLayoutProbe.EligibleWindow(Window: HWND): Boolean;
begin
  if AllowHidden then Result := IsWindow(Window)
  else Result := inherited EligibleWindow(Window);
end;

procedure TWindowLayoutTests.SetUp;
begin Layout := TFakeWindowLayouts.Create; end;
procedure TWindowLayoutTests.TearDown;
begin Layout.Free; end;

procedure TWindowLayoutTests.RestoreBeforeSaveDoesNothing;
var Outcome: TWindowLayoutResult;
begin
  Outcome := Layout.Restore;
  AssertEquals(Ord(wlsNoSnapshot), Ord(Outcome.Status));
  AssertEquals(0, Length(Layout.Applied));
  AssertEquals(0, Layout.DisplayReads);
end;

procedure TWindowLayoutTests.RestoresSavedStatesAndNegativeCoordinates;
var Outcome: TWindowLayoutResult; I: Integer;
begin
  Layout.AddWindow(1);
  Layout.AddWindow(2, SW_SHOWMINIMIZED);
  Layout.AddWindow(3, SW_SHOWMAXIMIZED);
  Layout.Windows[1].Placement.flags := WPF_RESTORETOMAXIMIZED;
  Outcome := Layout.Save;
  AssertEquals(3, Outcome.Saved);
  for I := 0 to 2 do Layout.Windows[I].Placement := Default(TWindowPlacement);
  Outcome := Layout.Restore;
  AssertEquals(3, Outcome.Restored);
  AssertEquals(-1800, Layout.Windows[0].Placement.rcNormalPosition.Left);
  AssertEquals(SW_SHOWNORMAL, Integer(Layout.Windows[0].Placement.showCmd));
  AssertEquals(SW_SHOWMINIMIZED, Integer(Layout.Windows[1].Placement.showCmd));
  AssertEquals(WPF_RESTORETOMAXIMIZED, Integer(Layout.Windows[1].Placement.flags));
  AssertEquals(SW_SHOWMAXIMIZED, Integer(Layout.Windows[2].Placement.showCmd));
end;

procedure TWindowLayoutTests.SkipsClosedHiddenAndNewWindows;
var Outcome: TWindowLayoutResult;
begin
  Layout.AddWindow(1); Layout.AddWindow(2); Layout.AddWindow(3);
  Layout.Save;
  Layout.Windows[0].Generation := 0;
  Layout.Windows[1].Eligible := False;
  Layout.AddWindow(4);
  Layout.Windows[3].Placement.rcNormalPosition.Left := 321;
  Outcome := Layout.Restore;
  AssertEquals(1, Outcome.Restored);
  AssertEquals(2, Outcome.Skipped);
  AssertEquals(0, Outcome.Failed);
  AssertEquals(321, Layout.Windows[3].Placement.rcNormalPosition.Left);
end;

procedure TWindowLayoutTests.SkipsReusedWindowHandles;
var Outcome: TWindowLayoutResult;
begin
  Layout.AddWindow(1); Layout.Save;
  Inc(Layout.Windows[0].Generation);
  Outcome := Layout.Restore;
  AssertEquals(0, Outcome.Restored);
  AssertEquals(1, Outcome.Skipped);
end;

procedure TWindowLayoutTests.RestoreRetainsSnapshot;
var Outcome: TWindowLayoutResult;
begin
  Layout.AddWindow(1); Layout.Save;
  Layout.Restore;
  Outcome := Layout.Restore;
  AssertEquals(1, Outcome.Restored);
  AssertEquals(2, Length(Layout.Applied));
  AssertEquals(0, Layout.Released);
end;

procedure TWindowLayoutTests.SaveReplacesPreviousSnapshot;
begin
  Layout.AddWindow(1); Layout.Save;
  Layout.Windows[0].Placement.rcNormalPosition.Left := 100;
  Layout.Save;
  Layout.Windows[0].Placement.rcNormalPosition.Left := 200;
  Layout.Restore;
  AssertEquals(100, Layout.Windows[0].Placement.rcNormalPosition.Left);
  AssertEquals(1, Layout.Released);
end;

procedure TWindowLayoutTests.FailedSaveRetainsPreviousSnapshot;
var Outcome: TWindowLayoutResult;
begin
  Layout.AddWindow(1); Layout.Save;
  Layout.Windows[0].CaptureFails := True;
  Outcome := Layout.Save;
  AssertEquals(Ord(wlsSaveFailed), Ord(Outcome.Status));
  Outcome := Layout.Restore;
  AssertEquals(1, Outcome.Restored);
  AssertEquals(0, Layout.Released);
end;

procedure TWindowLayoutTests.PartialSaveReportsFailures;
var Outcome: TWindowLayoutResult;
begin
  Layout.AddWindow(1); Layout.AddWindow(2);
  Layout.Windows[0].CaptureFails := True;
  Outcome := Layout.Save;
  AssertEquals(Ord(wlsSaved), Ord(Outcome.Status));
  AssertEquals(1, Outcome.Saved);
  AssertEquals(1, Outcome.Failed);
  Outcome := Layout.Restore;
  AssertEquals(1, Outcome.Restored);
end;

procedure TWindowLayoutTests.EmptySaveReplacesPreviousSnapshot;
var Outcome: TWindowLayoutResult;
begin
  Layout.AddWindow(1); Layout.Save;
  Layout.Windows[0].Eligible := False;
  Outcome := Layout.Save;
  AssertEquals(Ord(wlsSaved), Ord(Outcome.Status));
  AssertEquals(0, Outcome.Saved);
  Outcome := Layout.Restore;
  AssertEquals(Ord(wlsRestored), Ord(Outcome.Status));
  AssertEquals(0, Outcome.Restored);
  AssertEquals(1, Layout.Released);
end;

procedure TWindowLayoutTests.ReadFailureDoesNotMoveWindows;
var Outcome: TWindowLayoutResult;
begin
  Layout.AddWindow(1); Layout.Save;
  Layout.ListFails := True;
  Outcome := Layout.Restore;
  AssertEquals(Ord(wlsUnavailable), Ord(Outcome.Status));
  AssertEquals(0, Length(Layout.Applied));
  Layout.ListFails := False;
  Layout.FailDisplayRead := Layout.DisplayReads + 1;
  Outcome := Layout.Restore;
  AssertEquals(Ord(wlsUnavailable), Ord(Outcome.Status));
  AssertEquals(0, Length(Layout.Applied));
end;

procedure TWindowLayoutTests.DisplayChangesBlockRestore;
var Outcome: TWindowLayoutResult; Original: TLayoutDisplays; I: Integer;
begin
  Layout.AddWindow(1); Layout.Save;
  Original := Copy(Layout.Displays);
  for I := 0 to 7 do
  begin
    Layout.Displays := Copy(Original);
    case I of
      0: Layout.Displays[1].Bounds.Right := 1280;
      1: SetLength(Layout.Displays, 1);
      2: Inc(Layout.Displays[0].WorkArea.Top, 40);
      3: Layout.Displays[1].Scale := 100;
      4: Layout.Displays[0].Primary := True;
      5: Layout.Displays[1].Orientation := 2;
      6: Layout.Displays[0].Bounds.Left := -2000;
      7: Layout.Displays[0].Device := 'REPLACEMENT';
    end;
    Outcome := Layout.Restore;
    AssertEquals('Display mismatch case ' + IntToStr(I), Ord(wlsDisplayChanged), Ord(Outcome.Status));
    AssertEquals(0, Length(Layout.Applied));
  end;
  Layout.Displays := Copy(Original);
  Outcome := Layout.Restore;
  AssertEquals(1, Outcome.Restored);
end;

procedure TWindowLayoutTests.MonitorEnumerationOrderDoesNotMatter;
var Outcome: TWindowLayoutResult; Display: TLayoutDisplay;
begin
  Layout.AddWindow(1); Layout.Save;
  Display := Layout.Displays[0];
  Layout.Displays[0] := Layout.Displays[1];
  Layout.Displays[1] := Display;
  Outcome := Layout.Restore;
  AssertEquals(1, Outcome.Restored);
end;

procedure TWindowLayoutTests.DisplayChangeDuringSaveRetainsPreviousSnapshot;
var Outcome: TWindowLayoutResult;
begin
  Layout.AddWindow(1); Layout.Save;
  Layout.ChangeDisplayRead := Layout.DisplayReads + 2;
  Outcome := Layout.Save;
  AssertEquals(Ord(wlsDisplayChanged), Ord(Outcome.Status));
  AssertEquals(1, Layout.Released);
  Outcome := Layout.Restore;
  AssertEquals(1, Outcome.Restored);
end;

procedure TWindowLayoutTests.DisplayReadFailureDuringSaveRetainsPreviousSnapshot;
var Outcome: TWindowLayoutResult;
begin
  Layout.AddWindow(1); Layout.Save;
  Layout.FailDisplayRead := Layout.DisplayReads + 2;
  Outcome := Layout.Save;
  AssertEquals(Ord(wlsUnavailable), Ord(Outcome.Status));
  AssertEquals(1, Layout.Released);
  Outcome := Layout.Restore;
  AssertEquals(1, Outcome.Restored);
end;

procedure TWindowLayoutTests.RestoreContinuesAfterWindowFailure;
var Outcome: TWindowLayoutResult;
begin
  Layout.AddWindow(1); Layout.AddWindow(2); Layout.AddWindow(3);
  Layout.Save;
  Layout.Windows[0].ApplyFails := True;
  Layout.Windows[1].RaiseOnApply := True;
  Outcome := Layout.Restore;
  AssertEquals(1, Outcome.Restored);
  AssertEquals(2, Outcome.Failed);
end;

procedure TWindowLayoutTests.WindowClosingDuringRestoreCountsAsSkipped;
var Outcome: TWindowLayoutResult;
begin
  Layout.AddWindow(1); Layout.Save;
  Layout.Windows[0].CloseOnApply := True;
  Outcome := Layout.Restore;
  AssertEquals(1, Outcome.Skipped);
  AssertEquals(0, Outcome.Failed);
end;

procedure TWindowLayoutTests.ReentrantSaveCannotReplaceSnapshot;
var Outcome: TWindowLayoutResult;
begin
  Layout.AddWindow(1);
  Layout.ReenterOnCapture := True;
  Outcome := Layout.Save;
  AssertEquals(Ord(wlsBusy), Ord(Layout.ReentryStatus));
  AssertEquals(1, Outcome.Saved);
end;

procedure TWindowLayoutTests.NewServiceStartsWithoutSnapshot;
var Other: TFakeWindowLayouts; Outcome: TWindowLayoutResult;
begin
  Layout.AddWindow(1); Layout.Save;
  Other := TFakeWindowLayouts.Create;
  try
    Outcome := Other.Restore;
    AssertEquals(Ord(wlsNoSnapshot), Ord(Outcome.Status));
  finally Other.Free; end;
end;

function HiddenFixture: HWND;
begin
  Result := CreateWindowExW(WS_EX_TOOLWINDOW, 'STATIC', 'TDock window layout test',
    WS_POPUP, 120, 140, 320, 240, 0, 0, HInstance, nil);
  if Result = 0 then RaiseLastOSError;
end;

procedure TWindowLayoutTests.NativeMarkerDetectsWindowReplacement;
var Probe: TNativeLayoutProbe; Window, Replacement: HWND; Entry: TWindowLayoutEntry;
begin
  Probe := TNativeLayoutProbe.Create;
  Window := HiddenFixture;
  Replacement := 0;
  try
    AssertTrue(Probe.Capture(Window, Entry));
    AssertTrue(Probe.Matches(Entry));
    AssertTrue(DestroyWindow(Window));
    Window := 0;
    AssertFalse(Probe.Matches(Entry));
    Replacement := HiddenFixture;
    Entry.Window := Replacement;
    AssertFalse('A replacement must not inherit the old marker', Probe.Matches(Entry));
  finally
    Probe.Free;
    if Window <> 0 then DestroyWindow(Window);
    if Replacement <> 0 then DestroyWindow(Replacement);
  end;
end;

procedure TWindowLayoutTests.NativeReleaseRemovesOnlyItsOwnMarker;
var Probe: TNativeLayoutProbe; Window: HWND; First, Second: TWindowLayoutEntry;
begin
  Probe := TNativeLayoutProbe.Create;
  Window := HiddenFixture;
  try
    AssertTrue(Probe.Capture(Window, First));
    AssertTrue(Probe.Capture(Window, Second));
    AssertTrue(First.Marker <> Second.Marker);
    Probe.Release(First);
    AssertFalse(Probe.Matches(First));
    AssertTrue(Probe.Matches(Second));
    Probe.Release(Second);
    AssertFalse(Probe.Matches(Second));
  finally Probe.Free; DestroyWindow(Window); end;
end;

procedure TWindowLayoutTests.NativePlacementRestoresHiddenFixtureGeometry;
var Probe: TNativeLayoutProbe; Window: HWND; Entry: TWindowLayoutEntry; Bounds: TRect;
begin
  Probe := TNativeLayoutProbe.Create;
  Probe.AllowHidden := True;
  Window := HiddenFixture;
  try
    AssertTrue(Probe.Capture(Window, Entry));
    AssertTrue(SetWindowPos(Window, 0, 220, 240, 420, 340, SWP_NOZORDER or SWP_NOACTIVATE));
    // Apply hidden placement without showing a test window on the desktop.
    Entry.Placement.showCmd := SW_HIDE;
    AssertTrue(Probe.Apply(Entry));
    AssertTrue(GetWindowRect(Window, Bounds));
    AssertEquals(120, Bounds.Left);
    AssertEquals(140, Bounds.Top);
    AssertEquals(320, Bounds.Right - Bounds.Left);
    AssertEquals(240, Bounds.Bottom - Bounds.Top);
    AssertFalse(IsWindowVisible(Window));
    Probe.Release(Entry);
  finally Probe.Free; DestroyWindow(Window); end;
end;

procedure TWindowLayoutTests.NativeDisplaySnapshotIsStable;
var Probe: TNativeLayoutProbe; First, Second: TLayoutDisplays;
begin
  Probe := TNativeLayoutProbe.Create;
  try
    AssertTrue(Probe.Displays(First));
    AssertTrue(Length(First) > 0);
    AssertTrue(Probe.Displays(Second));
    AssertTrue(SameLayoutDisplays(First, Second));
  finally Probe.Free; end;
end;

procedure TWindowLayoutTests.ExistingFilterRejectsHiddenAndToolWindows;
var Window: HWND;
begin
  Window := HiddenFixture;
  try
    AssertFalse(IsApplicationWindow(Window));
    // Change only the style. Do not show the fixture.
    Windows.SetWindowLongPtr(Window, GWL_STYLE,
      Windows.GetWindowLongPtr(Window, GWL_STYLE) or WS_VISIBLE);
    AssertTrue(IsWindowVisible(Window));
    AssertFalse(IsApplicationWindow(Window));
    Windows.SetWindowLongPtr(Window, GWL_EXSTYLE, WS_EX_APPWINDOW or WS_EX_TOOLWINDOW);
    AssertTrue('Preserve the existing APPWINDOW override', IsApplicationWindow(Window));
    Windows.SetWindowLongPtr(Window, GWL_STYLE,
      Windows.GetWindowLongPtr(Window, GWL_STYLE) and not PtrInt(WS_VISIBLE));
  finally DestroyWindow(Window); end;
end;

procedure TWindowLayoutTests.ApplicationEnumerationDoesNotExposeHiddenFixture;
var Window: HWND; Handles: TApplicationWindows; Count, I: Integer;
begin
  Window := HiddenFixture;
  try
    AssertTrue(CaptureApplicationWindows(Handles, Count));
    AssertTrue(Count >= Length(Handles));
    for I := 0 to High(Handles) do AssertTrue(Handles[I] <> Window);
  finally DestroyWindow(Window); end;
end;

procedure TWindowLayoutTests.MessagesReportResults;
var Outcome: TWindowLayoutResult;
begin
  Outcome := Layout.Restore;
  AssertTrue(Pos('/savewindows', WindowLayoutMessage(Outcome)) > 0);
  Layout.AddWindow(1); Layout.AddWindow(2);
  Layout.Windows[1].CaptureFails := True;
  Outcome := Layout.Save;
  AssertEquals(1, Pos('Window layout saved: 1. Failed: 1.', WindowLayoutMessage(Outcome)));
  Outcome := Layout.Restore;
  AssertEquals('Windows restored: 1. Skipped: 0. Failed: 0.', WindowLayoutMessage(Outcome));
end;

procedure TWindowLayoutTests.NativeStatesRoundTripOnIsolatedDesktop;
var Worker: TIsolatedLayoutThread;
begin
  Worker := TIsolatedLayoutThread.Create(True);
  try
    Worker.Start;
    Worker.WaitFor;
    AssertEquals('Native desktop round trip', '', Worker.Failure);
  finally Worker.Free; end;
end;
function TFakeWindowLayouts.DescribeWindow(Window: HWND): string;
var I: Integer;
begin
  for I := 0 to High(Windows) do
    if Windows[I].Handle = Window then Exit(Windows[I].Title);
  Result := '';
end;

function TNativeLayoutProbe.CaptureFailure(Window: HWND): string;
var Entry: TWindowLayoutEntry;
begin
  CaptureWindow(Window, Entry, Result);
  ReleaseWindow(Entry);
end;

function TNativeLayoutProbe.Description(Window: HWND): string;
begin Result := DescribeWindow(Window); end;

procedure TWindowLayoutTests.SaveFailuresIncludeWindowAndReason;
var Outcome: TWindowLayoutResult; Message: string;
begin
  Layout.AddWindow(1); Layout.AddWindow(2); Layout.AddWindow(3);
  Layout.Windows[1].Title := UTF8Encode(UnicodeString('Editor ') + WideChar($03A9)) + ' (PID 42)';
  Layout.Windows[1].CaptureFails := True;
  Outcome := Layout.Save;
  AssertEquals(2, Outcome.Saved);
  AssertEquals(1, Outcome.Failed);
  AssertEquals(1, Length(Outcome.Failures));
  AssertEquals(Layout.Windows[1].Title, Outcome.Failures[0].Description);
  AssertEquals(Layout.Windows[1].CaptureReason, Outcome.Failures[0].Reason);
  Message := WindowLayoutMessage(Outcome);
  AssertTrue(Pos(Layout.Windows[1].Title, Message) > 0);
  AssertTrue(Pos('Windows error 5', Message) > 0);
  AssertEquals(0, Pos(Layout.Windows[0].Title + ':', Message));
end;

procedure TWindowLayoutTests.CaptureExceptionsIncludeWindowAndReason;
var Outcome: TWindowLayoutResult;
begin
  Layout.AddWindow(1);
  Layout.Windows[0].RaiseOnCapture := True;
  Layout.Windows[0].CaptureReason := 'Capture raised an exception';
  Outcome := Layout.Save;
  AssertEquals(Ord(wlsSaveFailed), Ord(Outcome.Status));
  AssertEquals(1, Outcome.Failed);
  AssertEquals(1, Length(Outcome.Failures));
  AssertEquals(Layout.Windows[0].Title, Outcome.Failures[0].Description);
  AssertEquals('Capture raised an exception', Outcome.Failures[0].Reason);
end;

procedure TWindowLayoutTests.RestoreFailuresIncludeCurrentTitleAndReason;
var Outcome: TWindowLayoutResult;
begin
  Layout.AddWindow(1); Layout.AddWindow(2); Layout.Save;
  Layout.Windows[0].Title := 'Current document (PID 42)';
  Layout.Windows[0].ApplyFails := True;
  Layout.Windows[1].Eligible := False;
  Outcome := Layout.Restore;
  AssertEquals(1, Outcome.Failed);
  AssertEquals(1, Outcome.Skipped);
  AssertEquals(1, Length(Outcome.Failures));
  AssertEquals(Layout.Windows[0].Title, Outcome.Failures[0].Description);
  AssertEquals(Layout.Windows[0].ApplyReason, Outcome.Failures[0].Reason);
end;

procedure TWindowLayoutTests.MissingReasonsRemainExplicit;
var Outcome: TWindowLayoutResult;
begin
  Layout.AddWindow(1);
  Layout.Windows[0].Title := '';
  Layout.Windows[0].CaptureFails := True;
  Layout.Windows[0].CaptureReason := '';
  Outcome := Layout.Save;
  AssertEquals(1, Pos('Window 0x', Outcome.Failures[0].Description));
  AssertEquals('The application did not provide an error reason.', Outcome.Failures[0].Reason);
end;

procedure TWindowLayoutTests.FailureDetailsStayOnOneLine;
var Outcome: TWindowLayoutResult; Message: string;
begin
  Layout.AddWindow(1);
  Layout.Windows[0].Title := 'First'#13#10'Second';
  Layout.Windows[0].CaptureFails := True;
  Layout.Windows[0].CaptureReason := 'Access'#13#10'denied';
  Outcome := Layout.Save;
  AssertEquals('First  Second', Outcome.Failures[0].Description);
  AssertEquals('Access  denied', Outcome.Failures[0].Reason);
  Message := WindowLayoutMessage(Outcome);
  AssertEquals(1, Pos('Window layout saved:', Message));
  AssertTrue(Pos(LineEnding + '- First  Second: Access  denied', Message) > 0);
end;

procedure TWindowLayoutTests.NativeCaptureReportsInvalidHandle;
var Probe: TNativeLayoutProbe; Reason: string;
begin
  Probe := TNativeLayoutProbe.Create;
  try
    Reason := Probe.CaptureFailure(0);
    AssertTrue(Pos('Cannot identify the window', Reason) > 0);
    AssertTrue(Pos('1400', Reason) > 0);
  finally Probe.Free; end;
end;

procedure TWindowLayoutTests.NativeDescriptionsPreserveUnicode;
var Probe: TNativeLayoutProbe; Window: HWND; Title: UnicodeString; Text: string;
begin
  Probe := TNativeLayoutProbe.Create;
  Window := HiddenFixture;
  try
    Title := 'Editor ' + UnicodeString(WideChar($03A9));
    AssertTrue(SetWindowTextW(Window, PWideChar(Title)));
    Text := Probe.Description(Window);
    AssertTrue(Pos(UTF8Encode(Title), Text) > 0);
    AssertTrue(Pos('PID ' + IntToStr(GetCurrentProcessId), Text) > 0);
  finally Probe.Free; DestroyWindow(Window); end;
end;
initialization
  RegisterTest(TWindowLayoutTests);
end.
