unit variableexpansiontests;
{$mode delphi}
interface
uses Windows, SysUtils, fpcunit, testregistry, toolu, shelltextu, launchserviceu, setsu, declu;
type
  TSavedVariable = record
    Name, Value: UnicodeString;
    Existed: Boolean;
  end;
  TVariableExpansionTests = class(TTestCase)
  private
    Name: string;
    Saved: array of TSavedVariable;
    WasVista: Boolean;
    procedure Put(const VariableName, Value: UnicodeString);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure GeneralEnvironmentExpandsUnicode;
    procedure EnvironmentNamesIgnoreCase;
    procedure TDockVariablesWinCollisions;
    procedure InsertedValuesRemainLiteral;
    procedure UnknownAndUnmatchedTokensRemainLiteral;
    procedure ExpansionBoundariesRejectWithoutTruncation;
    procedure CombinedExpansionHasOneBound;
    procedure ExistingLiteralPathsKeepPrecedence;
    procedure UnicodeFieldsReachBothLaunchModes;
    procedure ExpansionPrecedesApplicationRouting;
    procedure InvalidUnicodeAndNullAreRejected;
    procedure NonASCIIEnvironmentNamesAndCodePagesPreserveUnicode;
  end;
implementation
type
  TCaptureLaunch = class(TLaunchService)
  public
    Target, Arguments, Folder: WideString;
    Calls: Integer;
    procedure ExecuteShellTarget(const Value, Parameters, Directory: WideString; ShowCommand: Integer); override;
    function StartShellWorker(const Value, Parameters, Directory: WideString; ShowCommand: Integer): Boolean; override;
    procedure ActivatePackagedApp(const ID: UnicodeString); override;
  end;
procedure TCaptureLaunch.ExecuteShellTarget(const Value, Parameters, Directory: WideString; ShowCommand: Integer);
begin Inc(Calls); Target := Value; Arguments := Parameters; Folder := Directory; end;
function TCaptureLaunch.StartShellWorker(const Value, Parameters, Directory: WideString; ShowCommand: Integer): Boolean;
begin ExecuteShellTarget(Value, Parameters, Directory, ShowCommand); Result := True; end;
procedure TCaptureLaunch.ActivatePackagedApp(const ID: UnicodeString);
begin Inc(Calls); Target := ID; end;
procedure TVariableExpansionTests.SetUp;
var ID: TGUID;
begin
  CreateGUID(ID); Name := 'TDOCK_WO20_' + GUIDToString(ID);
  WasVista := bIsWindowsVistaOrHigher;
  bIsWindowsVistaOrHigher := True;
end;
procedure TVariableExpansionTests.Put(const VariableName, Value: UnicodeString);
var I, N: Integer; Count: DWORD;
begin
  I := 0;
  while (I < Length(Saved)) and (Saved[I].Name <> VariableName) do Inc(I);
  if I = Length(Saved) then
  begin
    N := Length(Saved);
    SetLength(Saved, N + 1);
    Saved[N].Name := VariableName;
    SetLastError(0);
    Count := GetEnvironmentVariableW(PWideChar(VariableName), nil, 0);
    Saved[N].Existed := (Count <> 0) or (GetLastError <> ERROR_ENVVAR_NOT_FOUND);
    if Count <> 0 then
    begin
      SetLength(Saved[N].Value, Count);
      Count := GetEnvironmentVariableW(PWideChar(VariableName), PWideChar(Saved[N].Value), Count);
      SetLength(Saved[N].Value, Count);
    end;
  end;
  AssertTrue(SetEnvironmentVariableW(PWideChar(VariableName), PWideChar(Value)));
end;
procedure TVariableExpansionTests.TearDown;
var I: Integer;
begin
  for I := High(Saved) downto 0 do
    if Saved[I].Existed then SetEnvironmentVariableW(PWideChar(Saved[I].Name), PWideChar(Saved[I].Value))
    else SetEnvironmentVariableW(PWideChar(Saved[I].Name), nil);
  Saved := nil;
  SetEnvironmentVariableW(PWideChar(ShellUTF16(Name)), nil);
  bIsWindowsVistaOrHigher := WasVista;
end;
procedure TVariableExpansionTests.GeneralEnvironmentExpandsUnicode;
var Value: UnicodeString;
begin
  Value := 'C:\' + WideChar($0416) + WideChar($4E2D) + '\launch';
  AssertTrue(SetEnvironmentVariableW(PWideChar(ShellUTF16(Name)), PWideChar(Value)));
  AssertEquals('General environment variables expand without losing Unicode',
    ShellUTF8(Value + '\app.exe'), UnzipPath('%' + Name + '%\app.exe'));
end;
procedure TVariableExpansionTests.EnvironmentNamesIgnoreCase;
begin
  Put(ShellUTF16(Name), 'unicode value');
  AssertEquals('unicode value', UnzipPath('%' + LowerCase(Name) + '%'));
end;
procedure TVariableExpansionTests.TDockVariablesWinCollisions;
var ProgramFolder, SystemFolder, AppData: string;
begin
  ProgramFolder := UnzipPath('%pp%');
  SystemFolder := UnzipPath('%sysdir%');
  AppData := UnzipPath('%appdata%');
  Put('PP', 'wrong'); Put('SYSDIR', 'wrong'); Put('APPDATA', 'wrong');
  AssertEquals(ProgramFolder, UnzipPath('%PP%'));
  AssertEquals(SystemFolder, UnzipPath('%SYSDIR%'));
  AssertEquals(AppData, UnzipPath('%APPDATA%'));
end;
procedure TVariableExpansionTests.InsertedValuesRemainLiteral;
begin
  Put(ShellUTF16(Name), '%sysdir%');
  AssertEquals('%sysdir%', UnzipPath('%' + Name + '%'));
  Put(ShellUTF16(Name + '_SECOND'), ShellUTF16('%' + Name + '%'));
  AssertEquals('%' + Name + '%', UnzipPath('%' + Name + '_SECOND%'));
end;
procedure TVariableExpansionTests.UnknownAndUnmatchedTokensRemainLiteral;
var Value: string;
begin
  Value := '%' + Name + '% unmatched %suffix';
  AssertEquals(Value, UnzipPath(Value));
  AssertEquals('https://example.invalid/a%20b', UnzipPath('https://example.invalid/a%20b'));
  AssertEquals('%% %unclosed', UnzipPath('%% %unclosed'));
end;
procedure TVariableExpansionTests.ExpansionBoundariesRejectWithoutTruncation;
var N: Integer; Value: UnicodeString; Raised: Boolean; Expanded: string;
begin
  for N := SHELL_TEXT_LIMIT - 1 to SHELL_TEXT_LIMIT do
  begin
    Value := UnicodeString(StringOfChar('x', N - 2)) + WideChar($D83D) + WideChar($DE80);
    Put(ShellUTF16(Name), Value);
    Expanded := UnzipPath('%' + Name + '%');
    AssertTrue(ShellUTF16(Expanded) = Value);
  end;
  Raised := False;
  try UnzipPath('%' + Name + '%x'); except on ERangeError do Raised := True; end;
  AssertTrue('Expansion beyond 32766 units rejects', Raised);
end;
procedure TVariableExpansionTests.CombinedExpansionHasOneBound;
var Raised: Boolean;
begin
  Put(ShellUTF16(Name), UnicodeString(StringOfChar('x', 17000)));
  Raised := False;
  try UnzipPath('%' + Name + '%%' + Name + '%'); except on ERangeError do Raised := True; end;
  AssertTrue('Combined output rejects before truncation', Raised);
end;
procedure TVariableExpansionTests.ExistingLiteralPathsKeepPrecedence;
var FileName: UnicodeString; Handle: THandle;
begin
  Put(ShellUTF16(Name), 'changed');
  FileName := ShellUTF16(ExtractFilePath(ParamStr(0)) + '%' + Name + '%');
  Handle := CreateFileW(PWideChar(FileName), GENERIC_WRITE, 0, nil, CREATE_NEW, 0, 0);
  AssertTrue(Handle <> INVALID_HANDLE_VALUE);
  CloseHandle(Handle);
  try AssertEquals(ShellUTF8(FileName), UnzipPath(ShellUTF8(FileName)));
  finally DeleteFileW(PWideChar(FileName)); end;
end;
procedure TVariableExpansionTests.UnicodeFieldsReachBothLaunchModes;
var Settings: TDSets; Service: TCaptureLaunch; Value: UnicodeString; Threaded: Boolean;
begin
  Value := 'C:\' + WideChar($0416) + WideChar($4E2D) + '\launch';
  Put(ShellUTF16(Name), Value);
  Settings := TDSets.Create('', '', 0);
  Service := TCaptureLaunch.Create(Settings, nil);
  try
    Settings.container.useShell := False;
    for Threaded := False to True do
    begin
      Settings.container.RunInThread := Threaded;
      Service.Run('%' + Name + '%\app.exe', '--name "%' + Name + '%"', '%' + Name + '%\work');
      AssertTrue(Service.Target = Value + '\app.exe');
      AssertTrue(Service.Arguments = '--name "' + Value + '"');
      AssertTrue(Service.Folder = Value + '\work');
    end;
    AssertEquals(2, Service.Calls);
  finally Service.Free; Settings.Free; end;
end;
procedure TVariableExpansionTests.ExpansionPrecedesApplicationRouting;
var Settings: TDSets; Service: TCaptureLaunch;
begin
  Put(ShellUTF16(Name), 'TDOCK.Test_8wekyb3d8bbwe!Main');
  Settings := TDSets.Create('', '', 0);
  Service := TCaptureLaunch.Create(Settings, nil);
  try
    Service.Run('%' + Name + '%');
    AssertEquals('TDOCK.Test_8wekyb3d8bbwe!Main', UTF8Encode(Service.Target));
    AssertEquals(1, Service.Calls);
  finally Service.Free; Settings.Free; end;
end;
procedure TVariableExpansionTests.InvalidUnicodeAndNullAreRejected;
var Raised: Boolean;
begin
  Raised := False;
  try UnzipPath('a' + #0 + 'b'); except on ERangeError do Raised := True; end;
  AssertTrue('Embedded null rejects', Raised);
  Raised := False;
  try UnzipPath('a' + #255); except on EConvertError do Raised := True; end;
  AssertTrue('Invalid UTF-8 rejects', Raised);
end;
procedure TVariableExpansionTests.NonASCIIEnvironmentNamesAndCodePagesPreserveUnicode;
const CodePages: array[0..1] of Integer = (1251, 1252);
var VariableName, Value: UnicodeString; OldCodePage: TSystemCodePage; CodePage: Integer;
begin
  VariableName := ShellUTF16(Name) + WideChar($0416) + WideChar($4E2D);
  Value := WideChar($0416) + WideChar($4E2D) + WideChar($D83D) + WideChar($DE80);
  Put(VariableName, Value);
  OldCodePage := DefaultSystemCodePage;
  try
    for CodePage in CodePages do
    begin
      DefaultSystemCodePage := CodePage;
      AssertTrue(ShellUTF16(UnzipPath(ShellUTF8('%' + VariableName + '%'))) = Value);
    end;
  finally DefaultSystemCodePage := OldCodePage; end;
end;
initialization
  RegisterTest(TVariableExpansionTests);
end.
