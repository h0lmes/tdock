unit itemserializationu;

{$mode delphi}

interface

uses Windows, Classes, SysUtils, iniproc, gfx;

const
  ITEM_DTO_VERSION = 1;
  STACK_CHILD_LIMIT = 64;
  STACK_MODE_MAX = 9;

type
  TShortcutDtoV1 = record
    Version: integer;
    Caption: WideString;
    Command, Params, Directory, Image: string;
    ColorData, ShowCmd: integer;
    Hide: boolean;
  end;
  TStackDtoV1 = record
    Version: integer;
    Caption: WideString;
    Image, SpecialFolder: string;
    ColorData, Mode, Offset, DistanceSteps, AnimationSpeed, Distort, Preview: integer;
    Background, Sorted: boolean;
  end;

function ParseLegacyItemText(const Text: string): TStringList;
function LegacyItemClass(const Text: string): string;
procedure CheckLegacyItemValue(const Value: string);
function LegacyItemField(const Name, Value: string): string;
function DefaultShortcutDto: TShortcutDtoV1;
function DefaultStackDto: TStackDtoV1;
procedure NormalizeShortcutDto(var Data: TShortcutDtoV1);
procedure NormalizeStackDto(var Data: TStackDtoV1);
function StackDistancePixels(Steps, IconSize: integer): integer;
function ResolveStackDistanceSteps(const Data: TStackDtoV1; IconSize: integer): integer;
function ReadShortcutText(const Text: string): TShortcutDtoV1;
function ReadShortcutIni(const Filename, Section: string): TShortcutDtoV1;
function WriteShortcutText(const Data: TShortcutDtoV1): string;
procedure WriteShortcutIni(const Filename, Section: string;
  const Data: TShortcutDtoV1; SaveCaption: boolean = True);
function ReadStackText(const Text: string): TStackDtoV1;
function ReadStackIni(const Filename, Section: string): TStackDtoV1;
function ReadStackChildren(const Filename, Section, Text: string): TStringList;
function WriteStackText(const Data: TStackDtoV1): string;
procedure WriteStackIni(const Filename, Section: string; const Data: TStackDtoV1);

implementation

uses shelltextu;

const OWNED_TEXT_PREFIX = 'UTF-8' + #39 + #39;
      OWNED_TEXT_LIMIT = 1048574;

function HasOwnedTextPrefix(const Value: RawByteString): Boolean;
var I: Integer;
begin
  if Length(Value) < Length(OWNED_TEXT_PREFIX) then Exit(False);
  for I := 1 to Length(OWNED_TEXT_PREFIX) do
    if UpCase(Value[I]) <> OWNED_TEXT_PREFIX[I] then Exit(False);
  Result := True;
end;

function NeedsEncoding(const Value: RawByteString): Boolean;
var I: Integer;
begin
  ShellUTF16(Value);
  // Escape literal prefixes so decoding once restores their original text.
  if HasOwnedTextPrefix(Value) then Exit(True);
  Result := False;
  for I := 1 to Length(Value) do
    if Ord(Value[I]) > 127 then Exit(True);
end;

function IsOwnedTextAttrChar(Value: AnsiChar): Boolean;
begin
  // RFC 8187 attr-char. A plus sign is literal, not a space.
  Result := Value in ['a'..'z', 'A'..'Z', '0'..'9', '!', '#', '$', '&',
    '+', '-', '.', '^', '_', '`', '|', '~'];
end;

function EncodeOwnedText(const Value: RawByteString): RawByteString;
const Digits: string = '0123456789ABCDEF';
var I, Position, Required: SizeInt;
begin
  if not NeedsEncoding(Value) then Exit(Value);
  Required := Length(OWNED_TEXT_PREFIX);
  for I := 1 to Length(Value) do
  begin
    if IsOwnedTextAttrChar(Value[I]) then Inc(Required)
    else Inc(Required, 3);
    if Required > OWNED_TEXT_LIMIT then
      raise ERangeError.Create('Encoded tdock text exceeds the supported INI value size');
  end;
  SetLength(Result, Required);
  Move(OWNED_TEXT_PREFIX[1], Result[1], Length(OWNED_TEXT_PREFIX));
  Position := Length(OWNED_TEXT_PREFIX) + 1;
  for I := 1 to Length(Value) do
  begin
    if IsOwnedTextAttrChar(Value[I]) then
    begin Result[Position] := Value[I]; Inc(Position); end
    else
    begin
      Result[Position] := '%';
      Result[Position + 1] := Digits[(Ord(Value[I]) shr 4) + 1];
      Result[Position + 2] := Digits[(Ord(Value[I]) and 15) + 1];
      Inc(Position, 3);
    end;
  end;
end;

function DecodeOwnedText(const Value: RawByteString): string;
var I, Position: SizeInt; Number: Integer; Bytes: RawByteString;
begin
  Bytes := Value;
  if HasOwnedTextPrefix(Value) then
  begin
    SetLength(Bytes, Length(Value) - Length(OWNED_TEXT_PREFIX));
    I := Length(OWNED_TEXT_PREFIX) + 1; Position := 0;
    while I <= Length(Value) do
    begin
      Inc(Position);
      if Value[I] = '%' then
      begin
        if I + 2 > Length(Value) then raise EConvertError.Create('Incomplete tdock percent escape');
        if not (Value[I + 1] in ['0'..'9', 'a'..'f', 'A'..'F']) or
          not (Value[I + 2] in ['0'..'9', 'a'..'f', 'A'..'F']) then
          raise EConvertError.Create('Invalid tdock percent escape');
        if not TryStrToInt('$' + Copy(Value, I + 1, 2), Number) then
          raise EConvertError.Create('Invalid tdock percent escape');
        Bytes[Position] := Chr(Number); Inc(I, 3);
      end
      else
      begin
        if not IsOwnedTextAttrChar(Value[I]) then raise EConvertError.Create('Invalid encoded tdock text');
        Bytes[Position] := Value[I]; Inc(I);
      end;
    end;
    SetLength(Bytes, Position);
  end;
  CheckIniValue(ShellUTF16(Bytes));
  SetCodePage(Bytes, CP_UTF8, False);
  Result := Bytes;
end;

function ReadOwnedIni(const Filename, Section, Name: string): RawByteString;
begin
  Result := ShellUTF8(ReadIniStringW(ShellUTF16(Filename), ShellUTF16(Section), ShellUTF16(Name), ''));
end;

procedure EncodeShortcut(var Value: TShortcutDtoV1);
begin
  Value.Caption := ShellUTF16(EncodeOwnedText(ShellUTF8(Value.Caption)));
  Value.Command := EncodeOwnedText(Value.Command);
  Value.Params := EncodeOwnedText(Value.Params);
  Value.Directory := EncodeOwnedText(Value.Directory);
  Value.Image := EncodeOwnedText(Value.Image);
end;

procedure EncodeStack(var Value: TStackDtoV1);
begin
  Value.Caption := ShellUTF16(EncodeOwnedText(ShellUTF8(Value.Caption)));
  Value.Image := EncodeOwnedText(Value.Image);
  Value.SpecialFolder := EncodeOwnedText(Value.SpecialFolder);
end;

function Clamp(Value, Minimum, Maximum: integer): integer;
begin
  if Value < Minimum then Exit(Minimum);
  if Value > Maximum then Exit(Maximum);
  Result := Value;
end;

function ParseLegacyItemText(const Text: string): TStringList;
var Position, Start: integer; Name, Value: string;
begin
  Result := TStringList.Create;
  Result.CaseSensitive := False;
  try
    Position := 1;
    while Position <= Length(Text) do
    begin
      while (Position <= Length(Text)) and (Text[Position] in [' ', #9, ';']) do Inc(Position);
      if Position > Length(Text) then Break;
      Start := Position;
      while (Position <= Length(Text)) and (Text[Position] <> '=') do Inc(Position);
      if Position > Length(Text) then raise EConvertError.Create('Invalid item field');
      Name := LowerCase(Trim(Copy(Text, Start, Position - Start)));
      Inc(Position);
      if (Name = '') or (Position > Length(Text)) or (Text[Position] <> '"') then
        raise EConvertError.Create('Invalid item field: ' + Name);
      Inc(Position);
      Start := Position;
      while Position <= Length(Text) do
      begin
        if (Text[Position] = '"') and (Position < Length(Text)) and
          (Text[Position + 1] = ';') then Break;
        Inc(Position);
      end;
      if Position >= Length(Text) then raise EConvertError.Create('Unterminated item field: ' + Name);
      Value := Copy(Text, Start, Position - Start);
      CheckLegacyItemValue(Value);
      if Result.IndexOfName(Name) >= 0 then raise EConvertError.Create('Duplicate item field: ' + Name);
      Result.Values[Name] := Value;
      Inc(Position, 2);
    end;
  except Result.Free; raise; end;
end;

function LegacyItemClass(const Text: string): string;
var Fields: TStringList; Header: string; LineEnd: integer;
begin
  Header := Text;
  LineEnd := Pos(#10, Header);
  if LineEnd > 0 then Header := TrimRight(Copy(Header, 1, LineEnd - 1));
  Fields := ParseLegacyItemText(Header);
  try
    if Fields.IndexOfName('class') < 0 then Result := 'shortcut'
    else Result := LowerCase(Trim(Fields.Values['class']));
  finally Fields.Free; end;
end;

procedure CheckLegacyItemValue(const Value: string);
begin
  if (Pos('";', Value) > 0) or (Pos(#10, Value) > 0) or
    (Pos(#13, Value) > 0) or (Pos(#0, Value) > 0) then
    raise EConvertError.Create('The value cannot be stored in the existing item format');
end;

function LegacyItemField(const Name, Value: string): string;
begin
  CheckLegacyItemValue(Value);
  Result := Name + '="' + Value + '";';
end;

function DefaultShortcutDto: TShortcutDtoV1;
begin
  Result := Default(TShortcutDtoV1);
  Result.Version := ITEM_DTO_VERSION;
  Result.ShowCmd := SW_SHOWNORMAL;
  Result.ColorData := DEF_COLOR_DATA;
end;

function DefaultStackDto: TStackDtoV1;
begin
  Result := Default(TStackDtoV1);
  Result.Version := ITEM_DTO_VERSION;
  Result.ColorData := DEF_COLOR_DATA;
  Result.AnimationSpeed := 8;
  Result.Distort := 1;
  Result.Preview := 1;
  // Missing distance_steps identifies the old pixel-based offset format.
  Result.DistanceSteps := -1;
end;

procedure NormalizeShortcutDto(var Data: TShortcutDtoV1);
begin
  if Data.Version <> ITEM_DTO_VERSION then raise EConvertError.Create('Unsupported item DTO version');
  if not (Data.ShowCmd in [0..11]) then Data.ShowCmd := SW_SHOWNORMAL;
end;

procedure NormalizeStackDto(var Data: TStackDtoV1);
begin
  if Data.Version <> ITEM_DTO_VERSION then raise EConvertError.Create('Unsupported item DTO version');
  Data.Mode := Clamp(Data.Mode, 0, STACK_MODE_MAX);
  Data.Offset := Clamp(Data.Offset, -100, 100);
  Data.DistanceSteps := Clamp(Data.DistanceSteps, -1, 8);
  Data.AnimationSpeed := Clamp(Data.AnimationSpeed, 1, 20);
  Data.Distort := Clamp(Data.Distort, -10, 10);
  Data.Preview := Clamp(Data.Preview, 0, 2);
end;

function StackDistancePixels(Steps, IconSize: integer): integer;
begin
  if IconSize < 1 then IconSize := 1;
  Result := Round(Int64(Clamp(Steps, 0, 8)) * IconSize / 4);
end;

function ResolveStackDistanceSteps(const Data: TStackDtoV1; IconSize: integer): integer;
begin
  if Data.DistanceSteps >= 0 then Exit(Clamp(Data.DistanceSteps, 0, 8));
  if IconSize < 1 then IconSize := 1;
  Result := Clamp(Round(Int64(Data.Offset) * 4 / IconSize), 0, 8);
end;

function TextInteger(Fields: TStrings; const Name: string; DefaultValue: integer): integer;
begin
  Result := StrToIntDef(Fields.Values[Name], DefaultValue);
end;

function ReadShortcutText(const Text: string): TShortcutDtoV1;
var Fields: TStringList;
begin
  Result := DefaultShortcutDto;
  Fields := ParseLegacyItemText(Text);
  try
    if (Fields.IndexOfName('class') >= 0) and not SameText(Trim(Fields.Values['class']), 'shortcut') then
      raise EConvertError.Create('Stack children must be shortcuts');
    Result.Caption := ShellUTF16(DecodeOwnedText(Fields.Values['caption']));
    Result.Command := DecodeOwnedText(Fields.Values['command']);
    Result.Params := DecodeOwnedText(Fields.Values['params']);
    Result.Directory := DecodeOwnedText(Fields.Values['dir']);
    Result.Image := DecodeOwnedText(Fields.Values['image']);
    Result.Hide := ParseLegacyBoolean(Fields.Values['hide'], False);
    Result.ColorData := TextInteger(Fields, 'color_data', Result.ColorData);
    Result.ShowCmd := TextInteger(Fields, 'showcmd', Result.ShowCmd);
    NormalizeShortcutDto(Result);
  finally Fields.Free; end;
end;

function ReadShortcutIni(const Filename, Section: string): TShortcutDtoV1;
begin
  Result := DefaultShortcutDto;
  Result.Caption := ShellUTF16(DecodeOwnedText(ReadOwnedIni(Filename, Section, 'caption')));
  Result.Command := DecodeOwnedText(ReadOwnedIni(Filename, Section, 'command'));
  Result.Params := DecodeOwnedText(ReadOwnedIni(Filename, Section, 'params'));
  Result.Directory := DecodeOwnedText(ReadOwnedIni(Filename, Section, 'dir'));
  Result.Image := DecodeOwnedText(ReadOwnedIni(Filename, Section, 'image'));
  Result.Hide := ReadIniBoolW(ShellUTF16(Filename), ShellUTF16(Section), 'hide', False);
  Result.ColorData := ReadIniIntW(ShellUTF16(Filename), ShellUTF16(Section), 'color_data', Result.ColorData);
  Result.ShowCmd := ReadIniIntW(ShellUTF16(Filename), ShellUTF16(Section), 'showcmd', Result.ShowCmd);
  NormalizeShortcutDto(Result);
end;

function WriteShortcutText(const Data: TShortcutDtoV1): string;
var Value: TShortcutDtoV1;
begin
  Value := Data;
  NormalizeShortcutDto(Value);
  CheckLegacyItemValue(ShellUTF8(Value.Caption));
  CheckLegacyItemValue(Value.Command); CheckLegacyItemValue(Value.Params);
  CheckLegacyItemValue(Value.Directory); CheckLegacyItemValue(Value.Image);
  EncodeShortcut(Value);
  Result := 'class="shortcut";';
  if Value.Caption <> '' then Result := Result + LegacyItemField('caption', ShellUTF8(Value.Caption));
  if Value.Command <> '' then Result := Result + LegacyItemField('command', Value.Command);
  if Value.Params <> '' then Result := Result + LegacyItemField('params', Value.Params);
  if Value.Directory <> '' then Result := Result + LegacyItemField('dir', Value.Directory);
  if Value.Image <> '' then Result := Result + LegacyItemField('image', Value.Image);
  if Value.ShowCmd <> SW_SHOWNORMAL then Result := Result + LegacyItemField('showcmd', IntToStr(Value.ShowCmd));
  if Value.ColorData <> DEF_COLOR_DATA then Result := Result + LegacyItemField('color_data', '$' + IntToHex(Value.ColorData, 8));
  if Value.Hide then Result := Result + 'hide="1";';
  if Length(Result) > OWNED_TEXT_LIMIT then raise ERangeError.Create('Serialized shortcut exceeds the supported INI value size');
end;

procedure WriteShortcutIni(const Filename, Section: string;
  const Data: TShortcutDtoV1; SaveCaption: boolean);
var Value: TShortcutDtoV1;
begin
  Value := Data;
  NormalizeShortcutDto(Value);
  CheckIniValue(Value.Caption);
  CheckIniValue(ShellUTF16(Value.Command));
  CheckIniValue(ShellUTF16(Value.Params));
  CheckIniValue(ShellUTF16(Value.Directory));
  CheckIniValue(ShellUTF16(Value.Image));
  EncodeShortcut(Value);
  ClearIniSectionW(ShellUTF16(Filename), ShellUTF16(Section));
  WriteIniStringW(ShellUTF16(Filename), ShellUTF16(Section), 'class', 'shortcut');
  if SaveCaption and (Value.Caption <> '') then WriteIniStringW(ShellUTF16(Filename), ShellUTF16(Section), 'caption', Value.Caption);
  if Value.Command <> '' then WriteIniStringW(ShellUTF16(Filename), ShellUTF16(Section), 'command', ShellUTF16(Value.Command));
  if Value.Params <> '' then WriteIniStringW(ShellUTF16(Filename), ShellUTF16(Section), 'params', ShellUTF16(Value.Params));
  if Value.Directory <> '' then WriteIniStringW(ShellUTF16(Filename), ShellUTF16(Section), 'dir', ShellUTF16(Value.Directory));
  if Value.Image <> '' then WriteIniStringW(ShellUTF16(Filename), ShellUTF16(Section), 'image', ShellUTF16(Value.Image));
  if Value.ShowCmd <> SW_SHOWNORMAL then WriteIniStringW(ShellUTF16(Filename), ShellUTF16(Section), 'showcmd', IntToStr(Value.ShowCmd));
  if Value.ColorData <> DEF_COLOR_DATA then WriteIniStringW(ShellUTF16(Filename), ShellUTF16(Section), 'color_data', '$' + IntToHex(Value.ColorData, 8));
  if Value.Hide then WriteIniStringW(ShellUTF16(Filename), ShellUTF16(Section), 'hide', '1');
end;

function ReadStackText(const Text: string): TStackDtoV1;
var Fields: TStringList; Header: string; LineEnd: integer;
begin
  Result := DefaultStackDto;
  Header := Text;
  LineEnd := Pos(#10, Header);
  if LineEnd > 0 then Header := TrimRight(Copy(Header, 1, LineEnd - 1));
  Fields := ParseLegacyItemText(Header);
  try
    Result.Caption := ShellUTF16(DecodeOwnedText(Fields.Values['caption']));
    Result.Image := DecodeOwnedText(Fields.Values['image']);
    Result.SpecialFolder := DecodeOwnedText(Fields.Values['special_folder']);
    Result.ColorData := TextInteger(Fields, 'color_data', Result.ColorData);
    Result.Mode := TextInteger(Fields, 'mode', 0);
    Result.Offset := TextInteger(Fields, 'offset', 0);
    Result.DistanceSteps := TextInteger(Fields, 'distance_steps', -1);
    Result.AnimationSpeed := TextInteger(Fields, 'animation_speed', Result.AnimationSpeed);
    Result.Distort := TextInteger(Fields, 'distort', Result.Distort);
    Result.Preview := TextInteger(Fields, 'preview', Result.Preview);
    Result.Background := ParseLegacyBoolean(Fields.Values['background'], False);
    Result.Sorted := ParseLegacyBoolean(Fields.Values['sorted'], False);
    NormalizeStackDto(Result);
  finally Fields.Free; end;
end;

function ReadStackIni(const Filename, Section: string): TStackDtoV1;
begin
  Result := DefaultStackDto;
  Result.Caption := ShellUTF16(DecodeOwnedText(ReadOwnedIni(Filename, Section, 'caption')));
  Result.Image := DecodeOwnedText(ReadOwnedIni(Filename, Section, 'image'));
  Result.SpecialFolder := DecodeOwnedText(ReadOwnedIni(Filename, Section, 'special_folder'));
  Result.ColorData := ReadIniIntW(ShellUTF16(Filename), ShellUTF16(Section), 'color_data', Result.ColorData);
  Result.Mode := ReadIniIntW(ShellUTF16(Filename), ShellUTF16(Section), 'mode', 0);
  Result.Offset := ReadIniIntW(ShellUTF16(Filename), ShellUTF16(Section), 'offset', 0);
  Result.DistanceSteps := ReadIniIntW(ShellUTF16(Filename), ShellUTF16(Section), 'distance_steps', -1);
  Result.AnimationSpeed := ReadIniIntW(ShellUTF16(Filename), ShellUTF16(Section), 'animation_speed', Result.AnimationSpeed);
  Result.Distort := ReadIniIntW(ShellUTF16(Filename), ShellUTF16(Section), 'distort', Result.Distort);
  Result.Preview := ReadIniIntW(ShellUTF16(Filename), ShellUTF16(Section), 'preview', Result.Preview);
  Result.Background := ReadIniBoolW(ShellUTF16(Filename), ShellUTF16(Section), 'background', False);
  Result.Sorted := ReadIniBoolW(ShellUTF16(Filename), ShellUTF16(Section), 'sorted', False);
  NormalizeStackDto(Result);
end;

function ReadStackChildren(const Filename, Section, Text: string): TStringList;
var Index: integer; Value: string;
begin
  Result := TStringList.Create;
  try
    if Filename <> '' then
    begin
      if ReadIniStringW(ShellUTF16(Filename), ShellUTF16(Section), 'subitem65', '') <> '' then
        raise ERangeError.Create('Stack capacity exceeded');
      for Index := 1 to STACK_CHILD_LIMIT do
      begin
        Value := ReadOwnedIni(Filename, Section, 'subitem' + IntToStr(Index));
        if Value <> '' then Result.Add(Value);
      end;
    end else
    begin
      Result.Text := Text;
      if Result.Count > 0 then Result.Delete(0);
      for Index := Result.Count - 1 downto 0 do if Result[Index] = '' then Result.Delete(Index);
    end;
    if Result.Count > STACK_CHILD_LIMIT then raise ERangeError.Create('Stack capacity exceeded');
    for Value in Result do ReadShortcutText(Value);
  except Result.Free; raise; end;
end;

function WriteStackText(const Data: TStackDtoV1): string;
var Value: TStackDtoV1;
begin
  Value := Data;
  NormalizeStackDto(Value);
  CheckLegacyItemValue(ShellUTF8(Value.Caption));
  CheckLegacyItemValue(Value.Image); CheckLegacyItemValue(Value.SpecialFolder);
  EncodeStack(Value);
  Result := 'class="stack";';
  if Value.Caption <> '' then Result := Result + LegacyItemField('caption', ShellUTF8(Value.Caption));
  if Value.Image <> '' then Result := Result + LegacyItemField('image', Value.Image);
  if Value.SpecialFolder <> '' then Result := Result + LegacyItemField('special_folder', Value.SpecialFolder);
  if Value.ColorData <> DEF_COLOR_DATA then Result := Result + LegacyItemField('color_data', '$' + IntToHex(Value.ColorData, 8));
  if Value.Mode <> 0 then Result := Result + LegacyItemField('mode', IntToStr(Value.Mode));
  if Value.DistanceSteps >= 0 then
    Result := Result + LegacyItemField('distance_steps', IntToStr(Value.DistanceSteps))
  else if Value.Offset <> 0 then Result := Result + LegacyItemField('offset', IntToStr(Value.Offset));
  Result := Result + LegacyItemField('animation_speed', IntToStr(Value.AnimationSpeed));
  Result := Result + LegacyItemField('distort', IntToStr(Value.Distort));
  if Value.Preview <> 1 then Result := Result + LegacyItemField('preview', IntToStr(Value.Preview));
  if Value.Background then Result := Result + 'background="1";';
  if Value.Sorted then Result := Result + 'sorted="1";';
  if Length(Result) > OWNED_TEXT_LIMIT then raise ERangeError.Create('Serialized stack exceeds the supported INI value size');
end;

procedure WriteStackIni(const Filename, Section: string; const Data: TStackDtoV1);
var Value: TStackDtoV1;
begin
  Value := Data;
  NormalizeStackDto(Value);
  CheckIniValue(Value.Caption);
  CheckIniValue(ShellUTF16(Value.Image));
  CheckIniValue(ShellUTF16(Value.SpecialFolder));
  EncodeStack(Value);
  ClearIniSectionW(ShellUTF16(Filename), ShellUTF16(Section));
  WriteIniStringW(ShellUTF16(Filename), ShellUTF16(Section), 'class', 'stack');
  if Value.Caption <> '' then WriteIniStringW(ShellUTF16(Filename), ShellUTF16(Section), 'caption', Value.Caption);
  if Value.Image <> '' then WriteIniStringW(ShellUTF16(Filename), ShellUTF16(Section), 'image', ShellUTF16(Value.Image));
  if Value.ColorData <> DEF_COLOR_DATA then WriteIniStringW(ShellUTF16(Filename), ShellUTF16(Section), 'color_data', '$' + IntToHex(Value.ColorData, 8));
  if Value.Mode <> 0 then WriteIniStringW(ShellUTF16(Filename), ShellUTF16(Section), 'mode', IntToStr(Value.Mode));
  if Value.DistanceSteps >= 0 then
    WriteIniStringW(ShellUTF16(Filename), ShellUTF16(Section), 'distance_steps', IntToStr(Value.DistanceSteps))
  else if Value.Offset <> 0 then WriteIniStringW(ShellUTF16(Filename), ShellUTF16(Section), 'offset', IntToStr(Value.Offset));
  if Value.AnimationSpeed <> 8 then WriteIniStringW(ShellUTF16(Filename), ShellUTF16(Section), 'animation_speed', IntToStr(Value.AnimationSpeed));
  if Value.Distort <> 1 then WriteIniStringW(ShellUTF16(Filename), ShellUTF16(Section), 'distort', IntToStr(Value.Distort));
  if Value.SpecialFolder <> '' then WriteIniStringW(ShellUTF16(Filename), ShellUTF16(Section), 'special_folder', ShellUTF16(Value.SpecialFolder));
  if Value.Preview <> 1 then WriteIniStringW(ShellUTF16(Filename), ShellUTF16(Section), 'preview', IntToStr(Value.Preview));
  if Value.Background then WriteIniStringW(ShellUTF16(Filename), ShellUTF16(Section), 'background', '1');
  if Value.Sorted then WriteIniStringW(ShellUTF16(Filename), ShellUTF16(Section), 'sorted', '1');
end;

end.
