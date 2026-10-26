unit appmetadatatests;

{$mode delphi}

interface

uses Windows, Classes, SysUtils, ActiveX, ComObj, ShlObj, ShellAPI, fpcunit,
  testregistry, scitemu, scsubitemu, stackitemu, customsubitemu, declu, itemserializationu, iconserviceu;

type
  TMetadataShortcut = class(TShortcutItem)
  protected
    function ParseAppShellItem(const ParsingName: UnicodeString): PItemIDList; override;
  public
    function HasImage: Boolean;
  end;

  TMetadataSubitem = class(TShortcutSubitem)
  protected
    function ParseAppShellItem(const ParsingName: UnicodeString): PItemIDList; override;
  public
    function HasImage: Boolean;
  end;

  TMetadataStack = class(TStackItem)
  protected
    function CreateSubitem: TCustomSubitem; override;
  public
    Child: TMetadataSubitem;
  end;

  TAppMetadataTests = class(TTestCase)
  private
    FItem: TMetadataShortcut;
    FSubitem: TMetadataSubitem;
    FExpectedCaption: string;
    procedure CreateShortcut(const Caption: WideString; const Image: string = '';
      const Target: string = '');
    procedure CreateStackShortcut(const Caption: WideString; const Image: string = '';
      const Target: string = '');
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure StackFactoryUsesPackagedPlaceholder;
    procedure StackNameAndIconUseAppsFolder;
    procedure StackCustomCaptionAndImageArePreserved;
    procedure StackMissingMetadataCanBeRetried;
    procedure StackMetadataSurvivesReloadWithConfiguredFields;
    procedure StackPrefixedAndNonAppIDsUseCanonicalMetadata;
    procedure StackPathsAndURIsDoNotRequestAppMetadata;
    procedure NativeMissingStackApplicationDoesNotRaise;
    procedure DroppedStackApplicationUsesShellCaption;
    procedure NameAndIconUseAppsFolder;
    procedure CustomCaptionIsPreserved;
    procedure CustomImageIsPreserved;
    procedure MissingMetadataPreservesLauncher;
    procedure MissingMetadataCanBeRetried;
    procedure ResolvedMetadataSurvivesSaveReload;
    procedure NativeMissingApplicationDoesNotRaise;
    procedure NonAppIDUsesAppsFolderMetadata;
    procedure PrefixedIDsUseCanonicalMetadataAndKeepSavedCommands;
    procedure PathsAndURIsEndingAppDoNotRequestAppMetadata;
  end;

implementation

uses themeu;

const
  CalculatorID = 'Microsoft.WindowsCalculator_8wekyb3d8bbwe!App';
  CalculatorShellName = 'shell:AppsFolder\' + CalculatorID;

var
  ParseRequests: TStringList;
  MetadataSource: UnicodeString;
  MetadataUnavailable: Boolean;

function NoPackageArtwork(const Name: UnicodeString; IDList: PItemIDList;
  out LogoPath: UnicodeString): Boolean;
begin
  LogoPath := '';
  Result := False;
end;

function ResolveMetadataIcon(const Name: UnicodeString; IDList: PItemIDList;
  out Factory: IShellItemImageFactory): HRESULT;
begin
  if Pos('shell:AppsFolder\', Name) = 1 then
  begin
    ParseRequests.Add(UTF8Encode(Name));
    if MetadataUnavailable then Exit(E_FAIL);
    Result := SHCreateItemFromParsingName(PWideChar(MetadataSource), nil,
      IID_IShellItemImageFactory, Factory);
  end
  else Result := SHCreateItemFromParsingName(PWideChar(Name), nil,
    IID_IShellItemImageFactory, Factory);
end;

function TMetadataShortcut.ParseAppShellItem(const ParsingName: UnicodeString): PItemIDList;
begin
  ParseRequests.Add(UTF8Encode(ParsingName));
  Result := nil;
  if MetadataUnavailable then Exit;
  // A real filesystem Shell item supplies metadata without an installed package.
  if SHParseDisplayName(PWideChar(MetadataSource), nil, Result, 0, nil) <> S_OK then
    raise Exception.Create('Cannot create the metadata fixture Shell item');
end;

function TMetadataShortcut.HasImage: Boolean;
begin Result := FImage <> nil; end;

function TMetadataSubitem.ParseAppShellItem(const ParsingName: UnicodeString): PItemIDList;
begin
  ParseRequests.Add(UTF8Encode(ParsingName));
  Result := nil;
  if MetadataUnavailable then Exit;
  if SHParseDisplayName(PWideChar(MetadataSource), nil, Result, 0, nil) <> S_OK then
    raise Exception.Create('Cannot create the metadata fixture Shell item');
end;

function TMetadataSubitem.HasImage: Boolean;
begin Result := FImage <> nil; end;

function TMetadataStack.CreateSubitem: TCustomSubitem;
var Params: TDItemCreateParams;
begin
  Params := Default(TDItemCreateParams);
  Params.ItemSize := 32; Params.BigItemSize := 64;
  Child := TMetadataSubitem.Create(Handle, Params);
  Result := Child;
end;

procedure TAppMetadataTests.SetUp;
var Info: TSHFileInfoW;
begin
  OleCheck(OleInitialize(nil));
  FItem := nil;
  FSubitem := nil;
  ResolveIconFactoryForTests := ResolveMetadataIcon;
  ResolvePackageArtworkForTests := NoPackageArtwork;
  ParseRequests := TStringList.Create;
  MetadataUnavailable := False;
  MetadataSource := UnicodeString(GetEnvironmentVariable('SystemRoot') +
    '\System32\notepad.exe');
  FillChar(Info, SizeOf(Info), 0);
  if SHGetFileInfoW(PWideChar(MetadataSource), 0, Info, SizeOf(Info),
    SHGFI_DISPLAYNAME) = 0 then raise Exception.Create('Cannot read fixture metadata');
  FExpectedCaption := UTF8Encode(UnicodeString(PWideChar(@Info.szDisplayName)));
end;

procedure TAppMetadataTests.TearDown;
begin
  FItem.Free;
  FSubitem.Free;
  ResolveIconFactoryForTests := nil;
  ResolvePackageArtworkForTests := nil;
  ParseRequests.Free;
  OleUninitialize;
end;

procedure TAppMetadataTests.CreateShortcut(const Caption: WideString; const Image: string;
  const Target: string);
var Params: TDItemCreateParams; Command: string;
begin
  Params := Default(TDItemCreateParams);
  Params.ItemSize := 32;
  Params.BigItemSize := 64;
  Command := Target;
  if Command = '' then Command := CalculatorID;
  Params.Parameter := TShortcutItem.Make(Caption, Command, '', '', Image);
  FItem := TMetadataShortcut.Create(0, Params);
end;

procedure TAppMetadataTests.CreateStackShortcut(const Caption: WideString; const Image: string;
  const Target: string);
var Params: TDItemCreateParams; Command: string;
begin
  Params := Default(TDItemCreateParams);
  Params.ItemSize := 32;
  Params.BigItemSize := 64;
  Command := Target;
  if Command = '' then Command := CalculatorID;
  FSubitem := TMetadataSubitem.Create(0, Params);
  FSubitem.FromString(TShortcutSubitem.Make(Caption, Command, '', '', Image));
end;

procedure TAppMetadataTests.StackNameAndIconUseAppsFolder;
begin
  CreateStackShortcut('?');
  AssertEquals('Stack captions must use the Shell display name', FExpectedCaption, UTF8Encode(FSubitem.Caption));
  AssertEquals(2, ParseRequests.Count);
  AssertEquals(CalculatorShellName, ParseRequests[0]);
  AssertEquals(CalculatorShellName, ParseRequests[1]);
  AssertEquals(CalculatorID, FSubitem.Command);
  AssertEquals('', FSubitem.ImageFile);
  AssertTrue(FSubitem.HasImage);
end;

procedure TAppMetadataTests.StackCustomCaptionAndImageArePreserved;
begin
  CreateStackShortcut('My calculator', UTF8Encode(MetadataSource));
  AssertEquals('My calculator', UTF8Encode(FSubitem.Caption));
  AssertEquals(UTF8Encode(MetadataSource), FSubitem.ImageFile);
  AssertEquals(CalculatorID, FSubitem.Command);
  AssertEquals('Custom fields must bypass app metadata', 0, ParseRequests.Count);
  AssertTrue(FSubitem.HasImage);
  FSubitem.FromString(TShortcutSubitem.Make('My calculator', CalculatorID));
  AssertEquals('My calculator', UTF8Encode(FSubitem.Caption));
  AssertEquals('Only the automatic icon needs metadata', 1, ParseRequests.Count);
  AssertEquals(CalculatorShellName, ParseRequests[0]);
end;

procedure TAppMetadataTests.StackMissingMetadataCanBeRetried;
begin
  MetadataUnavailable := True;
  CreateStackShortcut('?');
  AssertEquals('?', UTF8Encode(FSubitem.Caption));
  AssertEquals(CalculatorID, FSubitem.Command);
  AssertEquals('', FSubitem.ImageFile);
  AssertTrue(FSubitem.HasImage);
  AssertEquals(2, ParseRequests.Count);
  MetadataUnavailable := False;
  FSubitem.Update;
  AssertEquals(FExpectedCaption, UTF8Encode(FSubitem.Caption));
  AssertEquals(CalculatorID, FSubitem.Command);
  AssertEquals(4, ParseRequests.Count);
end;

procedure TAppMetadataTests.StackMetadataSurvivesReloadWithConfiguredFields;
var Saved: TShortcutDtoV1;
begin
  CreateStackShortcut('?');
  FSubitem.FromString(TShortcutSubitem.Make('?', CalculatorID, '--configured', 'C:\', '', 2));
  Saved := ReadShortcutText(FSubitem.ToString);
  AssertEquals(FExpectedCaption, UTF8Encode(Saved.Caption));
  AssertEquals(CalculatorID, Saved.Command);
  AssertEquals('--configured', Saved.Params);
  AssertEquals('C:\', Saved.Directory);
  AssertEquals(2, Saved.ShowCmd);
  AssertEquals('', Saved.Image);
  FreeAndNil(FSubitem);
  ParseRequests.Clear;
  CreateStackShortcut(Saved.Caption, Saved.Image, Saved.Command);
  FSubitem.FromString(WriteShortcutText(Saved));
  Saved := ReadShortcutText(FSubitem.ToString);
  AssertEquals(FExpectedCaption, UTF8Encode(Saved.Caption));
  AssertEquals(CalculatorID, Saved.Command);
  AssertEquals('--configured', Saved.Params);
  AssertEquals('C:\', Saved.Directory);
  AssertEquals('Reload must only request icons', 2, ParseRequests.Count);
end;

procedure TAppMetadataTests.StackPrefixedAndNonAppIDsUseCanonicalMetadata;
const Prefixes: array[0..3] of string = ('', 'ShElL:ApPsFoLdEr\',
  'shell:::{4234d49b-0245-4df3-b780-3893943456e1}\',
  '::{4234d49b-0245-4df3-b780-3893943456e1}\');
  AppID = 'TDOCK.Test_8wekyb3d8bbwe!Main';
var Prefix, Target: string; Saved: TShortcutDtoV1;
begin
  for Prefix in Prefixes do
  begin
    Target := Prefix + AppID;
    CreateStackShortcut('?', '', Target);
    AssertEquals(FExpectedCaption, UTF8Encode(FSubitem.Caption));
    AssertEquals(2, ParseRequests.Count);
    AssertEquals('shell:AppsFolder\' + AppID, ParseRequests[0]);
    AssertEquals('shell:AppsFolder\' + AppID, ParseRequests[1]);
    Saved := ReadShortcutText(FSubitem.ToString);
    AssertEquals(Target, Saved.Command);
    AssertEquals('', Saved.Image);
    FreeAndNil(FSubitem);
    ParseRequests.Clear;
  end;
end;

procedure TAppMetadataTests.StackPathsAndURIsDoNotRequestAppMetadata;
const Targets: array[0..2] of string = ('C:\TDOCK.Missing!App',
  'https://example.invalid/!App', 'custom:!App');
var Target: string;
begin
  for Target in Targets do
  begin
    CreateStackShortcut('Keep caption', '', Target);
    AssertEquals('Keep caption', UTF8Encode(FSubitem.Caption));
    AssertEquals(Target, FSubitem.Command);
    AssertEquals(0, ParseRequests.Count);
    FreeAndNil(FSubitem);
  end;
end;

procedure TAppMetadataTests.NativeMissingStackApplicationDoesNotRaise;
const MissingID = 'TDOCK.MissingPackage_0000000000000!App';
var Params: TDItemCreateParams; Native: TShortcutSubitem;
begin
  Params := Default(TDItemCreateParams);
  Params.ItemSize := 32; Params.BigItemSize := 64;
  ResolveIconFactoryForTests := nil;
  ResolvePackageArtworkForTests := nil;
  Native := TShortcutSubitem.Create(0, Params);
  try
    Native.FromString(TShortcutSubitem.MakeFromFilename(MissingID));
    AssertEquals(MissingID, Native.Command);
    AssertEquals('?', UTF8Encode(Native.Caption));
    AssertEquals('', Native.ImageFile);
  finally Native.Free; end;
end;

procedure TAppMetadataTests.DroppedStackApplicationUsesShellCaption;
var Params: TDItemCreateParams; Stack: TMetadataStack; FixtureTheme, PreviousTheme: TDTheme;
  Saved: TShortcutDtoV1; FixtureID: TGUID; FixtureFile: string;
begin
  OleCheck(CreateGUID(FixtureID));
  FixtureFile := ExtractFilePath(ParamStr(0)) + 'stack-metadata-' + GUIDToString(FixtureID) + '.ini';
  PreviousTheme := theme;
  FixtureTheme := TDTheme(TDTheme.NewInstance);
  theme := FixtureTheme;
  try
    Params := Default(TDItemCreateParams);
    Params.ItemSize := 32; Params.BigItemSize := 64;
    Params.Parameter := TStackItem.Make('metadata stack');
    Stack := TMetadataStack.Create(0, Params);
    try
      AssertTrue(Stack.DropFile(Stack.Handle, Point(0, 0), CalculatorID));
      AssertEquals(1, Stack.ItemCount);
      AssertEquals('A real stack drop must resolve the Shell name', FExpectedCaption, UTF8Encode(Stack.Child.Caption));
      Saved := ReadShortcutText(Stack.Child.ToString);
      AssertEquals(FExpectedCaption, UTF8Encode(Saved.Caption));
      AssertEquals(CalculatorID, Saved.Command);
      AssertTrue(Stack.Child.HasImage);
      Stack.Save(FixtureFile, 'item1');
      FreeAndNil(Stack);
      ParseRequests.Clear;
      Stack := TMetadataStack.Create(0, Params);
      Stack.FromIni(FixtureFile, 'item1');
      AssertEquals('A reloaded stack must retain its child', 1, Stack.ItemCount);
      AssertEquals(FExpectedCaption, UTF8Encode(Stack.Child.Caption));
      AssertEquals(CalculatorID, Stack.Child.Command);
      AssertEquals('The saved caption needs only icon metadata', 1, ParseRequests.Count);
    finally Stack.Free; DeleteFileW(PWideChar(UnicodeString(FixtureFile))); end;
  finally theme := PreviousTheme; FixtureTheme.Free; end;
end;

procedure TAppMetadataTests.StackFactoryUsesPackagedPlaceholder;
const Prefixes: array[0..3] of string = ('', 'shell:AppsFolder\',
  'shell:::{4234d49b-0245-4df3-b780-3893943456e1}\',
  '::{4234d49b-0245-4df3-b780-3893943456e1}\');
var Prefix, Target: string; Data: TShortcutDtoV1;
begin
  for Prefix in Prefixes do
  begin
    Target := Prefix + CalculatorID;
    Data := ReadShortcutText(TShortcutSubitem.MakeFromFilename(Target));
    AssertEquals('Packaged stack imports need automatic Shell captions', '?', UTF8Encode(Data.Caption));
    AssertEquals('Stack imports must preserve application identities', Target, Data.Command);
  end;
end;

procedure TAppMetadataTests.NameAndIconUseAppsFolder;
begin
  CreateShortcut('?');
  AssertEquals('Both name and icon need a Shell item', 2, ParseRequests.Count);
  AssertEquals('Name lookup must use AppsFolder', CalculatorShellName, ParseRequests[0]);
  AssertEquals('Icon lookup must use AppsFolder', CalculatorShellName, ParseRequests[1]);
  AssertEquals('The placeholder must become the Shell name',
    FExpectedCaption, UTF8Encode(FItem.Caption));
  AssertTrue('The Shell item must supply an icon', FItem.HasImage);
  AssertEquals('Activation must keep the original application ID', CalculatorID, FItem.Command);
  AssertEquals('Automatic icons need no custom image path', '', FItem.ImageFile);
end;

procedure TAppMetadataTests.CustomCaptionIsPreserved;
begin
  CreateShortcut('My calculator');
  AssertEquals('A custom caption must remain unchanged', 'My calculator', UTF8Encode(FItem.Caption));
  AssertEquals('Only automatic icon lookup needs metadata', 1, ParseRequests.Count);
  AssertEquals('Icon lookup must use AppsFolder', CalculatorShellName, ParseRequests[0]);
  AssertTrue('The automatic icon must remain available', FItem.HasImage);
end;

procedure TAppMetadataTests.CustomImageIsPreserved;
begin
  CreateShortcut('My calculator', UTF8Encode(MetadataSource));
  AssertEquals('Custom name and image must bypass app metadata', 0, ParseRequests.Count);
  AssertEquals('The custom image path must remain unchanged',
    UTF8Encode(MetadataSource), FItem.ImageFile);
  AssertTrue('The custom image must still load', FItem.HasImage);
  AssertEquals('The activation command must remain unchanged', CalculatorID, FItem.Command);
end;

procedure TAppMetadataTests.MissingMetadataPreservesLauncher;
begin
  MetadataUnavailable := True;
  CreateShortcut('?');
  AssertEquals('Both lookups must fail without aborting import', 2, ParseRequests.Count);
  AssertEquals('The placeholder must remain available for retry', '?', UTF8Encode(FItem.Caption));
  AssertEquals('Unavailable metadata must not change activation', CalculatorID, FItem.Command);
  AssertEquals('Unavailable metadata must not create a custom image path', '', FItem.ImageFile);
  AssertTrue('A failed lookup must provide the owned default image', FItem.HasImage);
end;

procedure TAppMetadataTests.MissingMetadataCanBeRetried;
begin
  MetadataUnavailable := True;
  CreateShortcut('?');
  MetadataUnavailable := False;
  FItem.Update;
  AssertEquals('Retry must resolve both name and icon', 4, ParseRequests.Count);
  AssertEquals('Retry must resolve the placeholder', FExpectedCaption, UTF8Encode(FItem.Caption));
  AssertTrue('Retry must load the icon', FItem.HasImage);
  AssertEquals('Retry must preserve activation', CalculatorID, FItem.Command);
end;

procedure TAppMetadataTests.ResolvedMetadataSurvivesSaveReload;
var Saved: TShortcutDtoV1;
begin
  CreateShortcut('?');
  Saved := ReadShortcutText(FItem.ToString);
  AssertEquals('Saving must retain the application ID', CalculatorID, Saved.Command);
  AssertEquals('Saving must retain the resolved caption', FExpectedCaption, UTF8Encode(Saved.Caption));
  AssertEquals('Saving must preserve automatic image selection', '', Saved.Image);
  FreeAndNil(FItem);
  ParseRequests.Clear;
  CreateShortcut(Saved.Caption, Saved.Image);
  AssertEquals('Reload must retain the resolved caption', FExpectedCaption, UTF8Encode(FItem.Caption));
  AssertEquals('Reload needs only an automatic icon lookup', 1, ParseRequests.Count);
  AssertEquals('Reload must use AppsFolder', CalculatorShellName, ParseRequests[0]);
  AssertTrue('Reload must restore the automatic icon', FItem.HasImage);
end;

procedure TAppMetadataTests.NativeMissingApplicationDoesNotRaise;
const MissingID = 'TDOCK.MissingPackage_0000000000000!App';
var Params: TDItemCreateParams; Native: TShortcutItem;
begin
  Params := Default(TDItemCreateParams);
  Params.ItemSize := 32;
  Params.BigItemSize := 64;
  Params.Parameter := TShortcutItem.Make('?', MissingID);
  ResolveIconFactoryForTests := nil;
  ResolvePackageArtworkForTests := nil;
  Native := TShortcutItem.Create(0, Params);
  try
    AssertEquals('A missing app must retain its activation identity', MissingID, Native.Command);
    AssertEquals('A missing app must retain automatic image selection', '', Native.ImageFile);
  finally Native.Free; end;
end;

procedure TAppMetadataTests.NonAppIDUsesAppsFolderMetadata;
const AppID = 'TDOCK.Test_8wekyb3d8bbwe!Main';
begin
  CreateShortcut('?', '', AppID);
  AssertEquals(2, ParseRequests.Count);
  AssertEquals('shell:AppsFolder\' + AppID, ParseRequests[0]);
  AssertEquals('shell:AppsFolder\' + AppID, ParseRequests[1]);
  AssertEquals(FExpectedCaption, UTF8Encode(FItem.Caption));
  AssertEquals(AppID, FItem.Command);
  AssertTrue(FItem.HasImage);
end;

procedure TAppMetadataTests.PrefixedIDsUseCanonicalMetadataAndKeepSavedCommands;
const
  AppID = 'TDOCK.Test_8wekyb3d8bbwe!Main';
  AppsGUID = '{4234d49b-0245-4df3-b780-3893943456e1}';
var Prefix: Integer; Target: string; Saved: TShortcutDtoV1;
begin
  for Prefix := 0 to 2 do
  begin
    case Prefix of
      0: Target := 'ShElL:ApPsFoLdEr\' + AppID;
      1: Target := 'shell:::' + AppsGUID + '\' + AppID;
      2: Target := '::' + AppsGUID + '\' + AppID;
    end;
    CreateShortcut('?', '', Target);
    AssertEquals(2, ParseRequests.Count);
    AssertEquals('shell:AppsFolder\' + AppID, ParseRequests[0]);
    AssertEquals('shell:AppsFolder\' + AppID, ParseRequests[1]);
    AssertEquals(FExpectedCaption, UTF8Encode(FItem.Caption));
    Saved := ReadShortcutText(FItem.ToString);
    AssertEquals('Saved commands must retain their original spelling', Target, Saved.Command);
    AssertEquals('', Saved.Image);
    AssertTrue(FItem.HasImage);
    FreeAndNil(FItem);
    ParseRequests.Clear;
    CreateShortcut(Saved.Caption, Saved.Image, Saved.Command);
    AssertEquals('Reload needs only the icon lookup', 1, ParseRequests.Count);
    AssertEquals('shell:AppsFolder\' + AppID, ParseRequests[0]);
    AssertEquals(Target, FItem.Command);
    FreeAndNil(FItem);
    ParseRequests.Clear;
  end;
end;

procedure TAppMetadataTests.PathsAndURIsEndingAppDoNotRequestAppMetadata;
var Target: string; Index: Integer;
begin
  for Index := 0 to 2 do
  begin
    case Index of
      0: Target := 'C:\TDOCK.Missing!App';
      1: Target := 'https://example.invalid/!App';
      2: Target := 'custom:!App';
    end;
    CreateShortcut('Keep caption', '', Target);
    AssertEquals('Ordinary targets must not request AppsFolder metadata', 0, ParseRequests.Count);
    AssertEquals('Keep caption', UTF8Encode(FItem.Caption));
    AssertEquals(Target, FItem.Command);
    FreeAndNil(FItem);
  end;
end;

initialization
  RegisterTest(TAppMetadataTests);
end.
