unit dropownershiptests;

{$mode delphi}

interface

uses Windows, Classes, SysUtils, ActiveX, ShlObj, ShellAPI, fpcunit,
  testregistry, DropTgtU;

type
  TDropOwnershipTests = class(TTestCase)
  private
    FManager: TDropManager;
    FPaths: TStrings;
    FFixtureRoot, FFile, FFolder, FShortcut, FInternetShortcut: string;
    procedure CreateFixtures;
    procedure CheckTransfer(ProviderOwned, FailInsertion: Boolean);
    procedure CheckShellImport(const Expected: array of UnicodeString;
      Repetitions: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure FileReaderPreservesBorrowedHandle;
    procedure FileReaderPreservesHandleOnInsertionFailure;
    procedure ReceiverOwnedMediumReleasedAfterImport;
    procedure ProviderOwnedMediumReleasedAfterImport;
    procedure ReceiverOwnedMediumReleasedAfterInsertionFailure;
    procedure ProviderOwnedMediumReleasedAfterInsertionFailure;
    procedure FailedGetDataDoesNotReleaseAnything;
    procedure RealShellExecutableImportsRepeatedly;
    procedure RealShellFolderImportsRepeatedly;
    procedure RealShellShortcutImportsRepeatedly;
    procedure RealShellMultipleFilesImportRepeatedly;
    procedure RealShellMixedSelectionImportsRepeatedly;
    procedure ShellIDFallbackStillImports;
    procedure VirtualShellObjectsStillImport;
  end;

implementation

type
  TTestDropManager = class(TDropManager)
    constructor CreateForTests;
  end;

  TFailingStrings = class(TStringList)
    function Add(const S: string): Integer; override;
  end;

  TTransferState = record
    Handle: HGLOBAL;
    GetCalls, ReleaseCalls: Integer;
    AliveAtRelease, FreeSucceeded: Boolean;
  end;
  PTransferState = ^TTransferState;

  TMediumOwner = class(TInterfacedObject)
  private
    FState: PTransferState;
  public
    constructor Create(State: PTransferState);
    destructor Destroy; override;
  end;

  TTestDataObject = class(TInterfacedObject, IDataObject)
  private
    FState: PTransferState;
    FProviderOwned, FFailGet: Boolean;
    FSource: IDataObject;
    FFormat: TFormatEtc;
  public
    constructor Create(State: PTransferState; ProviderOwned, FailGet: Boolean);
    constructor CreateShellOnly(const Source: IDataObject);
    function GetData(const Format: TFormatEtc; out Medium: TStgMedium): HRESULT; stdcall;
    function GetDataHere(const Format: TFormatEtc; out Medium: TStgMedium): HRESULT; stdcall;
    function QueryGetData(const Format: TFormatEtc): HRESULT; stdcall;
    function GetCanonicalFormatEtc(const Format: TFormatEtc;
      out Canonical: TFormatEtc): HRESULT; stdcall;
    function SetData(const Format: TFormatEtc; var Medium: TStgMedium;
      Release: BOOL): HRESULT; stdcall;
    function EnumFormatEtc(Direction: DWORD; out Formats: IEnumFormatEtc): HRESULT; stdcall;
    function DAdvise(const Format: TFormatEtc; Flags: DWORD;
      const Sink: IAdviseSink; out Connection: DWORD): HRESULT; stdcall;
    function DUnadvise(Connection: DWORD): HRESULT; stdcall;
    function EnumDAdvise(out Advises: IEnumStatData): HRESULT; stdcall;
  end;

function CreateFormatEnumerator(Count: UINT; Formats: PFormatEtc;
  out Enumerator: IEnumFormatEtc): HRESULT; stdcall;
  external 'shell32.dll' name 'SHCreateStdEnumFmtEtc';

procedure CheckHR(Value: HRESULT; const Operation: string);
begin
  if Value < 0 then
    raise Exception.Create(Operation + ': ' + IntToHex(LongWord(Value), 8));
end;

function HandleIsAlive(Handle: HGLOBAL): Boolean;
begin
  Result := (Handle <> 0) and (GlobalFlags(Handle) <> GMEM_INVALID_HANDLE);
end;

constructor TTestDropManager.CreateForTests;
begin end;

function TFailingStrings.Add(const S: string): Integer;
begin
  Result := -1;
  raise Exception.Create('Simulated list insertion failure');
end;

function FileDropHandle(const Paths: array of UnicodeString): HGLOBAL;
var
  Names: UnicodeString;
  I: Integer;
  Data: PDROPFILES;
begin
  Names := '';
  for I := 0 to High(Paths) do Names := Names + Paths[I] + #0;
  Names := Names + #0;
  Result := GlobalAlloc(GMEM_MOVEABLE or GMEM_ZEROINIT,
    SizeOf(TDROPFILES) + Length(Names) * SizeOf(WideChar));
  if Result = 0 then RaiseLastOSError;
  Data := GlobalLock(Result);
  if Data = nil then
  begin
    GlobalFree(Result);
    RaiseLastOSError;
  end;
  try
    Data^.pFiles := SizeOf(TDROPFILES);
    Data^.fWide := True;
    Move(Names[1], PByte(Data)[SizeOf(TDROPFILES)],
      Length(Names) * SizeOf(WideChar));
  finally
    GlobalUnlock(Result);
  end;
end;

constructor TMediumOwner.Create(State: PTransferState);
begin
  inherited Create;
  FState := State;
end;

destructor TMediumOwner.Destroy;
begin
  Inc(FState^.ReleaseCalls);
  FState^.AliveAtRelease := HandleIsAlive(FState^.Handle);
  if FState^.AliveAtRelease then
    FState^.FreeSucceeded := GlobalFree(FState^.Handle) = 0;
  inherited Destroy;
end;

constructor TTestDataObject.Create(State: PTransferState;
  ProviderOwned, FailGet: Boolean);
begin
  inherited Create;
  FState := State;
  FProviderOwned := ProviderOwned;
  FFailGet := FailGet;
  FFormat.cfFormat := CF_HDROP;
  FFormat.dwAspect := DVASPECT_CONTENT;
  FFormat.lindex := -1;
  FFormat.tymed := TYMED_HGLOBAL;
end;

constructor TTestDataObject.CreateShellOnly(const Source: IDataObject);
begin
  inherited Create;
  FSource := Source;
  FFormat.cfFormat := RegisterClipboardFormat('Shell IDList Array');
  FFormat.dwAspect := DVASPECT_CONTENT;
  FFormat.lindex := -1;
  FFormat.tymed := TYMED_HGLOBAL;
end;

function TTestDataObject.GetData(const Format: TFormatEtc;
  out Medium: TStgMedium): HRESULT;
var Owner: IUnknown;
begin
  FillChar(Medium, SizeOf(Medium), 0);
  Result := QueryGetData(Format);
  if Result <> S_OK then Exit;
  if Assigned(FSource) then Exit(FSource.GetData(Format, Medium));
  Inc(FState^.GetCalls);
  if FFailGet then Exit(E_FAIL);
  FState^.Handle := FileDropHandle(['C:\Example\one.txt', 'C:\Example\two.txt']);
  Medium.tymed := TYMED_HGLOBAL;
  Medium.hGlobal := FState^.Handle;
  if FProviderOwned then
  begin
    Owner := TMediumOwner.Create(FState);
    Medium.pUnkForRelease := Pointer(Owner);
    Owner._AddRef;
  end;
  Result := S_OK;
end;

function TTestDataObject.GetDataHere(const Format: TFormatEtc;
  out Medium: TStgMedium): HRESULT;
begin
  FillChar(Medium, SizeOf(Medium), 0);
  Result := E_NOTIMPL;
end;

function TTestDataObject.QueryGetData(const Format: TFormatEtc): HRESULT;
begin
  if (Format.cfFormat = FFormat.cfFormat) and
    (Format.dwAspect = DVASPECT_CONTENT) and (Format.lindex = -1) and
    ((Format.tymed and TYMED_HGLOBAL) <> 0) then Result := S_OK
  else Result := DV_E_FORMATETC;
end;

function TTestDataObject.GetCanonicalFormatEtc(const Format: TFormatEtc;
  out Canonical: TFormatEtc): HRESULT;
begin
  FillChar(Canonical, SizeOf(Canonical), 0);
  Result := E_NOTIMPL;
end;

function TTestDataObject.SetData(const Format: TFormatEtc;
  var Medium: TStgMedium; Release: BOOL): HRESULT;
begin Result := E_NOTIMPL; end;

function TTestDataObject.EnumFormatEtc(Direction: DWORD;
  out Formats: IEnumFormatEtc): HRESULT;
begin
  Formats := nil;
  if Direction <> DATADIR_GET then Exit(E_NOTIMPL);
  Result := CreateFormatEnumerator(1, @FFormat, Formats);
end;

function TTestDataObject.DAdvise(const Format: TFormatEtc; Flags: DWORD;
  const Sink: IAdviseSink; out Connection: DWORD): HRESULT;
begin Connection := 0; Result := E_NOTIMPL; end;

function TTestDataObject.DUnadvise(Connection: DWORD): HRESULT;
begin Result := E_NOTIMPL; end;

function TTestDataObject.EnumDAdvise(out Advises: IEnumStatData): HRESULT;
begin Advises := nil; Result := E_NOTIMPL; end;

function ShellData(const Paths: array of UnicodeString): IDataObject;
var
  AbsolutePIDLs, ChildPIDLs: array of PItemIDList;
  Parent: IShellFolder;
  I: Integer;
begin
  SetLength(AbsolutePIDLs, Length(Paths));
  SetLength(ChildPIDLs, Length(Paths));
  try
    // All selections in these tests contain siblings from one parent folder.
    for I := 0 to High(Paths) do
    begin
      CheckHR(SHParseDisplayName(PWideChar(Paths[I]), nil,
        AbsolutePIDLs[I], 0, nil), 'SHParseDisplayName');
      Parent := nil;
      CheckHR(SHBindToParent(AbsolutePIDLs[I], IID_IShellFolder,
        @Parent, ChildPIDLs[I]), 'SHBindToParent');
    end;
    CheckHR(Parent.GetUIObjectOf(0, Length(Paths), ChildPIDLs[0],
      IID_IDataObject, nil, Result), 'GetUIObjectOf');
  finally
    for I := 0 to High(AbsolutePIDLs) do
      CoTaskMemFree(AbsolutePIDLs[I]);
  end;
end;

procedure TDropOwnershipTests.SetUp;
begin
  CheckHR(OleInitialize(nil), 'OleInitialize');
  FManager := TTestDropManager.CreateForTests;
  FPaths := TStringList.Create;
end;

procedure TDropOwnershipTests.TearDown;
begin
  FPaths.Free;
  FManager.Free;
  if FFixtureRoot <> '' then
  begin
    SysUtils.DeleteFile(FShortcut);
    SysUtils.DeleteFile(FInternetShortcut);
    SysUtils.DeleteFile(FFile);
    RemoveDir(FFolder);
    RemoveDir(FFixtureRoot);
  end;
  OleUninitialize;
end;

procedure TDropOwnershipTests.CreateFixtures;
var
  FixtureId: TGUID;
  Link: IShellLinkW;
  Persist: IPersistFile;
  InternetShortcut: TStringList;
begin
  CheckHR(CreateGUID(FixtureId), 'CreateGUID');
  FFixtureRoot := ExtractFilePath(ParamStr(0)) + 'drop-' + GUIDToString(FixtureId);
  if not CreateDir(FFixtureRoot) then RaiseLastOSError;
  FFile := FFixtureRoot + '\document.txt';
  FFolder := FFixtureRoot + '\Folder';
  FShortcut := FFixtureRoot + '\Application.lnk';
  FInternetShortcut := FFixtureRoot + '\Internet.url';
  with TFileStream.Create(FFile, fmCreate) do Free;
  if not CreateDir(FFolder) then RaiseLastOSError;
  InternetShortcut := TStringList.Create;
  try
    InternetShortcut.Text := '[InternetShortcut]' + LineEnding +
      'URL=https://example.invalid/' + LineEnding;
    InternetShortcut.SaveToFile(FInternetShortcut);
  finally InternetShortcut.Free; end;
  CheckHR(CoCreateInstance(CLSID_ShellLink, nil, CLSCTX_INPROC_SERVER,
    IID_IShellLinkW, Link), 'Create Shell link');
  CheckHR(Link.SetPath(PWideChar(UnicodeString(GetEnvironmentVariable('SystemRoot') +
    '\System32\notepad.exe'))), 'Set Shell link path');
  Persist := Link as IPersistFile;
  CheckHR(Persist.Save(PWideChar(UnicodeString(FShortcut)), True), 'Save Shell link');
end;

procedure TDropOwnershipTests.FileReaderPreservesBorrowedHandle;
var
  Handle: HGLOBAL;
begin
  Handle := FileDropHandle(['C:\Example\document.txt']);
  try
    FManager.AddToListHDrop(Handle, FPaths);
    AssertEquals('One file must be imported', 1, FPaths.Count);
    AssertEquals('The path must remain intact', 'C:\Example\document.txt', FPaths[0]);
    AssertTrue('The reader must preserve the caller-owned handle',
      HandleIsAlive(Handle));
  finally
    if HandleIsAlive(Handle) then GlobalFree(Handle);
  end;
end;

procedure TDropOwnershipTests.FileReaderPreservesHandleOnInsertionFailure;
var
  Handle: HGLOBAL;
  Caught: Boolean;
begin
  Handle := FileDropHandle(['C:\Example\document.txt']);
  FPaths.Free;
  FPaths := TFailingStrings.Create;
  try
    Caught := False;
    try
      FManager.AddToListHDrop(Handle, FPaths);
    except
      on E: Exception do
      begin
        Caught := True;
        AssertTrue('The insertion failure must reach the caller',
          Pos('Simulated list insertion failure', E.Message) > 0);
      end;
    end;
    AssertTrue('The insertion must fail', Caught);
    AssertTrue('The caller must retain its handle after failure', HandleIsAlive(Handle));
  finally
    if HandleIsAlive(Handle) then GlobalFree(Handle);
  end;
end;

procedure TDropOwnershipTests.CheckTransfer(ProviderOwned, FailInsertion: Boolean);
var
  State: TTransferState;
  Data: IDataObject;
  Caught: Boolean;
begin
  FillChar(State, SizeOf(State), 0);
  Data := TTestDataObject.Create(@State, ProviderOwned, False);
  if FailInsertion then
  begin
    FPaths.Free;
    FPaths := TFailingStrings.Create;
  end;
  try
    Caught := False;
    try
      FManager.MakeList(Data, FPaths);
    except
      on E: Exception do
      begin
        Caught := True;
        AssertTrue('Only the requested insertion failure is expected',
          FailInsertion and (Pos('Simulated list insertion failure', E.Message) > 0));
      end;
    end;
    AssertEquals('Only failing insertions must raise', FailInsertion, Caught);
    AssertEquals('The medium must be obtained once', 1, State.GetCalls);
    AssertEquals('Only provider-owned media use a release object',
      Ord(ProviderOwned), State.ReleaseCalls);
    if ProviderOwned then
    begin
      AssertTrue('The provider must receive a live handle', State.AliveAtRelease);
      AssertTrue('The provider must free the handle successfully', State.FreeSucceeded);
    end;
    AssertFalse('The medium must be released before returning', HandleIsAlive(State.Handle));
    if not FailInsertion then
    begin
      AssertEquals('Both files must be imported', 2, FPaths.Count);
      AssertEquals('The first path must remain intact', 'C:\Example\one.txt', FPaths[0]);
      AssertEquals('The second path must remain intact', 'C:\Example\two.txt', FPaths[1]);
    end;
  finally
    Data := nil;
    if HandleIsAlive(State.Handle) then GlobalFree(State.Handle);
  end;
end;

procedure TDropOwnershipTests.ReceiverOwnedMediumReleasedAfterImport;
begin CheckTransfer(False, False); end;

procedure TDropOwnershipTests.ProviderOwnedMediumReleasedAfterImport;
begin CheckTransfer(True, False); end;

procedure TDropOwnershipTests.ReceiverOwnedMediumReleasedAfterInsertionFailure;
begin CheckTransfer(False, True); end;

procedure TDropOwnershipTests.ProviderOwnedMediumReleasedAfterInsertionFailure;
begin CheckTransfer(True, True); end;

procedure TDropOwnershipTests.FailedGetDataDoesNotReleaseAnything;
var
  State: TTransferState;
  Data: IDataObject;
begin
  FillChar(State, SizeOf(State), 0);
  Data := TTestDataObject.Create(@State, True, True);
  try
    FManager.MakeList(Data, FPaths);
    AssertEquals('The failing provider must be queried once', 1, State.GetCalls);
    AssertEquals('A failed transfer must not import files', 0, FPaths.Count);
    AssertEquals('A failed transfer owns no medium', QWord(0), QWord(State.Handle));
    AssertEquals('A failed transfer has no release callback', 0, State.ReleaseCalls);
  finally Data := nil; end;
end;

procedure TDropOwnershipTests.CheckShellImport(const Expected: array of UnicodeString;
  Repetitions: Integer);
var
  Data: IDataObject;
  I, J: Integer;
begin
  Data := ShellData(Expected);
  for I := 1 to Repetitions do
  begin
    FPaths.Clear;
    FManager.MakeList(Data, FPaths);
    AssertEquals('Each selected object must be imported', Length(Expected), FPaths.Count);
    for J := 0 to High(Expected) do
      AssertTrue('Each selected path must remain intact: ' + UTF8Encode(Expected[J]),
        FPaths.IndexOf(UTF8Encode(Expected[J])) >= 0);
  end;
end;

procedure TDropOwnershipTests.RealShellExecutableImportsRepeatedly;
begin
  CheckShellImport([UnicodeString(GetEnvironmentVariable('SystemRoot') +
    '\System32\notepad.exe')], 100);
end;

procedure TDropOwnershipTests.RealShellFolderImportsRepeatedly;
begin
  CreateFixtures;
  CheckShellImport([UnicodeString(FFolder)], 25);
end;

procedure TDropOwnershipTests.RealShellShortcutImportsRepeatedly;
begin
  CreateFixtures;
  CheckShellImport([UnicodeString(FShortcut)], 25);
end;

procedure TDropOwnershipTests.RealShellMultipleFilesImportRepeatedly;
begin
  CreateFixtures;
  CheckShellImport([UnicodeString(FFile), UnicodeString(FInternetShortcut)], 25);
end;

procedure TDropOwnershipTests.RealShellMixedSelectionImportsRepeatedly;
begin
  CreateFixtures;
  CheckShellImport([UnicodeString(FFile), UnicodeString(FFolder),
    UnicodeString(FShortcut)], 25);
end;

procedure TDropOwnershipTests.ShellIDFallbackStillImports;
var Data: IDataObject;
begin
  CreateFixtures;
  Data := TTestDataObject.CreateShellOnly(ShellData([UnicodeString(FFile)]));
  FManager.MakeList(Data, FPaths);
  AssertEquals('The Shell-ID fallback must import one file', 1, FPaths.Count);
  AssertEquals('The Shell-ID fallback must preserve the path', FFile, FPaths[0]);
end;

procedure TDropOwnershipTests.VirtualShellObjectsStillImport;
const
  Objects: array[0..1] of UnicodeString = (
    '::{20D04FE0-3AEA-1069-A2D8-08002B30309D}',
    '::{645FF040-5081-101B-9F08-00AA002F954E}');
var
  Data: IDataObject;
  I: Integer;
begin
  for I := 0 to High(Objects) do
  begin
    FPaths.Clear;
    Data := TTestDataObject.CreateShellOnly(ShellData([Objects[I]]));
    FManager.MakeList(Data, FPaths);
    AssertEquals('The virtual Shell object must import one item', 1, FPaths.Count);
    AssertTrue('The virtual Shell identity must remain available', FPaths[0] <> '');
  end;
end;

initialization
  RegisterTest(TDropOwnershipTests);
end.
