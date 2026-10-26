unit propertylifetimetests;

{$mode delphi}

interface

uses Windows, Classes, SysUtils, Forms, fpcunit, testregistry,
  declu, itemmgru, itemsettingsu, customitemu, customsubitemu, scitemu, scsubitemu, stackitemu,
  itemregistryu, themeu, frmitemoptu, frmstackpropu;

type
  TTestItemProp = class(TfrmItemProp)
  public
    function BindItem(wnd: HWND): boolean;
  end;

  TTestStackProp = class(TfrmStackProp)
  public
    function BindItem(wnd: HWND): boolean;
  end;

  TPropertyLifetimeTests = class(TTestCase)
  private
    Manager: TItemManager;
    FixtureTheme: TDTheme;
    ItemForm: TTestItemProp;
    StackForm: TTestStackProp;
    RetainedIdentity, RetainedChildIdentity: TItemIdentity;
    ReboundWindow: HWND;
    SavedWindowData: PtrInt;
    function CreateStackForm: TStackItem;
    function CreateItemForm: TShortcutItem;
    function CreateSubitemForm: TShortcutSubitem;
    function ReplaceShortcut(Item: TShortcutItem): TShortcutItem;
    procedure RetainItem(Item: TCustomItem);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure StackApplyAfterClearDoesNotEditRetiredItem;
    procedure StackCancelAfterClearDoesNotEditRetiredItem;
    procedure ShortcutApplyAfterDeleteDoesNotEditReplacement;
    procedure ShortcutCancelAfterDeleteDoesNotEditReplacement;
    procedure StackApplyAndCancelPreserveOriginalSnapshot;
    procedure ShortcutApplyAndCancelPreserveOriginalSnapshot;
    procedure StackSubitemActionsPreserveOrder;
    procedure StackSubitemActionsAfterClearDoNotEditRetiredItem;
    procedure ShortcutSubitemApplyAfterStackClearDoesNotEditRetiredItem;
    procedure ShortcutSubitemCancelAfterStackClearDoesNotEditRetiredItem;
  end;

implementation

function TTestItemProp.BindItem(wnd: HWND): boolean;
begin Result := SetData(wnd); end;

function TTestStackProp.BindItem(wnd: HWND): boolean;
begin Result := SetData(wnd); end;

procedure TPropertyLifetimeTests.SetUp;
var Settings: TItemManagerSettings;
begin
  FixtureTheme := TDTheme(TDTheme.NewInstance);
  theme := FixtureTheme;
  Settings := Default(TItemManagerSettings);
  Settings.ItemSize := 32;
  Settings.BigItemSize := 32;
  Settings.ItemSpacing := 4;
  Settings.ZoomTime := 100;
  Settings.SeparatorAlpha := 255;
  Settings.Site := bsBottom;
  Settings.TaskSpot := -1;
  Manager := TItemManager.Create(0, Settings, nil);
  Manager.Enable(True);
end;

procedure TPropertyLifetimeTests.TearDown;
begin
  if IsWindow(ReboundWindow) then
    Windows.SetWindowLongPtr(ReboundWindow, GWL_USERDATA, SavedWindowData);
  ItemForm.Free;
  frmItemProp := nil;
  StackForm.Free;
  frmStackProp := nil;
  Manager.Free;
  ItemRegistry.Unpin(RetainedChildIdentity);
  ItemRegistry.Unpin(RetainedIdentity);
  theme := nil;
  FixtureTheme.Free;
  Application.ProcessMessages;
end;

procedure TPropertyLifetimeTests.RetainItem(Item: TCustomItem);
begin
  RetainedIdentity := ItemRegistry.IdentityOf(Item.Handle);
  AssertTrue('The fixture must retain the old model safely',
    ItemRegistry.Pin(RetainedIdentity));
end;

function TPropertyLifetimeTests.CreateStackForm: TStackItem;
var Item: TCustomItem; wnd: HWND;
begin
  wnd := Manager.InsertItem(TStackItem.Make('Original stack'));
  AssertTrue(Manager.TryGetManagedItem(wnd, Item));
  Result := TStackItem(Item);
  RetainItem(Item);
  StackForm := TTestStackProp.Create(nil);
  frmStackProp := StackForm;
  AssertTrue('The hidden stack form must bind its model', StackForm.BindItem(wnd));
  AssertFalse(StackForm.Visible);
  AssertEquals('The form must release its binding lease', 1, Item.PinCount);
end;

function TPropertyLifetimeTests.CreateItemForm: TShortcutItem;
var Item: TCustomItem; wnd: HWND;
begin
  wnd := Manager.InsertItem(TShortcutItem.Make('Original shortcut'));
  AssertTrue(Manager.TryGetManagedItem(wnd, Item));
  Result := TShortcutItem(Item);
  RetainItem(Item);
  ItemForm := TTestItemProp.Create(nil);
  frmItemProp := ItemForm;
  AssertTrue('The hidden shortcut form must bind its model', ItemForm.BindItem(wnd));
  AssertFalse(ItemForm.Visible);
  AssertEquals('The form must release its binding lease', 1, Item.PinCount);
end;

function TPropertyLifetimeTests.ReplaceShortcut(Item: TShortcutItem): TShortcutItem;
var Replacement: TCustomItem; wnd: HWND;
begin
  Manager.DeleteItem(Item.Handle);
  wnd := Manager.InsertItem(TShortcutItem.Make('Replacement shortcut'));
  AssertTrue(Manager.TryGetManagedItem(wnd, Replacement));
  Result := TShortcutItem(Replacement);
  // Keep the old object alive while reproducing replacement native window data.
  ReboundWindow := Item.Handle;
  SavedWindowData := Windows.GetWindowLongPtr(ReboundWindow, GWL_USERDATA);
  Windows.SetWindowLongPtr(ReboundWindow, GWL_USERDATA, PtrInt(Result));
end;

function TPropertyLifetimeTests.CreateSubitemForm: TShortcutSubitem;
var Parent: TCustomItem; Child: TObject; StackWindow, wnd: HWND;
begin
  StackWindow := Manager.InsertItem(TStackItem.Make('Original stack'));
  AssertTrue(Manager.TryGetManagedItem(StackWindow, Parent));
  RetainItem(Parent);
  TStackItem(Parent).AddSubitem(TShortcutSubitem.Make('Original child'));
  wnd := 0;
  repeat
    wnd := Windows.FindWindowEx(0, wnd, TDSUBITEM_WCLASS, nil);
    AssertTrue('The stack must create a real shortcut window', wnd <> 0);
  until GetWindow(wnd, GW_OWNER) = StackWindow;
  AssertTrue(ItemRegistry.TryGetAny(wnd, Child));
  AssertTrue(Child is TShortcutSubitem);
  Result := TShortcutSubitem(Child);
  RetainedChildIdentity := ItemRegistry.IdentityOf(wnd);
  AssertTrue(ItemRegistry.Pin(RetainedChildIdentity));
  ItemForm := TTestItemProp.Create(nil);
  frmItemProp := ItemForm;
  AssertTrue(ItemForm.BindItem(wnd));
  AssertFalse(ItemForm.Visible);
end;

procedure TPropertyLifetimeTests.StackApplyAfterClearDoesNotEditRetiredItem;
var Item: TStackItem;
begin
  Item := CreateStackForm;
  StackForm.edCaption.Text := 'Changed stack';
  Manager.command('clear', '');
  StackForm.btnApplyClick(nil);
  AssertEquals('Apply must not edit a cleared stack', 'Original stack', UTF8Encode(Item.Caption));
end;

procedure TPropertyLifetimeTests.StackCancelAfterClearDoesNotEditRetiredItem;
var Item: TStackItem;
begin
  Item := CreateStackForm;
  StackForm.edCaption.Text := 'Changed stack';
  Manager.command('clear', '');
  Item.Caption := 'Retired stack';
  StackForm.btnCancelClick(nil);
  AssertEquals('Cancel must not restore a cleared stack', 'Retired stack', UTF8Encode(Item.Caption));
end;

procedure TPropertyLifetimeTests.ShortcutApplyAfterDeleteDoesNotEditReplacement;
var Item, Replacement: TShortcutItem;
begin
  Item := CreateItemForm;
  ItemForm.edCaption.Text := 'Changed shortcut';
  Replacement := ReplaceShortcut(Item);
  ItemForm.btnApplyClick(nil);
  AssertEquals('Apply must not follow replacement window data',
    'Replacement shortcut', UTF8Encode(Replacement.Caption));
end;

procedure TPropertyLifetimeTests.ShortcutCancelAfterDeleteDoesNotEditReplacement;
var Item, Replacement: TShortcutItem;
begin
  Item := CreateItemForm;
  ItemForm.edCaption.Text := 'Changed shortcut';
  Replacement := ReplaceShortcut(Item);
  ItemForm.btnCancelClick(nil);
  AssertEquals('Cancel must not follow replacement window data',
    'Replacement shortcut', UTF8Encode(Replacement.Caption));
end;

procedure TPropertyLifetimeTests.StackApplyAndCancelPreserveOriginalSnapshot;
var Item: TStackItem;
begin
  Item := CreateStackForm;
  StackForm.edCaption.Text := 'Applied stack';
  StackForm.btnApplyClick(nil);
  AssertEquals('Applied stack', UTF8Encode(Item.Caption));
  AssertEquals('Apply must release its model lease', 1, Item.PinCount);
  StackForm.edCaption.Text := 'Unsaved stack';
  StackForm.btnCancelClick(nil);
  AssertEquals('Cancel must keep the original edit snapshot',
    'Original stack', UTF8Encode(Item.Caption));
  AssertEquals('Cancel must release its model lease', 1, Item.PinCount);
end;

procedure TPropertyLifetimeTests.ShortcutApplyAndCancelPreserveOriginalSnapshot;
var Item: TShortcutItem;
begin
  Item := CreateItemForm;
  ItemForm.edCaption.Text := 'Applied shortcut';
  ItemForm.edCmd.Text := '/quit';
  ItemForm.edParams.Text := 'first argument';
  ItemForm.edDir.Text := 'work folder';
  ItemForm.chbHide.Checked := True;
  ItemForm.btnApplyClick(nil);
  AssertEquals('Applied shortcut', UTF8Encode(Item.Caption));
  AssertEquals('/quit', Item.Command);
  AssertEquals('first argument', Item.Params);
  AssertEquals('work folder', Item.Dir);
  AssertTrue(Item.Hide);
  AssertEquals('Apply must release its model lease', 1, Item.PinCount);
  ItemForm.edCaption.Text := 'Unsaved shortcut';
  ItemForm.btnCancelClick(nil);
  AssertEquals('Cancel must keep the original edit snapshot',
    'Original shortcut', UTF8Encode(Item.Caption));
  AssertEquals('', Item.Command);
  AssertEquals('', Item.Params);
  AssertEquals('', Item.Dir);
  AssertFalse(Item.Hide);
  AssertEquals('Cancel must release its model lease', 1, Item.PinCount);
end;

procedure TPropertyLifetimeTests.StackSubitemActionsPreserveOrder;
var Item: TStackItem;
begin
  Item := CreateStackForm;
  Item.AddSubitem(TShortcutItem.Make('First child'));
  Item.AddSubitem(TShortcutItem.Make('Second child'));
  AssertTrue(StackForm.BindItem(Item.Handle));
  StackForm.list.ItemIndex := 1;
  StackForm.bbIconUpClick(nil);
  AssertEquals('Second child', UTF8Encode(Item.GetSubitemCaption(0)));
  StackForm.bbIconDownClick(nil);
  AssertEquals('First child', UTF8Encode(Item.GetSubitemCaption(0)));
  StackForm.bbDelIconClick(nil);
  AssertEquals(1, Item.ItemCount);
  StackForm.bbAddIconClick(nil);
  AssertEquals(2, Item.ItemCount);
  AssertEquals(Item.ItemCount, StackForm.list.Items.Count);
  AssertEquals('Child actions must release their model leases', 1, Item.PinCount);
end;

procedure TPropertyLifetimeTests.StackSubitemActionsAfterClearDoNotEditRetiredItem;
var Item: TStackItem;
begin
  Item := CreateStackForm;
  Manager.command('clear', '');
  StackForm.bbAddIconClick(nil);
  AssertEquals('A cleared stack must reject new children', 0, Item.ItemCount);
  AssertFalse('The unavailable form must disable editing', StackForm.pages.Enabled);
  StackForm.bbDelIconClick(nil);
  StackForm.bbIconUpClick(nil);
  StackForm.bbIconDownClick(nil);
  StackForm.bbEditIconClick(nil);
  AssertEquals(0, Item.ItemCount);
end;

procedure TPropertyLifetimeTests.ShortcutSubitemApplyAfterStackClearDoesNotEditRetiredItem;
var Item: TShortcutSubitem;
begin
  Item := CreateSubitemForm;
  ItemForm.edCaption.Text := 'Changed child';
  Manager.command('clear', '');
  ItemForm.btnApplyClick(nil);
  AssertEquals('Apply must reject a retired child', 'Original child', UTF8Encode(Item.Caption));
end;

procedure TPropertyLifetimeTests.ShortcutSubitemCancelAfterStackClearDoesNotEditRetiredItem;
var Item: TShortcutSubitem;
begin
  Item := CreateSubitemForm;
  ItemForm.edCaption.Text := 'Changed child';
  Manager.command('clear', '');
  Item.Caption := 'Retired child';
  ItemForm.btnCancelClick(nil);
  AssertEquals('Cancel must reject a retired child', 'Retired child', UTF8Encode(Item.Caption));
end;

initialization
  RegisterTest(TPropertyLifetimeTests);
end.
