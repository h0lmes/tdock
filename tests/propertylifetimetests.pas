unit propertylifetimetests;

{$mode delphi}

interface

uses Windows, Classes, SysUtils, Forms, Controls, StdCtrls, ActiveX, fpcunit, testregistry,
  declu, itemmgru, itemsettingsu, customitemu, customsubitemu, scitemu, scsubitemu, stackitemu,
  itemregistryu, themeu, frmitemoptu, frmstackpropu, itemserializationu, GDIPAPI;

type
  TTestItemProp = class(TfrmItemProp)
  public
    function BindItem(wnd: HWND): boolean;
  end;

  TTestStackProp = class(TfrmStackProp)
  protected
    function EditChild(var Text: string): boolean; override;
  public
    EditedText: string;
    AcceptEdit: boolean;
    function BindItem(wnd: HWND): boolean;
    procedure PaintPreview(Graphics: Pointer; Size: integer);
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
    AcceptDraftEditor: boolean;
    procedure DriveDraftEditor(Sender: TObject; var Done: boolean);
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
    procedure StackApplyAndCancelPreserveAppliedSnapshot;
    procedure ShortcutApplyAndCancelPreserveOriginalSnapshot;
    procedure StackSubitemActionsPreserveOrder;
    procedure StackSubitemActionsAfterClearDoNotEditRetiredItem;
    procedure ShortcutSubitemApplyAfterStackClearDoesNotEditRetiredItem;
    procedure ShortcutSubitemCancelAfterStackClearDoesNotEditRetiredItem;
    procedure StackCancelDiscardsPendingChildChanges;
    procedure StackEditsRefreshDraftAndCommitTogether;
    procedure StackActionStatesFollowSelectionAndOrder;
    procedure StackDistanceAndNumbersStaySynchronized;
    procedure StackLocationPreservesControlPanelAndCustomDraft;
    procedure StackCloseAndEscapeDiscardDrafts;
    procedure StackValidationFailureKeepsModelAndDraft;
    procedure StackClosedPreviewUsesPendingItems;
    procedure StackLayoutFitsAtLargerScales;
    procedure StackChildEditorKeepsTheLiveShortcutUntouched;
  end;

implementation

function TTestItemProp.BindItem(wnd: HWND): boolean;
begin Result := SetData(wnd); end;

function TTestStackProp.BindItem(wnd: HWND): boolean;
begin Result := SetData(wnd); end;

function TTestStackProp.EditChild(var Text: string): boolean;
begin
  Result := AcceptEdit;
  if Result then Text := EditedText;
end;

procedure TTestStackProp.PaintPreview(Graphics: Pointer; Size: integer);
begin RenderPreview(Graphics, Size); end;

procedure TPropertyLifetimeTests.SetUp;
var Settings: TItemManagerSettings;
begin
  CoInitialize(nil);
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
  CoUninitialize;
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

procedure TPropertyLifetimeTests.StackApplyAndCancelPreserveAppliedSnapshot;
var Item: TStackItem;
begin
  Item := CreateStackForm;
  StackForm.edCaption.Text := 'Applied stack';
  StackForm.btnApplyClick(nil);
  AssertEquals('Applied stack', UTF8Encode(Item.Caption));
  AssertEquals('Apply must release its model lease', 1, Item.PinCount);
  StackForm.edCaption.Text := 'Unsaved stack';
  StackForm.btnCancelClick(nil);
  AssertEquals('Cancel must retain the last applied settings',
    'Applied stack', UTF8Encode(Item.Caption));
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
  AssertEquals('Second child', StackForm.list.Items[0]);
  AssertEquals('Moves must remain pending', 'First child', UTF8Encode(Item.GetSubitemCaption(0)));
  StackForm.bbIconDownClick(nil);
  AssertEquals('First child', UTF8Encode(Item.GetSubitemCaption(0)));
  StackForm.bbDelIconClick(nil);
  AssertEquals(1, StackForm.list.Items.Count);
  AssertEquals('Removal must remain pending', 2, Item.ItemCount);
  StackForm.bbAddIconClick(nil);
  AssertEquals(2, Item.ItemCount);
  AssertEquals(Item.ItemCount, StackForm.list.Items.Count);
  StackForm.btnApplyClick(nil);
  AssertEquals('New item', UTF8Encode(Item.GetSubitemCaption(1)));
  AssertEquals('Child actions must release their model leases', 1, Item.PinCount);
end;

procedure TPropertyLifetimeTests.StackCancelDiscardsPendingChildChanges;
var Item: TStackItem;
begin
  Item := CreateStackForm;
  AssertFalse('Apply starts disabled', StackForm.btnApply.Enabled);
  Item.AddSubitem(TShortcutSubitem.Make('First'));
  Item.AddSubitem(TShortcutSubitem.Make('Second'));
  AssertTrue(StackForm.BindItem(Item.Handle));
  StackForm.list.ItemIndex := 0;
  StackForm.bbDelIconClick(nil);
  StackForm.bbAddIconClick(nil);
  StackForm.edCaption.Text := 'Pending';
  AssertTrue(StackForm.btnApply.Enabled);
  StackForm.btnCancelClick(nil);
  AssertEquals('Original stack', UTF8Encode(Item.Caption));
  AssertEquals(2, Item.ItemCount);
  AssertEquals('First', UTF8Encode(Item.GetSubitemCaption(0)));
  AssertEquals('Second', UTF8Encode(Item.GetSubitemCaption(1)));
end;

procedure TPropertyLifetimeTests.StackEditsRefreshDraftAndCommitTogether;
var Item: TStackItem;
begin
  Item := CreateStackForm;
  StackForm.bbAddIconClick(nil);
  StackForm.AcceptEdit := true;
  StackForm.EditedText := TShortcutSubitem.Make('Edited child', '/quit');
  StackForm.bbEditIconClick(nil);
  AssertEquals('Edited child', StackForm.list.Items[0]);
  AssertEquals('Child editing must not mutate the live stack', 0, Item.ItemCount);
  StackForm.btnApplyClick(nil);
  AssertEquals('Edited child', UTF8Encode(Item.GetSubitemCaption(0)));
  AssertFalse('Apply must establish a new baseline', StackForm.btnApply.Enabled);
  StackForm.bbDelIconClick(nil);
  StackForm.btnCancelClick(nil);
  AssertEquals('Cancel must keep applied children', 1, Item.ItemCount);
  AssertEquals('Edited child', UTF8Encode(Item.GetSubitemCaption(0)));
end;

procedure TPropertyLifetimeTests.StackActionStatesFollowSelectionAndOrder;
var Item: TStackItem;
begin
  Item := CreateStackForm;
  AssertFalse(StackForm.bbEditIcon.Enabled);
  AssertFalse(StackForm.bbDelIcon.Enabled);
  StackForm.bbAddIconClick(nil);
  AssertFalse(StackForm.bbIconUp.Enabled);
  AssertFalse(StackForm.bbIconDown.Enabled);
  StackForm.bbAddIconClick(nil);
  AssertTrue(StackForm.bbIconUp.Enabled);
  AssertFalse(StackForm.bbIconDown.Enabled);
  StackForm.cboOrder.ItemIndex := 1;
  StackForm.OrderChanged(nil);
  AssertFalse(StackForm.bbIconUp.Enabled);
  AssertFalse(StackForm.bbIconDown.Enabled);
  AssertEquals('Sorting must remain pending', 0, Item.ItemCount);
  StackForm.btnApplyClick(nil);
  AssertTrue(Item.Sorted);
  AssertEquals(2, Item.ItemCount);
end;

procedure TPropertyLifetimeTests.StackDistanceAndNumbersStaySynchronized;
var Item: TStackItem;
begin
  Item := CreateStackForm;
  StackForm.numDistance.Value := 1.75;
  AssertEquals(7, StackForm.tbOffset.Position);
  StackForm.tbOffset.Position := 8;
  AssertEquals(2.0, StackForm.numDistance.Value, 0.001);
  StackForm.numHue.Value := 90;
  AssertEquals(90, StackForm.tbHue.Position);
  StackForm.numCont.Value := 255;
  AssertEquals(255, StackForm.tbCont.Position);
  StackForm.numSpeed.Value := 20;
  AssertEquals(20, StackForm.tbAnimationSpeed.Position);
  StackForm.btnApplyClick(nil);
  AssertEquals(8, Item.DistanceSteps);
  AssertEquals(255, byte(cardinal(Item.ColorData) shr 24));
  AssertEquals('The 100-pixel limit must not clip a 2x distance', 128, StackDistancePixels(Item.DistanceSteps, 64));
  Item.cmd(gpItemSize, 96);
  AssertEquals('Icon size changes retain the quarter-step value', 8, Item.DistanceSteps);
  AssertFalse(StackForm.btnApply.Enabled);
  StackForm.edCaption.Text := 'Changed';
  AssertTrue(StackForm.btnApply.Enabled);
  StackForm.edCaption.Text := 'Original stack';
  AssertFalse('Reverting a field must clear pending changes', StackForm.btnApply.Enabled);
end;

procedure TPropertyLifetimeTests.StackLocationPreservesControlPanelAndCustomDraft;
var Item: TStackItem;
begin
  Item := CreateStackForm;
  AssertEquals('None (custom stack)', StackForm.cboLocation.Items[0]);
  StackForm.bbAddIconClick(nil);
  StackForm.cboLocation.ItemIndex := 1;
  StackForm.LocationChanged(nil);
  AssertEquals('Control Panel must be a supported virtual location', '', StackForm.lblError.Caption);
  AssertFalse(StackForm.bbAddIcon.Enabled);
  AssertFalse(StackForm.bbEditIcon.Enabled);
  AssertEquals('The source must remain pending', '', Item.SpecialFolder);
  StackForm.cboLocation.ItemIndex := 0;
  StackForm.LocationChanged(nil);
  AssertEquals('Switching back must restore custom draft items', 1, StackForm.list.Items.Count);
  AssertTrue(StackForm.bbAddIcon.Enabled);
  StackForm.cboLocation.ItemIndex := 1;
  StackForm.LocationChanged(nil);
  StackForm.btnApplyClick(nil);
  AssertEquals('Applying Control Panel must succeed', '', StackForm.lblError.Caption);
  AssertEquals('CSIDL_CONTROLS', Item.SpecialFolder);
  AssertFalse(StackForm.btnApply.Enabled);
end;

procedure TPropertyLifetimeTests.StackCloseAndEscapeDiscardDrafts;
var Item: TStackItem; Key: word;
begin
  Item := CreateStackForm;
  StackForm.bbAddIconClick(nil);
  Key := VK_ESCAPE;
  StackForm.FormKeyDown(nil, Key, []);
  AssertEquals(0, Item.ItemCount);
  AssertEquals(0, Key);
  StackForm.Free;
  StackForm := nil;
  StackForm := TTestStackProp.Create(nil);
  AssertTrue(StackForm.BindItem(Item.Handle));
  StackForm.bbAddIconClick(nil);
  StackForm.Close;
  AssertEquals('Window close must discard additions', 0, Item.ItemCount);
end;

procedure TPropertyLifetimeTests.StackValidationFailureKeepsModelAndDraft;
var Item: TStackItem;
begin
  Item := CreateStackForm;
  StackForm.bbAddIconClick(nil);
  StackForm.cboLocation.ItemIndex := -1;
  StackForm.btnApplyClick(nil);
  AssertEquals(0, Item.ItemCount);
  AssertEquals('Original stack', UTF8Encode(Item.Caption));
  AssertTrue(StackForm.lblError.Caption <> '');
  AssertTrue(StackForm.btnApply.Enabled);
  AssertEquals('A validation error must retain the pending item', 1, StackForm.list.Items.Count);
end;

procedure TPropertyLifetimeTests.StackClosedPreviewUsesPendingItems;
var Item: TStackItem; Bitmap, Graphics: Pointer; Pixel: cardinal;
  X, Y, VisiblePixels: integer;
begin
  Item := CreateStackForm;
  StackForm.bbAddIconClick(nil);
  GdipCreateBitmapFromScan0(64, 64, 0, PixelFormat32bppPARGB, nil, Bitmap);
  GdipGetImageGraphicsContext(Bitmap, Graphics);
  try
    GdipGraphicsClear(Graphics, 0);
    StackForm.cboPreview.ItemIndex := 0;
    StackForm.PaintPreview(Graphics, 64);
    GdipBitmapGetPixel(Bitmap, 32, 32, Pixel);
    AssertEquals('None must leave the empty fixture icon unchanged', 0, Int64(Pixel));
    StackForm.cboPreview.ItemIndex := 2;
    StackForm.PaintPreview(Graphics, 64);
    VisiblePixels := 0;
    for Y := 0 to 63 do
      for X := 0 to 63 do
      begin
        GdipBitmapGetPixel(Bitmap, X, Y, Pixel);
        if Pixel shr 24 <> 0 then Inc(VisiblePixels);
      end;
    AssertTrue('Pending items must appear in the closed icon preview', VisiblePixels > 0);
    AssertEquals('Previewing must not commit draft children', 0, Item.ItemCount);
    AssertEquals(128, StackForm.iPic.Width);
    AssertEquals(128, StackForm.iPic.Height);
  finally GdipDeleteGraphics(Graphics); GdipDisposeImage(Bitmap); end;
end;

procedure TPropertyLifetimeTests.StackLayoutFitsAtLargerScales;
const Scales: array[0..2] of integer = (125, 150, 200);
var Item: TStackItem; Scale, Index: integer; Control: TControl;
begin
  Item := CreateStackForm;
  for Scale in Scales do
  begin
    StackForm.Free;
    StackForm := TTestStackProp.Create(nil);
    AssertTrue(StackForm.BindItem(Item.Handle));
    StackForm.Width := StackForm.Constraints.MinWidth;
    StackForm.Height := StackForm.Constraints.MinHeight;
    StackForm.ScaleBy(Scale, 100);
    AssertEquals(4, StackForm.pages.PageCount);
    AssertTrue(StackForm.pages.ShowTabs);
    for Index := 0 to StackForm.ComponentCount - 1 do
      if StackForm.Components[Index] is TControl then
      begin
        Control := TControl(StackForm.Components[Index]);
        if (Control.Parent = StackForm.tsItems) or (Control.Parent = StackForm.tsAnimation) then
        begin
          AssertTrue(Control.Name + ' must fit horizontally',
            (Control.Left >= 0) and (Control.Left + Control.Width <= Control.Parent.ClientWidth));
          AssertTrue(Control.Name + ' must fit vertically',
            (Control.Top >= 0) and (Control.Top + Control.Height <= Control.Parent.ClientHeight));
        end;
      end;
  end;
end;

procedure TPropertyLifetimeTests.DriveDraftEditor(Sender: TObject; var Done: boolean);
var Index: integer; Editor: TfrmItemProp;
begin
  for Index := 0 to Screen.FormCount - 1 do
    if (Screen.Forms[Index] is TfrmItemProp) and (Screen.Forms[Index] <> ItemForm) then
    begin
      Editor := TfrmItemProp(Screen.Forms[Index]);
      if not Editor.Visible then Continue;
      Editor.edCaption.Text := 'Pending child edit';
      Editor.edCmd.Text := '/pending';
      if AcceptDraftEditor then Editor.btnOKClick(nil) else Editor.btnCancelClick(nil);
      Done := true;
      Exit;
    end;
  Done := false;
end;

procedure TPropertyLifetimeTests.StackChildEditorKeepsTheLiveShortcutUntouched;
var Item: TShortcutItem; Text, Original: string; PreviousIdle: TIdleEvent;
begin
  Item := CreateItemForm;
  Text := TShortcutSubitem.Make('Original child');
  Original := Text;
  PreviousIdle := Application.OnIdle;
  Application.OnIdle := DriveDraftEditor;
  try
    AcceptDraftEditor := false;
    AssertFalse(TfrmItemProp.EditDraft(Text));
    AssertEquals(Original, Text);
    AcceptDraftEditor := true;
    AssertTrue(TfrmItemProp.EditDraft(Text));
    AssertEquals('Pending child edit', UTF8Encode(ReadShortcutText(Text).Caption));
    AssertEquals('/pending', ReadShortcutText(Text).Command);
    AssertEquals('Original shortcut', UTF8Encode(Item.Caption));
    AssertEquals('', Item.Command);
    AssertTrue('Draft editors must preserve the existing property form', frmItemProp = ItemForm);
  finally Application.OnIdle := PreviousIdle; end;
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
