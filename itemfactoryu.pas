unit itemfactoryu;

{$mode delphi}

interface

uses SysUtils, customitemu, declu;

type
  TCustomItemClass = class of TCustomItem;
  TItemDefinitionValidator = procedure(const Params: TDItemCreateParams);
  TItemType = record
    Name: string;
    ItemClass: TCustomItemClass;
    Persistent, Plugin: boolean;
    Validate: TItemDefinitionValidator;
  end;
  TItemTypeRegistry = class
  private
    FTypes: array of TItemType;
  public
    procedure RegisterType(const Name: string; ItemClass: TCustomItemClass;
      Persistent: boolean = True; Plugin: boolean = False;
      Validate: TItemDefinitionValidator = nil);
    function Find(const Name: string; out ItemType: TItemType): boolean;
    function FindClass(ItemClass: TCustomItemClass; out ItemType: TItemType): boolean;
  end;
  TLegacyItemValue = record
    Name, Value: WideString;
  end;
  TLegacyItemSection = record
    BeforeItem: integer;
    Values: array of TLegacyItemValue;
  end;
  TLegacyItemSections = array of TLegacyItemSection;

function ItemTypes: TItemTypeRegistry;

implementation

uses Classes, scitemu, sepitemu, stackitemu, plgitemu, taskitemu, itemserializationu;

var Registry: TItemTypeRegistry;

procedure TItemTypeRegistry.RegisterType(const Name: string;
  ItemClass: TCustomItemClass; Persistent: boolean; Plugin: boolean;
  Validate: TItemDefinitionValidator);
var Entry: TItemType; Index: integer;
begin
  if (Trim(Name) = '') or (ItemClass = nil) then
    raise EArgumentException.Create('Invalid item type registration');
  if Find(Name, Entry) then raise EArgumentException.Create('Duplicate item type: ' + Name);
  Index := Length(FTypes);
  SetLength(FTypes, Index + 1);
  FTypes[Index].Name := LowerCase(Trim(Name));
  FTypes[Index].ItemClass := ItemClass;
  FTypes[Index].Persistent := Persistent;
  FTypes[Index].Plugin := Plugin;
  FTypes[Index].Validate := Validate;
end;

function TItemTypeRegistry.Find(const Name: string; out ItemType: TItemType): boolean;
var Entry: TItemType;
begin
  ItemType := Default(TItemType);
  for Entry in FTypes do
    if SameText(Entry.Name, Trim(Name)) then
    begin ItemType := Entry; Exit(True); end;
  Result := False;
end;

function TItemTypeRegistry.FindClass(ItemClass: TCustomItemClass;
  out ItemType: TItemType): boolean;
var Entry: TItemType;
begin
  ItemType := Default(TItemType);
  if ItemClass = nil then Exit(False);
  Result := False;
  for Entry in FTypes do
    if ItemClass.InheritsFrom(Entry.ItemClass) then
    begin
      if not Result then ItemType := Entry
      else if Entry.ItemClass.InheritsFrom(ItemType.ItemClass) then ItemType := Entry;
      Result := True;
    end;
end;

function ItemTypes: TItemTypeRegistry;
begin Result := Registry; end;

procedure ValidateShortcut(const Params: TDItemCreateParams);
begin
  if Params.IniFile <> '' then ReadShortcutIni(Params.IniFile, Params.IniSection)
  else ReadShortcutText(Params.Parameter);
end;

procedure ValidateStack(const Params: TDItemCreateParams);
var Children: TStringList;
begin
  if Params.IniFile <> '' then ReadStackIni(Params.IniFile, Params.IniSection)
  else ReadStackText(Params.Parameter);
  Children := ReadStackChildren(Params.IniFile, Params.IniSection, Params.Parameter);
  Children.Free;
end;

initialization
  Registry := TItemTypeRegistry.Create;
  Registry.RegisterType('shortcut', TShortcutItem, True, False, ValidateShortcut);
  Registry.RegisterType('separator', TSeparatorItem);
  Registry.RegisterType('stack', TStackItem, True, False, ValidateStack);
  Registry.RegisterType('plugin', TPluginItem, True, True);
  Registry.RegisterType('task', TTaskItem, False);
finalization
  Registry.Free;
end.
