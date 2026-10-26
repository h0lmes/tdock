unit targetpreservationtests;
{$mode delphi}
{$codepage utf8}
interface
uses Windows, Classes, SysUtils, ActiveX, ShlObj, ShellAPI, ComObj, Forms,
  fpcunit, testregistry, DropTgtU, PIDL, itemserializationu, iniproc,
  shelltextu, toolu, dropimportu, launchserviceu, setsu, GDIPAPI, iconserviceu,
  declu, itemsettingsu, itemmgru, customitemu, scitemu, stackitemu, themeu,
  frmitemoptu, frmstackpropu, plgitemu, settingssaveu;
type
  TTargetPreservationTests = class(TTestCase)
  private
    Root, IniName: string;
    Cleanup: TStringList;
    function FixtureFile(LongPath: Boolean): UnicodeString;
    function FixtureFolder(LongPath: Boolean): UnicodeString;
    procedure CheckProperties(IsStack: Boolean);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure UnicodeShortcutUsesSelectiveEncoding;
    procedure ASCIIShortcutKeepsPlainFields;
    procedure UnicodeStackUsesSelectiveEncoding;
    procedure ANSIPluginWritesPreserveUnicodeShortcut;
    procedure HDropPreservesLongPath;
    procedure MalformedPIDLHexIsRejected;
    procedure CIDAAcceptsLargeAndReorderedLists;
    procedure CIDARejectsMalformedBounds;
    procedure CIDALimitsCombinedSizeAndCount;
    procedure CIDAFuzzStaysWithinBounds;
    procedure ShellStreamsHandlePartialReads;
    procedure ShellStreamsRejectFailureAndOversize;
    procedure MalformedHDropPreservesBorrowedMemory;
    procedure HDropLengthBoundaryRejectsWithoutPartialItems;
    procedure NativeLongUnicodeShellName;
    procedure NativeLongUnicodeLinkMetadata;
    procedure NativeInMemoryLongMetadata;
    procedure FailedLinkConversionPreservesTarget;
    procedure UnicodeLaunchFieldsSurviveBothSettings;
    procedure EncodedStackChildrenSurviveReload;
    procedure EncodingRejectsMalformedData;
    procedure EncodingReturnsToPlainASCII;
    procedure PercentPrefixPreservesLiteralPrefix;
    procedure PercentPrefixDecodesExactlyOnce;
    procedure PercentPrefixAcceptsCharsetCase;
    procedure PercentPrefixLimitPreservesExistingSection;
    procedure ExplicitCodePagesDoNotControlUTF8;
    procedure CP1252DefaultsPreserveOwnedFields;
    procedure ShortcutPropertiesPreserveUnicode;
    procedure StackPropertiesPreserveUnicode;
    procedure UnicodeCustomImageLoads;
    procedure MetadataLimitRejectsBeforeCommit;
    procedure SharedSaveKeepsANSIPluginContract;
    procedure LongFilesystemChecksFindCompleteTargets;
    procedure RelativeFolderRestoresProgramDirectory;
    procedure RelativeLongFolderLoadsNativeIcon;
    procedure RelativeLongFolderLaunchesBothSettings;
  end;
implementation
const PercentPrefix = 'UTF-8' + #39 + #39;
type TTestManager = class(TDropManager)
  constructor CreateForTests;
end;
  TPartialStream = class(TStreamAdapter)
    Mode: Integer;
    function Read(pv: Pointer; cb: DWORD; pcbRead: PDWORD): HRESULT; override; stdcall;
    function Stat(out StatStg: TStatStg; Flags: DWORD): HRESULT; override; stdcall;
  end;
  TLaunchProbe = class(TLaunchService)
    Target, Arguments, Folder: WideString;
    Calls: Integer;
    procedure ExecuteShellTarget(const Value, Parameters, Directory: WideString; ShowCommand: Integer); override;
    function StartShellWorker(const Value, Parameters, Directory: WideString; ShowCommand: Integer): Boolean; override;
  end;
  TProperties = class(TfrmItemProp)
    function Bind(Window: HWND): Boolean;
  end;
  TStackProperties = class(TfrmStackProp)
    function Bind(Window: HWND): Boolean;
  end;
  TANSIPlugin = class(TPluginItem)
  protected
    procedure LoadPlugin; override;
    function CreatePluginData(Ini, Section: PChar): Pointer; override;
  end;
  TANSIManager = class(TItemManager)
  protected
    function CreatePluginItem(var Params: TDItemCreateParams): TCustomItem; override;
  end;
var PluginSaveCalls: Integer;
    PluginSavePath, PluginSaveSection: string;
procedure ANSIPluginSave(Data: Pointer; Ini, Section: PChar; IsExport: Boolean); stdcall;
begin
  Inc(PluginSaveCalls); PluginSavePath := StrPas(Ini); PluginSaveSection := StrPas(Section);
  if not WritePrivateProfileStringA(Section, 'vendor-option', 'unchanged-ANSI-value', Ini) then RaiseLastOSError;
  if not WritePrivateProfileStringA(Section, 'vendor-prefix', PAnsiChar(PercentPrefix + 'caf%C3%A9'), Ini) then RaiseLastOSError;
end;
procedure TANSIPlugin.LoadPlugin;
begin OnSave := ANSIPluginSave; end;
function TANSIPlugin.CreatePluginData(Ini, Section: PChar): Pointer;
begin Result := nil; end;
function TANSIManager.CreatePluginItem(var Params: TDItemCreateParams): TCustomItem;
begin Result := TANSIPlugin.Create(ParentWindow, Params); end;
function TProperties.Bind(Window: HWND): Boolean;
begin Result := SetData(Window); end;
function TStackProperties.Bind(Window: HWND): Boolean;
begin Result := SetData(Window); end;
function Extended(const Path: UnicodeString): UnicodeString;
begin Result := '\\?\' + Path; end;
procedure Put32(var Bytes: TBytes; Offset: Integer; Value: DWORD);
begin Move(Value, Bytes[Offset], SizeOf(Value)); end;
function ItemBytes(Count: Integer): TBytes;
var ItemSize: Word;
begin
  SetLength(Result, Count); FillChar(Result[0], Count, $41);
  ItemSize := Count - 2; Move(ItemSize, Result[0], 2);
  Result[Count - 2] := 0; Result[Count - 1] := 0;
end;
function CIDABytes(const Parent, Child: TBytes; Reordered: Boolean = False): TBytes;
begin
  SetLength(Result, 12 + Length(Parent) + Length(Child)); Put32(Result, 0, 1);
  if Reordered then
  begin
    Put32(Result, 4, 12 + Length(Child)); Put32(Result, 8, 12);
    Move(Child[0], Result[12], Length(Child));
    Move(Parent[0], Result[12 + Length(Child)], Length(Parent));
  end else
  begin
    Put32(Result, 4, 12); Put32(Result, 8, 12 + Length(Parent));
    Move(Parent[0], Result[12], Length(Parent));
    Move(Child[0], Result[12 + Length(Parent)], Length(Child));
  end;
end;
function EmptyPIDL: TBytes;
begin SetLength(Result, 2); Result[0] := 0; Result[1] := 0; end;
function ShellCIDA: TBytes;
var P: PItemIDList; Bytes: TBytes;
begin
  P := PIDL_GetFromPath('::{20D04FE0-3AEA-1069-A2D8-08002B30309D}');
  if P = nil then raise Exception.Create('Missing native This PC fixture');
  try SetLength(Bytes, PIDL_GetSize(P)); Move(P^, Bytes[0], Length(Bytes));
  finally PIDL_Free(P); end;
  Result := CIDABytes(EmptyPIDL, Bytes);
end;
function TPartialStream.Read(pv: Pointer; cb: DWORD; pcbRead: PDWORD): HRESULT;
var Count: Integer;
begin
  if (Mode = 2) and (Stream.Position > 0) then Exit(E_FAIL);
  if cb > 3 then cb := 3;
  Count := Stream.Read(pv^, cb); if pcbRead <> nil then pcbRead^ := Count;
  if (Count = 0) or ((Mode = 1) and (Stream.Position = Stream.Size)) then Result := S_FALSE
  else Result := S_OK;
end;
function TPartialStream.Stat(out StatStg: TStatStg; Flags: DWORD): HRESULT;
begin
  FillChar(StatStg, SizeOf(StatStg), 0);
  if Mode = 3 then begin StatStg.cbSize := High(Int64); Result := S_OK; end
  else Result := E_NOTIMPL;
end;
procedure TLaunchProbe.ExecuteShellTarget(const Value, Parameters, Directory: WideString; ShowCommand: Integer);
begin Inc(Calls); Target := Value; Arguments := Parameters; Folder := Directory; end;
function TLaunchProbe.StartShellWorker(const Value, Parameters, Directory: WideString; ShowCommand: Integer): Boolean;
begin ExecuteShellTarget(Value, Parameters, Directory, ShowCommand); Result := True; end;
constructor TTestManager.CreateForTests;
begin end;
procedure TTargetPreservationTests.SetUp;
var Id: TGUID;
begin
  OleCheck(OleInitialize(nil));
  CreateGUID(Id);
  Root := ExtractFilePath(ParamStr(0)) + 'preserve-' + GUIDToString(Id);
  if not CreateDir(Root) then RaiseLastOSError;
  IniName := Root + '\items.ini';
  Cleanup := TStringList.Create;
end;
procedure TTargetPreservationTests.TearDown;
var I: Integer; Value: UnicodeString;
begin
  DeleteFile(IniName);
  for I := Cleanup.Count - 1 downto 0 do
  begin
    Value := ShellUTF16(Copy(Cleanup[I], 2, MaxInt));
    if Cleanup[I][1] = 'F' then DeleteFileW(PWideChar(Extended(Value)))
    else RemoveDirectoryW(PWideChar(Extended(Value)));
  end;
  Cleanup.Free;
  RemoveDir(Root);
  OleUninitialize;
end;
function TTargetPreservationTests.FixtureFile(LongPath: Boolean): UnicodeString;
var Directory: UnicodeString; Handle: THandle;
begin
  Directory := ShellUTF16(Root) + '\資料';
  if not CreateDirectoryW(PWideChar(Extended(Directory)), nil) and (GetLastError <> ERROR_ALREADY_EXISTS) then RaiseLastOSError;
  Cleanup.Add('D' + ShellUTF8(Directory));
  if LongPath then
  begin
    Directory := Directory + '\' + UnicodeString(StringOfChar('d', 150));
    if not CreateDirectoryW(PWideChar(Extended(Directory)), nil) then RaiseLastOSError;
    Cleanup.Add('D' + ShellUTF8(Directory));
  end;
  Result := Directory + '\猫-Ж-' + UnicodeString(StringOfChar('f', 45)) + '.txt';
  Handle := CreateFileW(PWideChar(Extended(Result)), GENERIC_WRITE, FILE_SHARE_READ, nil, CREATE_NEW, 0, 0);
  if Handle = INVALID_HANDLE_VALUE then RaiseLastOSError;
  CloseHandle(Handle); Cleanup.Add('F' + ShellUTF8(Result));
end;
function TTargetPreservationTests.FixtureFolder(LongPath: Boolean): UnicodeString;
var I: Integer;
begin
  Result := ShellUTF16(Root);
  for I := 1 to 2 do
  begin
    Result := Result + '\folder-' + IntToStr(I);
    if LongPath then Result := Result + UnicodeString(StringOfChar('d', 160));
    if not CreateDirectoryW(PWideChar(Extended(Result)), nil) then RaiseLastOSError;
    Cleanup.Add('D' + ShellUTF8(Result));
  end;
end;
procedure TTargetPreservationTests.LongFilesystemChecksFindCompleteTargets;
var Folder, Name: UnicodeString;
begin
  Folder := FixtureFolder(True); Name := FixtureFile(True);
  AssertTrue(Length(Folder) > MAX_PATH);
  AssertTrue('Long folder exists', ShellPathExists(Folder));
  AssertTrue('Long folder type', ShellDirectoryExists(Folder));
  AssertFalse('Folder is not a file', ShellFileExists(Folder));
  AssertTrue('Long file exists', ShellPathExists(Name));
  AssertTrue('Long file type', ShellFileExists(Name));
  AssertFalse('File is not a folder', ShellDirectoryExists(Name));
  AssertTrue('Existing extended path', ShellDirectoryExists(Extended(Folder)));
  AssertFalse('Missing long path', ShellPathExists(Folder + '\missing'));
  AssertFalse('Empty path', ShellPathExists(''));
end;
procedure TTargetPreservationTests.RelativeFolderRestoresProgramDirectory;
var Folder: UnicodeString; Relative: string; LongPath: Boolean;
begin
  for LongPath in [False, True] do
  begin
    Folder := FixtureFolder(LongPath); Relative := ZipPath(ShellUTF8(Folder));
    AssertFalse('Saved folder is relative', (Length(Relative) > 1) and (Relative[2] = ':'));
    AssertEquals('Restore exact absolute folder', ShellUTF8(Folder), UnzipPath(Relative));
    AssertEquals('Absolute path stays intact', ShellUTF8(Folder), UnzipPath(ShellUTF8(Folder)));
  end;
  AssertEquals('Unknown relative path stays intact', 'missing-folder\child', UnzipPath('missing-folder\child'));
  AssertEquals('URI stays intact', 'https://example.com/path', UnzipPath('https://example.com/path'));
end;
procedure TTargetPreservationTests.RelativeLongFolderLoadsNativeIcon;
var Folder: UnicodeString; Data: TShortcutDtoV1; Image: Pointer; Width, Height: UINT;
begin
  Folder := FixtureFolder(True);
  Data := ReadShortcutText(TShortcutItem.MakeFromFilename(ShellUTF8(Folder)));
  WriteShortcutIni(IniName, 'item1', Data); Data := ReadShortcutIni(IniName, 'item1');
  Image := nil;
  LoadShortcutImage(ShellUTF16(UnzipPath(Data.Command)), '', 64, False, False, Image, Width, Height);
  try
    AssertTrue('Folder receives a native icon without default fallback', Image <> nil);
    AssertTrue(Width > 0); AssertTrue(Height > 0);
  finally if Image <> nil then GdipDisposeImage(Image); end;
end;
procedure TTargetPreservationTests.RelativeLongFolderLaunchesBothSettings;
var Folder: UnicodeString; Data: TShortcutDtoV1; Settings: TDSets;
  Launch: TLaunchProbe; Threaded: Boolean;
begin
  Folder := FixtureFolder(True);
  Data := ReadShortcutText(TShortcutItem.MakeFromFilename(ShellUTF8(Folder)));
  AssertTrue('Saved relative command exceeds MAX_PATH', Length(Data.Command) > MAX_PATH);
  WriteShortcutIni(IniName, 'item1', Data); Data := ReadShortcutIni(IniName, 'item1');
  Settings := TDSets.Create('', '', 0); Settings.container.useShell := False;
  Launch := TLaunchProbe.Create(Settings, nil);
  try
    for Threaded in [False, True] do
    begin
      Settings.container.RunInThread := Threaded; Launch.Run(Data.Command);
      AssertEquals('Launch receives complete absolute folder', ShellUTF8(Folder), ShellUTF8(Launch.Target));
    end;
    AssertEquals(2, Launch.Calls);
  finally Launch.Free; Settings.Free; end;
end;
procedure TTargetPreservationTests.UnicodeShortcutUsesSelectiveEncoding;
var A, B: TShortcutDtoV1; Text: string;
begin
  A := DefaultShortcutDto;
  A.Caption := UTF8Decode('猫-Ж');
  A.Command := 'C:\資料\report.txt';
  A.Params := '--literal=%20+%pp%';
  A.Directory := 'C:\plain'; A.Image := 'C:\資料\image.png';
  WriteShortcutIni(IniName, 'item1', A);
  AssertEquals(PercentPrefix + '%E7%8C%AB-%D0%96', ShellUTF8(ReadIniStringW(ShellUTF16(IniName), 'item1', 'caption', '')));
  AssertEquals(PercentPrefix + 'C%3A%5C%E8%B3%87%E6%96%99%5Creport.txt', ShellUTF8(ReadIniStringW(ShellUTF16(IniName), 'item1', 'command', '')));
  AssertEquals(A.Params, ShellUTF8(ReadIniStringW(ShellUTF16(IniName), 'item1', 'params', '')));
  AssertEquals(A.Directory, ShellUTF8(ReadIniStringW(ShellUTF16(IniName), 'item1', 'dir', '')));
  B := ReadShortcutIni(IniName, 'item1');
  AssertEquals(A.Command, B.Command);
  AssertEquals(A.Params, B.Params);
  AssertEquals(A.Directory, B.Directory);
  AssertEquals(A.Image, B.Image);
  AssertEquals(UTF8Encode(A.Caption), UTF8Encode(B.Caption));
  Text := WriteShortcutText(A);
  AssertTrue('Only Unicode values receive a prefix', Pos('caption="' + PercentPrefix + '%E7%8C%AB-%D0%96";', Text) > 0);
  AssertTrue('ASCII parameters remain plain', Pos('params="' + A.Params + '";', Text) > 0);
  B := ReadShortcutText(Text);
  AssertEquals(A.Command, B.Command);
  AssertEquals(UTF8Encode(A.Caption), UTF8Encode(B.Caption));
end;
procedure TTargetPreservationTests.ASCIIShortcutKeepsPlainFields;
var A: TShortcutDtoV1;
begin
  A := DefaultShortcutDto; A.Command := 'C:\Apps\one.exe;C:\Apps\two.exe';
  A.Params := 'one;two'; A.Image := 'empty.png;full.png';
  WriteShortcutIni(IniName, 'item1', A);
  AssertEquals(A.Command, UTF8Encode(ReadIniStringW(UTF8Decode(IniName), 'item1', 'command', '')));
  AssertEquals('class="shortcut";command="' + A.Command + '";params="one;two";image="empty.png;full.png";', WriteShortcutText(A));
end;
procedure TTargetPreservationTests.UnicodeStackUsesSelectiveEncoding;
var A, B: TStackDtoV1;
begin
  A := DefaultStackDto; A.Caption := UTF8Decode('資料');
  A.SpecialFolder := '%desktop%'; A.Image := 'C:\資料\icon.png';
  WriteStackIni(IniName, 'item1', A);
  AssertEquals(PercentPrefix + '%E8%B3%87%E6%96%99', ShellUTF8(ReadIniStringW(ShellUTF16(IniName), 'item1', 'caption', '')));
  AssertEquals(A.SpecialFolder, ShellUTF8(ReadIniStringW(ShellUTF16(IniName), 'item1', 'special_folder', '')));
  B := ReadStackIni(IniName, 'item1');
  AssertEquals(A.SpecialFolder, B.SpecialFolder);
  AssertEquals(A.Image, B.Image);
  AssertEquals(UTF8Encode(A.Caption), UTF8Encode(B.Caption));
  B := ReadStackText(WriteStackText(A));
  AssertEquals(A.SpecialFolder, B.SpecialFolder);
  A.Caption := 'Plain stack'; A.SpecialFolder := 'C:\資料';
  WriteStackIni(IniName, 'item1', A);
  AssertEquals('Plain stack', ShellUTF8(ReadIniStringW(ShellUTF16(IniName), 'item1', 'caption', '')));
  AssertEquals(PercentPrefix + 'C%3A%5C%E8%B3%87%E6%96%99', ShellUTF8(ReadIniStringW(ShellUTF16(IniName), 'item1', 'special_folder', '')));
  B := ReadStackIni(IniName, 'item1'); AssertEquals(A.SpecialFolder, B.SpecialFolder);
end;
procedure TTargetPreservationTests.ANSIPluginWritesPreserveUnicodeShortcut;
var A, B: TShortcutDtoV1; Buffer: array[0..63] of AnsiChar;
begin
  AssertTrue(WritePrivateProfileStringA('item2', 'class', 'plugin', PAnsiChar(IniName)));
  AssertTrue(WritePrivateProfileStringA('item2', 'vendor', 'unchanged', PAnsiChar(IniName)));
  A := DefaultShortcutDto; A.Command := 'C:\資料\猫.txt';
  WriteShortcutIni(IniName, 'item1', A);
  AssertTrue(WritePrivateProfileStringA('item2', 'option', 'after-save', PAnsiChar(IniName)));
  GetPrivateProfileStringA('item2', 'vendor', '', @Buffer[0], Length(Buffer), PAnsiChar(IniName));
  AssertEquals('unchanged', StrPas(@Buffer[0]));
  GetPrivateProfileStringA('item2', 'option', '', @Buffer[0], Length(Buffer), PAnsiChar(IniName));
  AssertEquals('after-save', StrPas(@Buffer[0]));
  B := ReadShortcutIni(IniName, 'item1');
  AssertEquals(A.Command, B.Command);
end;
procedure TTargetPreservationTests.HDropPreservesLongPath;
var Path, Payload: UnicodeString; H: HGLOBAL; P: Pointer; Header: TDropFiles;
  Manager: TTestManager; List: TStrings;
begin
  Path := 'C:\' + UnicodeString(StringOfChar('a', 200)) + '\' + UnicodeString(StringOfChar('b', 75)) + '.txt';
  Payload := Path + #0#0;
  H := GlobalAlloc(GMEM_MOVEABLE or GMEM_ZEROINIT, SizeOf(Header) + Length(Payload) * 2);
  AssertTrue(H <> 0);
  P := GlobalLock(H);
  FillChar(Header, SizeOf(Header), 0); Header.pFiles := SizeOf(Header); Header.fWide := True;
  Move(Header, P^, SizeOf(Header)); Move(PWideChar(Payload)^, PByte(P)[SizeOf(Header)], Length(Payload) * 2);
  GlobalUnlock(H);
  Manager := TTestManager.CreateForTests; List := TStringList.Create;
  try
    Manager.AddToListHDrop(H, List);
    AssertEquals(1, List.Count);
    AssertEquals(UTF8Encode(Path), List[0]);
    AssertTrue(GlobalFlags(H) <> GMEM_INVALID_HANDLE);
  finally List.Free; Manager.Free; GlobalFree(H); end;
end;
procedure TTargetPreservationTests.MalformedPIDLHexIsRejected;
const Bad: array[0..5] of string = ('::::0', '::::GG00', '::::01000000', '::::040001', '::::04000102', '::::0000AA');
var Text: string; P: PItemIDList;
begin
  for Text in Bad do
  begin
    P := PIDL_FromString(Text);
    try AssertTrue('Reject malformed PIDL: ' + Text, P = nil);
    finally PIDL_Free(P); end;
  end;
end;
procedure TTargetPreservationTests.CIDAAcceptsLargeAndReorderedLists;
var Bytes: TBytes; P: PItemIDList; Size: Integer; Reordered: Boolean; Used: SizeUInt;
begin
  for Reordered in [False, True] do
  begin
    Bytes := CIDABytes(ItemBytes(3002), ItemBytes(5002), Reordered);
    AssertEquals(1, PIDL_CountFromCIDA(@Bytes[0], Length(Bytes)));
    Size := Length(Bytes); P := PIDL_FromCIDA(0, @Bytes[0], Size);
    try
      AssertTrue(P <> nil); AssertEquals(8002, Size);
      AssertTrue(PIDL_Validate(P, Size, Used)); AssertEquals(Size, Integer(Used));
      AssertEquals('Parent and child each retain their size fields', 5000, PWord(@PByte(P)[3000])^);
    finally PIDL_Free(P); end;
  end;
end;
procedure TTargetPreservationTests.CIDARejectsMalformedBounds;
var Valid, Bad: TBytes; N, I: Integer;
  procedure Reject;
  var P: PItemIDList; Size: Integer;
  begin
    AssertEquals(0, PIDL_CountFromCIDA(@Bad[0], Length(Bad)));
    Size := Length(Bad); P := PIDL_FromCIDA(0, @Bad[0], Size);
    try AssertTrue(P = nil); finally PIDL_Free(P); end;
  end;
begin
  Valid := CIDABytes(EmptyPIDL, ItemBytes(8));
  AssertEquals(0, PIDL_CountFromCIDA(nil, 123));
  for N := 0 to Length(Valid) - 1 do
    AssertEquals('Truncation at ' + IntToStr(N), 0, PIDL_CountFromCIDA(@Valid[0], N));
  for I := 0 to 6 do
  begin
    Bad := Copy(Valid);
    case I of
      0: Put32(Bad, 0, $FFFFFFFF);
      1: Put32(Bad, 4, 1);
      2: Put32(Bad, 8, Length(Bad));
      3: begin Bad[14] := 1; Bad[15] := 0; end;
      4: begin Bad[14] := $FF; Bad[15] := $FF; end;
      5: begin Bad[Length(Bad)-2] := 2; end;
      6: Put32(Bad, 8, 13);
    end;
    Reject;
  end;
end;
procedure TTargetPreservationTests.CIDALimitsCombinedSizeAndCount;
var Bytes: TBytes; Size: Integer; P: PItemIDList;
begin
  Bytes := CIDABytes(EmptyPIDL, ItemBytes(SHELL_PIDL_LIMIT));
  Size := Length(Bytes); P := PIDL_FromCIDA(0, @Bytes[0], Size);
  try AssertTrue(P <> nil); AssertEquals(SHELL_PIDL_LIMIT, Size);
  finally PIDL_Free(P); end;
  Bytes := CIDABytes(ItemBytes(4), ItemBytes(SHELL_PIDL_LIMIT));
  AssertEquals(0, PIDL_CountFromCIDA(@Bytes[0], Length(Bytes)));
  Put32(Bytes, 0, SHELL_ITEM_LIMIT + 1);
  AssertEquals(0, PIDL_CountFromCIDA(@Bytes[0], Length(Bytes)));
  SetLength(Bytes, SHELL_DATA_LIMIT + 1);
  AssertEquals(0, PIDL_CountFromCIDA(@Bytes[0], Length(Bytes)));
end;
procedure TTargetPreservationTests.CIDAFuzzStaysWithinBounds;
var Bytes: TBytes; State: QWord; I, J: Integer;
begin
  State := 12345;
  for I := 0 to 1999 do
  begin
    SetLength(Bytes, I mod 256 + 1);
    for J := 0 to High(Bytes) do
    begin State := (State * 1664525 + 1013904223) and $FFFFFFFF; Bytes[J] := State and 255; end;
    AssertEquals(0, PIDL_CountFromCIDA(@Bytes[0], Length(Bytes)));
  end;
end;
procedure TTargetPreservationTests.ShellStreamsHandlePartialReads;
var Bytes: TBytes; Memory: TMemoryStream; Probe: TPartialStream; Stream: IStream;
  Manager: TTestManager; List: TStrings; Mode: Integer;
begin
  Bytes := ShellCIDA; Manager := TTestManager.CreateForTests; List := TStringList.Create;
  try
    for Mode := 0 to 3 do if Mode <> 2 then
    begin
      Memory := TMemoryStream.Create; Memory.WriteBuffer(Bytes[0], Length(Bytes)); Memory.Position := 0;
      Probe := TPartialStream.Create(Memory, soOwned); Probe.Mode := Mode; Stream := Probe;
      List.Clear; Manager.AddToListIStreamPIDL(Pointer(Stream), List);
      AssertEquals('Partial stream mode ' + IntToStr(Mode), 1, List.Count);
      Stream := nil;
    end;
  finally Stream := nil; List.Free; Manager.Free; end;
end;
procedure TTargetPreservationTests.ShellStreamsRejectFailureAndOversize;
var Bytes: TBytes; Memory: TMemoryStream; Probe: TPartialStream; Stream: IStream;
  Manager: TTestManager; List: TStrings; Raised: Boolean; Mode: Integer;
begin
  Manager := TTestManager.CreateForTests; List := TStringList.Create;
  try
    for Mode := 0 to 1 do
    begin
      if Mode = 0 then Bytes := ShellCIDA else SetLength(Bytes, SHELL_DATA_LIMIT + 1);
      Memory := TMemoryStream.Create; Memory.WriteBuffer(Bytes[0], Length(Bytes)); Memory.Position := 0;
      Probe := TPartialStream.Create(Memory, soOwned);
      if Mode = 0 then Probe.Mode := 2;
      Stream := Probe; Raised := False;
      try Manager.AddToListIStreamPIDL(Pointer(Stream), List);
      except on EDropTransferError do Raised := True; end;
      AssertTrue(Raised); AssertEquals(0, List.Count); Stream := nil;
    end;
  finally Stream := nil; List.Free; Manager.Free; end;
end;
procedure TTargetPreservationTests.MalformedHDropPreservesBorrowedMemory;
var H: HGLOBAL; Data: Pointer; Header: TDropFiles; Manager: TTestManager; List: TStrings;
begin
  H := GlobalAlloc(GMEM_MOVEABLE or GMEM_ZEROINIT, SizeOf(Header) + 8);
  Data := GlobalLock(H); FillChar(Header, SizeOf(Header), 0);
  Header.pFiles := $FFFFFFFF; Header.fWide := True; Move(Header, Data^, SizeOf(Header)); GlobalUnlock(H);
  Manager := TTestManager.CreateForTests; List := TStringList.Create;
  try
    Manager.AddToListHDrop(H, List); AssertEquals(0, List.Count);
    AssertTrue(GlobalFlags(H) <> GMEM_INVALID_HANDLE);
  finally List.Free; Manager.Free; GlobalFree(H); end;
end;
procedure TTargetPreservationTests.HDropLengthBoundaryRejectsWithoutPartialItems;
var H: HGLOBAL; Data: Pointer; Header: TDropFiles; Text: UnicodeString;
  Manager: TTestManager; List: TStrings; N: Integer; Raised: Boolean;
begin
  Manager := TTestManager.CreateForTests; List := TStringList.Create;
  try
    for N := 1023 to 1024 do
    begin
      Text := 'C:\' + UnicodeString(StringOfChar('a', N - 3)) + #0#0;
      H := GlobalAlloc(GMEM_MOVEABLE or GMEM_ZEROINIT, SizeOf(Header) + Length(Text) * 2);
      Data := GlobalLock(H); FillChar(Header, SizeOf(Header), 0);
      Header.pFiles := SizeOf(Header); Header.fWide := True;
      Move(Header, Data^, SizeOf(Header)); Move(PWideChar(Text)^, PByte(Data)[SizeOf(Header)], Length(Text) * 2); GlobalUnlock(H);
      try
        List.Clear; Raised := False;
        try Manager.AddToListHDrop(H, List); except on EDropTransferError do Raised := True; end;
        AssertEquals(N > 1023, Raised);
        if N = 1023 then AssertEquals(1, List.Count) else AssertEquals(0, List.Count);
      finally GlobalFree(H); end;
    end;
  finally List.Free; Manager.Free; end;
end;
procedure TTargetPreservationTests.NativeLongUnicodeShellName;
var Path, Name: UnicodeString; P: PItemIDList;
begin
  Path := FixtureFile(True); AssertTrue(Length(Path) > MAX_PATH);
  P := PIDL_GetFromPath(PChar(ShellUTF8(Path)));
  try
    AssertTrue('Native long Unicode path parses', P <> nil);
    AssertTrue(PIDL_GetDisplayNameText(nil, P, SHGDN_FORPARSING, Name));
    AssertEquals(ShellUTF8(Path), ShellUTF8(Name));
    AssertEquals(ShellUTF8(Path), PIDL_GetDisplayName2(P));
  finally PIDL_Free(P); end;
end;
procedure TTargetPreservationTests.NativeLongUnicodeLinkMetadata;
var Path, LinkName, ExpectedArgs, ExpectedDir, Value: UnicodeString;
  P: PItemIDList; Obj: IUnknown; Link: IShellLinkW; Persist: IPersistFile;
  Target: WideString; Args, Dir, Icon: string; NativeArgs: array[0..2047] of WideChar;
begin
  Path := FixtureFile(True); LinkName := ShellUTF16(Root) + '\unicode.lnk';
  ExpectedDir := ExtractFileDir(ExtractFileDir(Path)); ExpectedArgs := UnicodeString(StringOfChar('a', 600)) + '-猫-Ж';
  Obj := CreateComObject(CLSID_ShellLink); Link := Obj as IShellLinkW; Persist := Obj as IPersistFile;
  P := PIDL_GetFromPath(PChar(ShellUTF8(Path))); AssertTrue(P <> nil);
  try OleCheck(Link.SetIDList(P)); finally PIDL_Free(P); end;
  OleCheck(Link.SetArguments(PWideChar(ExpectedArgs)));
  OleCheck(Link.SetWorkingDirectory(PWideChar(ExpectedDir)));
  Value := ExpectedDir + '\icon-猫.ico'; OleCheck(Link.SetIconLocation(PWideChar(Value), 0));
  OleCheck(Persist.Save(PWideChar(LinkName), True)); Cleanup.Add('F' + ShellUTF8(LinkName));
  OleCheck(Link.GetArguments(@NativeArgs[0], Length(NativeArgs)));
  AssertEquals('Native arguments before reload', ShellUTF8(ExpectedArgs), ShellUTF8(UnicodeString(PWideChar(@NativeArgs[0]))));
  OleCheck(Persist.Load(PWideChar(LinkName), STGM_READ));
  OleCheck(Link.GetArguments(@NativeArgs[0], Length(NativeArgs)));
  AssertEquals('Native arguments after reload', ShellUTF8(ExpectedArgs), ShellUTF8(UnicodeString(PWideChar(@NativeArgs[0]))));
  Target := LinkName;
  AssertTrue('Native link metadata resolves completely', ResolveLNK(0, Target, Args, Dir, Icon));
  AssertEquals(ShellUTF8(Path), ShellUTF8(Target));
  AssertEquals(ShellUTF8(ExpectedArgs), Args); AssertEquals(ShellUTF8(ExpectedDir), Dir);
  AssertEquals(ShellUTF8(Value), Icon);
end;
procedure TTargetPreservationTests.NativeInMemoryLongMetadata;
var Obj: IUnknown; Link: IShellLinkW; Path, Directory, Image, Arguments: UnicodeString;
  Target: WideString; Params, Dir, Icon: string;
begin
  Path := FixtureFile(False); Obj := CreateComObject(CLSID_ShellLink); Link := Obj as IShellLinkW;
  OleCheck(Link.SetPath(PWideChar(Path)));
  Arguments := UnicodeString(StringOfChar('a', 1600)) + '-猫';
  Directory := ShellUTF16(Root) + '\' + UnicodeString(StringOfChar('d', 400)) + '-猫';
  Image := ShellUTF16(Root) + '\' + UnicodeString(StringOfChar('i', 400)) + '-猫.ico';
  OleCheck(Link.SetArguments(PWideChar(Arguments)));
  OleCheck(Link.SetWorkingDirectory(PWideChar(Directory)));
  OleCheck(Link.SetIconLocation(PWideChar(Image), 0));
  Target := 'unchanged.lnk';
  AssertTrue(ReadLNKMetadata(Link, Target, Params, Dir, Icon));
  AssertEquals(ShellUTF8(Path), ShellUTF8(Target));
  AssertEquals(ShellUTF8(Arguments), Params);
  AssertEquals(ShellUTF8(Directory), Dir);
  AssertEquals(ShellUTF8(Image), Icon);
end;
procedure TTargetPreservationTests.FailedLinkConversionPreservesTarget;
var Target: WideString; Args, Dir, Icon: string;
begin
  Target := ShellUTF16(Root) + '\missing.lnk';
  AssertFalse(ResolveLNK(0, Target, Args, Dir, Icon));
  AssertEquals(ShellUTF8(ShellUTF16(Root) + '\missing.lnk'), ShellUTF8(Target));
end;
procedure TTargetPreservationTests.UnicodeLaunchFieldsSurviveBothSettings;
var Settings: TDSets; Launch: TLaunchProbe; A, B: TShortcutDtoV1; Threaded: Boolean;
begin
  A := DefaultShortcutDto; A.Command := ShellUTF8(FixtureFile(False));
  A.Params := '--name="猫-Ж-😀"'; A.Directory := ShellUTF8(ExtractFileDir(ShellUTF16(A.Command)));
  WriteShortcutIni(IniName, 'item1', A); B := ReadShortcutIni(IniName, 'item1');
  Settings := TDSets.Create('', '', 0); Settings.container.useShell := False;
  Launch := TLaunchProbe.Create(Settings, nil);
  try
    for Threaded in [False, True] do
    begin
      Settings.container.RunInThread := Threaded;
      Launch.Run(B.Command, B.Params, B.Directory);
      AssertEquals(A.Command, ShellUTF8(Launch.Target));
      AssertEquals(A.Params, ShellUTF8(Launch.Arguments));
      AssertEquals(A.Directory, ShellUTF8(Launch.Folder));
    end;
    AssertEquals(2, Launch.Calls);
  finally Launch.Free; Settings.Free; end;
end;
procedure TTargetPreservationTests.EncodedStackChildrenSurviveReload;
var A, B: TShortcutDtoV1; Stack: TStackDtoV1; Children: TStringList;
begin
  A := DefaultShortcutDto; A.Command := 'C:\資料\猫.txt';
  Stack := DefaultStackDto; WriteStackIni(IniName, 'item1', Stack);
  WriteIniStringW(ShellUTF16(IniName), 'item1', 'subitem1', ShellUTF16(WriteShortcutText(A)));
  Children := ReadStackChildren(IniName, 'item1', '');
  try AssertEquals(1, Children.Count); B := ReadShortcutText(Children[0]); AssertEquals(A.Command, B.Command);
  finally Children.Free; end;
end;
procedure TTargetPreservationTests.EncodingRejectsMalformedData;
const Bad: array[0..12] of string = ('%', '%0', '%GG', '%FF', '%C0%80',
  '%E7%8C', '%ED%A0%80', '%F4%90%80%80', '%00', '%0A', '%0D', 'raw space', 'raw;separator');
var Text: string; Raised: Boolean; A: TShortcutDtoV1;
begin
  for Text in Bad do
  begin
    Raised := False;
    try A := ReadShortcutText('class="shortcut";command="' + PercentPrefix + Text + '";');
    except on EConvertError do Raised := True; end;
    AssertTrue('Reject invalid encoding ' + Text, Raised);
  end;
end;
procedure TTargetPreservationTests.EncodingReturnsToPlainASCII;
var A: TShortcutDtoV1;
begin
  A := DefaultShortcutDto; A.Command := 'C:\資料\猫.txt'; WriteShortcutIni(IniName, 'item1', A);
  A.Command := 'C:\plain.txt'; WriteShortcutIni(IniName, 'item1', A);
  AssertEquals(A.Command, UTF8Encode(ReadIniStringW(ShellUTF16(IniName), 'item1', 'command', '')));
end;
procedure TTargetPreservationTests.PercentPrefixPreservesLiteralPrefix;
var A, B: TShortcutDtoV1; Raw: string;
begin
  A := DefaultShortcutDto; A.Command := PercentPrefix + 'caf%C3%A9';
  WriteShortcutIni(IniName, 'item1', A);
  Raw := ShellUTF8(ReadIniStringW(ShellUTF16(IniName), 'item1', 'command', ''));
  AssertEquals(PercentPrefix + 'UTF-8%27%27caf%25C3%25A9', Raw);
  B := ReadShortcutIni(IniName, 'item1'); AssertEquals(A.Command, B.Command);
  B := ReadShortcutText(WriteShortcutText(A)); AssertEquals(A.Command, B.Command);
  A.Command := 'utf-8' + #39 + #39 + 'literal';
  B := ReadShortcutText(WriteShortcutText(A)); AssertEquals(A.Command, B.Command);
end;
procedure TTargetPreservationTests.PercentPrefixDecodesExactlyOnce;
var A, B: TShortcutDtoV1; Raw: string;
begin
  A := DefaultShortcutDto; A.Command := 'https://example.com/a%20b?x=a+b';
  A.Params := '--name=猫+%20%pp%'; A.Directory := '%pp%\tools';
  A.Image := 'https://example.com/icon%20x.png';
  WriteShortcutIni(IniName, 'item1', A);
  Raw := ShellUTF8(ReadIniStringW(ShellUTF16(IniName), 'item1', 'params', ''));
  AssertEquals(PercentPrefix + '--name%3D%E7%8C%AB+%2520%25pp%25', Raw);
  B := ReadShortcutIni(IniName, 'item1');
  AssertEquals(A.Command, B.Command); AssertEquals(A.Params, B.Params);
  AssertEquals(A.Directory, B.Directory); AssertEquals(A.Image, B.Image);
  B := ReadShortcutText(WriteShortcutText(A)); AssertEquals(A.Params, B.Params);
end;
procedure TTargetPreservationTests.PercentPrefixAcceptsCharsetCase;
var A: TShortcutDtoV1;
begin
  WriteIniStringW(ShellUTF16(IniName), 'item1', 'caption', 'utf-8' + #39 + #39 + 'caf%c3%a9');
  A := ReadShortcutIni(IniName, 'item1'); AssertEquals('café', ShellUTF8(A.Caption));
  A := ReadShortcutText('class="shortcut";caption="uTf-8' + #39 + #39 + 'caf%C3%A9";');
  AssertEquals('café', ShellUTF8(A.Caption));
end;
procedure TTargetPreservationTests.PercentPrefixLimitPreservesExistingSection;
var A: TShortcutDtoV1; Raised: Boolean;
begin
  A := DefaultShortcutDto; A.Command := 'C:\original.exe'; WriteShortcutIni(IniName, 'item1', A);
  A.Command := 'C:\replacement.exe'; A.Params := StringOfChar(' ', 350000) + '猫';
  Raised := False;
  try WriteShortcutIni(IniName, 'item1', A);
  except on ERangeError do Raised := True; end;
  AssertTrue('Reject oversized percent expansion before clearing the section', Raised);
  AssertEquals('C:\original.exe', ShellUTF8(ReadIniStringW(ShellUTF16(IniName), 'item1', 'command', '')));
end;
procedure TTargetPreservationTests.ExplicitCodePagesDoNotControlUTF8;
var Value: UnicodeString;
begin
  Value := ShellDecodeBytes(AnsiString(#$C6), 1251); AssertEquals('Ж', ShellUTF8(Value));
  Value := ShellDecodeBytes(AnsiString(#$E9), 1252); AssertEquals('é', ShellUTF8(Value));
  AssertEquals('猫-Ж-😀', ShellUTF8(ShellUTF16('猫-Ж-😀')));
end;
procedure TTargetPreservationTests.CP1252DefaultsPreserveOwnedFields;
var A, B: TShortcutDtoV1; Original: TSystemCodePage; CodePage: Integer; Text: string;
  Settings: TDSets; Launch: TLaunchProbe; Threaded: Boolean;
begin
  A := DefaultShortcutDto; A.Caption := ShellUTF16('猫-Ж-😀');
  A.Command := 'C:\資料\猫.txt'; A.Params := '--name="猫-Ж-😀"';
  A.Directory := 'C:\資料'; A.Image := 'C:\資料\icon.png';
  Settings := TDSets.Create('', '', 0); Settings.container.useShell := False;
  Launch := TLaunchProbe.Create(Settings, nil);
  Original := DefaultSystemCodePage;
  try
  for CodePage := 1251 to 1252 do
  begin
    SetMultiByteConversionCodePage(CodePage);
    try
      WriteShortcutIni(IniName, 'item1', A);
      B := ReadShortcutIni(IniName, 'item1'); Text := WriteShortcutText(B);
      B := ReadShortcutText(Text);
      for Threaded in [False, True] do
      begin Settings.container.RunInThread := Threaded; Launch.Run(B.Command, B.Params, B.Directory); end;
    finally SetMultiByteConversionCodePage(Original); end;
    AssertEquals(A.Command, B.Command); AssertEquals(A.Params, B.Params);
    AssertEquals(A.Directory, B.Directory); AssertEquals(A.Image, B.Image);
    AssertEquals(ShellUTF8(A.Caption), ShellUTF8(B.Caption));
    AssertEquals(A.Command, ShellUTF8(Launch.Target));
    AssertEquals(A.Params, ShellUTF8(Launch.Arguments));
    AssertEquals(A.Directory, ShellUTF8(Launch.Folder));
  end;
  AssertEquals(4, Launch.Calls);
  finally SetMultiByteConversionCodePage(Original); Launch.Free; Settings.Free; end;
end;
procedure TTargetPreservationTests.CheckProperties(IsStack: Boolean);
var FixtureTheme: TDTheme; Settings: TItemManagerSettings; Manager: TItemManager;
  Window: HWND; Item: TCustomItem; Form: TProperties; StackForm: TStackProperties;
  Data: TShortcutDtoV1; StackData: TStackDtoV1; Stage: string;
begin
  FixtureTheme := TDTheme(TDTheme.NewInstance); theme := FixtureTheme;
  Settings := Default(TItemManagerSettings); Settings.ItemSize := 32; Settings.BigItemSize := 32;
  Settings.ItemSpacing := 4; Settings.ZoomTime := 100; Settings.SeparatorAlpha := 255;
  Settings.Site := bsBottom; Settings.TaskSpot := -1;
  Manager := TItemManager.Create(0, Settings, nil); Manager.Enable(True);
  Form := nil; StackForm := nil;
  try
    Stage := 'create properties';
    try
    if IsStack then
    begin
      Window := Manager.InsertItem(TStackItem.Make('Original stack'));
      StackForm := TStackProperties.Create(nil); frmStackProp := StackForm;
      AssertTrue(StackForm.Bind(Window)); StackForm.edCaption.Text := '猫-Ж-😀';
      StackForm.edImage.Text := 'C:\資料\icon.png'; StackForm.btnApplyClick(nil);
      AssertTrue(Manager.TryGetManagedItem(Window, Item));
      AssertEquals('猫-Ж-😀', ShellUTF8(TStackItem(Item).Caption));
      Item.Save(IniName, 'item1'); StackData := ReadStackIni(IniName, 'item1');
      AssertEquals('猫-Ж-😀', ShellUTF8(StackData.Caption));
      AssertEquals('C:\資料\icon.png', StackData.Image);
      AssertTrue(StackForm.Bind(Window)); AssertEquals('C:\資料\icon.png', StackForm.edImage.Text);
    end else
    begin
      Stage := 'insert shortcut';
      Window := Manager.InsertItem(TShortcutItem.Make('Original item'));
      Stage := 'construct shortcut form';
      Form := TProperties.Create(nil); frmItemProp := Form;
      Stage := 'bind shortcut form';
      AssertTrue(Form.Bind(Window)); Stage := 'edit caption'; Form.edCaption.Text := '猫-Ж-😀';
      Stage := 'edit target'; Form.edCmd.Text := 'C:\資料\app.exe';
      Stage := 'edit arguments'; Form.edParams.Text := '--name="猫-Ж-😀"';
      Stage := 'edit directory and image';
      Form.edDir.Text := 'C:\資料'; Form.edImage.Text := 'C:\資料\icon.png';
      Stage := 'apply';
      Form.btnApplyClick(nil); AssertTrue(Manager.TryGetManagedItem(Window, Item));
      AssertEquals('C:\資料\app.exe', TShortcutItem(Item).Command);
      Item.Save(IniName, 'item1'); Data := ReadShortcutIni(IniName, 'item1');
      AssertEquals('猫-Ж-😀', ShellUTF8(Data.Caption));
      AssertEquals('C:\資料\app.exe', Data.Command); AssertEquals('--name="猫-Ж-😀"', Data.Params);
      AssertEquals('C:\資料', Data.Directory); AssertEquals('C:\資料\icon.png', Data.Image);
      AssertTrue(Form.Bind(Window)); AssertEquals('C:\資料\app.exe', Form.edCmd.Text);
      AssertEquals('--name="猫-Ж-😀"', Form.edParams.Text);
    end;
    except on E: Exception do raise Exception.Create(Stage + ': ' + E.Message); end;
  finally
    Form.Free; frmItemProp := nil; StackForm.Free; frmStackProp := nil;
    Manager.Free; theme := nil; FixtureTheme.Free; Application.ProcessMessages;
  end;
end;
procedure TTargetPreservationTests.ShortcutPropertiesPreserveUnicode;
begin CheckProperties(False); end;
procedure TTargetPreservationTests.StackPropertiesPreserveUnicode;
begin CheckProperties(True); end;
procedure TTargetPreservationTests.UnicodeCustomImageLoads;
const Encoder: TGUID = '{557CF406-1A04-11D3-9A73-0000F81EF32E}';
var Source, Image: Pointer; Name: UnicodeString; Width, Height: UINT;
begin
  Name := ShellUTF16(Root) + '\猫-Ж.png'; Source := nil; Image := nil;
  AssertEquals(Ord(Ok), Ord(GdipCreateBitmapFromScan0(80, 40, 0, PixelFormat32bppPARGB, nil, Source)));
  try AssertEquals(Ord(Ok), Ord(GdipSaveImageToFile(Source, PWideChar(Name), @Encoder, nil)));
  finally GdipDisposeImage(Source); end;
  Cleanup.Add('F' + ShellUTF8(Name));
  LoadShortcutImage('missing.exe', Name, 64, True, False, Image, Width, Height);
  try AssertTrue(Image <> nil); AssertEquals(64, Integer(Width)); AssertEquals(32, Integer(Height));
  finally if Image <> nil then GdipDisposeImage(Image); end;
end;
procedure TTargetPreservationTests.MetadataLimitRejectsBeforeCommit;
var Obj: IUnknown; Link: IShellLinkW; Path, Arguments: UnicodeString;
  Target: WideString; Params, Dir, Icon: string; Raised: Boolean;
begin
  Path := FixtureFile(False); Obj := CreateComObject(CLSID_ShellLink); Link := Obj as IShellLinkW;
  OleCheck(Link.SetPath(PWideChar(Path)));
  Arguments := UnicodeString(StringOfChar('a', SHELL_TEXT_LIMIT + 1));
  OleCheck(Link.SetArguments(PWideChar(Arguments)));
  Target := 'original.lnk'; Raised := False;
  try ReadLNKMetadata(Link, Target, Params, Dir, Icon);
  except on ERangeError do Raised := True; end;
  AssertTrue('Reject unsupported metadata without committing a shortened target', Raised);
  AssertEquals('original.lnk', ShellUTF8(Target));
end;
procedure TTargetPreservationTests.SharedSaveKeepsANSIPluginContract;
var FixtureTheme: TDTheme; Options: TItemManagerSettings; Manager: TANSIManager;
  Settings: TDSets; Save: TSettingsSaveCoordinator; Data: TShortcutDtoV1;
  Buffer: array[0..127] of AnsiChar; I, Found: Integer; Section: string;
begin
  FixtureTheme := TDTheme(TDTheme.NewInstance); theme := FixtureTheme;
  Options := Default(TItemManagerSettings); Options.ItemSize := 32; Options.BigItemSize := 32;
  Options.Site := bsBottom; Options.TaskSpot := -1;
  Manager := TANSIManager.Create(0, Options, nil); Manager.Enable(True);
  Settings := TDSets.Create(IniName, Root, 0);
  Save := TSettingsSaveCoordinator.Create(Settings.SaveTo, Manager.SaveTo);
  PluginSaveCalls := 0;
  try
    AssertTrue(Manager.InsertItem(TShortcutItem.Make(ShellUTF16('猫-Ж'), 'C:\資料\猫.txt')) <> 0);
    AssertTrue(Manager.InsertItem(TPluginItem.Make('fixture.dll')) <> 0);
    AssertTrue(Save.Save(IniName));
    AssertEquals(1, PluginSaveCalls);
    AssertTrue('Plugin receives the snapshot path', Pos(IniName + '.', PluginSavePath) = 1);
    GetPrivateProfileStringA(PAnsiChar(PluginSaveSection), 'vendor-option', '', @Buffer[0], Length(Buffer), PAnsiChar(IniName));
    AssertEquals('unchanged-ANSI-value', StrPas(@Buffer[0]));
    GetPrivateProfileStringA(PAnsiChar(PluginSaveSection), 'vendor-prefix', '', @Buffer[0], Length(Buffer), PAnsiChar(IniName));
    AssertEquals('Plugin values keep their literal prefix', PercentPrefix + 'caf%C3%A9', StrPas(@Buffer[0]));
    Found := 0;
    for I := 1 to 2 do
    begin
      Section := 'item' + IntToStr(I);
      if ReadIniStringW(ShellUTF16(IniName), ShellUTF16(Section), 'class', '') = 'shortcut' then
      begin
        Data := ReadShortcutIni(IniName, Section); Inc(Found);
        AssertEquals('C:\資料\猫.txt', Data.Command); AssertEquals('猫-Ж', ShellUTF8(Data.Caption));
      end;
    end;
    AssertEquals(1, Found);
    AssertTrue(Save.Save(IniName)); AssertEquals(2, PluginSaveCalls);
    GetPrivateProfileStringA(PAnsiChar(PluginSaveSection), 'vendor-option', '', @Buffer[0], Length(Buffer), PAnsiChar(IniName));
    AssertEquals('unchanged-ANSI-value', StrPas(@Buffer[0]));
    GetPrivateProfileStringA(PAnsiChar(PluginSaveSection), 'vendor-prefix', '', @Buffer[0], Length(Buffer), PAnsiChar(IniName));
    AssertEquals(PercentPrefix + 'caf%C3%A9', StrPas(@Buffer[0]));
  finally Save.Free; Manager.Free; Settings.Free; theme := nil; FixtureTheme.Free; Application.ProcessMessages; end;
end;
initialization
  RegisterTest(TTargetPreservationTests);
end.
