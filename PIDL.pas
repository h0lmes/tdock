unit PIDL;

interface

uses Windows, ShellApi, ShlObj, ComObj, SysUtils, Forms, ActiveX, shelltextu;

type
  PPItemIDList = ^PItemIDList;

const
  APPS_FOLDER_PREFIX = 'shell:AppsFolder\';

function PIDL_Validate(Data: Pointer; Capacity: SizeUInt; out Used: SizeUInt): Boolean;
function PIDL_CountFromCIDA(ida: PCIDA; size: SizeUInt): longint;
function PIDL_FromCIDA(index: longint; ida: PCIDA; var size: longint): PItemIDList;
function PIDL_ToString(p: Pointer): string; overload;
function PIDL_ToString(p: Pointer; size: uint): string; overload;
function PIDL_FromString(Data: string): PItemIDList;
function PIDL_GetSize(pidl: PITEMIDLIST): integer;
function PIDL_Create(size: uint): PItemIDList;
function PIDL_Copy(pidl: PItemIDList): PItemIDList;
function PIDL_Next(pidl: PItemIDList): PItemIDList;
function PIDL_GetDisplayName(folder: IShellFolder; pidl: PItemIDList; dwFlags: DWORD; pszName: PChar; cchMax: uint): boolean;
function PIDL_GetDisplayNameText(folder: IShellFolder; pidl: PItemIDList;
  dwFlags: DWORD; out Name: UnicodeString): Boolean;
function PIDL_GetDisplayName2(pidl: PItemIDList): string;
function PIDL_GetDisplayName3(pidl: string): string; overload;
function PIDL_GetDisplayName3(pidl: PItemIDList): string; overload;
procedure PIDL_GetRelative(var pidlFQ, ppidlRoot, ppidlItem: PItemIDList);
function PIDL_GetAbsolute(var pidlRoot, pidlItem: PItemIDList): PItemIDList;
function PIDL_GetFromPath(pszFile: PChar): PItemIDList;
function PIDL_GetFileFolder(pidl: PItemIDList; var folder: IShellFolder): boolean;
procedure PIDL_Free(var pidl: PItemIDList);
function IsGUID(str: string): boolean;
function IsShellName(const Target: UnicodeString): Boolean;
function PIDL_ParseTarget(const Target: UnicodeString): PItemIDList;
function TryNormalizeAppTarget(const Target: UnicodeString; out AppID: UnicodeString): Boolean;
function IsPackagedApp(str: string): boolean;
function IsPIDLString(str: string): boolean;
function CSIDL_ToInt(csidl: string): integer;

var
  ShellMalloc: IMalloc;
  {$ifdef PACKAGEDAPP_TESTS}
  PackageFamilyParserUnavailableForTests: Boolean;
  {$endif}

implementation

type
  // FPC 3.2.2 declares IShellItem.GetDisplayName without its output indirection.
  IShellNameItem = interface(IUnknown)
    ['{43826d1e-e718-42ee-bc55-a1e261c37bfe}']
    function BindToHandler(Bind: Pointer; Handler, IID: Pointer; out Obj): HRESULT; stdcall;
    function GetParent(out Parent: IShellNameItem): HRESULT; stdcall;
    function GetDisplayName(Kind: DWORD; out Name: PWideChar): HRESULT; stdcall;
  end;
  TPackageFamilyParser = function(Family: PWideChar; var NameLength: UINT32;
    Name: PWideChar; var PublisherLength: UINT32; Publisher: PWideChar): LongInt; stdcall;

var
  PackageFamilyParser: TPackageFamilyParser;

function CreateNameItem(IDList: PItemIDList; const IID: TGUID; out Item: IShellNameItem): HRESULT; stdcall;
  external 'shell32.dll' name 'SHCreateItemFromIDList';

//------------------------------------------------------------------------------
// get PIDL count from CIDA structure
type
  TPIDLRange = record Offset, Size: SizeUInt; end;
  TCIDARanges = array[0..SHELL_ITEM_LIMIT] of TPIDLRange;

function PIDL_Validate(Data: Pointer; Capacity: SizeUInt; out Used: SizeUInt): Boolean;
var Position: SizeUInt; ItemSize: Word;
begin
  Result := False; Used := 0;
  if Data = nil then Exit;
  if Capacity > SHELL_PIDL_LIMIT then Capacity := SHELL_PIDL_LIMIT;
  Position := 0;
  while (Position <= Capacity) and (Capacity - Position >= SizeOf(Word)) do
  begin
    Move(PByte(Data)[Position], ItemSize, SizeOf(ItemSize));
    if ItemSize = 0 then
    begin Used := Position + SizeOf(Word); Exit(True); end;
    if (ItemSize < SizeOf(Word)) or (ItemSize > Capacity - Position) then Exit;
    Inc(Position, ItemSize);
  end;
end;

function CIDARanges(ida: PCIDA; Size: SizeUInt; out Count: Integer;
  out Ranges: TCIDARanges): Boolean;
var N, Offset: DWORD; Header, I, J: SizeUInt;
begin
  Result := False; Count := 0;
  if (ida = nil) or (Size < 8) or (Size > SHELL_DATA_LIMIT) then Exit;
  Move(ida^, N, SizeOf(N));
  if (N = 0) or (N > SHELL_ITEM_LIMIT) then Exit;
  Header := SizeOf(DWORD) + (SizeUInt(N) + 1) * SizeOf(DWORD);
  if Header > Size then Exit;
  for I := 0 to N do
  begin
    Move(PByte(ida)[SizeOf(DWORD) + I * SizeOf(DWORD)], Offset, SizeOf(Offset));
    if (Offset < Header) or (Offset > Size) or (Size - Offset < 2) then Exit;
    Ranges[I].Offset := Offset;
    if not PIDL_Validate(@PByte(ida)[Offset], Size - Offset, Ranges[I].Size) then Exit;
    for J := 0 to I do
      if (J <> I) and (Ranges[I].Offset < Ranges[J].Offset + Ranges[J].Size) and
        (Ranges[J].Offset < Ranges[I].Offset + Ranges[I].Size) and
        ((Ranges[I].Offset <> Ranges[J].Offset) or (Ranges[I].Size <> Ranges[J].Size)) then Exit;
  end;
  for I := 1 to N do
    if Ranges[0].Size - 2 + Ranges[I].Size > SHELL_PIDL_LIMIT then Exit;
  Count := N; Result := True;
end;

function PIDL_CountFromCIDA(ida: PCIDA; size: SizeUInt): longint;
var Ranges: TCIDARanges; Count: Integer;
begin
  Result := 0;
  if CIDARanges(ida, size, Count, Ranges) then Result := Count;
end;
//------------------------------------------------------------------------------
// converts CIDA structure to a PIDL
function PIDL_FromCIDA(index: longint; ida: PCIDA; var size: longint): PItemIDList;
var Ranges: TCIDARanges; Count: Integer; ParentSize, Total: SizeUInt;
begin
  Result := nil;
  if (size < 0) or not CIDARanges(ida, size, Count, Ranges) then Exit;
  if (index < 0) or (index >= Count) then Exit;
  ParentSize := Ranges[0].Size - 2;
  Total := ParentSize + Ranges[index + 1].Size;
  Result := ShellMalloc.Alloc(Total);
  if Result = nil then Exit;
  if ParentSize > 0 then Move(PByte(ida)[Ranges[0].Offset], Result^, ParentSize);
  Move(PByte(ida)[Ranges[index + 1].Offset], PByte(Result)[ParentSize], Ranges[index + 1].Size);
  size := Total;
end;
//------------------------------------------------------------------------------
function PIDL_ToString(p: Pointer): string;
begin
  Result := PIDL_ToString(p, PIDL_GetSize(p));
end;
//------------------------------------------------------------------------------
function PIDL_ToString(p: Pointer; size: uint): string;
const Digits: string = '0123456789ABCDEF';
var I: UINT; Value: Byte;
begin
  Result := '';
  if (p <> nil) and (size > 0) then
  begin
    if size > SHELL_PIDL_LIMIT then raise ERangeError.Create('Shell identity exceeds supported size');
    SetLength(Result, size * 2 + 4);
    for I := 1 to 4 do Result[I] := ':';
    for I := 0 to size - 1 do
    begin
      Value := PByte(p)[I];
      Result[5 + I * 2] := Digits[(Value shr 4) + 1];
      Result[6 + I * 2] := Digits[(Value and 15) + 1];
    end;
  end;
end;
//------------------------------------------------------------------------------
// converts string of type "::::14001F50E04FD020EA3A6910A2D808002B30309D0000" into a PIDL
// each 2 digits represent one byte of PIDL in hex
function PIDL_FromString(Data: string): PItemIDList;
var I, Size, Used: SizeUInt; Value: Integer; Bytes: TBytes;
begin
  Result := nil;
  if (Copy(Data, 1, 4) <> '::::') or (Length(Data) < 8) or
    ((Length(Data) - 4) mod 2 <> 0) then Exit;
  Size := (Length(Data) - 4) div 2;
  if Size > SHELL_PIDL_LIMIT then Exit;
  SetLength(Bytes, Size);
  for I := 0 to Size - 1 do
  begin
    if not (Data[5 + I * 2] in ['0'..'9', 'a'..'f', 'A'..'F']) or
      not (Data[6 + I * 2] in ['0'..'9', 'a'..'f', 'A'..'F']) then Exit;
    if not TryStrToInt('$' + Copy(Data, 5 + I * 2, 2), Value) then Exit;
    Bytes[I] := Value;
  end;
  if not PIDL_Validate(@Bytes[0], Size, Used) or (Used <> Size) then Exit;
  Result := ShellMalloc.Alloc(Size);
  if Result <> nil then Move(Bytes[0], Result^, Size);
end;
//------------------------------------------------------------------------------
// returns the total number of bytes in an ITEMIDLIST
function PIDL_GetSize(pidl: PItemIDList): integer;
var
  p: PChar;
begin
  Result := 0;
  p := PChar(pidl);
  while p <> nil do
  begin
    if PItemIDList(p + Result)^.mkid.cb = 0 then
    begin
      Inc( Result, sizeof(Word) ); // size of terminator;
      break;
    end;
    Inc( Result, PItemIDList(p + Result)^.mkid.cb );
  end;
end;
//------------------------------------------------------------------------------
function PIDL_Create(size: uint): PItemIDList;
begin
  Result := ShellMalloc.Alloc(size);
  if assigned(Result) then FillChar(Result^, size, #0);
end;
//------------------------------------------------------------------------------
function PIDL_Copy(pidl: PItemIDList): PItemIDList;
var
  size: Integer;
begin
  Result := nil;
  if not Assigned(pidl) then Exit;
  size := PIDL_GetSize(pidl);
  Result := ShellMalloc.Alloc(size);
  if Assigned(Result) then CopyMemory(Result, pidl, size);
end;
//------------------------------------------------------------------------------
function PIDL_Next(pidl: PItemIDList): PItemIDList;
begin
  if assigned(pidl) then Result := PItemIDList(PtrUInt(pidl) + pidl^.mkid.cb)
  else Result := nil;
end;
//------------------------------------------------------------------------------
// retrieves string representation of a PIDL
function PIDL_GetDisplayNameText(folder: IShellFolder; pidl: PItemIDList;
  dwFlags: DWORD; out Name: UnicodeString): Boolean;
var Str: TStrRet; Text: PAnsiChar; Capacity, Count: SizeUInt;
  Item: IShellNameItem; Kind: DWORD; HasName: Boolean;
begin
  Result := False; Name := '';
  if pidl = nil then Exit;
  FillChar(Str, SizeOf(Str), 0);
  HasName := False;
  if folder = nil then
    if CreateNameItem(pidl, StringToGUID('{43826d1e-e718-42ee-bc55-a1e261c37bfe}'), Item) = S_OK then
    begin
      if (dwFlags and SHGDN_FORPARSING) <> 0 then Kind := SIGDN_DESKTOPABSOLUTEPARSING
      else Kind := SIGDN_NORMALDISPLAY;
      Str.uType := STRRET_WSTR;
      HasName := Item.GetDisplayName(Kind, Str.pOleStr) = S_OK;
      if not HasName then
      begin CoTaskMemFree(Str.pOleStr); FillChar(Str, SizeOf(Str), 0); end;
    end;
  if not HasName then
  begin
    if (folder = nil) and Failed(SHGetDesktopFolder(folder)) then Exit;
    if folder.GetDisplayNameOf(pidl, dwFlags, Str) <> S_OK then Exit;
  end;
  case Str.uType of
    STRRET_WSTR:
      try
        if Str.pOleStr = nil then Exit;
        Count := 0;
        while (Count <= SHELL_TEXT_LIMIT) and (Str.pOleStr[Count] <> #0) do Inc(Count);
        if Count > SHELL_TEXT_LIMIT then raise ERangeError.Create('Shell name exceeds supported size');
        SetString(Name, Str.pOleStr, Count);
      finally CoTaskMemFree(Str.pOleStr); end;
    STRRET_OFFSET, STRRET_CSTR:
      begin
        if Str.uType = STRRET_CSTR then
        begin Text := @Str.cStr[0]; Capacity := SizeOf(Str.cStr); end
        else
        begin
          Capacity := PIDL_GetSize(pidl);
          if Str.uOffset >= Capacity then Exit;
          Dec(Capacity, Str.uOffset); Text := PAnsiChar(pidl) + Str.uOffset;
        end;
        Count := 0;
        while (Count < Capacity) and (Text[Count] <> #0) do Inc(Count);
        if Count = Capacity then Exit;
        Name := ShellDecodeBytes(Copy(RawByteString(Text), 1, Count), CP_ACP);
      end;
    else Exit;
  end;
  CheckShellText(Name);
  if (dwFlags and SHGDN_FORPARSING) <> 0 then Name := ShellLongPath(Name);
  Result := True;
end;

function PIDL_GetDisplayName(folder: IShellFolder; pidl: PItemIDList;
  dwFlags: DWORD; pszName: PChar; cchMax: UINT): boolean;
var Name: UnicodeString; Text: UTF8String;
begin
  Result := False;
  if (pszName = nil) or (cchMax = 0) then Exit;
  pszName[0] := #0;
  if not PIDL_GetDisplayNameText(folder, pidl, dwFlags, Name) then Exit;
  Text := ShellUTF8(Name);
  if SizeUInt(Length(Text)) >= cchMax then Exit;
  if Text <> '' then Move(PAnsiChar(Text)^, pszName^, Length(Text));
  pszName[Length(Text)] := #0;
  Result := True;
end;
//------------------------------------------------------------------------------
function PIDL_GetDisplayName2(pidl: PItemIDList): string;
var Name: UnicodeString; apidl: PItemIDList;
begin
  Result := '';
  if PIDL_GetDisplayNameText(nil, pidl, SHGDN_FORPARSING, Name) then Result := ShellUTF8(Name);
  if IsPackagedApp(Result) then Exit;
  if not ShellPathExists(Name) then
  begin
    apidl := PIDL_GetFromPath(PChar(Result));
    if assigned(apidl) then
    begin
      PIDL_Free(apidl);
    end else begin
      result := PIDL_ToString(pidl);
    end;
  end;
end;
//------------------------------------------------------------------------------
function PIDL_GetDisplayName3(pidl: string): string; overload;
var apidl: PItemIDList;
begin
  Result := '';
  apidl := PIDL_FromString(pidl);
  try Result := PIDL_GetDisplayName3(apidl);
  finally PIDL_Free(apidl); end;
end;
//------------------------------------------------------------------------------
function PIDL_GetDisplayName3(pidl: PItemIDList): string; overload;
var Name: UnicodeString;
begin
  Result := '';
  if PIDL_GetDisplayNameText(nil, pidl, SHGDN_NORMAL, Name) then Result := ShellUTF8(Name);
end;
//------------------------------------------------------------------------------
//  takes a fully qualified pidl and returns the relative pidl and the root part
//  pidlFQ   - PITEMIDLIST that needs to be parsed
//  pidlRoot - pidl that will contain the root after parsing
//  pidlItem - pidl that will contain the relative part
procedure PIDL_GetRelative(var pidlFQ, ppidlRoot, ppidlItem: PItemIDList);
var
  pidlTemp, pidlNext: PItemIDList;
begin
  if pidlFQ = nil then
  begin
    ppidlRoot := nil;
    ppidlItem := nil;
    exit;
  end;
  ppidlRoot := PIDL_Copy(pidlFQ);
  pidlTemp := ppidlRoot;
  while pidlTemp^.mkid.cb > 0 do
  begin
    pidlNext := PIDL_Next(pidlTemp);
    if pidlNext^.mkid.cb = 0 then
    begin
      ppidlItem := PIDL_Copy(pidlTemp);
      pidlTemp^.mkid.cb := 0;
      pidlTemp^.mkid.abID[0] := 0;
    end;
    pidlTemp := pidlNext;
  end;
end;
//------------------------------------------------------------------------------
function PIDL_GetAbsolute(var pidlRoot, pidlItem: PItemIDList): PItemIDList;
var ParentSize, ChildSize: SizeUInt;
begin
  Result := nil;
  if (pidlRoot = nil) or (pidlItem = nil) then Exit;
  ParentSize := PIDL_GetSize(pidlRoot); ChildSize := PIDL_GetSize(pidlItem);
  if (ParentSize < 2) or (ChildSize < 2) or (ParentSize - 2 + ChildSize > SHELL_PIDL_LIMIT) then Exit;
  Result := ShellMalloc.Alloc(ParentSize - 2 + ChildSize);
  if Result = nil then Exit;
  Move(pidlRoot^, Result^, ParentSize - 2);
  Move(pidlItem^, PByte(Result)[ParentSize - 2], ChildSize);
end;
//------------------------------------------------------------------------------
// converts filesystem path or GUID (as string) to PIDL //
function PIDL_GetFromPath(pszFile: PChar): PItemIDList;
var Path: UnicodeString;
begin
  Result := nil;
  if pszFile = nil then Exit;
  Path := ShellUTF16(StrPas(pszFile)); CheckShellText(Path);
  if SHParseDisplayName(PWideChar(Path), nil, Result, 0, nil) <> S_OK then PIDL_Free(Result);
end;
//------------------------------------------------------------------------------
// makes IShellFolder for pidl (that is FQ PIDL folder) //
function PIDL_GetFileFolder(pidl: PItemIDList; var folder: IShellFolder): boolean;
var
  desk: IShellFolder;
begin
  Result := False;
  if Failed(SHGetDesktopFolder(desk)) then exit;
  if not assigned(folder) then
    if Failed(SHGetDesktopFolder(folder)) then exit;
  Result := not Failed(desk.BindToObject(pidl, nil, IID_IShellFolder, pointer(folder)));
end;
//------------------------------------------------------------------------------
procedure PIDL_Free(var pidl: PItemIDList);
begin
  if assigned(pidl) then ShellMalloc.Free(pidl);
  pidl := nil;
end;
//------------------------------------------------------------------------------
// GUID starts with "::{"
function IsGUID(str: string): boolean;
begin
  result := strlcomp(pchar(str), '::{', 3) = 0;
end;

function IsShellName(const Target: UnicodeString): Boolean;
begin
  Result := (Copy(Target, 1, 3) = '::{') or
    SameText(UTF8Encode(Copy(Target, 1, 6)), 'shell:');
end;

function PIDL_ParseTarget(const Target: UnicodeString): PItemIDList;
var Status: HRESULT;
begin
  Result := nil;
  CheckShellText(Target);
  if Copy(Target, 1, 4) = '::::' then
  begin
    Result := PIDL_FromString(ShellUTF8(Target));
    if Result = nil then raise EConvertError.Create('Invalid serialized Shell identity');
  end
  else if IsShellName(Target) then
  begin
    Status := SHParseDisplayName(PWideChar(Target), nil, Result, 0, nil);
    if Failed(Status) then
    begin PIDL_Free(Result); OleCheck(Status); end;
    if Result = nil then raise EConvertError.Create('Shell name has no resolved identity');
  end;
end;
//------------------------------------------------------------------------------
// Resolve packaged application targets without changing their saved spelling.
function TryNormalizeAppTarget(const Target: UnicodeString; out AppID: UnicodeString): Boolean;
const
  ShellGUIDPrefix = 'shell:::{4234d49b-0245-4df3-b780-3893943456e1}\';
  GUIDPrefix = '::{4234d49b-0245-4df3-b780-3893943456e1}\';
var
  Candidate, Family, ApplicationID: UnicodeString;
  Separator, I: Integer;
  ExplicitAppsFolder: Boolean;
  PackageName: array[0..50] of WideChar;
  PublisherID: array[0..13] of WideChar;
  NameLength, PublisherLength: UINT32;
  function HasPrefix(const Prefix: string): Boolean;
  begin
    Result := SameText(UTF8Encode(Copy(Target, 1, Length(Prefix))), Prefix);
  end;
begin
  Result := False;
  AppID := '';
  if (Target = '') or (Pos(#0, Target) <> 0) then Exit;
  Candidate := Target;
  ExplicitAppsFolder := True;
  if HasPrefix(APPS_FOLDER_PREFIX) then
    Candidate := Copy(Target, Length(APPS_FOLDER_PREFIX) + 1, MaxInt)
  else if HasPrefix(ShellGUIDPrefix) then
    Candidate := Copy(Target, Length(ShellGUIDPrefix) + 1, MaxInt)
  else if HasPrefix(GUIDPrefix) then
    Candidate := Copy(Target, Length(GUIDPrefix) + 1, MaxInt)
  else ExplicitAppsFolder := False;

  Separator := Pos('!', Candidate);
  if Separator <= 1 then Exit;
  Family := Copy(Candidate, 1, Separator - 1);
  ApplicationID := Copy(Candidate, Separator + 1, MaxInt);
  if (Length(ApplicationID) < 1) or (Length(ApplicationID) > 64) then Exit;
  for I := 1 to Length(ApplicationID) do
    if (Ord(ApplicationID[I]) > 127) or
      not (ApplicationID[I] in ['A'..'Z', 'a'..'z', '0'..'9', '.']) then Exit;

  {$ifdef PACKAGEDAPP_TESTS}
  if PackageFamilyParserUnavailableForTests then Exit;
  {$endif}
  if not Assigned(PackageFamilyParser) then Exit;
  NameLength := Length(PackageName);
  PublisherLength := Length(PublisherID);
  if PackageFamilyParser(PWideChar(Family), NameLength, @PackageName[0],
    PublisherLength, @PublisherID[0]) <> ERROR_SUCCESS then Exit;
  if not ExplicitAppsFolder and (FileExists(Target) or DirectoryExists(Target)) then Exit;
  AppID := Candidate;
  Result := True;
end;
//------------------------------------------------------------------------------
function IsPackagedApp(str: string): boolean;
var AppID: UnicodeString;
begin
  Result := TryNormalizeAppTarget(UTF8Decode(str), AppID);
end;
//------------------------------------------------------------------------------
// proprietary format PIDL string starts with "::::"
function IsPIDLString(str: string): boolean;
begin
  result := strlcomp(pchar(str), '::::', 4) = 0;
end;
//------------------------------------------------------------------------------
// convert CSIDL_ constant name to its value
function CSIDL_ToInt(csidl: string): integer;
begin
  result := -1;
  if strlcomp(pchar(csidl), 'CSIDL_', 6) = 0 then
  begin
    if csidl = 'CSIDL_CONTROLS' then result := CSIDL_CONTROLS
    else if csidl = 'CSIDL_DRIVES' then result := CSIDL_DRIVES
    else if csidl = 'CSIDL_BITBUCKET' then result := CSIDL_BITBUCKET
    else if csidl = 'CSIDL_NETWORK' then result := CSIDL_NETWORK
    else if csidl = 'CSIDL_DESKTOPDIRECTORY' then result := CSIDL_DESKTOPDIRECTORY
    else if csidl = 'CSIDL_PRINTERS' then result := CSIDL_PRINTERS
    else if csidl = 'CSIDL_MYMUSIC' then result := CSIDL_MYMUSIC
    else if csidl = 'CSIDL_MYVIDEO' then result := CSIDL_MYVIDEO;
    // not working properly
    //if csidl = 'CSIDL_PERSONAL' then result := CSIDL_PERSONAL;
    //if csidl = 'CSIDL_MYDOCUMENTS' then result := CSIDL_MYDOCUMENTS;
  end;
end;
//------------------------------------------------------------------------------
initialization
  // Windows 8 provides this API. Earlier Windows keeps its Shell routes.
  @PackageFamilyParser := GetProcAddress(GetModuleHandle('kernel32.dll'),
    'PackageNameAndPublisherIdFromFamilyName');
  SHGetMalloc(ShellMalloc);
finalization
  ShellMalloc := nil;
end.

