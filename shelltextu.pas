unit shelltextu;
{$mode delphi}
interface
uses Windows, SysUtils;
const
  SHELL_TEXT_LIMIT = 32766;
  SHELL_DATA_LIMIT = 1048576;
  SHELL_PIDL_LIMIT = 65536;
  SHELL_ITEM_LIMIT = 64;
function ShellUTF16(const Text: RawByteString): UnicodeString;
function ShellUTF8(const Text: UnicodeString): RawByteString;
function ShellDecodeBytes(const Text: RawByteString; CodePage: UINT): UnicodeString;
procedure CheckShellText(const Text: UnicodeString);
function ShellPathExists(const Path: UnicodeString): Boolean;
function ShellFileExists(const Path: UnicodeString): Boolean;
function ShellDirectoryExists(const Path: UnicodeString): Boolean;
function ShellLongPath(const Path: UnicodeString): UnicodeString;
function ShellProgramPath: string;
implementation
const WC_ERR_INVALID_CHARS = $00000080;
function NativeLongPathName(Path, Buffer: PWideChar; Capacity: DWORD): DWORD; stdcall;
  external 'kernel32.dll' name 'GetLongPathNameW';
function ShellDecodeBytes(const Text: RawByteString; CodePage: UINT): UnicodeString;
var Count: Integer;
begin
  Result := '';
  if Text = '' then Exit;
  Count := MultiByteToWideChar(CodePage, MB_ERR_INVALID_CHARS, PAnsiChar(Text), Length(Text), nil, 0);
  if Count = 0 then raise EConvertError.Create('Invalid text encoding');
  SetLength(Result, Count);
  if MultiByteToWideChar(CodePage, MB_ERR_INVALID_CHARS, PAnsiChar(Text), Length(Text),
    PWideChar(Result), Count) <> Count then raise EConvertError.Create('Invalid text encoding');
end;
function ShellUTF16(const Text: RawByteString): UnicodeString;
begin Result := ShellDecodeBytes(RawByteString(Text), CP_UTF8); end;
function ShellUTF8(const Text: UnicodeString): RawByteString;
var Count: Integer;
begin
  Result := '';
  if Text = '' then Exit;
  Count := WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, PWideChar(Text), Length(Text), nil, 0, nil, nil);
  if Count = 0 then raise EConvertError.Create('Invalid UTF-16 text');
  SetLength(Result, Count);
  if WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, PWideChar(Text), Length(Text),
    PAnsiChar(Result), Count, nil, nil) <> Count then raise EConvertError.Create('Invalid UTF-16 text');
  SetCodePage(Result, CP_UTF8, False);
end;
procedure CheckShellText(const Text: UnicodeString);
begin
  if (Length(Text) > SHELL_TEXT_LIMIT) or (Pos(#0, Text) > 0) then
    raise ERangeError.Create('Shell text exceeds its supported size or contains a null character');
  ShellUTF8(Text);
end;
function FileSystemAttributes(const Path: UnicodeString): DWORD;
var NativePath: UnicodeString;
begin
  NativePath := Path;
  // Keep extended prefixes at the filesystem boundary. Shell APIs receive ordinary paths.
  if Length(Path) >= MAX_PATH then
    if (Path[2] = ':') and (Path[3] = '\') then NativePath := '\\?\' + Path
    else if (Copy(Path, 1, 2) = '\\') and
      (Copy(Path, 1, 4) <> '\\?\') and (Copy(Path, 1, 4) <> '\\.\') then
      NativePath := '\\?\UNC\' + Copy(Path, 3, MaxInt);
  Result := GetFileAttributesW(PWideChar(NativePath));
end;
function ShellPathExists(const Path: UnicodeString): Boolean;
begin Result := (Path <> '') and (FileSystemAttributes(Path) <> INVALID_FILE_ATTRIBUTES); end;
function ShellFileExists(const Path: UnicodeString): Boolean;
var Attributes: DWORD;
begin
  Attributes := FileSystemAttributes(Path);
  Result := (Attributes <> INVALID_FILE_ATTRIBUTES) and ((Attributes and FILE_ATTRIBUTE_DIRECTORY) = 0);
end;
function ShellDirectoryExists(const Path: UnicodeString): Boolean;
var Attributes: DWORD;
begin
  Attributes := FileSystemAttributes(Path);
  Result := (Attributes <> INVALID_FILE_ATTRIBUTES) and ((Attributes and FILE_ATTRIBUTE_DIRECTORY) <> 0);
end;
function ShellLongPath(const Path: UnicodeString): UnicodeString;
var Input: UnicodeString; Buffer: array of WideChar; Required, Count: DWORD;
begin
  Result := Path;
  // Namespace identifiers and URIs must not enter filesystem normalization.
  if (Length(Path) >= 3) and (Path[2] = ':') and (Path[3] = '\') then Input := '\\?\' + Path
  else if (Copy(Path, 1, 2) = '\\') and (Copy(Path, 1, 4) <> '\\?\') then
    Input := '\\?\UNC\' + Copy(Path, 3, MaxInt)
  else Exit;
  Required := NativeLongPathName(PWideChar(Input), nil, 0);
  if Required = 0 then Exit;
  if Required > SHELL_TEXT_LIMIT + 1 then raise ERangeError.Create('Long filesystem name exceeds supported size');
  SetLength(Buffer, Required + 1);
  Count := NativeLongPathName(PWideChar(Input), @Buffer[0], Length(Buffer));
  if (Count = 0) or (Count >= DWORD(Length(Buffer))) then Exit;
  SetString(Result, PWideChar(@Buffer[0]), Count);
  if Copy(Result, 1, 8) = '\\?\UNC\' then Result := '\\' + Copy(Result, 9, MaxInt)
  else if Copy(Result, 1, 4) = '\\?\' then Delete(Result, 1, 4);
  CheckShellText(Result);
end;
function ShellProgramPath: string;
var Buffer: array of WideChar; Count: DWORD;
begin
  SetLength(Buffer, 256);
  repeat
    Count := GetModuleFileNameW(0, @Buffer[0], Length(Buffer));
    if Count = 0 then RaiseLastOSError;
    if Count < DWORD(Length(Buffer)) then Break;
    if Length(Buffer) >= SHELL_TEXT_LIMIT + 2 then raise ERangeError.Create('Program path exceeds supported size');
    if Length(Buffer) * 2 > SHELL_TEXT_LIMIT + 2 then SetLength(Buffer, SHELL_TEXT_LIMIT + 2)
    else SetLength(Buffer, Length(Buffer) * 2);
  until False;
  CheckShellText(UnicodeString(PWideChar(@Buffer[0])));
  Result := ShellUTF8(UnicodeString(PWideChar(@Buffer[0])));
end;
end.
