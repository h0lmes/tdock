unit shellactivationu;
{$mode delphi}
interface
uses Windows, ActiveX, ShlObj;
type
  TShellTargetKind = (skNamespace, skExecutable, skDocument, skFolder, skPackaged);
  TShellTarget = record
    Kind: TShellTargetKind;
    Path, AppID: UnicodeString;
  end;
  TShellActivation = class
  protected
    function ContextMenu(List: PItemIDList; Owner: HWND; out Menu: IContextMenu): HRESULT; virtual;
    function IsNetworkConnection(List: PItemIDList): Boolean; virtual;
  public
    function Describe(List: PItemIDList): TShellTarget; virtual;
    function Executable(const Target: UnicodeString): Boolean; virtual;
    function HasContract(const AppID, Document: UnicodeString; Protocol: Boolean): Boolean; virtual;
    function ActivateDocument(const AppID, Document: UnicodeString; Protocol: Boolean): HRESULT; virtual;
    function InvokeNamespace(List: PItemIDList; Owner: HWND; Show: Integer): HRESULT; virtual;
  end;
function DocumentIsURI(const Value: UnicodeString): Boolean;
function QuoteDocumentArgument(const Value: UnicodeString): UnicodeString;
implementation
uses SysUtils, ComObj, ShellAPI, PIDL, shelltextu, toolu, uwp_tlb;
type
  IAssociationHandler = interface(IUnknown)
    ['{F04061AC-1659-4A3F-A954-775AA57FC083}']
    function GetName(out Name: PWideChar): HRESULT; stdcall;
  end;
  IAssociationEnumerator = interface(IUnknown)
    ['{973810AE-9599-4B88-9E4D-6EE98C9552DA}']
    function Next(Count: ULONG; out Handler: IAssociationHandler; out Fetched: ULONG): HRESULT; stdcall;
  end;
  IHandlerAppID = interface(IUnknown)
    ['{36DB0196-9665-46D1-9BA7-D3709EECF9ED}']
    function SetAppID(Name: PWideChar): HRESULT; stdcall;
    function GetAppID(out Name: PWideChar): HRESULT; stdcall;
  end;
const
  IID_AssociationEnumerator: TGUID = '{973810AE-9599-4B88-9E4D-6EE98C9552DA}';
  IID_PropertyStore: TGUID = '{886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99}';
function EnumFileHandlers(Extension: PWideChar; Filter: DWORD; out Items: IAssociationEnumerator): HRESULT; stdcall;
  external 'shell32.dll' name 'SHAssocEnumHandlers';
function EnumProtocolHandlers(Scheme: PWideChar; const IID: TGUID; out Items: IAssociationEnumerator): HRESULT; stdcall;
  external 'shell32.dll' name 'SHAssocEnumHandlersForProtocolByApplication';
function CreateItemArray(Count: UINT; Lists: Pointer; out Items: uwp_tlb.IShellItemArray): HRESULT; stdcall;
  external 'shell32.dll' name 'SHCreateShellItemArrayFromIDLists';
function BindParent(List: PItemIDList; const IID: TGUID; out Folder: IShellFolder;
  out Child: PItemIDList): HRESULT; stdcall; external 'shell32.dll' name 'SHBindToParent';
function ParentContains(Parent, Child: PItemIDList; Immediate: BOOL): BOOL; stdcall;
  external 'shell32.dll' name 'ILIsParent';
function PropertyStoreFromList(List: PItemIDList; Flags: DWORD; const IID: TGUID;
  out Store: IPropertyStore): HRESULT; stdcall; external 'shell32.dll' name 'SHGetPropertyStoreFromIDList';
function PropertyKeyFromName(Name: PWideChar; out Key: PROPERTYKEY): HRESULT; stdcall;
  external 'propsys.dll' name 'PSGetPropertyKeyFromName';
function ClearProperty(var Value: PROPVARIANT): HRESULT; stdcall;
  external 'ole32.dll' name 'PropVariantClear';

function DocumentIsURI(const Value: UnicodeString): Boolean;
var I, Colon: Integer;
begin
  Result := False;
  Colon := Pos(':', Value);
  if Colon <= 2 then Exit; // Preserve drive-qualified paths.
  if not (Value[1] in ['a'..'z', 'A'..'Z']) then Exit;
  for I := 2 to Colon - 1 do
    if not (Value[I] in ['a'..'z', 'A'..'Z', '0'..'9', '+', '-', '.']) then Exit;
  Result := not IsShellName(Value);
end;

function QuoteDocumentArgument(const Value: UnicodeString): UnicodeString;
var I, Slashes: Integer;
begin
  Result := '"'; Slashes := 0;
  for I := 1 to Length(Value) do
    if Value[I] = '\' then Inc(Slashes)
    else begin
      if Value[I] = '"' then Result := Result + UnicodeString(StringOfChar('\', Slashes * 2 + 1))
      else Result := Result + UnicodeString(StringOfChar('\', Slashes));
      Slashes := 0;
      Result := Result + Value[I];
    end;
  Result := Result + UnicodeString(StringOfChar('\', Slashes * 2)) + '"';
end;

function TShellActivation.Executable(const Target: UnicodeString): Boolean;
var Path: WideString; Parameters, Directory, Icon: string;
  Buffer: array of WideChar; Needed: DWORD; Extension: UnicodeString;
begin
  Result := False;
  Path := Target;
  if not ShellFileExists(Path) then
  begin
    Needed := SearchPathW(nil, PWideChar(Path), '.exe', 0, nil, nil);
    if (Needed = 0) or (Needed > SHELL_TEXT_LIMIT) then Exit;
    SetLength(Buffer, Needed + 1);
    if SearchPathW(nil, PWideChar(Path), '.exe', Length(Buffer), @Buffer[0], nil) >= DWORD(Length(Buffer)) then Exit;
    Path := PWideChar(@Buffer[0]);
  end;
  if SameText(UTF8Encode(ExtractFileExt(Path)), '.lnk') then
    if not ResolveLNK(0, Path, Parameters, Directory, Icon) then Exit;
  Extension := LowerCase(ExtractFileExt(Path));
  Result := ShellFileExists(Path) and ((Extension = '.exe') or (Extension = '.com') or
    (Extension = '.bat') or (Extension = '.cmd'));
end;

function TShellActivation.Describe(List: PItemIDList): TShellTarget;
var Name, Identity: UnicodeString; Store: IPropertyStore; Key: PROPERTYKEY;
  Value: PROPVARIANT; Folder: IShellFolder; Child: PItemIDList; Attributes: ULONG;
begin
  Result := Default(TShellTarget);
  Result.Kind := skNamespace;
  if List = nil then Exit;
  if PIDL_GetDisplayNameText(nil, List, SHGDN_FORPARSING, Name) then
  begin
    if TryNormalizeAppTarget(Name, Identity) then
    begin Result.Kind := skPackaged; Result.AppID := Identity; Exit; end;
    if ShellPathExists(Name) then
    begin
      Result.Path := Name;
      if ShellDirectoryExists(Name) then Result.Kind := skFolder
      else if Executable(Name) then Result.Kind := skExecutable
      else Result.Kind := skDocument;
      Exit;
    end;
  end;
  if Succeeded(PropertyStoreFromList(List, 0, IID_PropertyStore, Store)) and (Store <> nil) then
    if Succeeded(PropertyKeyFromName('System.AppUserModel.ID', Key)) then
    begin
      Value := Default(PROPVARIANT);
      try
        if Succeeded(Store.GetValue(@Key, Value)) and (Value.vt = VT_LPWSTR) and (Value.pwszVal <> nil) then
          if TryNormalizeAppTarget(UnicodeString(Value.pwszVal), Identity) then
          begin Result.Kind := skPackaged; Result.AppID := Identity; Exit; end;
      finally ClearProperty(Value); end;
    end;
  if Succeeded(BindParent(List, IID_IShellFolder, Folder, Child)) and (Folder <> nil) then
  begin
    Attributes := SFGAO_FOLDER;
    if Succeeded(Folder.GetAttributesOf(1, Child, Attributes)) and ((Attributes and SFGAO_FOLDER) <> 0) then
      Result.Kind := skFolder;
  end;
end;

function TShellActivation.HasContract(const AppID, Document: UnicodeString; Protocol: Boolean): Boolean;
var Items: IAssociationEnumerator; Handler: IAssociationHandler; App: IHandlerAppID;
  Name: PWideChar; Association: UnicodeString; Status: HRESULT; Fetched: ULONG;
begin
  Result := False;
  if Protocol then
  begin
    Association := Copy(Document, 1, Pos(':', Document) - 1);
    Status := EnumProtocolHandlers(PWideChar(Association), IID_AssociationEnumerator, Items);
  end else begin
    Association := ExtractFileExt(Document);
    if Association = '' then Exit;
    Status := EnumFileHandlers(PWideChar(Association), 0, Items);
  end;
  if Failed(Status) then OleCheck(Status);
  if Items = nil then Exit;
  repeat
    Handler := nil; Fetched := 0;
    Status := Items.Next(1, Handler, Fetched);
    if Failed(Status) then OleCheck(Status);
    if (Fetched = 0) or (Handler = nil) then Exit;
    App := nil;
    if Supports(Handler, IHandlerAppID, App) then
    begin
      Name := nil;
      try
        if Succeeded(App.GetAppID(Name)) and (Name <> nil) then
          if SameText(UTF8Encode(UnicodeString(Name)), UTF8Encode(AppID)) then Exit(True);
      finally CoTaskMemFree(Name); end;
    end;
  until False;
end;

function TShellActivation.ActivateDocument(const AppID, Document: UnicodeString; Protocol: Boolean): HRESULT;
var List: PItemIDList; Items: uwp_tlb.IShellItemArray;
  Manager: ApplicationActivationManager; ProcessID: UInt32;
begin
  List := nil;
  Result := SHParseDisplayName(PWideChar(Document), nil, List, 0, nil);
  try
    if Failed(Result) then Exit;
    if List = nil then Exit(E_INVALIDARG);
    Result := CreateItemArray(1, @List, Items);
    if Failed(Result) then Exit;
    Manager := ApplicationActivationManager.Create;
    try
      if Protocol then Result := Manager.ActivateForProtocol(PWideChar(AppID), Items, ProcessID)
      else Result := Manager.ActivateForFile(PWideChar(AppID), Items, ProcessID);
    finally Manager.Free; end;
  finally PIDL_Free(List); end;
end;

function TShellActivation.ContextMenu(List: PItemIDList; Owner: HWND; out Menu: IContextMenu): HRESULT;
var Folder: IShellFolder; Child: PItemIDList;
begin
  Menu := nil;
  Result := BindParent(List, IID_IShellFolder, Folder, Child);
  if Succeeded(Result) then
    Result := Folder.GetUIObjectOf(Owner, 1, Child, IID_IContextMenu, nil, Pointer(Menu));
end;

function TShellActivation.IsNetworkConnection(List: PItemIDList): Boolean;
var Parent: PItemIDList;
begin
  Parent := PIDL_ParseTarget('shell:ConnectionsFolder');
  try Result := (Parent <> nil) and ParentContains(Parent, List, True);
  finally PIDL_Free(Parent); end;
end;

function TShellActivation.InvokeNamespace(List: PItemIDList; Owner: HWND; Show: Integer): HRESULT;
var Menu: IContextMenu; Popup: HMENU; Count, I, State, DefaultID: UINT;
  OpenOffset, ExploreOffset, StatusOffset, Selected: Integer;
  Buffer: array of WideChar; Verb: UnicodeString; Info: TCMINVOKECOMMANDINFOEX;
begin
  Result := ContextMenu(List, Owner, Menu);
  if Failed(Result) then Exit;
  if Menu = nil then Exit(E_NOINTERFACE);
  Popup := CreatePopupMenu;
  if Popup = 0 then Exit(E_OUTOFMEMORY);
  try
    Result := Menu.QueryContextMenu(Popup, 0, 1, $7FFF, CMF_NORMAL);
    if Failed(Result) then Exit;
    Count := DWORD(Result) and $FFFF;
    DefaultID := GetMenuDefaultItem(Popup, 0, 0);
    OpenOffset := -1; ExploreOffset := -1; StatusOffset := -1;
    SetLength(Buffer, SHELL_TEXT_LIMIT + 1);
    if Count > 0 then for I := 0 to Count - 1 do
    begin
      State := GetMenuState(Popup, I + 1, MF_BYCOMMAND);
      if (State = UINT(-1)) or ((State and (MF_DISABLED or MF_GRAYED or MF_SEPARATOR or MF_POPUP)) <> 0) then Continue;
      FillChar(Buffer[0], Length(Buffer) * SizeOf(WideChar), $FF);
      if Failed(Menu.GetCommandString(I, GCS_VERBW, nil, PAnsiChar(@Buffer[0]), Length(Buffer))) then Continue;
      Selected := 0;
      while (Selected < Length(Buffer)) and (Buffer[Selected] <> #0) do Inc(Selected);
      if Selected = Length(Buffer) then Continue;
      SetString(Verb, PWideChar(@Buffer[0]), Selected);
      if SameText(UTF8Encode(Verb), 'open') then OpenOffset := I
      else if SameText(UTF8Encode(Verb), 'explore') then ExploreOffset := I
      else if SameText(UTF8Encode(Verb), 'status') and (DefaultID = I + 1) then StatusOffset := I;
    end;
    Selected := OpenOffset;
    if Selected < 0 then Selected := ExploreOffset;
    if (Selected < 0) and (StatusOffset >= 0) and IsNetworkConnection(List) then Selected := StatusOffset;
    if Selected < 0 then Exit(HRESULT($80070483)); // ERROR_NO_ASSOCIATION: no supported open action.
    Info := Default(TCMINVOKECOMMANDINFOEX);
    Info.cbSize := SizeOf(Info);
    Info.fMask := CMIC_MASK_UNICODE or CMIC_MASK_FLAG_NO_UI;
    Info.hwnd := Owner;
    Info.lpVerb := PAnsiChar(PtrUInt(Selected));
    Info.lpVerbW := PWideChar(PtrUInt(Selected));
    Info.nShow := Show;
    Result := Menu.InvokeCommand(PCMINVOKECOMMANDINFO(@Info)^);
  finally DestroyMenu(Popup); end;
end;
end.
