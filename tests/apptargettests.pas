unit apptargettests;

{$mode delphi}

interface

uses Classes, SysUtils, fpcunit, testregistry, PIDL;

type
  TAppTargetTests = class(TTestCase)
  private
    FOriginalDirectory, FFixtureDirectory: string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure AcceptsDifferentApplicationIDs;
    procedure RejectsFilesystemPaths;
    procedure RejectsURIs;
    procedure RejectsMalformedIdentities;
    procedure AcceptsAppsFolderPrefixes;
    procedure RejectsOtherShellNames;
    procedure ExistingBareFileWins;
    procedure ExistingBareDirectoryWins;
    procedure NormalizationPreservesIdentitySpelling;
    procedure IdentityLengthBoundaries;
    procedure InvalidPackageFamiliesAreRejected;
    procedure InvalidApplicationCharactersAreRejected;
    procedure FailedNormalizationClearsOutput;
    procedure MissingPackageAPIKeepsShellRouting;
  end;

implementation

const
  TestFamily = 'TDOCK.Test_8wekyb3d8bbwe';
  TestApp = TestFamily + '!App';
  AppsGUID = '{4234d49b-0245-4df3-b780-3893943456e1}';

procedure TAppTargetTests.SetUp;
var ID: TGUID;
begin
  FOriginalDirectory := GetCurrentDir;
  repeat
    CreateGUID(ID);
    FFixtureDirectory := ExtractFilePath(ParamStr(0)) + 'fixtures-' + GUIDToString(ID);
    if CreateDir(FFixtureDirectory) then Break;
    if not DirectoryExists(FFixtureDirectory) then RaiseLastOSError;
  until False;
  SetCurrentDir(FFixtureDirectory);
end;

procedure TAppTargetTests.TearDown;
begin
  PackageFamilyParserUnavailableForTests := False;
  DeleteFile(IncludeTrailingPathDelimiter(FFixtureDirectory) + TestApp);
  RemoveDir(IncludeTrailingPathDelimiter(FFixtureDirectory) + TestApp);
  SetCurrentDir(FOriginalDirectory);
  RemoveDir(FFixtureDirectory);
end;

procedure TAppTargetTests.AcceptsDifferentApplicationIDs;
begin
  AssertTrue(IsPackagedApp(TestApp));
  AssertTrue('Main must receive application activation', IsPackagedApp(TestFamily + '!Main'));
  AssertTrue(IsPackagedApp(TestFamily + '!MicrosoftEdge'));
  AssertTrue(IsPackagedApp(TestFamily + '!microsoft.windowslive.calendar'));
end;

procedure TAppTargetTests.RejectsFilesystemPaths;
begin
  AssertFalse('A drive path must keep file routing', IsPackagedApp('C:\Example!App'));
  AssertFalse(IsPackagedApp('\\server\share\Example!App'));
  AssertFalse(IsPackagedApp('.\Example!App'));
  AssertFalse(IsPackagedApp('folder/Example!App'));
  AssertFalse(IsPackagedApp('Example!App'));
end;

procedure TAppTargetTests.RejectsURIs;
begin
  AssertFalse('HTTP URLs must keep URI routing', IsPackagedApp('https://example.invalid/!App'));
  AssertFalse(IsPackagedApp('custom:!App'));
  AssertFalse(IsPackagedApp('custom:' + TestApp));
  AssertFalse(IsPackagedApp('file:///C:/Example!App'));
end;

procedure TAppTargetTests.RejectsMalformedIdentities;
begin
  AssertFalse(IsPackagedApp(''));
  AssertFalse(IsPackagedApp('PackageFamily!App'));
  AssertFalse(IsPackagedApp('!App'));
  AssertFalse(IsPackagedApp(TestFamily + '!'));
  AssertFalse(IsPackagedApp(TestFamily + '!Main!App'));
  AssertFalse(IsPackagedApp(TestFamily + '!Main App'));
  AssertFalse(IsPackagedApp(TestFamily + '!App' + #0 + 'hidden'));
end;

procedure TAppTargetTests.AcceptsAppsFolderPrefixes;
begin
  AssertTrue(IsPackagedApp('shell:AppsFolder\' + TestFamily + '!Main'));
  AssertTrue(IsPackagedApp('ShElL:ApPsFoLdEr\' + TestFamily + '!Main'));
  AssertTrue(IsPackagedApp('shell:::' + AppsGUID + '\' + TestFamily + '!Main'));
  AssertTrue(IsPackagedApp('::' + AppsGUID + '\' + TestFamily + '!Main'));
end;

procedure TAppTargetTests.RejectsOtherShellNames;
begin
  AssertFalse(IsPackagedApp('shell:AppsFolder'));
  AssertFalse(IsPackagedApp('shell:AppsFolder\DesktopApp'));
  AssertFalse(IsPackagedApp('shell:OtherFolder\' + TestApp));
  AssertFalse(IsPackagedApp('::{20D04FE0-3AEA-1069-A2D8-08002B30309D}\' + TestApp));
  AssertFalse(IsPackagedApp('::::0000'));
end;

procedure TAppTargetTests.ExistingBareFileWins;
var Stream: TFileStream;
begin
  Stream := TFileStream.Create(TestApp, fmCreate);
  Stream.Free;
  AssertFalse('Existing files must keep file routing', IsPackagedApp(TestApp));
end;

procedure TAppTargetTests.ExistingBareDirectoryWins;
begin
  AssertTrue(CreateDir(TestApp));
  AssertFalse('Existing folders must keep folder routing', IsPackagedApp(TestApp));
end;

procedure TAppTargetTests.NormalizationPreservesIdentitySpelling;
const ID = 'TDOCK.Test_8WEKYB3D8BBWE!MiXeD.Case1';
var Normalized: UnicodeString;
begin
  AssertTrue(TryNormalizeAppTarget('ShElL:ApPsFoLdEr\' + ID, Normalized));
  AssertEquals('Only the prefix may change', ID, UTF8Encode(Normalized));
  AssertTrue(TryNormalizeAppTarget('shell:::' + UpperCase(AppsGUID) + '\' + ID, Normalized));
  AssertEquals(ID, UTF8Encode(Normalized));
  AssertTrue(TryNormalizeAppTarget('::' + UpperCase(AppsGUID) + '\' + ID, Normalized));
  AssertEquals(ID, UTF8Encode(Normalized));
end;

procedure TAppTargetTests.IdentityLengthBoundaries;
begin
  AssertTrue(IsPackagedApp('abc_0000000000000!1'));
  AssertTrue(IsPackagedApp(StringOfChar('a', 50) + '_0000000000000!' + StringOfChar('b', 64)));
  AssertFalse(IsPackagedApp(StringOfChar('a', 51) + '_0000000000000!App'));
  AssertFalse(IsPackagedApp(TestFamily + '!' + StringOfChar('b', 65)));
  AssertFalse(IsPackagedApp('ab_0000000000000!App'));
end;

procedure TAppTargetTests.InvalidPackageFamiliesAreRejected;
begin
  AssertFalse(IsPackagedApp('abc_iiiiiiiiiiiii!App'));
  AssertFalse(IsPackagedApp('abc_000000000000!App'));
  AssertFalse(IsPackagedApp('abc_00000000000000!App'));
  AssertFalse(IsPackagedApp('con_0000000000000!App'));
  AssertFalse(IsPackagedApp('abc._0000000000000!App'));
  AssertFalse(IsPackagedApp('abc_extra_0000000000000!App'));
end;

procedure TAppTargetTests.InvalidApplicationCharactersAreRejected;
begin
  AssertFalse(IsPackagedApp(TestFamily + '!x_y'));
  AssertFalse(IsPackagedApp(TestFamily + '!x-y'));
  AssertFalse(IsPackagedApp(TestFamily + '!x/y'));
  AssertFalse(IsPackagedApp(TestFamily + '!x\y'));
  AssertFalse(IsPackagedApp(TestFamily + '!x:y'));
  AssertFalse(IsPackagedApp(TestFamily + '!x"y'));
  AssertFalse(IsPackagedApp(TestFamily + '!x' + #9));
  AssertFalse(IsPackagedApp(TestFamily + '!' + UTF8Encode(UnicodeString(WideChar($0141)))));
  AssertFalse(IsPackagedApp(TestFamily + '!' + UTF8Encode(UnicodeString(WideChar($0430)))));
  AssertFalse(IsPackagedApp('"' + TestApp + '"'));
  AssertFalse(IsPackagedApp(' ' + TestApp));
end;

procedure TAppTargetTests.FailedNormalizationClearsOutput;
var Normalized: UnicodeString;
begin
  Normalized := 'old value';
  AssertFalse(TryNormalizeAppTarget('https://example.invalid/!App', Normalized));
  AssertEquals('', UTF8Encode(Normalized));
  AssertFalse(TryNormalizeAppTarget('shell:AppsFolder\\' + TestApp, Normalized));
  AssertFalse(TryNormalizeAppTarget('shell:AppsFolder/' + TestApp, Normalized));
  AssertFalse(TryNormalizeAppTarget('shell:AppsFolder\shell:AppsFolder\' + TestApp, Normalized));
end;

procedure TAppTargetTests.MissingPackageAPIKeepsShellRouting;
begin
  PackageFamilyParserUnavailableForTests := True;
  AssertFalse(IsPackagedApp(TestApp));
  AssertFalse(IsPackagedApp('shell:AppsFolder\' + TestApp));
  PackageFamilyParserUnavailableForTests := False;
  AssertTrue(IsPackagedApp(TestApp));
end;

initialization
  RegisterTest(TAppTargetTests);
end.
