unit documentdroptests;
{$mode delphi}
interface
uses Windows, Classes, SysUtils, ActiveX, ComObj, fpcunit, testregistry, itemmgru,
  scitemu, scsubitemu, stackitemu, customitemu, customsubitemu, declu, itemhostu,
  themeu, dropimportu, shelltextu, DropTgtU, ShlObj;
type
  TDocumentDropTests = class(TTestCase)
  private
    Manager: TItemManager;
    Window: HWND;
    FixtureTheme: TDTheme;
    Fixture: string;
    DropWindow: HWND;
    Calls, Entered, Left: Integer;
    Accepted: Boolean;
    Command, Parameters, Directory, Document: string;
    procedure EnterHost;
    procedure LeaveHost;
    procedure ImportBatch(Batch: TDropImportBatch; Target: THandle);
    function Receive(CommandValue, ParametersValue, DirectoryValue, DocumentValue: string;
      Show: Integer; Caller: HWND): Boolean;
    function DockShortcut(const Target: string): HWND;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure DockPIDLReportsAcceptanceAndRejection;
    procedure DockPackageUsesTypedDocumentBridge;
    procedure StackPIDLReturnsChildRejection;
    procedure StackPackageUsesTypedDocumentBridge;
    procedure RejectedDockTargetCreatesNoFallbackShortcut;
    procedure RejectedStackChildCreatesNoDockFallback;
    procedure AcceptedStackChildCreatesNoDuplicate;
    procedure DockPNGAndICOChangeImages;
    procedure StackPNGAndICOChangeImages;
    procedure MissingPackagedPrefixStillCreatesStackShortcut;
    procedure RejectedPackageDropReportsNoneAndEmptySpaceImports;
    procedure RejectedStackChildDropReportsNone;
  end;
implementation
const NamespaceTarget = '::{20D04FE0-3AEA-1069-A2D8-08002B30309D}';
  PackageTarget = 'Microsoft.WindowsCalculator_8wekyb3d8bbwe!App';
type
  TTestDropManager = class(TDropManager)
    constructor CreateForTests;
  end;
  TObservedStack = class(TStackItem)
    Child: TCustomSubitem;
    function CreateSubitem: TCustomSubitem; override;
    procedure ExposeChild;
  end;
constructor TTestDropManager.CreateForTests;
begin end;

function FileData(const Path: UnicodeString): IDataObject;
var Absolute, Child: PItemIDList; Parent: IShellFolder;
begin
  Absolute := nil;
  OleCheck(SHParseDisplayName(PWideChar(Path), nil, Absolute, 0, nil));
  try
    OleCheck(SHBindToParent(Absolute, IID_IShellFolder, @Parent, Child));
    OleCheck(Parent.GetUIObjectOf(0, 1, Child, IID_IDataObject, nil, Result));
  finally CoTaskMemFree(Absolute); end;
end;

procedure TDocumentDropTests.ImportBatch(Batch: TDropImportBatch; Target: THandle);
begin Manager.ImportDropFiles(Batch, DropWindow, Point(0, 0)); end;

function TObservedStack.CreateSubitem: TCustomSubitem;
begin Result := inherited CreateSubitem; Child := Result; end;
procedure TObservedStack.ExposeChild;
begin FState := stsOpen; end;
procedure TDocumentDropTests.EnterHost;
begin Inc(Entered); end;
procedure TDocumentDropTests.LeaveHost;
begin Inc(Left); end;
function TDocumentDropTests.Receive(CommandValue, ParametersValue, DirectoryValue, DocumentValue: string;
  Show: Integer; Caller: HWND): Boolean;
begin Inc(Calls); Command := CommandValue; Parameters := ParametersValue; Directory := DirectoryValue; Document := DocumentValue; Result := Accepted; end;
procedure TDocumentDropTests.SetUp;
var Services: TItemHostServices; Font: TDFontData; ID: TGUID; FileHandle: THandle; Name: UnicodeString;
begin
  OleCheck(OleInitialize(nil));
  Window := CreateWindowExW(0, 'STATIC', 'document-host', WS_POPUP, 0, 0, 0, 0, 0, 0, HInstance, nil);
  Font := Default(TDFontData);
  Manager := TItemManager.Create(Window, nil, 32, 32, 4, 100, 0, False, False,
    0, 0, 0, 255, False, False, False, False, False, False, False, False, 0, -1, False, Font);
  Manager.Enable(True);
  FixtureTheme := TDTheme(TDTheme.NewInstance); theme := FixtureTheme;
  Services := Default(TItemHostServices); Services.OnEnter := EnterHost; Services.OnLeave := LeaveHost; Services.OnOpenDocument := Receive;
  BindItemHost(Window, Services);
  CreateGUID(ID);
  Name := UnicodeString(ExtractFilePath(ParamStr(0)) + GUIDToString(ID)) + WideChar($0416) + WideChar($6587) + '.jpg';
  Fixture := ShellUTF8(Name);
  FileHandle := CreateFileW(PWideChar(Name), GENERIC_WRITE, 0, nil, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, 0);
  AssertTrue(FileHandle <> INVALID_HANDLE_VALUE); CloseHandle(FileHandle);
  Calls := 0; Entered := 0; Left := 0; Accepted := False;
end;
procedure TDocumentDropTests.TearDown;
begin
  Manager.Free; UnbindItemHost(Window); DestroyWindow(Window);
  theme := nil; FixtureTheme.Free; DeleteFileW(PWideChar(ShellUTF16(Fixture))); OleUninitialize;
end;
function TDocumentDropTests.DockShortcut(const Target: string): HWND;
begin Result := Manager.InsertItem(TShortcutItem.Make('test', Target, '--configured', 'C:\', '', 2)); AssertTrue(Result <> 0); end;
function CreateStack(Manager: TItemManager; Window: HWND; const Target: string): TObservedStack;
var Params: TDItemCreateParams;
begin
  Params := Default(TDItemCreateParams); Params.ItemSize := 32; Params.BigItemSize := 32;
  Params.Parameter := TStackItem.Make('stack');
  Result := TObservedStack.Create(Window, Params);
  Manager.AdoptItem(Result);
  if not Result.AddSubitem(TShortcutSubitem.Make('child', Target)) then raise Exception.Create('Cannot create stack fixture');
  Result.ExposeChild;
end;
procedure TDocumentDropTests.DockPIDLReportsAcceptanceAndRejection;
var Target: HWND;
begin
  Target := DockShortcut(NamespaceTarget);
  AssertFalse(Manager.ItemDropFile(Target, Point(0, 0), Fixture)); Accepted := True;
  AssertTrue(Manager.ItemDropFile(Target, Point(0, 0), Fixture));
  AssertEquals(2, Calls); AssertEquals(NamespaceTarget, Command); AssertEquals('--configured', Parameters); AssertEquals('C:\', Directory);
  AssertEquals(Fixture, Document); AssertEquals(Entered, Left);
end;
procedure TDocumentDropTests.DockPackageUsesTypedDocumentBridge;
var Target: HWND;
begin Target := DockShortcut(PackageTarget); Accepted := True; AssertTrue(Manager.ItemDropFile(Target, Point(0, 0), Fixture)); AssertEquals(PackageTarget, Command); AssertEquals(Fixture, Document); end;
procedure TDocumentDropTests.StackPIDLReturnsChildRejection;
var Stack: TObservedStack;
begin
  Stack := CreateStack(Manager, Window, NamespaceTarget);
  AssertFalse(Stack.DropFile(Stack.Child.Handle, Point(0, 0), Fixture)); Accepted := True;
  AssertTrue(Stack.DropFile(Stack.Child.Handle, Point(0, 0), Fixture)); AssertEquals(2, Calls); AssertEquals(Fixture, Document); AssertEquals(Entered, Left);
end;
procedure TDocumentDropTests.StackPackageUsesTypedDocumentBridge;
var Stack: TObservedStack;
begin Stack := CreateStack(Manager, Window, PackageTarget); Accepted := True; AssertTrue(Stack.DropFile(Stack.Child.Handle, Point(0, 0), Fixture)); AssertEquals(PackageTarget, Command); end;
procedure TDocumentDropTests.RejectedDockTargetCreatesNoFallbackShortcut;
var Target: HWND; Batch: TDropImportBatch;
begin
  Target := DockShortcut(NamespaceTarget); Batch := TDropImportBatch.Create('');
  try Batch.Add(Fixture); Batch.Expose; Manager.ImportDropFiles(Batch, Target, Point(0, 0)); AssertEquals('Rejected targeted drops must remain rejected', 0, Batch.AcceptedCount); AssertEquals('No launcher may appear elsewhere', 1, Manager.ItemCount); AssertTrue(ShellFileExists(ShellUTF16(Fixture))); finally Batch.Free; end;
end;
procedure TDocumentDropTests.RejectedStackChildCreatesNoDockFallback;
var Stack: TObservedStack; Batch: TDropImportBatch;
begin
  Stack := CreateStack(Manager, Window, NamespaceTarget); Batch := TDropImportBatch.Create('');
  try Batch.Add(Fixture); Batch.Expose; Manager.ImportDropFiles(Batch, Stack.Child.Handle, Point(0, 0)); AssertEquals(1, Calls); AssertEquals('A rejected child must not redirect insertion', 0, Batch.AcceptedCount); AssertEquals(1, Manager.ItemCount); AssertEquals(1, Stack.ItemCount); finally Batch.Free; end;
end;
procedure TDocumentDropTests.AcceptedStackChildCreatesNoDuplicate;
var Stack: TObservedStack; Batch: TDropImportBatch;
begin
  Stack := CreateStack(Manager, Window, NamespaceTarget); Accepted := True; Batch := TDropImportBatch.Create('');
  try Batch.Add(Fixture); Batch.Expose; Manager.ImportDropFiles(Batch, Stack.Child.Handle, Point(0, 0)); AssertEquals(1, Calls); AssertEquals(1, Batch.AcceptedCount); AssertEquals(1, Manager.ItemCount); finally Batch.Free; end;
end;
procedure TDocumentDropTests.DockPNGAndICOChangeImages;
var Target: HWND; Item: TCustomItem; Extension: string;
begin
  Target := DockShortcut(NamespaceTarget); AssertTrue(Manager.TryGetManagedItem(Target, Item));
  for Extension in ['.png', '.ico'] do begin AssertTrue(Manager.ItemDropFile(Target, Point(0, 0), Fixture + Extension)); AssertTrue(Pos(Extension, Item.ToString) > 0); end;
  AssertEquals(0, Calls);
end;
procedure TDocumentDropTests.StackPNGAndICOChangeImages;
var Stack: TObservedStack; Extension: string;
begin
  Stack := CreateStack(Manager, Window, NamespaceTarget);
  for Extension in ['.png', '.ico'] do begin AssertTrue(Stack.DropFile(Stack.Child.Handle, Point(0, 0), Fixture + Extension)); AssertTrue(Pos(Extension, Stack.Child.ToString) > 0); end;
  AssertEquals(0, Calls);
end;
procedure TDocumentDropTests.MissingPackagedPrefixStillCreatesStackShortcut;
var Stack: TObservedStack;
begin
  Stack := CreateStack(Manager, Window, 'shell:AppsFolder\TDOCK.Missing_8wekyb3d8bbwe!Main');
  AssertEquals(1, Stack.ItemCount);
  AssertTrue(Pos('TDOCK.Missing', Stack.Child.ToString) > 0);
end;
procedure TDocumentDropTests.RejectedPackageDropReportsNoneAndEmptySpaceImports;
var Drops: TDropManager; Data: IDataObject; Effect: DWORD;
begin
  DropWindow := DockShortcut(PackageTarget);
  Drops := TTestDropManager.CreateForTests;
  try
    Drops.OnDrop := ImportBatch;
    Data := FileData(ShellUTF16(Fixture));
    Effect := DROPEFFECT_COPY or DROPEFFECT_LINK;
    AssertEquals(S_OK, Drops.Drop(Data, 0, Point(0, 0), Effect));
    AssertEquals('Rejected Calculator drops must report NONE', 0, Integer(Effect));
    AssertEquals(1, Calls);
    AssertEquals('Rejected documents must not become dock launchers', 1, Manager.ItemCount);
    AssertTrue(ShellFileExists(ShellUTF16(Fixture)));
    DropWindow := 0;
    Effect := DROPEFFECT_COPY;
    AssertEquals(S_OK, Drops.Drop(Data, 0, Point(0, 0), Effect));
    AssertEquals(Integer(DROPEFFECT_COPY), Integer(Effect));
    AssertEquals('The same file must still import into free space', 2, Manager.ItemCount);
  finally Data := nil; Drops.Free; end;
end;

procedure TDocumentDropTests.RejectedStackChildDropReportsNone;
var Drops: TDropManager; Data: IDataObject; Effect: DWORD; Stack: TObservedStack;
begin
  Stack := CreateStack(Manager, Window, PackageTarget);
  DropWindow := Stack.Child.Handle;
  Drops := TTestDropManager.CreateForTests;
  try
    Drops.OnDrop := ImportBatch;
    Data := FileData(ShellUTF16(Fixture));
    Effect := DROPEFFECT_LINK;
    AssertEquals(S_OK, Drops.Drop(Data, 0, Point(0, 0), Effect));
    AssertEquals(0, Integer(Effect));
    AssertEquals(1, Calls);
    AssertEquals(1, Manager.ItemCount);
    AssertEquals(1, Stack.ItemCount);
    AssertTrue(ShellFileExists(ShellUTF16(Fixture)));
  finally Data := nil; Drops.Free; end;
end;

initialization RegisterTest(TDocumentDropTests);
end.
