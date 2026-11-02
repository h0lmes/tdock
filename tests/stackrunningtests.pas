unit stackrunningtests;

{$mode delphi}

interface

uses Windows, SysUtils, Math, fpcunit, testregistry, declu, gfx, GDIPAPI, attentionu, itemviewu, processhlp,
  customdrawitemu, customsubitemu, scsubitemu, scitemu, taskitemu, stackitemu, themeu;

type
  TCountShortcut = class(TShortcutSubitem)
  protected
    function ContainsWindow(Window: HWND): boolean; override;
  public
    AttentionWindow: HWND;
    procedure SetCachedWindows(Count: integer);
  end;

  TBadgeStack = class(TStackItem)
  protected
    function MotionNow: Double; override;
    function CreateSubitem: TCustomSubitem; override;
    function PaintDrawImage(Graphics, Attributes: Pointer; X, Y, Size: integer): boolean; override;
    function PresentDrawSurface(const Bitmap: _SimpleBitmap; Alpha: integer): boolean; override;
  public
    Now: Double;
    LastChild: TCountShortcut;
    Pixels: array of cardinal;
    procedure Render;
    function ColorCount(Color: cardinal): integer;
    function AnimationActive: boolean;
    function AnimationStartedAt: Double;
  end;

  TBadgeShortcut = class(TShortcutItem)
  protected
    function MotionNow: Double; override;
    function PaintDrawImage(Graphics, Attributes: Pointer; X, Y, Size: integer): boolean; override;
    function PresentDrawSurface(const Bitmap: _SimpleBitmap; Alpha: integer): boolean; override;
  public
    Now: Double;
    PixelWidth: integer;
    Pixels: array of cardinal;
    procedure SetCachedWindows(Count: integer);
    procedure BindWindows(const Windows: array of HWND);
    function ColorCount(Color: cardinal): integer;
    function AnimationActive: boolean;
    function AnimationProgress: Double;
  end;

  TBadgeTask = class(TTaskItem)
  protected
    function PaintDrawImage(Graphics, Attributes: Pointer; X, Y, Size: integer): boolean; override;
    function PresentDrawSurface(const Bitmap: _SimpleBitmap; Alpha: integer): boolean; override;
  public
    Pixels: array of cardinal;
    procedure SetCachedWindows(Count: integer);
    procedure BindWindows(const Windows: array of HWND);
    function ColorCount(Color: cardinal): integer;
  end;

  TStackRunningTests = class(TTestCase)
  private
    Stack: TBadgeStack;
    Shortcut: TBadgeShortcut;
    Task: TBadgeTask;
    FixtureTheme: TDTheme;
    FixtureDirectory: string;
    WindowA, WindowB: HWND;
    function AddChild(Count: integer): TCountShortcut;
    procedure SetThemeFile(const Name: string; Color: cardinal);
    procedure DrawItem(Item: TCustomDrawItem);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure OneWindowShowsBadge;
    procedure StackAddsAllChildWindows;
    procedure StackOmitsRunningBackground;
    procedure StackOmitsThemeIndicator;
    procedure BadgeDisappearsWhenLastWindowCloses;
    procedure SettingToggleRestoresUnchangedCount;
    procedure DisabledSettingSurvivesRunningRefresh;
    procedure NewChildInheritsDisabledSetting;
    procedure ChildSettingToggleRestoresUnchangedCount;
    procedure ShortcutOneWindowShowsBadge;
    procedure ShortcutMultipleWindowsShowBadge;
    procedure ShortcutEmptyShowsNoBadge;
    procedure ShortcutBadgeFollowsSetting;
    procedure ShortcutOmitsThemeDecorations;
    procedure TaskOneWindowShowsBadge;
    procedure TaskMultipleWindowsShowBadge;
    procedure TaskEmptyGroupShowsNoBadge;
    procedure TaskBadgeFollowsSetting;
    procedure TaskOmitsThemeDecorations;
    procedure AttentionBadgeHasSymmetricPlacementAndBlackText;
    procedure AttentionUsesSelectedAnimationAndSurvivesItsEnd;
    procedure AttentionWithoutAnimationAppearsImmediately;
    procedure ShortcutAttentionTracksIndividualWindows;
    procedure TaskAttentionTracksIndividualWindows;
    procedure AttentionStaysVisibleWithWindowBadgesDisabled;
    procedure ClosedWindowsClearAttention;
    procedure AttentionPollRemainsArmedUntilActivation;
    procedure StackCollectsAndClearsChildAttention;
    procedure RemovingChildClearsItsAttention;
    procedure DeletionClearsPendingAttention;
    procedure AttentionModelRejectsActiveAndInvalidWindows;
    procedure NativeWindowMappingSupportsAttentionWithBadgesDisabled;
    procedure AttentionSurvivesNativeViewReplacement;
    procedure RepeatedStackFlashDoesNotRestartAnimation;
    procedure AnotherStackChildStartsAnotherAnimation;
    procedure AcknowledgedWindowCanAnimateAgain;
  end;

implementation

function TCountShortcut.ContainsWindow(Window: HWND): boolean;
begin
  if AttentionWindow <> 0 then Result := Window = AttentionWindow
  else Result := inherited ContainsWindow(Window);
end;

procedure TCountShortcut.SetCachedWindows(Count: integer);
begin
  // Supply a process snapshot without starting external applications.
  FExecutable := '';
  FProcessWindowsCount := Count;
  cmd(icUpdateRunning, 0);
end;

function TBadgeStack.CreateSubitem: TCustomSubitem;
var Params: TDItemCreateParams;
begin
  Params := Default(TDItemCreateParams);
  Params.ItemSize := 48;
  LastChild := TCountShortcut.Create(Handle, Params);
  Result := LastChild;
end;

function TBadgeStack.PaintDrawImage(Graphics, Attributes: Pointer;
  X, Y, Size: integer): boolean;
begin Result := true; end;

function TBadgeStack.PresentDrawSurface(const Bitmap: _SimpleBitmap;
  Alpha: integer): boolean;
begin
  SetLength(Pixels, Bitmap.width * Bitmap.height);
  Move(Bitmap.BufferBits^, Pixels[0], Length(Pixels) * SizeOf(cardinal));
  Result := true;
end;

procedure TBadgeStack.Render;
begin Draw(-20000, -20000, 48, true, 0, 0); end;

function TBadgeStack.ColorCount(Color: cardinal): integer;
var Index: integer;
begin
  Result := 0;
  for Index := 0 to High(Pixels) do
    if Pixels[Index] = Color then Inc(Result);
end;

function TBadgeStack.AnimationActive: boolean;
begin Result := FIconAnimationActive; end;
function TBadgeStack.MotionNow: Double;
begin Result := Now; end;
function TBadgeStack.AnimationStartedAt: Double;
begin Result := FIconAnimation.StartedAt; end;

procedure TBadgeShortcut.SetCachedWindows(Count: integer);
var Index: integer;
begin
  FAppList.Clear;
  for Index := 1 to Count do FAppList.Add(Pointer(PtrUInt(Index)));
  FRunning := Count > 0;
end;

function TBadgeShortcut.PaintDrawImage(Graphics, Attributes: Pointer;
  X, Y, Size: integer): boolean;
begin Result := true; end;

function TBadgeShortcut.PresentDrawSurface(const Bitmap: _SimpleBitmap;
  Alpha: integer): boolean;
begin
  PixelWidth := Bitmap.width;
  SetLength(Pixels, Bitmap.width * Bitmap.height);
  Move(Bitmap.BufferBits^, Pixels[0], Length(Pixels) * SizeOf(cardinal));
  Result := true;
end;

function TBadgeShortcut.MotionNow: Double;
begin Result := Now; end;

procedure TBadgeShortcut.BindWindows(const Windows: array of HWND);
var Index: integer;
begin
  FAppList.Clear;
  for Index := 0 to High(Windows) do FAppList.Add(Pointer(Windows[Index]));
  FRunning := FAppList.Count > 0;
end;

function TBadgeShortcut.AnimationActive: boolean;
begin Result := FIconAnimationActive; end;
function TBadgeShortcut.AnimationProgress: Double;
begin Result := FAnimationProgress; end;

function TBadgeShortcut.ColorCount(Color: cardinal): integer;
var Index: integer;
begin
  Result := 0;
  for Index := 0 to High(Pixels) do
    if Pixels[Index] = Color then Inc(Result);
end;

procedure TBadgeTask.SetCachedWindows(Count: integer);
var Index: integer;
begin
  FAppList.Clear;
  for Index := 1 to Count do FAppList.Add(Pointer(PtrUInt(Index)));
end;

procedure TBadgeTask.BindWindows(const Windows: array of HWND);
var Index: integer;
begin
  FAppList.Clear;
  for Index := 0 to High(Windows) do FAppList.Add(Pointer(Windows[Index]));
end;

function TBadgeTask.PaintDrawImage(Graphics, Attributes: Pointer;
  X, Y, Size: integer): boolean;
begin Result := true; end;

function TBadgeTask.PresentDrawSurface(const Bitmap: _SimpleBitmap;
  Alpha: integer): boolean;
begin
  SetLength(Pixels, Bitmap.width * Bitmap.height);
  Move(Bitmap.BufferBits^, Pixels[0], Length(Pixels) * SizeOf(cardinal));
  Result := true;
end;

function TBadgeTask.ColorCount(Color: cardinal): integer;
var Index: integer;
begin
  Result := 0;
  for Index := 0 to High(Pixels) do
    if Pixels[Index] = Color then Inc(Result);
end;

procedure TStackRunningTests.SetUp;
var Params: TDItemCreateParams; Id: TGUID;
begin
  CreateGUID(Id);
  FixtureDirectory := ExtractFilePath(ParamStr(0)) + 'legacy-theme-' + GUIDToString(Id);
  AssertTrue('Create a theme fixture beside the test executable', CreateDir(FixtureDirectory));
  FixtureTheme := TDTheme(TDTheme.NewInstance);
  FixtureTheme.Path := IncludeTrailingPathDelimiter(FixtureDirectory);
  theme := FixtureTheme;
  Params := Default(TDItemCreateParams);
  Params.ItemSize := 48;
  Params.BigItemSize := 48;
  Params.Site := Ord(bsBottom);
  StrPLCopy(@Params.Font.Name[0], 'Segoe UI', High(Params.Font.Name));
  Params.Parameter := TStackItem.Make;
  Stack := TBadgeStack.Create(0, Params);
  Stack.Preview := 0;
  Stack.Update;
  Params.Parameter := TShortcutItem.Make('Badge fixture', '/probe');
  Shortcut := TBadgeShortcut.Create(0, Params);
  Task := TBadgeTask.Create(0, Params);
  WindowA := CreateWindowExW(WS_EX_TOOLWINDOW, 'STATIC', 'attention A', WS_POPUP,
    -20000, -20000, 10, 10, 0, 0, HInstance, nil);
  WindowB := CreateWindowExW(WS_EX_TOOLWINDOW, 'STATIC', 'attention B', WS_POPUP,
    -20000, -20000, 10, 10, 0, 0, HInstance, nil);
  AssertTrue((WindowA <> 0) and (WindowB <> 0));
end;

procedure TStackRunningTests.TearDown;
begin
  Stack.Free;
  Shortcut.Free;
  Task.Free;
  if WindowA <> 0 then DestroyWindow(WindowA);
  if WindowB <> 0 then DestroyWindow(WindowB);
  theme := nil;
  FixtureTheme.Free;
  DeleteFile(FixtureDirectory + '\button.png');
  DeleteFile(FixtureDirectory + '\indicator.png');
  RemoveDir(FixtureDirectory);
end;

function TStackRunningTests.AddChild(Count: integer): TCountShortcut;
begin
  AssertTrue(Stack.AddSubitem(TShortcutSubitem.Make('Count fixture', '/probe')));
  Result := Stack.LastChild;
  Result.SetCachedWindows(Count);
  Stack.cmd(icUpdateRunning, 0);
end;

procedure TStackRunningTests.SetThemeFile(const Name: string; Color: cardinal);
const PNGEncoder: TGUID = '{557CF406-1A04-11D3-9A73-0000F81EF32E}';
var Image, Graphics: Pointer; Filename: UnicodeString;
begin
  Image := nil;
  AssertEquals(Ord(Ok), Ord(GdipCreateBitmapFromScan0(8, 8, 0,
    PixelFormat32bppPARGB, nil, Image)));
  GdipGetImageGraphicsContext(Image, Graphics);
  try GdipGraphicsClear(Graphics, Color);
  finally GdipDeleteGraphics(Graphics); end;
  Filename := UnicodeString(IncludeTrailingPathDelimiter(FixtureDirectory) + Name);
  try AssertEquals(Ord(Ok), Ord(GdipSaveImageToFile(Image, PWideChar(Filename), @PNGEncoder, nil)));
  finally GdipDisposeImage(Image); end;
  FixtureTheme.ReloadGraphics;
end;

procedure TStackRunningTests.DrawItem(Item: TCustomDrawItem);
begin Item.Draw(-20000, -20000, 48, true, 0, 0); end;

procedure TStackRunningTests.OneWindowShowsBadge;
begin
  AddChild(1);
  Stack.Render;
  AssertTrue('One window must mark the stack as running', Stack.Running);
  AssertTrue('One window must draw the red badge', Stack.ColorCount($ffff0000) > 0);
end;

procedure TStackRunningTests.StackAddsAllChildWindows;
var OneWindowPixels: integer;
begin
  AddChild(1);
  Stack.Render;
  OneWindowPixels := Stack.ColorCount($ffff0000);
  AddChild(9);
  Stack.Render;
  AssertTrue('The total of ten windows must draw a wider badge',
    Stack.ColorCount($ffff0000) > OneWindowPixels);
end;

procedure TStackRunningTests.StackOmitsRunningBackground;
begin
  SetThemeFile('button.png', $ff00ff00);
  AddChild(1);
  Stack.Render;
  AssertEquals('Stacks must omit the theme running background', 0,
    Stack.ColorCount($ff00ff00));
  AssertTrue(Stack.ColorCount($ffff0000) > 0);
end;

procedure TStackRunningTests.StackOmitsThemeIndicator;
begin
  SetThemeFile('indicator.png', $ffff00ff);
  AddChild(1);
  Stack.Render;
  AssertEquals('Stacks must omit the theme running indicator', 0,
    Stack.ColorCount($ffff00ff));
  AssertTrue(Stack.ColorCount($ffff0000) > 0);
end;

procedure TStackRunningTests.BadgeDisappearsWhenLastWindowCloses;
var Child: TCountShortcut;
begin
  Child := AddChild(1);
  Child.SetCachedWindows(0);
  Stack.cmd(icUpdateRunning, 0);
  Stack.Render;
  AssertFalse(Stack.Running);
  AssertEquals(0, Stack.ColorCount($ffff0000));
end;

procedure TStackRunningTests.SettingToggleRestoresUnchangedCount;
begin
  AddChild(1);
  Stack.cmd(gpShowRunningIndicator, 0);
  Stack.Render;
  AssertFalse(Stack.Running);
  AssertEquals('Disabling must remove the badge immediately', 0,
    Stack.ColorCount($ffff0000));
  Stack.cmd(gpShowRunningIndicator, 1);
  AssertTrue('Enabling must restore the cached running status immediately', Stack.Running);
  Stack.Render;
  AssertTrue('The same window count must restore running status', Stack.Running);
  AssertTrue('Enabling must restore the badge', Stack.ColorCount($ffff0000) > 0);
  Stack.cmd(icUpdateRunning, 0);
  AssertTrue('Refreshing the same count must retain running status', Stack.Running);
end;

procedure TStackRunningTests.DisabledSettingSurvivesRunningRefresh;
begin
  Stack.cmd(gpShowRunningIndicator, 0);
  AddChild(2);
  Stack.Render;
  AssertFalse('A running refresh must respect the disabled setting', Stack.Running);
  AssertEquals(0, Stack.ColorCount($ffff0000));
  Stack.cmd(gpShowRunningIndicator, 1);
  Stack.Render;
  AssertTrue(Stack.Running);
  AssertTrue(Stack.ColorCount($ffff0000) > 0);
end;

procedure TStackRunningTests.NewChildInheritsDisabledSetting;
var Child: TCountShortcut;
begin
  Stack.cmd(gpShowRunningIndicator, 0);
  Child := AddChild(1);
  AssertFalse('New children must retain the disabled setting', Child.Running);
end;

procedure TStackRunningTests.ChildSettingToggleRestoresUnchangedCount;
var Child: TCountShortcut;
begin
  Child := AddChild(1);
  AssertTrue(Child.Running);
  Stack.cmd(gpShowRunningIndicator, 0);
  AssertFalse(Child.Running);
  Child.cmd(icUpdateRunning, 0);
  AssertFalse('Refreshing cannot re-enable a disabled child badge', Child.Running);
  Stack.cmd(gpShowRunningIndicator, 1);
  AssertTrue('The unchanged child count must restore running status', Child.Running);
end;

procedure TStackRunningTests.ShortcutOneWindowShowsBadge;
begin
  Shortcut.SetCachedWindows(1);
  DrawItem(Shortcut);
  AssertTrue('One shortcut window must draw a badge', Shortcut.ColorCount($ffff0000) > 0);
end;

procedure TStackRunningTests.ShortcutMultipleWindowsShowBadge;
var OneWindowPixels: integer;
begin
  Shortcut.SetCachedWindows(1);
  DrawItem(Shortcut);
  OneWindowPixels := Shortcut.ColorCount($ffff0000);
  Shortcut.SetCachedWindows(10);
  DrawItem(Shortcut);
  AssertTrue(Shortcut.ColorCount($ffff0000) > OneWindowPixels);
end;

procedure TStackRunningTests.ShortcutEmptyShowsNoBadge;
begin
  Shortcut.SetCachedWindows(0);
  DrawItem(Shortcut);
  AssertEquals(0, Shortcut.ColorCount($ffff0000));
end;

procedure TStackRunningTests.ShortcutBadgeFollowsSetting;
begin
  Shortcut.SetCachedWindows(2);
  Shortcut.cmd(gpShowRunningIndicator, 0);
  DrawItem(Shortcut);
  AssertEquals('Disabling must hide the shortcut badge', 0, Shortcut.ColorCount($ffff0000));
  Shortcut.cmd(gpShowRunningIndicator, 1);
  DrawItem(Shortcut);
  AssertTrue('Enabling must restore the unchanged count', Shortcut.ColorCount($ffff0000) > 0);
end;

procedure TStackRunningTests.ShortcutOmitsThemeDecorations;
begin
  SetThemeFile('button.png', $ff00ff00);
  Shortcut.SetCachedWindows(2);
  DrawItem(Shortcut);
  AssertEquals('Shortcuts must omit the running background', 0, Shortcut.ColorCount($ff00ff00));
  AssertTrue(Shortcut.ColorCount($ffff0000) > 0);
  DeleteFile(FixtureDirectory + '\button.png');
  SetThemeFile('indicator.png', $ffff00ff);
  DrawItem(Shortcut);
  AssertEquals('Shortcuts must omit the theme indicator', 0, Shortcut.ColorCount($ffff00ff));
end;

procedure TStackRunningTests.TaskOneWindowShowsBadge;
begin
  Task.SetCachedWindows(1);
  DrawItem(Task);
  AssertTrue('One task window must draw a badge', Task.ColorCount($ffff0000) > 0);
end;

procedure TStackRunningTests.TaskMultipleWindowsShowBadge;
var OneWindowPixels: integer;
begin
  Task.SetCachedWindows(1);
  DrawItem(Task);
  OneWindowPixels := Task.ColorCount($ffff0000);
  Task.SetCachedWindows(10);
  DrawItem(Task);
  AssertTrue(Task.ColorCount($ffff0000) > OneWindowPixels);
end;

procedure TStackRunningTests.TaskEmptyGroupShowsNoBadge;
begin
  Task.SetCachedWindows(0);
  DrawItem(Task);
  AssertEquals(0, Task.ColorCount($ffff0000));
end;

procedure TStackRunningTests.TaskBadgeFollowsSetting;
begin
  Task.SetCachedWindows(2);
  Task.cmd(gpShowRunningIndicator, 0);
  DrawItem(Task);
  AssertEquals('Disabling must hide the task badge', 0, Task.ColorCount($ffff0000));
  Task.cmd(gpShowRunningIndicator, 1);
  DrawItem(Task);
  AssertTrue('Enabling must restore the unchanged count', Task.ColorCount($ffff0000) > 0);
end;

procedure TStackRunningTests.TaskOmitsThemeDecorations;
begin
  SetThemeFile('button.png', $ff00ff00);
  Task.SetCachedWindows(2);
  DrawItem(Task);
  AssertEquals('Tasks must omit the running background', 0, Task.ColorCount($ff00ff00));
  AssertTrue(Task.ColorCount($ffff0000) > 0);
  DeleteFile(FixtureDirectory + '\button.png');
  SetThemeFile('indicator.png', $ffff00ff);
  DrawItem(Task);
  AssertEquals('Tasks must omit the theme indicator', 0, Task.ColorCount($ffff00ff));
end;

function ColorBounds(const Pixels: array of cardinal; Width: integer;
  Color: cardinal): Windows.TRect;
var Index, X, Y: integer;
begin
  Result.Left := MaxInt;
  Result.Top := MaxInt;
  Result.Right := 0;
  Result.Bottom := 0;
  for Index := 0 to High(Pixels) do
    if Pixels[Index] = Color then
    begin
      X := Index mod Width; Y := Index div Width;
      Result.Left := Min(Result.Left, X);
      Result.Top := Min(Result.Top, Y);
      Result.Right := Max(Result.Right, X + 1);
      Result.Bottom := Max(Result.Bottom, Y + 1);
    end;
end;

procedure SaveBadgePreview(const Pixels: array of cardinal; Width: integer);
const PNGEncoder: TGUID = '{557CF406-1A04-11D3-9A73-0000F81EF32E}';
var Bitmap: Pointer; Filename: UnicodeString;
begin
  Bitmap := nil;
  if GdipCreateBitmapFromScan0(Width, Length(Pixels) div Width, Width * 4,
    PixelFormat32bppPARGB, @Pixels[0], Bitmap) <> Ok then Exit;
  try
    Filename := UnicodeString(ExtractFilePath(ParamStr(0)) + 'attention-badges.png');
    GdipSaveImageToFile(Bitmap, PWideChar(Filename), @PNGEncoder, nil);
  finally GdipDisposeImage(Bitmap); end;
end;

procedure TStackRunningTests.AttentionBadgeHasSymmetricPlacementAndBlackText;
var Amber, Red, Black: Windows.TRect;
begin
  Shortcut.BindWindows([WindowA]);
  Shortcut.cmd(icFlashTaskWindow, WindowA);
  DrawItem(Shortcut);
  AssertTrue(Shortcut.ColorCount(ATTENTION_BADGE_COLOR) > 0);
  AssertTrue(Shortcut.ColorCount($ffff0000) > 0);
  AssertTrue('The exclamation mark must contain solid black pixels', Shortcut.ColorCount($ff000000) > 0);
  Amber := ColorBounds(Shortcut.Pixels, Shortcut.PixelWidth, ATTENTION_BADGE_COLOR);
  Red := ColorBounds(Shortcut.Pixels, Shortcut.PixelWidth, $ffff0000);
  Black := ColorBounds(Shortcut.Pixels, Shortcut.PixelWidth, $ff000000);
  AssertEquals('Both badges must share their top edge', Red.Top, Amber.Top);
  AssertEquals(Red.Bottom, Amber.Bottom);
  AssertEquals(Red.Right - Red.Left, Amber.Right - Amber.Left);
  AssertEquals('Badge centers must mirror around the icon center',
    Shortcut.PixelWidth * 2, Amber.Left + Amber.Right + Red.Left + Red.Right);
  AssertTrue((Black.Left >= Amber.Left) and (Black.Right <= Amber.Right) and
    (Black.Top >= Amber.Top) and (Black.Bottom <= Amber.Bottom));
  SaveBadgePreview(Shortcut.Pixels, Shortcut.PixelWidth);
end;

procedure TStackRunningTests.AttentionUsesSelectedAnimationAndSurvivesItsEnd;
begin
  Shortcut.BindWindows([WindowA]);
  Shortcut.Now := 1000;
  Shortcut.cmd(gpItemAnimationType, 8);
  DrawItem(Shortcut);
  Shortcut.cmd(icFlashTaskWindow, WindowA);
  AssertTrue('Attention must start the selected animation', Shortcut.AnimationActive);
  Shortcut.Now := 1010;
  Shortcut.Timer;
  AssertTrue(Shortcut.AnimationProgress > 0);
  Shortcut.Now := 4000;
  Shortcut.Timer;
  AssertFalse(Shortcut.AnimationActive);
  AssertTrue('Animation completion must retain the attention badge', Shortcut.AttentionPending);
  DrawItem(Shortcut);
  AssertTrue(Shortcut.ColorCount(ATTENTION_BADGE_COLOR) > 0);
end;

procedure TStackRunningTests.AttentionWithoutAnimationAppearsImmediately;
begin
  Shortcut.BindWindows([WindowA]);
  Shortcut.cmd(gpItemAnimationType, 0);
  DrawItem(Shortcut);
  AssertEquals(0, Shortcut.ColorCount(ATTENTION_BADGE_COLOR));
  Shortcut.cmd(icFlashTaskWindow, WindowA);
  AssertFalse(Shortcut.AnimationActive);
  AssertTrue('None must still repaint the attention badge immediately',
    Shortcut.ColorCount(ATTENTION_BADGE_COLOR) > 0);
end;

procedure TStackRunningTests.ShortcutAttentionTracksIndividualWindows;
begin
  Shortcut.BindWindows([WindowA, WindowB]);
  Shortcut.cmd(icFlashTaskWindow, WindowA);
  Shortcut.ForegroundChanged(WindowB);
  AssertTrue('A different grouped window cannot acknowledge attention', Shortcut.AttentionPending);
  Shortcut.cmd(icFlashTaskWindow, WindowB);
  Shortcut.ForegroundChanged(WindowA);
  AssertTrue('The other requesting window still needs attention', Shortcut.AttentionPending);
  Shortcut.ForegroundChanged(WindowB);
  AssertFalse('Foreground activation must clear the final request', Shortcut.AttentionPending);
  DrawItem(Shortcut);
  AssertEquals(0, Shortcut.ColorCount(ATTENTION_BADGE_COLOR));
end;

procedure TStackRunningTests.TaskAttentionTracksIndividualWindows;
begin
  Task.BindWindows([WindowA, WindowB]);
  Task.cmd(icFlashTaskWindow, WindowA);
  Task.ForegroundChanged(WindowB);
  AssertTrue(Task.AttentionPending);
  Task.cmd(icFlashTaskWindow, WindowB);
  Task.ForegroundChanged(WindowA);
  AssertTrue(Task.AttentionPending);
  Task.ForegroundChanged(WindowB);
  AssertFalse(Task.AttentionPending);
end;

procedure TStackRunningTests.AttentionStaysVisibleWithWindowBadgesDisabled;
begin
  Shortcut.BindWindows([WindowA]);
  Task.BindWindows([WindowB]);
  Shortcut.cmd(gpShowRunningIndicator, 0);
  Task.cmd(gpShowRunningIndicator, 0);
  Shortcut.cmd(icFlashTaskWindow, WindowA);
  Task.cmd(icFlashTaskWindow, WindowB);
  DrawItem(Shortcut);
  DrawItem(Task);
  AssertEquals(0, Shortcut.ColorCount($ffff0000));
  AssertEquals(0, Task.ColorCount($ffff0000));
  AssertTrue(Shortcut.ColorCount(ATTENTION_BADGE_COLOR) > 0);
  AssertTrue(Task.ColorCount(ATTENTION_BADGE_COLOR) > 0);
end;

procedure TStackRunningTests.ClosedWindowsClearAttention;
begin
  Shortcut.BindWindows([WindowA]);
  Shortcut.cmd(icFlashTaskWindow, WindowA);
  AssertTrue(Shortcut.AttentionPending);
  DestroyWindow(WindowA);
  WindowA := 0;
  Shortcut.ForegroundChanged(0);
  AssertFalse(Shortcut.AttentionPending);
end;

procedure TStackRunningTests.AttentionPollRemainsArmedUntilActivation;
begin
  Shortcut.BindWindows([WindowA]);
  Shortcut.cmd(icFlashTaskWindow, WindowA);
  AssertTrue(ItemViews.ConsumeItemTimer(Shortcut.ItemId, ID_TIMER_WINDOWACTIVATED, GetTickCount64 + 2000));
  Shortcut.ForegroundChanged(0);
  AssertTrue('An unacknowledged request must retain its fallback timer',
    ItemViews.ConsumeItemTimer(Shortcut.ItemId, ID_TIMER_WINDOWACTIVATED, GetTickCount64 + 2000));
  Shortcut.ForegroundChanged(WindowA);
  AssertFalse(ItemViews.ConsumeItemTimer(Shortcut.ItemId, ID_TIMER_WINDOWACTIVATED, GetTickCount64 + 2000));
end;

procedure TStackRunningTests.StackCollectsAndClearsChildAttention;
var First, Second: TCountShortcut;
begin
  First := AddChild(1);
  First.AttentionWindow := WindowA;
  Second := AddChild(1);
  Second.AttentionWindow := WindowB;
  Stack.cmd(gpShowRunningIndicator, 0);
  Stack.cmd(gpItemAnimationType, 5);
  Stack.cmd(icFlashTaskWindow, WindowA);
  AssertTrue(First.AttentionPending);
  AssertTrue(Stack.AttentionPending);
  AssertTrue(Stack.AnimationActive);
  Stack.ForegroundChanged(WindowB);
  AssertTrue(Stack.AttentionPending);
  Stack.cmd(icFlashTaskWindow, WindowB);
  Stack.ForegroundChanged(WindowA);
  AssertFalse(First.AttentionPending);
  AssertTrue(Second.AttentionPending);
  AssertTrue(Stack.AttentionPending);
  Stack.Render;
  AssertEquals(0, Stack.ColorCount($ffff0000));
  AssertTrue(Stack.ColorCount(ATTENTION_BADGE_COLOR) > 0);
  Stack.ForegroundChanged(WindowB);
  AssertFalse(Stack.AttentionPending);
  AssertFalse(Second.AttentionPending);
end;

procedure TStackRunningTests.RemovingChildClearsItsAttention;
var Child: TCountShortcut;
begin
  Child := AddChild(1);
  Child.AttentionWindow := WindowA;
  AddChild(0);
  Stack.cmd(icFlashTaskWindow, WindowA);
  AssertTrue(Stack.AttentionPending);
  Stack.DeleteSubitem(0);
  AssertFalse(Stack.AttentionPending);
end;

procedure TStackRunningTests.DeletionClearsPendingAttention;
begin
  Shortcut.BindWindows([WindowA]);
  Shortcut.cmd(icFlashTaskWindow, WindowA);
  Shortcut.PrepareDeletion;
  AssertFalse(Shortcut.AttentionPending);
  Shortcut.ForegroundChanged(0);
  AssertFalse('Deletion must discard the pending window identities', Shortcut.AttentionPending);
end;

procedure TStackRunningTests.AttentionModelRejectsActiveAndInvalidWindows;
var Attention: TAttentionWindows;
begin
  Attention := Default(TAttentionWindows);
  AssertFalse(Attention.Request(0, 0));
  AssertFalse(Attention.Request(WindowA, WindowA));
  AssertFalse(Attention.Active);
  AssertTrue(Attention.Request(WindowA, 0));
  AssertFalse('An existing pending request must not become a new event', Attention.Request(WindowA, 0));
  Attention.Observe(WindowA);
  AssertFalse('Repeated requests for one window must acknowledge together', Attention.Active);
end;

procedure TStackRunningTests.NativeWindowMappingSupportsAttentionWithBadgesDisabled;
var PreviousHelper: TProcessHelper; Child: TCountShortcut;
begin
  PreviousHelper := ProcessHelper;
  ProcessHelper := TProcessHelper.Create;
  try
    SetWindowLongPtr(WindowA, GWL_EXSTYLE, WS_EX_APPWINDOW or WS_EX_TOOLWINDOW or WS_EX_NOACTIVATE);
    ShowWindow(WindowA, SW_SHOWNOACTIVATE);
    ProcessHelper.EnumProc;
    ProcessHelper.EnumAppWindows;
    Shortcut.Command := ParamStr(0);
    Shortcut.Update;
    Child := AddChild(0);
    Child.FromString(TShortcutSubitem.Make('Native attention', ParamStr(0)));
    Shortcut.cmd(gpShowRunningIndicator, 0);
    Stack.cmd(gpShowRunningIndicator, 0);
    Shortcut.cmd(icUpdateRunning, 0);
    Stack.cmd(icUpdateRunning, 0);
    Shortcut.cmd(icFlashTaskWindow, WindowA);
    Stack.cmd(icFlashTaskWindow, WindowA);
    AssertTrue('A pinned shortcut must match a real process window', Shortcut.AttentionPending);
    AssertTrue('A stack child must match the same real process window', Child.AttentionPending);
    AssertTrue(Stack.AttentionPending);
    Shortcut.ForegroundChanged(WindowA);
    Stack.ForegroundChanged(WindowA);
    AssertFalse(Shortcut.AttentionPending);
    AssertFalse(Stack.AttentionPending);
  finally
    ProcessHelper.Free;
    ProcessHelper := PreviousHelper;
  end;
end;

procedure TStackRunningTests.AttentionSurvivesNativeViewReplacement;
var PreviousWindow: HWND;
begin
  Shortcut.BindWindows([WindowA]);
  Shortcut.cmd(icFlashTaskWindow, WindowA);
  PreviousWindow := Shortcut.Handle;
  Shortcut.RecreateWindow;
  AssertTrue(Shortcut.Handle <> PreviousWindow);
  AssertTrue(Shortcut.AttentionPending);
  AssertTrue(ItemViews.ConsumeItemTimer(Shortcut.ItemId, ID_TIMER_WINDOWACTIVATED, GetTickCount64 + 2000));
  Shortcut.ForegroundChanged(WindowA);
  AssertFalse(Shortcut.AttentionPending);
end;

procedure TStackRunningTests.RepeatedStackFlashDoesNotRestartAnimation;
var Child: TCountShortcut; RepeatIndex: integer;
begin
  Child := AddChild(1);
  Child.AttentionWindow := WindowA;
  Stack.cmd(gpItemAnimationType, 4);
  Stack.Now := 1000;
  AssertEquals(1, Stack.cmd(icFlashTaskWindow, WindowA));
  AssertTrue(Stack.AnimationActive);
  for RepeatIndex := 1 to 4 do
  begin
    Stack.Now := 1000 + RepeatIndex * 2000;
    Stack.Timer;
    AssertFalse(Stack.AnimationActive);
    AssertEquals('Each repeated flash must report no new attention', 0,
      Stack.cmd(icFlashTaskWindow, WindowA));
    AssertFalse('Four repeat notifications must not start four more bounce sequences', Stack.AnimationActive);
    AssertTrue('The badge must remain visible', Stack.AttentionPending);
  end;
end;

procedure TStackRunningTests.AnotherStackChildStartsAnotherAnimation;
var First, Second: TCountShortcut;
begin
  First := AddChild(1);
  First.AttentionWindow := WindowA;
  Second := AddChild(1);
  Second.AttentionWindow := WindowB;
  Stack.cmd(gpItemAnimationType, 4);
  Stack.Now := 1000;
  AssertEquals(1, Stack.cmd(icFlashTaskWindow, WindowA));
  Stack.Now := 1200;
  Stack.Timer;
  AssertEquals(0, Stack.cmd(icFlashTaskWindow, WindowA));
  AssertEquals('A duplicate cannot reset the active animation clock', 1000.0, Stack.AnimationStartedAt, 0.001);
  Stack.Now := 1500;
  AssertEquals('Another child must report new attention', 1, Stack.cmd(icFlashTaskWindow, WindowB));
  AssertEquals('Another child must restart the animation clock', 1500.0, Stack.AnimationStartedAt, 0.001);
  AssertTrue(First.AttentionPending and Second.AttentionPending);
end;

procedure TStackRunningTests.AcknowledgedWindowCanAnimateAgain;
var Child: TCountShortcut;
begin
  Child := AddChild(1);
  Child.AttentionWindow := WindowA;
  Stack.cmd(gpItemAnimationType, 4);
  Stack.Now := 1000;
  AssertEquals(1, Stack.cmd(icFlashTaskWindow, WindowA));
  Stack.ForegroundChanged(WindowA);
  AssertFalse(Stack.AttentionPending);
  Stack.Now := 3000;
  Stack.Timer;
  AssertFalse(Stack.AnimationActive);
  Stack.Now := 4000;
  AssertEquals('Activation must permit a later attention request', 1, Stack.cmd(icFlashTaskWindow, WindowA));
  AssertTrue(Stack.AnimationActive);
  AssertEquals(4000.0, Stack.AnimationStartedAt, 0.001);
end;

initialization
  RegisterTest(TStackRunningTests);
end.
