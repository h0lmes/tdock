unit itemcollectionu;

{$mode delphi}

interface

uses SysUtils, itemmodelu;

const
  NO_ITEM_INDEX = -1;

type
  PItem = ^TItem;
  TItem = record
    Id: TItemId;
    x, y, s: integer;
    xe, ye, se: extended;
  end;
  TItemArray = array of TItem;

  { Stores model IDs and layout records. TItemStore owns the models. }
  TItemCollection = class
  private
    FItems, FDeleted: TItemArray;
    FPreview: TItem;
    FPreviewIndex: integer;
    FDragged: TItem;
    FDragOrigin: integer;
    function GetCount: integer;
    function GetViewCount: integer;
    function GetDeletedCount: integer;
    function GetSaveCount: integer;
    function GetSavedItem(index: integer): TItem;
    function GetDraggedId: TItemId;
    function GetItem(index: integer): PItem;
    function ActualIndex(wnd: TItemId): integer;
    function OwnsId(wnd: TItemId): boolean;
    procedure InsertRecord(const item: TItem; index: integer);
    procedure RemoveRecord(index: integer);
  protected
    procedure Grow(newCount: integer); virtual;
  public
    constructor Create;
    function IndexOf(wnd: TItemId): integer;
    function SaveIndexOf(wnd: TItemId): integer;
    function Contains(wnd: TItemId): boolean;
    function Add(wnd: TItemId; size: integer): boolean;
    procedure SetPreview(index, size: integer);
    procedure ClearPreview;
    function BeginDrag(wnd: TItemId; size: integer): boolean;
    function DropDragged: TItemId;
    function CancelDrag: TItemId;
    function Delete(wnd: TItemId): boolean;
    function DeletePending(Id: TItemId; size: integer): boolean;
    function Forget(wnd: TItemId): boolean;
    function RestoreLast: TItemId;
    function DeletedId(index: integer): TItemId;
    procedure ForgetDeleted(index: integer);
    procedure Clear;
    procedure ClearDeleted;
    property Count: integer read GetCount;
    property ViewCount: integer read GetViewCount;
    property DeletedCount: integer read GetDeletedCount;
    property SaveCount: integer read GetSaveCount;
    property SavedItems[index: integer]: TItem read GetSavedItem;
    property PreviewIndex: integer read FPreviewIndex;
    property DraggedId: TItemId read GetDraggedId;
    { Returned pointers remain valid only until the next collection mutation. }
    property Items[index: integer]: PItem read GetItem; default;
  end;

implementation

constructor TItemCollection.Create;
begin
  inherited Create;
  FPreviewIndex := NO_ITEM_INDEX;
  FDragOrigin := NO_ITEM_INDEX;
end;

function TItemCollection.GetCount: integer;
begin
  result := Length(FItems);
end;

function TItemCollection.GetViewCount: integer;
begin
  result := Count;
  if FPreviewIndex <> NO_ITEM_INDEX then inc(result);
end;

function TItemCollection.GetDeletedCount: integer;
begin
  result := Length(FDeleted);
end;

function TItemCollection.GetSaveCount: integer;
begin
  result := Count;
  if FDragged.Id <> 0 then inc(result);
end;

function TItemCollection.GetSavedItem(index: integer): TItem;
begin
  if (index < 0) or (index >= SaveCount) then
    raise ERangeError.Create('Invalid saved item index');
  if FDragged.Id <> 0 then
  begin
    if index = FDragOrigin then exit(FDragged);
    if index > FDragOrigin then dec(index);
  end;
  result := FItems[index];
end;

function TItemCollection.GetDraggedId: TItemId;
begin
  result := FDragged.Id;
end;

function TItemCollection.GetItem(index: integer): PItem;
begin
  if (index < 0) or (index >= ViewCount) then
    raise ERangeError.CreateFmt('Item index %d is outside the collection', [index]);
  if FPreviewIndex <> NO_ITEM_INDEX then
  begin
    if index = FPreviewIndex then exit(@FPreview);
    if index > FPreviewIndex then dec(index);
  end;
  result := @FItems[index];
end;

function TItemCollection.ActualIndex(wnd: TItemId): integer;
var i: integer;
begin
  result := NO_ITEM_INDEX;
  if wnd = 0 then exit;
  for i := 0 to Count - 1 do
    if FItems[i].Id = wnd then exit(i);
end;

function TItemCollection.IndexOf(wnd: TItemId): integer;
begin
  result := ActualIndex(wnd);
  if (result <> NO_ITEM_INDEX) and (FPreviewIndex <> NO_ITEM_INDEX) then
    if result >= FPreviewIndex then inc(result);
end;

function TItemCollection.OwnsId(wnd: TItemId): boolean;
var i: integer;
begin
  result := (ActualIndex(wnd) <> NO_ITEM_INDEX) or (FDragged.Id = wnd);
  if result then exit;
  for i := 0 to DeletedCount - 1 do
    if FDeleted[i].Id = wnd then exit(true);
end;

function TItemCollection.Contains(wnd: TItemId): boolean;
begin
  result := (wnd <> 0) and OwnsId(wnd);
end;

function TItemCollection.SaveIndexOf(wnd: TItemId): integer;
begin
  result := NO_ITEM_INDEX;
  if wnd = 0 then exit;
  if FDragged.Id = wnd then exit(FDragOrigin);
  result := ActualIndex(wnd);
  if (result <> NO_ITEM_INDEX) and (FDragged.Id <> 0) then
    if result >= FDragOrigin then inc(result);
end;

procedure TItemCollection.Grow(newCount: integer);
begin
  SetLength(FItems, newCount);
end;

procedure TItemCollection.InsertRecord(const item: TItem; index: integer);
var i, previousCount: integer;
begin
  previousCount := Count;
  if (index < 0) or (index > previousCount) then
    raise ERangeError.Create('Invalid insertion position');
  { Allocate before changing records or ownership. }
  Grow(previousCount + 1);
  for i := previousCount downto index + 1 do FItems[i] := FItems[i - 1];
  FItems[index] := item;
  if (FDragOrigin <> NO_ITEM_INDEX) and (index < FDragOrigin) then inc(FDragOrigin);
end;

procedure TItemCollection.RemoveRecord(index: integer);
var i: integer;
begin
  for i := index to Count - 2 do FItems[i] := FItems[i + 1];
  SetLength(FItems, Count - 1);
  if (FPreviewIndex <> NO_ITEM_INDEX) and (index < FPreviewIndex) then dec(FPreviewIndex);
  if (FDragOrigin <> NO_ITEM_INDEX) and (index < FDragOrigin) then dec(FDragOrigin);
end;

function TItemCollection.Add(wnd: TItemId; size: integer): boolean;
var item: TItem; index: integer;
begin
  result := false;
  if (wnd = 0) or OwnsId(wnd) then exit;
  item := Default(TItem);
  item.Id := wnd;
  item.s := size;
  index := FPreviewIndex;
  if index = NO_ITEM_INDEX then index := Count;
  InsertRecord(item, index);
  ClearPreview;
  result := true;
end;

procedure TItemCollection.SetPreview(index, size: integer);
begin
  if index < 0 then index := 0;
  if index > Count then index := Count;
  if index <> FPreviewIndex then FPreview := Default(TItem);
  FPreviewIndex := index;
  FPreview.s := size;
end;

procedure TItemCollection.ClearPreview;
begin
  FPreviewIndex := NO_ITEM_INDEX;
  FPreview := Default(TItem);
end;

function TItemCollection.BeginDrag(wnd: TItemId; size: integer): boolean;
var index: integer;
begin
  result := false;
  if (wnd = 0) or (FDragged.Id <> 0) then exit;
  index := ActualIndex(wnd);
  if index <> NO_ITEM_INDEX then
  begin
    FDragged := FItems[index];
    RemoveRecord(index);
    FDragOrigin := index;
    SetPreview(index, size);
  end else begin
    if OwnsId(wnd) then exit;
    FDragged := Default(TItem);
    FDragged.Id := wnd;
    FDragged.s := size;
    FDragOrigin := Count;
    ClearPreview;
  end;
  result := true;
end;

function TItemCollection.DropDragged: TItemId;
begin
  result := 0;
  if (FDragged.Id = 0) or (FPreviewIndex = NO_ITEM_INDEX) then exit;
  InsertRecord(FDragged, FPreviewIndex);
  result := FDragged.Id;
  FDragged := Default(TItem);
  FDragOrigin := NO_ITEM_INDEX;
  ClearPreview;
end;

function TItemCollection.CancelDrag: TItemId;
begin
  result := 0;
  if FDragged.Id = 0 then exit;
  InsertRecord(FDragged, FDragOrigin);
  result := FDragged.Id;
  FDragged := Default(TItem);
  FDragOrigin := NO_ITEM_INDEX;
  ClearPreview;
end;

function TItemCollection.Delete(wnd: TItemId): boolean;
var index, previousDeleted: integer; item: TItem;
begin
  result := false;
  if wnd = 0 then exit;
  index := ActualIndex(wnd);
  if index <> NO_ITEM_INDEX then item := FItems[index]
  else if FDragged.Id = wnd then item := FDragged
  else exit;
  previousDeleted := DeletedCount;
  SetLength(FDeleted, previousDeleted + 1);
  FDeleted[previousDeleted] := item;
  if index <> NO_ITEM_INDEX then RemoveRecord(index)
  else begin
    FDragged := Default(TItem);
    FDragOrigin := NO_ITEM_INDEX;
    ClearPreview;
  end;
  result := true;
end;

function TItemCollection.RestoreLast: TItemId;
var index, last: integer;
begin
  result := 0;
  last := DeletedCount - 1;
  if last < 0 then exit;
  index := FPreviewIndex;
  if index = NO_ITEM_INDEX then index := Count;
  InsertRecord(FDeleted[last], index);
  result := FDeleted[last].Id;
  SetLength(FDeleted, last);
  ClearPreview;
end;

function TItemCollection.DeletePending(Id: TItemId; size: integer): boolean;
var index: integer;
begin
  result := false;
  if (Id = NO_ITEM_ID) or OwnsId(Id) then exit;
  index := DeletedCount;
  SetLength(FDeleted, index + 1);
  FDeleted[index].Id := Id;
  FDeleted[index].s := size;
  result := true;
end;

function TItemCollection.Forget(wnd: TItemId): boolean;
var index: integer;
begin
  result := false;
  if wnd = 0 then exit;
  index := ActualIndex(wnd);
  if index >= 0 then
  begin
    RemoveRecord(index);
    exit(true);
  end;
  if FDragged.Id = wnd then
  begin
    FDragged := Default(TItem);
    FDragOrigin := NO_ITEM_INDEX;
    ClearPreview;
    exit(true);
  end;
  for index := 0 to DeletedCount - 1 do
    if FDeleted[index].Id = wnd then
    begin
      ForgetDeleted(index);
      exit(true);
    end;
end;

function TItemCollection.DeletedId(index: integer): TItemId;
begin
  if (index < 0) or (index >= DeletedCount) then
    raise ERangeError.Create('Invalid deleted item index');
  result := FDeleted[index].Id;
end;

procedure TItemCollection.ForgetDeleted(index: integer);
var i: integer;
begin
  DeletedId(index); // validate before changing the list
  for i := index to DeletedCount - 2 do FDeleted[i] := FDeleted[i + 1];
  SetLength(FDeleted, DeletedCount - 1);
end;

procedure TItemCollection.Clear;
begin
  SetLength(FItems, 0);
  FDragged := Default(TItem);
  FDragOrigin := NO_ITEM_INDEX;
  ClearPreview;
end;

procedure TItemCollection.ClearDeleted;
begin
  SetLength(FDeleted, 0);
end;

end.
