unit serializationtests;

{$mode delphi}

interface

uses Windows, Classes, SysUtils, IniFiles, Forms, fpcunit, testregistry,
  declu, docksettingsu, settingsschemau, settingscoordinatoru, setsu,
  itemserializationu, itemfactoryu, scitemu, sepitemu, stackitemu, taskitemu,
  iniproc, gfx, stackmodeu;

type
  TSerializationTests = class(TTestCase)
  private
    Filename, SavedName: string;
    LastOld, LastNew: integer;
    procedure CaptureChange(const Change: TDockSettingChange);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure SettingsKeepLegacyKeysAndUnknownValues;
    procedure SettingsLoadBoundsEveryTextBuffer;
    procedure AllStoredParametersUseTheSchema;
    procedure LoadAndLiveUpdatesUseTheSameLimits;
    procedure FontValidationMatchesReload;
    procedure MouseLockBypassesPersistentSettings;
    procedure UnsupportedDtoVersionCannotWrite;
    procedure ShortcutGoldenTextKeepsLegacySyntax;
    procedure ShortcutRoundTripsEveryField;
    procedure SecondaryOnlyImageSurvivesIni;
    procedure StackSortedSurvivesTextAndIni;
    procedure StackSourcesUseTheSameLimits;
    procedure SparseStackKeysPreserveChildren;
    procedure ExcessStackChildrenFailBeforeCreation;
    procedure ChildTypeMustBeShortcut;
    procedure LegacyTextRejectsLossyValues;
    procedure FieldNamesInsideValuesCannotSelectFields;
    procedure MissingClassDefaultsToShortcut;
    procedure LongIniValuesAreNotTruncated;
    procedure MalformedIniNumbersUseDefaults;
    procedure IniBooleanConversionUsesValues;
    procedure ProfileWriteFailureIsReported;
    procedure RegistrySelectsEveryBuiltInType;
    procedure RegistryRejectsDuplicateTypes;
    procedure UnknownTypesRemainUnregistered;
    procedure StackControllerRejectsInvalidModeSafely;
    procedure InvalidIniExportPreservesExistingSection;
    procedure InvalidSettingsExportPreservesExistingFile;
    procedure RegistryPrefersSpecificClasses;
  end;

implementation

type TSpecificShortcut = class(TShortcutItem);

procedure TSerializationTests.SetUp;
var Id: TGUID;
begin
  CreateGUID(Id);
  Filename := ExtractFilePath(ParamStr(0)) + 'schema-' + GUIDToString(Id) + '.ini';
  SavedName := Filename + '.saved.ini';
end;

procedure TSerializationTests.TearDown;
begin
  DeleteFile(Filename);
  DeleteFile(SavedName);
end;

procedure TSerializationTests.CaptureChange(const Change: TDockSettingChange);
begin
  LastOld := Change.OldValue;
  LastNew := Change.NewValue;
end;

procedure TSerializationTests.SettingsKeepLegacyKeysAndUnknownValues;
const Fixture: string =
  '[base]'#13#10'Theme=Legacy theme'#13#10'Monitor=0'#13#10'Site=right'#13#10+
  'CenterOffsetPercent=37'#13#10'EdgeOffset=-12'#13#10'OccupyFullMonitor=1'#13#10+
  'StartOffset=17'#13#10'EndOffset=23'#13#10'Shell=explorer.exe'#13#10+
  'AutoHide=1'#13#10'AutoHideTime=935'#13#10'AutoShowTime=263'#13#10+
  'AutoHidePixels=7'#13#10'LaunchInterval=650'#13#10'ActivateRunning=0'#13#10+
  'ShowRunningIndicator=0'#13#10'ItemAnimation=7'#13#10'ItemSize=64'#13#10+
  'BigItemSize=112'#13#10'ItemSpacing=11'#13#10'ZoomWidth=8'#13#10'ZoomTime=230'#13#10+
  'GlobalHotkeyFlag_Hide=1'#13#10'GlobalHotkeyValue_Hide=16507'#13#10+
  'GlobalHotkeyFlag_Console=1'#13#10'GlobalHotkeyValue_Console=16508'#13#10+
  'AutoHideOnFullScreenApp=0'#13#10'UseShell=1'#13#10'RunInThread=1'#13#10+
  'ZoomItems=0'#13#10'LaunchInThread=0'#13#10'ActivateOnMouse=0'#13#10+
  'ActivateOnMouseInterval=305'#13#10'CloseCmdWindow=0'#13#10'HideTaskBar=1'#13#10+
  'ReserveScreenEdge=1'#13#10'ReserveScreenEdgePercent=87'#13#10'AeroPeekEnabled=0'#13#10+
  'Taskbar=1'#13#10'TaskbarLivePreviews=0'#13#10'TaskThumbSize=275'#13#10+
  'TaskbarGrouping=0'#13#10'TaskbarSameMonitor=1'#13#10'TaskSystemMenus=1'#13#10+
  'TaskSpot=4'#13#10'StayOnTop=1'#13#10'LockDragging=0'#13#10'ShowHint=0'#13#10+
  'HintEffects=1'#13#10'UseShellContextMenus=0'#13#10'StackOpenAnimation=0'#13#10+
  'Hello=0'#13#10'FutureOption=preserve me'#13#10+
  '[gfx]'#13#10'BaseAlpha=137'#13#10'SeparatorAlpha=91'#13#10'Reflection=0'#13#10+
  'ReflectionSize=13'#13#10'Blur=0'#13#10+
  '[Font]'#13#10'name=Segoe UI'#13#10'size=21'#13#10'size2=19'#13#10+
  'color=-16711936'#13#10'backcolor=-14671840'#13#10'bold=0'#13#10'italic=1'#13#10+
  '[autorun]'#13#10'command0="explorer.exe /test"'#13#10+
  '[future]'#13#10'value=keep this too'#13#10;
var Lines, Sections, Names: TStringList; Original, Saved: TIniFile;
  Store, Reloaded: TDSets; Section, Name: string;
begin
  Lines := TStringList.Create;
  Sections := TStringList.Create;
  Names := TStringList.Create;
  Store := TDSets.Create(Filename, '', 0);
  Reloaded := TDSets.Create(SavedName, '', 0);
  try
    Lines.Text := Fixture;
    Lines.SaveToFile(Filename);
    Store.Load;
    Store.SaveTo(SavedName);
    Reloaded.Load;
    AssertTrue('Every settings value survives reload',
      CompareMem(@Store.container, @Reloaded.container, SizeOf(TDockSettings)));
    AssertEquals(64, Store.container.DropDistance);
    AssertEquals('explorer.exe /test', Reloaded.AutoRunList[0]);
    Original := TIniFile.Create(Filename);
    Saved := TIniFile.Create(SavedName);
    try
      Original.ReadSections(Sections);
      for Section in Sections do
      begin
        Names.Clear;
        Original.ReadSection(Section, Names);
        for Name in Names do
          AssertEquals(Section + '.' + Name, Original.ReadString(Section, Name, ''),
            Saved.ReadString(Section, Name, 'MISSING'));
      end;
      AssertFalse(Saved.ValueExists('base', 'SchemaVersion'));
      AssertFalse(Saved.ValueExists('base', 'DropDistance'));
    finally Saved.Free; Original.Free; end;
  finally Reloaded.Free; Store.Free; Names.Free; Sections.Free; Lines.Free; end;
end;

procedure TSerializationTests.SettingsLoadBoundsEveryTextBuffer;
var Ini: TIniFile; Store: TDSets;
begin
  Ini := TIniFile.Create(Filename);
  try
    Ini.WriteString('base', 'Theme', StringOfChar('t', 2000));
    Ini.WriteString('base', 'Shell', StringOfChar('s', 2000));
    Ini.WriteString('Font', 'name', StringOfChar('f', 2000));
    Ini.WriteInteger('Font', 'size', 21);
    Ini.WriteInteger('base', 'EndOffset', 37);
  finally Ini.Free; end;
  Store := TDSets.Create(Filename, '', 0);
  try
    Store.Load;
    AssertEquals(MAX_PATH, Length(StrPas(Store.container.ThemeName)));
    AssertEquals(MAX_PATH, Length(StrPas(Store.container.Shell)));
    AssertEquals(255, Length(StrPas(Store.container.Font.Name)));
    AssertEquals(21, Store.container.Font.Size);
    AssertEquals(37, Store.container.EndOffset);
  finally Store.Free; end;
end;

procedure TSerializationTests.AllStoredParametersUseTheSchema;
var Store: TDSets; Key: TDParam; Count: integer; Actual: PtrInt;
begin
  Store := TDSets.Create('', '', 0);
  try
    Count := 0;
    for Key := gpMonitor to gpTaskSpot do
      if not (Key in [gpActivateRunningApps, gpLockMouseEffect]) then
      begin
        AssertTrue(IsStoredDockParam(Key));
        Actual := Store.StoreParam(Key, 1);
        AssertEquals(Int64(Actual), Int64(Store.GetParam(Key)));
        Inc(Count);
      end;
    AssertEquals(55, Count);
    AssertFalse(IsStoredDockParam(gpLockMouseEffect));
    AssertFalse(IsStoredDockParam(gpActivateRunningApps));
  finally Store.Free; end;
end;

procedure TSerializationTests.LoadAndLiveUpdatesUseTheSameLimits;
var Ini: TIniFile; Store: TDSets; Expected: TDockSettings;
begin
  Store := TDSets.Create(Filename, '', 0);
  try
    Store.StoreParam(gpAutoHideTime, -2);
    Store.StoreParam(gpAutoShowTime, 100000);
    Store.StoreParam(gpAutoHidePixels, -3);
    Store.StoreParam(gpItemAnimationType, 99);
    Store.StoreParam(gpZoomWidth, 5);
    Expected := Store.container;
    Ini := TIniFile.Create(Filename);
    try
      Ini.WriteInteger('base', 'AutoHideTime', -2);
      Ini.WriteInteger('base', 'AutoShowTime', 100000);
      Ini.WriteInteger('base', 'AutoHidePixels', -3);
      Ini.WriteInteger('base', 'ItemAnimation', 99);
      Ini.WriteInteger('base', 'ZoomWidth', 5);
    finally Ini.Free; end;
    Store.Load;
    AssertEquals(Expected.AutoHideTime, Store.container.AutoHideTime);
    AssertEquals(Expected.AutoShowTime, Store.container.AutoShowTime);
    AssertEquals(Expected.AutoHidePixels, Store.container.AutoHidePixels);
    AssertEquals(Expected.ItemAnimationType, Store.container.ItemAnimationType);
    AssertEquals(Expected.ZoomWidth, Store.container.ZoomWidth);
    Store.StoreSetsContainer;
    Store.StoreParam(gpDropDistance, 75);
    Store.RestoreSetsContainer;
    Expected := Store.container;
    NormalizeDockSettings(Store.container, Screen.MonitorCount);
    AssertEquals(Expected.DropDistance, Store.container.DropDistance);
  finally Store.Free; end;
end;

procedure TSerializationTests.FontValidationMatchesReload;
var Store: TDSets; Coordinator: TSettingsCoordinator; Font: TDFontData;
begin
  Store := TDSets.Create(Filename, '', 0);
  Coordinator := TSettingsCoordinator.Create(Store);
  try
    Font := Store.container.Font;
    Font.Size := 3; Font.Size2 := 100;
    Coordinator.SetFont(Font);
    AssertEquals(6, Store.container.Font.Size);
    AssertEquals(72, Store.container.Font.Size2);
    Store.SaveTo(Filename);
    Store.Load;
    AssertEquals(6, Store.container.Font.Size);
    AssertEquals(72, Store.container.Font.Size2);
  finally Coordinator.Free; Store.Free; end;
end;

procedure TSerializationTests.MouseLockBypassesPersistentSettings;
var Store: TDSets; Coordinator: TSettingsCoordinator; Before: TDockSettings;
begin
  Store := TDSets.Create('', '', 0);
  Coordinator := TSettingsCoordinator.Create(Store);
  try
    Before := Store.container;
    Coordinator.OnNotifyItems := CaptureChange;
    Coordinator.Apply(gpLockMouseEffect, 1);
    AssertEquals(0, LastOld); AssertEquals(1, LastNew);
    Coordinator.Apply(gpLockMouseEffect, 0);
    AssertEquals(1, LastOld); AssertEquals(0, LastNew);
    AssertTrue(CompareMem(@Before, @Store.container, SizeOf(Before)));
  finally Coordinator.Free; Store.Free; end;
end;

procedure TSerializationTests.UnsupportedDtoVersionCannotWrite;
var Ini: TIniFile; Data: TDockSettingsDtoV1; Rejected: boolean;
begin
  Data := Default(TDockSettingsDtoV1);
  Data.Version := 999;
  Ini := TIniFile.Create(Filename);
  try
    Rejected := False;
    try WriteLegacySettings(Ini, Data); except on EConvertError do Rejected := True; end;
    AssertTrue(Rejected);
    AssertFalse(Ini.ValueExists('base', 'Theme'));
  finally Ini.Free; end;
end;

procedure TSerializationTests.ShortcutGoldenTextKeepsLegacySyntax;
var Data: TShortcutDtoV1;
begin
  Data := DefaultShortcutDto;
  Data.Caption := 'Test'; Data.Command := '%pp%\run.exe';
  Data.Params := '--test'; Data.Directory := '%pp%'; Data.Image := 'a.png;b.png';
  Data.ShowCmd := 3; Data.ColorData := $12345678; Data.Hide := True;
  AssertEquals('class="shortcut";caption="Test";command="%pp%\run.exe";' +
    'params="--test";dir="%pp%";image="a.png;b.png";showcmd="3";' +
    'color_data="$12345678";hide="1";', WriteShortcutText(Data));
end;

procedure TSerializationTests.ShortcutRoundTripsEveryField;
var A, B, C: TShortcutDtoV1; Text: string;
begin
  A := ReadShortcutText('class="shortcut";caption="Quoted "name"";command="x.exe";' +
    'params="--name="value"";dir="%pp%";image="a.png;b.png";' +
    'showcmd="2";color_data="$FF00FF00";hide="1";');
  Text := WriteShortcutText(A);
  B := ReadShortcutText(Text);
  WriteShortcutIni(Filename, 'item1', B);
  C := ReadShortcutIni(Filename, 'item1');
  AssertEquals(Text, WriteShortcutText(C));
  AssertEquals(Int64(-16711936), Int64(C.ColorData));
end;

procedure TSerializationTests.SecondaryOnlyImageSurvivesIni;
var A, B: TShortcutDtoV1;
begin
  A := DefaultShortcutDto; A.Image := ';secondary.png';
  WriteShortcutIni(Filename, 'item1', A);
  B := ReadShortcutIni(Filename, 'item1');
  AssertEquals(A.Image, B.Image);
end;

procedure TSerializationTests.StackSortedSurvivesTextAndIni;
var A, B: TStackDtoV1; Text: string;
begin
  A := DefaultStackDto;
  A.Caption := 'Sorted'; A.Image := 'stack.png'; A.Mode := 3; A.Offset := -12;
  A.AnimationSpeed := 17; A.Distort := -4; A.Preview := 2;
  A.Background := True; A.Sorted := True; A.ColorData := $12345678;
  Text := WriteStackText(A);
  B := ReadStackText(Text);
  AssertTrue(B.Sorted);
  WriteStackIni(Filename, 'item1', B);
  B := ReadStackIni(Filename, 'item1');
  AssertEquals(Text, WriteStackText(B));
end;

procedure TSerializationTests.StackSourcesUseTheSameLimits;
var A, B: TStackDtoV1;
begin
  WriteIniStringW(Filename, 'item1', 'mode', '99');
  WriteIniStringW(Filename, 'item1', 'animation_speed', '-10');
  WriteIniStringW(Filename, 'item1', 'offset', '999');
  WriteIniStringW(Filename, 'item1', 'distort', '-99');
  WriteIniStringW(Filename, 'item1', 'preview', '99');
  A := ReadStackIni(Filename, 'item1');
  B := ReadStackText('class="stack";mode="99";animation_speed="-10";' +
    'offset="999";distort="-99";preview="99";');
  AssertEquals(WriteStackText(A), WriteStackText(B));
  AssertEquals(9, A.Mode); AssertEquals(1, A.AnimationSpeed);
  AssertEquals(100, A.Offset); AssertEquals(-10, A.Distort); AssertEquals(2, A.Preview);
end;

procedure TSerializationTests.SparseStackKeysPreserveChildren;
var Children: TStringList;
begin
  WriteIniStringW(Filename, 'item1', 'subitem1', 'class="shortcut";caption="First";');
  WriteIniStringW(Filename, 'item1', 'subitem3', 'class="shortcut";caption="Third";');
  Children := ReadStackChildren(Filename, 'item1', '');
  try AssertEquals(2, Children.Count); AssertTrue(Pos('Third', Children[1]) > 0);
  finally Children.Free; end;
end;

procedure TSerializationTests.ExcessStackChildrenFailBeforeCreation;
var Children: TStringList; Rejected: boolean;
begin
  WriteIniStringW(Filename, 'item1', 'subitem65', 'class="shortcut";');
  Rejected := False;
  try Children := ReadStackChildren(Filename, 'item1', ''); Children.Free;
  except on ERangeError do Rejected := True; end;
  AssertTrue(Rejected);
end;

procedure TSerializationTests.ChildTypeMustBeShortcut;
var Rejected: boolean;
begin
  Rejected := False;
  try ReadShortcutText('class="plugin";file="test.dll";');
  except on EConvertError do Rejected := True; end;
  AssertTrue(Rejected);
end;

procedure TSerializationTests.LegacyTextRejectsLossyValues;
var Data: TShortcutDtoV1; Rejected: boolean;
begin
  Data := DefaultShortcutDto; Data.Params := 'value";another';
  Rejected := False;
  try WriteShortcutText(Data); except on EConvertError do Rejected := True; end;
  AssertTrue(Rejected);
  Data.Params := 'first' + #10 + 'second';
  Rejected := False;
  try WriteShortcutText(Data); except on EConvertError do Rejected := True; end;
  AssertTrue(Rejected);
end;

procedure TSerializationTests.FieldNamesInsideValuesCannotSelectFields;
var Data: TShortcutDtoV1;
begin
  Data := ReadShortcutText('caption="contains command="wrong";command="correct";');
  AssertEquals('correct', Data.Command);
end;

procedure TSerializationTests.MissingClassDefaultsToShortcut;
begin
  AssertEquals('shortcut', LegacyItemClass('caption="Legacy item";'));
  AssertEquals('stack', LegacyItemClass('CLASS="STACK";caption="Legacy item";'));
end;

procedure TSerializationTests.LongIniValuesAreNotTruncated;
var Value: WideString;
begin
  Value := WideString(StringOfChar('x', 12000));
  WriteIniStringW(Filename, 'item1', 'params', Value);
  AssertEquals(Value, ReadIniStringW(Filename, 'item1', 'params', ''));
end;

procedure TSerializationTests.MalformedIniNumbersUseDefaults;
begin
  WriteIniStringW(Filename, 'item1', 'mode', 'invalid');
  AssertEquals(0, ReadStackIni(Filename, 'item1').Mode);
  WriteIniStringW(Filename, 'item1', 'showcmd', 'invalid');
  AssertEquals(SW_SHOWNORMAL, ReadShortcutIni(Filename, 'item1').ShowCmd);
end;

procedure TSerializationTests.IniBooleanConversionUsesValues;
begin
  WriteIniStringW(Filename, 'item1', 'hide', 'false');
  AssertFalse(ReadShortcutIni(Filename, 'item1').Hide);
  WriteIniStringW(Filename, 'item1', 'hide', '2');
  AssertTrue(ReadShortcutIni(Filename, 'item1').Hide);
end;

procedure TSerializationTests.ProfileWriteFailureIsReported;
var Rejected: boolean;
begin
  Rejected := False;
  try WriteIniStringW(Filename + '\missing\dock.ini', 'item1', 'class', 'shortcut');
  except on EOSError do Rejected := True; end;
  AssertTrue(Rejected);
end;

procedure TSerializationTests.RegistrySelectsEveryBuiltInType;
var Entry: TItemType;
begin
  AssertTrue(ItemTypes.Find('SHORTCUT', Entry)); AssertTrue(Entry.ItemClass = TShortcutItem);
  AssertTrue(ItemTypes.Find('separator', Entry)); AssertTrue(Entry.ItemClass = TSeparatorItem);
  AssertTrue(ItemTypes.Find('stack', Entry)); AssertTrue(Entry.ItemClass = TStackItem);
  AssertTrue(ItemTypes.Find('plugin', Entry)); AssertTrue(Entry.Plugin);
  AssertTrue(ItemTypes.Find('task', Entry)); AssertTrue(Entry.ItemClass = TTaskItem);
  AssertFalse(Entry.Persistent);
end;

procedure TSerializationTests.RegistryRejectsDuplicateTypes;
var Registry: TItemTypeRegistry; Rejected: boolean;
begin
  Registry := TItemTypeRegistry.Create;
  try
    Registry.RegisterType('test', TSeparatorItem);
    Rejected := False;
    try Registry.RegisterType('TEST', TShortcutItem);
    except on EArgumentException do Rejected := True; end;
    AssertTrue(Rejected);
  finally Registry.Free; end;
end;

procedure TSerializationTests.UnknownTypesRemainUnregistered;
var Entry: TItemType;
begin AssertFalse(ItemTypes.Find('future-class', Entry)); end;

procedure TSerializationTests.StackControllerRejectsInvalidModeSafely;
var Controller: TStackModeController; A, B: TStackItemData;
begin
  Controller := TStackModeController.Create;
  try
    A := Controller.GetItemData(99, True, True, 1, 0, 1, 0, 32, 0, 1);
    B := Controller.GetItemData(0, True, True, 1, 0, 1, 0, 32, 0, 1);
    AssertTrue(CompareMem(@A, @B, SizeOf(A)));
  finally Controller.Free; end;
end;

procedure TSerializationTests.InvalidIniExportPreservesExistingSection;
var Data: TShortcutDtoV1; Rejected: boolean;
begin
  WriteIniStringW(Filename, 'item1', 'caption', 'Keep this');
  Data := DefaultShortcutDto;
  Data.Params := 'first' + #10 + 'second';
  Rejected := False;
  try WriteShortcutIni(Filename, 'item1', Data);
  except on EConvertError do Rejected := True; end;
  AssertTrue(Rejected);
  AssertEquals('Keep this', ReadIniStringW(Filename, 'item1', 'caption', ''));
end;

procedure TSerializationTests.InvalidSettingsExportPreservesExistingFile;
var Store: TDSets; Rejected: boolean;
begin
  WriteIniStringW(Filename, 'base', 'Theme', 'Keep this');
  Store := TDSets.Create(Filename, '', 0);
  try
    StrPCopy(Store.container.Shell, 'first' + #10 + 'second');
    Rejected := False;
    try Store.SaveTo(Filename); except on EConvertError do Rejected := True; end;
    AssertTrue(Rejected);
    AssertEquals('Keep this', ReadIniStringW(Filename, 'base', 'Theme', ''));
  finally Store.Free; end;
end;

procedure TSerializationTests.RegistryPrefersSpecificClasses;
var Registry: TItemTypeRegistry; Entry: TItemType;
begin
  Registry := TItemTypeRegistry.Create;
  try
    Registry.RegisterType('specific', TSpecificShortcut, False);
    Registry.RegisterType('base', TShortcutItem);
    AssertTrue(Registry.FindClass(TSpecificShortcut, Entry));
    AssertEquals('specific', Entry.Name);
    AssertFalse(Entry.Persistent);
    AssertFalse(Registry.FindClass(nil, Entry));
  finally Registry.Free; end;
end;

initialization
  RegisterTest(TSerializationTests);
end.
