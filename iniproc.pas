unit iniproc;

{$mode delphi}

interface
uses Windows, Classes, SysUtils;

function  ReadIniStringW(ini, section, key, default: WideString): WideString;
function  ReadIniIntW(ini, section, key: WideString; default: integer): integer; overload;
function  ReadIniIntW(ini, section, key: WideString; default, min, max: integer): integer; overload;
function  ReadIniBoolW(ini, section, key: WideString; default: boolean): boolean;
function ParseLegacyBoolean(const Value: string; DefaultValue: boolean): boolean;
procedure CheckIniValue(const Value: WideString);
procedure WriteIniStringW(ini, section, key, value: WideString);
procedure ClearIniSectionW(const ini, section: WideString);

implementation
//------------------------------------------------------------------------------
function ReadIniStringW(ini, section, key, default: WideString): WideString;
var Capacity: integer; Count: DWORD;
begin
  Capacity := 2048;
  repeat
    SetLength(Result, Capacity);
    Count := GetPrivateProfileStringW(PWideChar(section), PWideChar(key),
      PWideChar(default), PWideChar(Result), Capacity, PWideChar(ini));
    if Count < DWORD(Capacity - 1) then
    begin SetLength(Result, Count); Exit; end;
    if Capacity >= 1048576 then raise EReadError.Create('INI value exceeds the supported size');
    Capacity := Capacity * 2;
  until False;
end;
//------------------------------------------------------------------------------
function ReadIniIntW(ini, section, key: WideString; default: integer): integer; overload;
begin
  result := StrToIntDef(Trim(ReadIniStringW(ini, section, key, inttostr(default))), default);
end;
//------------------------------------------------------------------------------
function ReadIniIntW(ini, section, key: WideString; default, min, max: integer): integer; overload;
begin
  result := ReadIniIntW(ini, section, key, default);
  if result < min then result := min;
  if result > max then result := max;
end;
//------------------------------------------------------------------------------
function ReadIniBoolW(ini, section, key: WideString; default: boolean): boolean;
begin
  Result := ParseLegacyBoolean(ReadIniStringW(ini, section, key, ''), default);
end;
//------------------------------------------------------------------------------
function ParseLegacyBoolean(const Value: string; DefaultValue: boolean): boolean;
var Text: string; Number: integer;
begin
  Text := Trim(Value);
  if TryStrToInt(Text, Number) then Exit(Number <> 0);
  if not TryStrToBool(Text, Result) then Result := DefaultValue;
end;
//------------------------------------------------------------------------------
procedure CheckIniValue(const Value: WideString);
begin
  if (Pos(#0, Value) > 0) or (Pos(#10, Value) > 0) or (Pos(#13, Value) > 0) then
    raise EConvertError.Create('The value cannot be stored in the existing INI format');
end;
//------------------------------------------------------------------------------
procedure WriteIniStringW(ini, section, key, value: WideString);
begin
  CheckIniValue(value);
  if not WritePrivateProfileStringW(pwchar(section), pwchar(key), pwchar(value), pwchar(ini)) then
    RaiseLastOSError;
end;
//------------------------------------------------------------------------------
procedure ClearIniSectionW(const ini, section: WideString);
begin
  if not WritePrivateProfileStringW(PWideChar(section), nil, nil, PWideChar(ini)) then
    RaiseLastOSError;
end;
//------------------------------------------------------------------------------
end.

