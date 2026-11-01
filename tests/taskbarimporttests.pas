unit taskbarimporttests;
{$mode delphi}
{$codepage utf8}
interface
uses Windows, Classes, SysUtils, ActiveX, ShlObj, ComObj, fpcunit, testregistry,
  taskbarimportu, itemserializationu, shelltextu, toolu, PIDL, dockcommandu,
  itemmgru, itemsettingsu, scitemu, iniproc, customitemu;
type
  TFixtureSource = class(TTaskbarSource)
  public
    Items: IEnumIDList;
    Folder: UnicodeString;
  protected
    function OpenPinnedList(out Value: IEnumIDList): HRESULT; override;
    function ShortcutFolder: UnicodeString; override;
  end;
  TPinEnumerator = class(TInterfacedObject, IEnumIDList)
  public
    Targets: array of string;
    Index: Integer;
    FailAfterFirst: Boolean;
    function Next(celt: ULONG; out List: PItemIDList; var Fetched: ULONG): HRESULT; stdcall;
    function Skip(celt: ULONG): HRESULT; stdcall;
    function Reset: HRESULT; stdcall;
    function Clone(out Value: IEnumIDList): HRESULT; stdcall;
  end;
  TTaskbarImportTests = class(TTestCase)
  private
    Root, LinkPath, TargetPath: UnicodeString;
    Keys: TStringList;
    Added: array of TShortcutDtoV1;
    RejectNext, RaiseNext: Boolean;
    LastAction: TApplicationAction;
    function Insert(const Data: TShortcutDtoV1): Boolean;
    function Snapshot(const Targets: array of string): TTaskbarSnapshot;
    procedure CreateLink(const Path: UnicodeString; const Params: string = '--profile Work');
    procedure RecordCommand(Action: TApplicationAction; const Request: TCommandRequest);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure CopiesUnicodeShortcutWithoutChangingMetadata;
    procedure RepeatedImportSkipsCopiedShortcuts;
    procedure ExistingExecutableIsNotDuplicated;
    procedure ArgumentCaseRemainsSignificant;
    procedure StoreTargetsNeedNoShortcutFiles;
    procedure MissingShortcutDoesNotStopLaterApps;
    procedure RejectedCopyIsRemoved;
    procedure ExceptionRetainsExposedCopy;
    procedure PreservesOrderAndSkipsBatchDuplicates;
    procedure NativeEnumerationPreservesOrder;
    procedure EnumerationFailureReportsPartialResults;
    procedure UnavailableInterfaceReportsFolderFallback;
    procedure EmptyTaskbarReportsZeroCounts;
    procedure WarningsAndFailuresReachTheResult;
    procedure ImportCommandUsesTypedRoute;
    procedure ManagerImportSurvivesSaveAndReload;
    procedure DisabledManagerDoesNotImport;
    procedure OpaqueShortcutCopiesAreNotDuplicated;
    procedure ReferencesUnicodeShortcutWithoutCopying;
    procedure ReferenceModeRejectsMissingShortcut;
    procedure ReferenceModeSurvivesSaveAndReload;
    procedure ReferenceReimportUpdatesOwnedCopy;
    procedure ReferenceReimportKeepsCustomLauncher;
    procedure DefaultModeCopiesShortcuts;
  end;
implementation

function TFixtureSource.OpenPinnedList(out Value: IEnumIDList): HRESULT;
begin
  Value := Items;
  if Value = nil then Result := E_NOINTERFACE else Result := S_OK;
end;
function TFixtureSource.ShortcutFolder: UnicodeString;
begin Result := Folder; end;
function TPinEnumerator.Next(celt: ULONG; out List: PItemIDList; var Fetched: ULONG): HRESULT;
begin
  List := nil; Fetched := 0;
  if FailAfterFirst and (Index > 0) then Exit(E_ACCESSDENIED);
  if Index >= Length(Targets) then Exit(S_FALSE);
  if SHParseDisplayName(PWideChar(ShellUTF16(Targets[Index])), nil, List, 0, nil) <> S_OK then Exit(E_FAIL);
  if List = nil then Exit(E_FAIL);
  Inc(Index); Fetched := 1; Result := S_OK;
end;
function TPinEnumerator.Skip(celt: ULONG): HRESULT;
begin Inc(Index, celt); Result := S_OK; end;
function TPinEnumerator.Reset: HRESULT;
begin Index := 0; Result := S_OK; end;
function TPinEnumerator.Clone(out Value: IEnumIDList): HRESULT;
begin Value := nil; Result := E_NOTIMPL; end;

procedure RemoveFixture(const Path: UnicodeString);
var Search: THandle; Data: WIN32_FIND_DATAW; Name: UnicodeString;
begin
  Search := FindFirstFileW(PWideChar(Path + '\*'), Data);
  if Search <> INVALID_HANDLE_VALUE then
  try
    repeat
      Name := UnicodeString(Data.cFileName);
      if (Name = '.') or (Name = '..') then Continue;
      Name := Path + '\' + Name;
      if (Data.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY) <> 0 then RemoveFixture(Name)
      else DeleteFileW(PWideChar(Name));
    until not FindNextFileW(Search, Data);
  finally Windows.FindClose(Search); end;
  RemoveDirectoryW(PWideChar(Path));
end;

procedure TTaskbarImportTests.CreateLink(const Path: UnicodeString; const Params: string);
var Link: IShellLinkW; Persist: IPersistFile;
begin
  Link := CreateComObject(CLSID_ShellLink) as IShellLinkW;
  OleCheck(Link.SetPath(PWideChar(TargetPath)));
  OleCheck(Link.SetArguments(PWideChar(ShellUTF16(Params))));
  OleCheck(Link.SetWorkingDirectory(PWideChar(Root)));
  OleCheck(Link.SetIconLocation(PWideChar(TargetPath), 3));
  OleCheck(Link.SetShowCmd(SW_SHOWMINNOACTIVE));
  Persist := Link as IPersistFile;
  OleCheck(Persist.Save(PWideChar(Path), True));
end;

procedure TTaskbarImportTests.SetUp;
var Id: TGUID; Handle: THandle;
begin
  OleCheck(OleInitialize(nil));
  OleCheck(CreateGUID(Id));
  Root := ShellUTF16(ExtractFilePath(ParamStr(0))) + 'taskbar-fixture-' + UnicodeString(GUIDToString(Id));
  if not CreateDirectoryW(PWideChar(Root), nil) then RaiseLastOSError;
  TargetPath := Root + '\программа-应用.exe';
  Handle := CreateFileW(PWideChar(TargetPath), GENERIC_WRITE, 0, nil, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, 0);
  if Handle = INVALID_HANDLE_VALUE then RaiseLastOSError;
  CloseHandle(Handle);
  LinkPath := Root + '\Работа-应用.lnk';
  CreateLink(LinkPath);
  Keys := TStringList.Create;
  SetLength(Added, 0);
  RejectNext := False;
  RaiseNext := False;
end;

procedure TTaskbarImportTests.TearDown;
begin
  Keys.Free;
  RemoveFixture(Root);
  OleUninitialize;
end;

function TTaskbarImportTests.Insert(const Data: TShortcutDtoV1): Boolean;
begin
  if RejectNext then begin RejectNext := False; Exit(False); end;
  SetLength(Added, Length(Added) + 1);
  Added[High(Added)] := Data;
  if RaiseNext then begin RaiseNext := False; raise Exception.Create('Insertion callback failed'); end;
  Result := True;
end;

function TTaskbarImportTests.Snapshot(const Targets: array of string): TTaskbarSnapshot;
var I: Integer;
begin
  Result := Default(TTaskbarSnapshot);
  SetLength(Result.Pins, Length(Targets));
  for I := 0 to High(Targets) do
  begin
    Result.Pins[I].Caption := 'Launcher ' + IntToStr(I);
    Result.Pins[I].Target := Targets[I];
  end;
end;

procedure TTaskbarImportTests.CopiesUnicodeShortcutWithoutChangingMetadata;
var Value: TTaskbarImportResult; Path, Target: WideString; Params, Directory, Icon: string;
  A, B: TMemoryStream; Link: IShellLinkW; Persist: IPersistFile; Show: Integer;
begin
  Value := ImportTaskbarPins(Snapshot([ShellUTF8(LinkPath)]), Root + '\ImportedFiles', Keys, Insert, timCopyShortcuts);
  AssertEquals(TaskbarImportMessage(Value), 1, Value.Added);
  AssertEquals(0, Value.Failed);
  Path := ShellUTF16(UnzipPath(Added[0].Command));
  AssertTrue(Path <> LinkPath);
  AssertTrue(Pos(UnicodeString('Работа-应用.lnk'), UnicodeString(Path)) > 0);
  A := TMemoryStream.Create;
  B := TMemoryStream.Create;
  try
    A.LoadFromFile(ShellUTF8(LinkPath)); B.LoadFromFile(ShellUTF8(Path));
    AssertTrue('The copy must have the same size', A.Size = B.Size);
    AssertTrue('The copy must preserve all shortcut bytes', CompareMem(A.Memory, B.Memory, A.Size));
  finally B.Free; A.Free; end;
  Target := Path;
  AssertTrue(ResolveLNK(0, Target, Params, Directory, Icon));
  AssertEquals(ShellUTF8(TargetPath), ShellUTF8(Target));
  AssertEquals('--profile Work', Params);
  AssertEquals(ShellUTF8(Root), Directory);
  Link := CreateComObject(CLSID_ShellLink) as IShellLinkW;
  Persist := Link as IPersistFile;
  OleCheck(Persist.Load(PWideChar(Path), STGM_READ));
  OleCheck(Link.GetShowCmd(@Show));
  AssertEquals(SW_SHOWMINNOACTIVE, Show);
  AssertTrue(DeleteFileW(PWideChar(LinkPath)));
  AssertTrue('Unpinning must not remove the copy', ShellFileExists(Path));
end;

procedure TTaskbarImportTests.RepeatedImportSkipsCopiedShortcuts;
var Value: TTaskbarImportResult;
begin
  ImportTaskbarPins(Snapshot([ShellUTF8(LinkPath)]), Root + '\ImportedFiles', Keys, Insert, timCopyShortcuts);
  Keys.Add(TaskbarLauncherKey(Added[0]));
  Value := ImportTaskbarPins(Snapshot([ShellUTF8(LinkPath)]), Root + '\ImportedFiles', Keys, Insert, timCopyShortcuts);
  AssertEquals(0, Value.Added); AssertEquals(1, Value.Skipped); AssertEquals(1, Length(Added));
end;

procedure TTaskbarImportTests.ExistingExecutableIsNotDuplicated;
var Data: TShortcutDtoV1; Value: TTaskbarImportResult;
begin
  Data := DefaultShortcutDto;
  Data.Command := ShellUTF8(TargetPath); Data.Params := '--profile Work'; Data.Directory := ShellUTF8(Root);
  Keys.Add(TaskbarLauncherKey(Data));
  Value := ImportTaskbarPins(Snapshot([ShellUTF8(LinkPath)]), Root + '\ImportedFiles', Keys, Insert, timCopyShortcuts);
  AssertEquals(1, Value.Skipped);
end;

procedure TTaskbarImportTests.ArgumentCaseRemainsSignificant;
var Other: UnicodeString; Value: TTaskbarImportResult;
begin
  Other := Root + '\Other.lnk'; CreateLink(Other, '--profile work');
  Value := ImportTaskbarPins(Snapshot([ShellUTF8(LinkPath), ShellUTF8(Other)]), Root + '\ImportedFiles', Keys, Insert, timCopyShortcuts);
  AssertEquals(2, Value.Added);
end;

procedure TTaskbarImportTests.StoreTargetsNeedNoShortcutFiles;
const App = 'Microsoft.WindowsCalculator_8wekyb3d8bbwe!App';
var Value: TTaskbarImportResult;
begin
  Value := ImportTaskbarPins(Snapshot([App, APPS_FOLDER_PREFIX + App]), '', Keys, Insert, timCopyShortcuts);
  AssertEquals(1, Value.Added); AssertEquals(1, Value.Skipped);
  AssertTrue(IsPackagedApp(Added[0].Command));
end;

procedure TTaskbarImportTests.MissingShortcutDoesNotStopLaterApps;
var Value: TTaskbarImportResult;
begin
  Value := ImportTaskbarPins(Snapshot([ShellUTF8(Root + '\missing.lnk'), ShellUTF8(LinkPath)]),
    Root + '\ImportedFiles', Keys, Insert, timCopyShortcuts);
  AssertEquals(1, Value.Added); AssertEquals(1, Value.Failed);
  AssertTrue(Pos('Launcher 0:', Value.Details) > 0);
end;

procedure TTaskbarImportTests.RejectedCopyIsRemoved;
var Value: TTaskbarImportResult; Search: THandle; Data: WIN32_FIND_DATAW;
begin
  RejectNext := True;
  Value := ImportTaskbarPins(Snapshot([ShellUTF8(LinkPath)]), Root + '\ImportedFiles', Keys, Insert, timCopyShortcuts);
  AssertEquals(0, Value.Added); AssertEquals(1, Value.Failed);
  Search := FindFirstFileW(PWideChar(Root + '\ImportedFiles\import-*'), Data);
  if Search <> INVALID_HANDLE_VALUE then Windows.FindClose(Search);
  AssertTrue('Rejected copies must not leave an import directory', Search = INVALID_HANDLE_VALUE);
end;

procedure TTaskbarImportTests.ExceptionRetainsExposedCopy;
var Value: TTaskbarImportResult;
begin
  RaiseNext := True;
  Value := ImportTaskbarPins(Snapshot([ShellUTF8(LinkPath)]), Root + '\ImportedFiles', Keys, Insert, timCopyShortcuts);
  AssertEquals(1, Value.Failed);
  AssertTrue('Callbacks can retain paths before raising', ShellFileExists(ShellUTF16(UnzipPath(Added[0].Command))));
end;

procedure TTaskbarImportTests.PreservesOrderAndSkipsBatchDuplicates;
var Value: TTaskbarImportResult;
begin
  Value := ImportTaskbarPins(Snapshot(['shell:AppsFolder\B', 'shell:AppsFolder\A', 'shell:AppsFolder\B']), '', Keys, Insert, timCopyShortcuts);
  AssertEquals(2, Value.Added); AssertEquals(1, Value.Skipped);
  AssertEquals('shell:AppsFolder\B', Added[0].Command); AssertEquals('shell:AppsFolder\A', Added[1].Command);
end;

procedure TTaskbarImportTests.NativeEnumerationPreservesOrder;
var Source: TFixtureSource; Items: TPinEnumerator; Value: TTaskbarSnapshot;
begin
  Source := TFixtureSource.Create;
  try
    Items := TPinEnumerator.Create; SetLength(Items.Targets, 2);
    Items.Targets[0] := ShellUTF8(LinkPath); Items.Targets[1] := ShellUTF8(TargetPath);
    Source.Items := Items; Value := Source.ReadPins;
    AssertEquals('', Value.Warning); AssertEquals(2, Length(Value.Pins));
    AssertEquals(ShellUTF8(LinkPath), Value.Pins[0].Target); AssertEquals(ShellUTF8(TargetPath), Value.Pins[1].Target);
  finally Source.Free; end;
end;

procedure TTaskbarImportTests.EnumerationFailureReportsPartialResults;
var Source: TFixtureSource; Items: TPinEnumerator; Value: TTaskbarSnapshot;
begin
  Source := TFixtureSource.Create;
  try
    Items := TPinEnumerator.Create; SetLength(Items.Targets, 1);
    Items.Targets[0] := ShellUTF8(LinkPath); Items.FailAfterFirst := True;
    Source.Items := Items; Value := Source.ReadPins;
    AssertEquals(1, Length(Value.Pins)); AssertTrue(Pos('80070005', Value.Warning) > 0);
  finally Source.Free; end;
end;

procedure TTaskbarImportTests.UnavailableInterfaceReportsFolderFallback;
var Source: TFixtureSource; Value: TTaskbarSnapshot;
begin
  Source := TFixtureSource.Create;
  try
    Source.Folder := Root; Value := Source.ReadPins;
    AssertEquals(1, Length(Value.Pins)); AssertEquals(ShellUTF8(LinkPath), Value.Pins[0].Target);
    AssertEquals('Работа-应用', Value.Pins[0].Caption); AssertTrue(Pos('Store apps', Value.Warning) > 0);
  finally Source.Free; end;
end;

procedure TTaskbarImportTests.EmptyTaskbarReportsZeroCounts;
var Value: TTaskbarImportResult;
begin
  Value := ImportTaskbarPins(Snapshot([]), '', Keys, Insert, timCopyShortcuts);
  AssertEquals('Taskbar import: 0 added, 0 updated, 0 already present, 0 failed.', TaskbarImportMessage(Value));
end;

procedure TTaskbarImportTests.WarningsAndFailuresReachTheResult;
var Pins: TTaskbarSnapshot; Value: TTaskbarImportResult;
begin
  Pins := Snapshot([]); Pins.Failed := 1; Pins.Details := 'Unreadable item'; Pins.Warning := 'Partial list';
  Value := ImportTaskbarPins(Pins, '', Keys, Insert, timCopyShortcuts);
  AssertEquals(1, Value.Failed); AssertTrue(Pos('Unreadable item', TaskbarImportMessage(Value)) > 0);
  AssertTrue(Pos('Partial list', TaskbarImportMessage(Value)) > 0);
end;

procedure TTaskbarImportTests.RecordCommand(Action: TApplicationAction; const Request: TCommandRequest);
begin LastAction := Action; end;
procedure TTaskbarImportTests.ImportCommandUsesTypedRoute;
var Controller: TDockCommandController;
begin
  Controller := TDockCommandController.Create(RecordCommand, nil);
  try
    Controller.ExecuteCommandLine('/importtaskbar'); AssertEquals(Ord(aaImportTaskbar), Ord(LastAction));
    Controller.ExecuteCommandLine('/importtaskbarlinks'); AssertEquals(Ord(aaImportTaskbarLinks), Ord(LastAction));
    Controller.ExecuteCommandLine('/systaskbar'); AssertEquals(Ord(aaToggleTaskbar), Ord(LastAction));
  finally Controller.Free; end;
end;

procedure TTaskbarImportTests.ManagerImportSurvivesSaveAndReload;
var Source: TFixtureSource; Items: TPinEnumerator; Manager, Restored: TItemManager;
  Settings: TItemManagerSettings; Value: TTaskbarImportResult; Ini, CopiedCommand: string;
begin
  Settings := Default(TItemManagerSettings);
  Settings.ItemSize := 32; Settings.BigItemSize := 32; Settings.ZoomWidth := 4; Settings.ZoomTime := 100;
  Settings.TaskSpot := -1;
  Source := TFixtureSource.Create;
  Manager := TItemManager.Create(0, Settings, nil);
  try
    Manager.Enable(True);
    AssertTrue(Manager.InsertItem(TShortcutItem.Make('Existing', 'https://example.invalid/')) <> 0);
    Items := TPinEnumerator.Create; SetLength(Items.Targets, 1);
    Items.Targets[0] := ShellUTF8(LinkPath); Source.Items := Items;
    Value := Manager.ImportTaskbar(Root + '\ImportedFiles', Source, timCopyShortcuts);
    AssertEquals(TaskbarImportMessage(Value), 1, Value.Added);
    AssertEquals(2, Manager.ItemCount);
    Ini := ShellUTF8(Root + '\saved.ini');
    Manager.Save(Ini);
    AssertEquals('https://example.invalid/', ReadShortcutIni(Ini, 'item1').Command);
    CopiedCommand := ReadShortcutIni(Ini, 'item2').Command;
    AssertTrue(ShellFileExists(ShellUTF16(UnzipPath(CopiedCommand))));
    Manager.Free; Manager := nil;
    Restored := TItemManager.Create(0, Settings, nil);
    try
      Restored.Load(Ini);
      Restored.Enable(True);
      Items.Reset;
      Value := Restored.ImportTaskbar(Root + '\ImportedFiles', Source, timCopyShortcuts);
      AssertEquals(TaskbarImportMessage(Value), 1, Value.Skipped); AssertEquals(0, Value.Added);
      AssertEquals(2, Restored.ItemCount);
      AssertTrue(DeleteFileW(PWideChar(LinkPath)));
      AssertTrue(ShellFileExists(ShellUTF16(UnzipPath(CopiedCommand))));
    finally Restored.Free; end;
  finally Manager.Free; Source.Free; end;
end;

procedure TTaskbarImportTests.DisabledManagerDoesNotImport;
var Manager: TItemManager; Settings: TItemManagerSettings; Value: TTaskbarImportResult;
begin
  Settings := Default(TItemManagerSettings);
  Settings.ItemSize := 32; Settings.BigItemSize := 32;
  Manager := TItemManager.Create(0, Settings, nil);
  try
    Value := Manager.ImportTaskbar('');
    AssertEquals(0, Manager.ItemCount); AssertEquals(0, Value.Added);
    AssertTrue(Value.Warning <> '');
  finally Manager.Free; end;
end;

procedure TTaskbarImportTests.OpaqueShortcutCopiesAreNotDuplicated;
var Handle: THandle; Bytes: AnsiString; Count: DWORD; Value: TTaskbarImportResult;
begin
  // Some Shell links cannot expose complete target metadata.
  Handle := CreateFileW(PWideChar(LinkPath), GENERIC_WRITE, 0, nil, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
  if Handle = INVALID_HANDLE_VALUE then RaiseLastOSError;
  try
    Bytes := 'opaque shortcut fixture';
    AssertTrue(WriteFile(Handle, Bytes[1], Length(Bytes), Count, nil));
  finally CloseHandle(Handle); end;
  Value := ImportTaskbarPins(Snapshot([ShellUTF8(LinkPath)]), Root + '\ImportedFiles', Keys, Insert, timCopyShortcuts);
  AssertEquals(1, Value.Added);
  Keys.Add(TaskbarLauncherKey(Added[0]));
  Value := ImportTaskbarPins(Snapshot([ShellUTF8(LinkPath)]), Root + '\ImportedFiles', Keys, Insert, timCopyShortcuts);
  AssertEquals(1, Value.Skipped); AssertEquals(0, Value.Added);
end;

procedure TTaskbarImportTests.ReferencesUnicodeShortcutWithoutCopying;
var Value: TTaskbarImportResult;
begin
  Value := ImportTaskbarPins(Snapshot([ShellUTF8(LinkPath)]), '', Keys, Insert, timReferenceShortcuts);
  AssertEquals(TaskbarImportMessage(Value), 1, Value.Added);
  AssertEquals(ShellUTF8(LinkPath), Added[0].Command);
  AssertFalse(ShellDirectoryExists(Root + '\ImportedFiles'));
  AssertTrue(ShellFileExists(LinkPath));
end;

procedure TTaskbarImportTests.ReferenceModeRejectsMissingShortcut;
var Value: TTaskbarImportResult;
begin
  Value := ImportTaskbarPins(Snapshot([ShellUTF8(Root + '\missing.lnk'), ShellUTF8(LinkPath)]),
    '', Keys, Insert, timReferenceShortcuts);
  AssertEquals(1, Value.Failed); AssertEquals(1, Value.Added);
  AssertEquals(ShellUTF8(LinkPath), Added[0].Command);
end;

function FixtureSettings: TItemManagerSettings;
begin
  Result := Default(TItemManagerSettings);
  Result.ItemSize := 32; Result.BigItemSize := 32; Result.ZoomWidth := 4;
  Result.ZoomTime := 100; Result.TaskSpot := -1;
end;

procedure TTaskbarImportTests.ReferenceModeSurvivesSaveAndReload;
var Source: TFixtureSource; Items: TPinEnumerator; Manager: TItemManager;
  Value: TTaskbarImportResult; Ini: string;
begin
  Source := TFixtureSource.Create;
  Manager := TItemManager.Create(0, FixtureSettings, nil);
  try
    Manager.Enable(True);
    Items := TPinEnumerator.Create; SetLength(Items.Targets, 1);
    Items.Targets[0] := ShellUTF8(LinkPath); Source.Items := Items;
    Value := Manager.ImportTaskbar('', Source, timReferenceShortcuts);
    AssertEquals(1, Value.Added);
    Ini := ShellUTF8(Root + '\references.ini'); Manager.Save(Ini);
    AssertEquals(ShellUTF8(LinkPath), ReadShortcutIni(Ini, 'item1').Command);
    Manager.Free; Manager := TItemManager.Create(0, FixtureSettings, nil);
    Manager.Load(Ini); Manager.Enable(True); Items.Reset;
    Value := Manager.ImportTaskbar('', Source, timReferenceShortcuts);
    AssertEquals(1, Value.Skipped); AssertEquals(0, Value.Added);
    AssertEquals(1, Manager.ItemCount);
    AssertFalse(ShellDirectoryExists(Root + '\ImportedFiles'));
  finally Manager.Free; Source.Free; end;
end;

procedure TTaskbarImportTests.ReferenceReimportUpdatesOwnedCopy;
var Source: TFixtureSource; Items: TPinEnumerator; Manager: TItemManager;
  Value: TTaskbarImportResult; Ini, CopiedCommand: string; Item: TCustomItem;
  Window: HWND; Data: TShortcutDtoV1;
begin
  Source := TFixtureSource.Create;
  Manager := TItemManager.Create(0, FixtureSettings, nil);
  try
    Manager.Enable(True);
    Items := TPinEnumerator.Create; SetLength(Items.Targets, 1);
    Items.Targets[0] := ShellUTF8(LinkPath); Source.Items := Items;
    Value := Manager.ImportTaskbar(Root + '\ImportedFiles', Source, timCopyShortcuts);
    AssertEquals(1, Value.Added);
    Ini := ShellUTF8(Root + '\migration.ini'); Manager.Save(Ini);
    CopiedCommand := ReadShortcutIni(Ini, 'item1').Command;
    Manager.Free; Manager := TItemManager.Create(0, FixtureSettings, nil);
    Manager.Enable(True);
    Window := Manager.InsertItem(TShortcutItem.Make('Custom label', CopiedCommand, '', '', '', SW_SHOWMAXIMIZED));
    AssertTrue(Manager.TryGetManagedItem(Window, Item));
    TShortcutItem(Item).Hide := True;
    Items.Reset;
    Value := Manager.ImportTaskbar(Root + '\ImportedFiles', Source, timReferenceShortcuts);
    AssertEquals(TaskbarImportMessage(Value), 1, Value.Updated);
    AssertEquals(0, Value.Added); AssertEquals(0, Value.Skipped);
    AssertEquals(1, Manager.ItemCount);
    Manager.Save(Ini); Data := ReadShortcutIni(Ini, 'item1');
    AssertEquals(ShellUTF8(LinkPath), Data.Command);
    AssertEquals('Custom label', UTF8Encode(Data.Caption));
    AssertEquals(SW_SHOWMAXIMIZED, Data.ShowCmd); AssertTrue(Data.Hide);
    AssertTrue('Existing copies must remain available', ShellFileExists(ShellUTF16(UnzipPath(CopiedCommand))));
    Items.Reset;
    Value := Manager.ImportTaskbar(Root + '\ImportedFiles', Source, timReferenceShortcuts);
    AssertEquals(1, Value.Skipped); AssertEquals(0, Value.Updated);
  finally Manager.Free; Source.Free; end;
end;

procedure TTaskbarImportTests.ReferenceReimportKeepsCustomLauncher;
var Source: TFixtureSource; Items: TPinEnumerator; Manager: TItemManager;
  Value: TTaskbarImportResult; Other: UnicodeString; Ini: string;
begin
  Other := Root + '\custom.lnk';
  if not CopyFileW(PWideChar(LinkPath), PWideChar(Other), True) then RaiseLastOSError;
  Source := TFixtureSource.Create;
  Manager := TItemManager.Create(0, FixtureSettings, nil);
  try
    Manager.Enable(True);
    AssertTrue(Manager.InsertItem(TShortcutItem.Make('Custom', ShellUTF8(Other))) <> 0);
    Items := TPinEnumerator.Create; SetLength(Items.Targets, 1);
    Items.Targets[0] := ShellUTF8(LinkPath); Source.Items := Items;
    Value := Manager.ImportTaskbar(Root + '\ImportedFiles', Source, timReferenceShortcuts);
    AssertEquals(1, Value.Skipped); AssertEquals(0, Value.Updated);
    Ini := ShellUTF8(Root + '\custom.ini'); Manager.Save(Ini);
    AssertEquals(ShellUTF8(Other), ReadShortcutIni(Ini, 'item1').Command);
  finally Manager.Free; Source.Free; end;
end;

procedure TTaskbarImportTests.DefaultModeCopiesShortcuts;
var Value: TTaskbarImportResult;
begin
  Value := ImportTaskbarPins(Snapshot([ShellUTF8(LinkPath)]), Root + '\ImportedFiles', Keys, Insert);
  AssertEquals(1, Value.Added);
  AssertTrue(ShellUTF8(LinkPath) <> UnzipPath(Added[0].Command));
  AssertTrue(ShellDirectoryExists(Root + '\ImportedFiles'));
end;

initialization
  RegisterTest(TTaskbarImportTests);
end.
