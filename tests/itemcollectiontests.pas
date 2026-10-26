unit itemcollectiontests;

{$mode delphi}

interface

uses SysUtils, fpcunit, testregistry, itemcollectionu;

type
  TAllocationFailureCollection = class(TItemCollection)
  protected
    procedure Grow(newCount: integer); override;
  public
    FailNextGrowth: boolean;
  end;

  TItemCollectionTests = class(TTestCase)
  private
    Items: TItemCollection;
    procedure Populate(count: integer);
    procedure CheckOrder(const expected: array of THandle);
    procedure CheckReadRejected(index: integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure EmptyCollection;
    procedure GrowsAcrossFormerLimit;
    procedure InsertsAtBeginningMiddleAndEnd;
    procedure BulkInsertionAcrossFormerLimit;
    procedure PreviewDoesNotConsumeCapacity;
    procedure MovesPreviewPreserveOrder;
    procedure NormalizesPreviewBounds;
    procedure InvalidReadsRaiseWithRangeChecksDisabled;
    procedure FailedAddPreservesPreview;
    procedure RejectsDuplicateHandles;
    procedure DeletesFirstMiddleAndLast;
    procedure DeletionRebasesPreview;
    procedure DeletionMovesCompleteRecords;
    procedure RestoreBeyondFormerLimit;
    procedure RestoreIntoPreview;
    procedure RestoreUsesLastDeletedFirst;
    procedure InvalidDeletionPreservesUndo;
    procedure DragAndRedockAtFormerLimit;
    procedure DragLeaveAndReentryPreserveOwnership;
    procedure CancelDragRestoresOriginalOrder;
    procedure DeleteDraggedItemCanBeRestored;
    procedure ExternalDragCanBeDeletedAndRestored;
    procedure DragOriginTracksOtherMutations;
    procedure ClearResetsPreviewAndDrag;
    procedure ForgetDeletedPreservesOtherUndoEntries;
    procedure FailedGrowthPreservesItemsAndPreview;
    procedure FailedRestorationKeepsUndoEntry;
    procedure FailedDropPreservesDraggedItem;
    procedure SavingIncludesDraggedItemWithoutPreview;
    procedure SamePreviewPreservesGeometry;
    procedure ForgetRemovesDestroyedOwnership;
  end;

implementation

procedure TAllocationFailureCollection.Grow(newCount: integer);
begin
  if FailNextGrowth then
  begin
    FailNextGrowth := false;
    raise EOutOfMemory.Create('Simulated allocation failure');
  end;
  inherited Grow(newCount);
end;

procedure TItemCollectionTests.SetUp;
begin
  Items := TAllocationFailureCollection.Create;
end;

procedure TItemCollectionTests.TearDown;
begin
  Items.Free;
end;

procedure TItemCollectionTests.Populate(count: integer);
var i: integer;
begin
  for i := 1 to count do AssertTrue(Items.Add(THandle(i), 32));
end;

procedure TItemCollectionTests.CheckOrder(const expected: array of THandle);
var i: integer;
begin
  AssertEquals(Length(expected), Items.ViewCount);
  for i := 0 to High(expected) do
    AssertEquals('Handle at ' + IntToStr(i), int64(expected[i]), int64(Items[i]^.Id));
end;

procedure TItemCollectionTests.CheckReadRejected(index: integer);
var raised: boolean;
begin
  raised := false;
  try
    Items[index];
  except
    on ERangeError do raised := true;
  end;
  AssertTrue('Invalid read ' + IntToStr(index), raised);
end;

procedure TItemCollectionTests.EmptyCollection;
begin
  AssertEquals(0, Items.Count);
  AssertEquals(0, Items.ViewCount);
  AssertEquals(0, Items.DeletedCount);
  AssertEquals(NO_ITEM_INDEX, Items.PreviewIndex);
  AssertEquals(int64(0), int64(Items.RestoreLast));
end;

procedure TItemCollectionTests.GrowsAcrossFormerLimit;
var i: integer;
begin
  Populate(1024);
  AssertEquals(1024, Items.Count);
  for i := 0 to 1023 do AssertEquals(int64(i + 1), int64(Items[i]^.Id));
end;

procedure TItemCollectionTests.InsertsAtBeginningMiddleAndEnd;
begin
  Populate(3);
  Items.SetPreview(0, 32);
  AssertTrue(Items.Add(4, 32));
  Items.SetPreview(2, 32);
  AssertTrue(Items.Add(5, 32));
  Items.SetPreview(Items.Count, 32);
  AssertTrue(Items.Add(6, 32));
  CheckOrder([4, 1, 5, 2, 3, 6]);
end;

procedure TItemCollectionTests.BulkInsertionAcrossFormerLimit;
var i: integer;
begin
  Populate(127);
  for i := 0 to 3 do
  begin
    Items.SetPreview(64 + i, 32);
    AssertTrue(Items.Add(THandle(128 + i), 32));
  end;
  AssertEquals(131, Items.Count);
  AssertEquals(int64(64), int64(Items[63]^.Id));
  for i := 0 to 3 do AssertEquals(int64(128 + i), int64(Items[64 + i]^.Id));
  AssertEquals(int64(65), int64(Items[68]^.Id));
end;

procedure TItemCollectionTests.PreviewDoesNotConsumeCapacity;
begin
  Populate(128);
  Items.SetPreview(128, 32);
  AssertEquals(128, Items.Count);
  AssertEquals(129, Items.ViewCount);
  AssertEquals(int64(0), int64(Items[128]^.Id));
  AssertEquals(32, Items[128]^.s);
  AssertTrue(Items.Add(129, 32));
  AssertEquals(129, Items.Count);
  AssertEquals(129, Items.ViewCount);
  AssertEquals(NO_ITEM_INDEX, Items.PreviewIndex);
end;

procedure TItemCollectionTests.MovesPreviewPreserveOrder;
begin
  Populate(3);
  Items.SetPreview(0, 32);
  CheckOrder([0, 1, 2, 3]);
  Items.SetPreview(2, 32);
  CheckOrder([1, 2, 0, 3]);
  AssertEquals(3, Items.IndexOf(3));
  Items.SetPreview(3, 32);
  CheckOrder([1, 2, 3, 0]);
  Items.ClearPreview;
  CheckOrder([1, 2, 3]);
end;

procedure TItemCollectionTests.NormalizesPreviewBounds;
begin
  Items.SetPreview(999, 32);
  CheckOrder([0]);
  Items.ClearPreview;
  Populate(3);
  Items.SetPreview(-100, 32);
  AssertEquals(0, Items.PreviewIndex);
  Items.SetPreview(MaxInt, 32);
  AssertEquals(3, Items.PreviewIndex);
  CheckOrder([1, 2, 3, 0]);
end;

procedure TItemCollectionTests.InvalidReadsRaiseWithRangeChecksDisabled;
begin
  CheckReadRejected(0);
  Populate(128);
  CheckReadRejected(-1);
  CheckReadRejected(128);
  CheckReadRejected(MaxInt);
  Items.SetPreview(128, 32);
  CheckReadRejected(129);
end;

procedure TItemCollectionTests.FailedAddPreservesPreview;
begin
  Populate(128);
  Items.SetPreview(64, 32);
  AssertFalse(Items.Add(0, 32));
  AssertEquals(128, Items.Count);
  AssertEquals(64, Items.PreviewIndex);
  AssertTrue(Items.Add(129, 32));
  AssertEquals(int64(129), int64(Items[64]^.Id));
  AssertEquals(int64(65), int64(Items[65]^.Id));
end;

procedure TItemCollectionTests.RejectsDuplicateHandles;
begin
  Populate(3);
  AssertFalse(Items.Add(2, 32));
  AssertTrue(Items.BeginDrag(2, 32));
  AssertFalse(Items.Add(2, 32));
  AssertTrue(Items.Delete(2));
  AssertFalse(Items.Add(2, 32));
  AssertEquals(int64(2), int64(Items.RestoreLast));
  CheckOrder([1, 3, 2]);
end;

procedure TItemCollectionTests.DeletesFirstMiddleAndLast;
begin
  Populate(128);
  AssertTrue(Items.Delete(1));
  AssertTrue(Items.Delete(64));
  AssertTrue(Items.Delete(128));
  AssertEquals(125, Items.Count);
  AssertEquals(3, Items.DeletedCount);
  AssertEquals(int64(2), int64(Items[0]^.Id));
  AssertEquals(int64(65), int64(Items[62]^.Id));
  AssertEquals(int64(127), int64(Items[124]^.Id));
end;

procedure TItemCollectionTests.DeletionRebasesPreview;
begin
  Populate(3);
  Items.SetPreview(2, 32);
  AssertTrue(Items.Delete(1));
  AssertEquals(1, Items.PreviewIndex);
  AssertTrue(Items.Add(4, 32));
  CheckOrder([2, 4, 3]);
end;

procedure TItemCollectionTests.DeletionMovesCompleteRecords;
begin
  Populate(3);
  Items[2]^.x := 10;
  Items[2]^.y := 20;
  Items[2]^.xe := 10.5;
  Items[2]^.ye := 20.5;
  Items[2]^.se := 32.5;
  AssertTrue(Items.Delete(2));
  AssertEquals(10, Items[1]^.x);
  AssertEquals(20, Items[1]^.y);
  AssertTrue(Items[1]^.xe = 10.5);
  AssertTrue(Items[1]^.ye = 20.5);
  AssertTrue(Items[1]^.se = 32.5);
end;

procedure TItemCollectionTests.RestoreBeyondFormerLimit;
begin
  Populate(128);
  AssertTrue(Items.Delete(64));
  AssertTrue(Items.Add(129, 32));
  AssertTrue(Items.Add(130, 32));
  AssertEquals(int64(64), int64(Items.RestoreLast));
  AssertEquals(130, Items.Count);
  AssertEquals(0, Items.DeletedCount);
  AssertEquals(int64(64), int64(Items[129]^.Id));
end;

procedure TItemCollectionTests.RestoreIntoPreview;
begin
  Populate(3);
  AssertTrue(Items.Delete(2));
  Items.SetPreview(0, 32);
  AssertEquals(int64(2), int64(Items.RestoreLast));
  CheckOrder([2, 1, 3]);
  AssertEquals(0, Items.DeletedCount);
  AssertEquals(NO_ITEM_INDEX, Items.PreviewIndex);
end;

procedure TItemCollectionTests.RestoreUsesLastDeletedFirst;
begin
  Populate(3);
  AssertTrue(Items.Delete(1));
  AssertTrue(Items.Delete(3));
  AssertEquals(int64(3), int64(Items.RestoreLast));
  AssertEquals(int64(1), int64(Items.RestoreLast));
  CheckOrder([2, 3, 1]);
end;

procedure TItemCollectionTests.InvalidDeletionPreservesUndo;
begin
  Populate(3);
  AssertFalse(Items.Delete(0));
  AssertFalse(Items.Delete(4));
  AssertTrue(Items.Delete(2));
  AssertFalse(Items.Delete(2));
  AssertEquals(1, Items.DeletedCount);
  AssertEquals(int64(2), int64(Items.RestoreLast));
end;

procedure TItemCollectionTests.DragAndRedockAtFormerLimit;
begin
  Populate(128);
  AssertTrue(Items.BeginDrag(128, 32));
  AssertEquals(127, Items.Count);
  AssertEquals(128, Items.ViewCount);
  Items.SetPreview(0, 32);
  AssertEquals(int64(128), int64(Items.DropDragged));
  AssertEquals(128, Items.Count);
  AssertEquals(int64(128), int64(Items[0]^.Id));
  AssertEquals(int64(127), int64(Items[127]^.Id));
  AssertEquals(int64(0), int64(Items.DraggedId));
end;

procedure TItemCollectionTests.DragLeaveAndReentryPreserveOwnership;
begin
  Populate(128);
  AssertTrue(Items.BeginDrag(64, 32));
  Items.ClearPreview;
  AssertEquals(127, Items.ViewCount);
  AssertEquals(int64(64), int64(Items.DraggedId));
  AssertEquals(int64(0), int64(Items.DropDragged));
  Items.SetPreview(Items.Count, 32);
  AssertEquals(int64(64), int64(Items.DropDragged));
  AssertEquals(128, Items.Count);
end;

procedure TItemCollectionTests.CancelDragRestoresOriginalOrder;
begin
  Populate(3);
  AssertTrue(Items.BeginDrag(2, 32));
  AssertFalse(Items.BeginDrag(3, 32));
  Items.SetPreview(0, 32);
  AssertEquals(int64(2), int64(Items.CancelDrag));
  CheckOrder([1, 2, 3]);
end;

procedure TItemCollectionTests.DeleteDraggedItemCanBeRestored;
begin
  Populate(3);
  AssertTrue(Items.BeginDrag(2, 32));
  Items.ClearPreview;
  AssertTrue(Items.Delete(2));
  AssertEquals(1, Items.DeletedCount);
  AssertEquals(int64(0), int64(Items.DraggedId));
  AssertEquals(int64(2), int64(Items.RestoreLast));
  CheckOrder([1, 3, 2]);
end;

procedure TItemCollectionTests.ExternalDragCanBeDeletedAndRestored;
begin
  Populate(128);
  AssertTrue(Items.BeginDrag(129, 32));
  AssertEquals(128, Items.Count);
  AssertEquals(NO_ITEM_INDEX, Items.PreviewIndex);
  AssertTrue(Items.Delete(129));
  AssertEquals(int64(129), int64(Items.RestoreLast));
  AssertEquals(129, Items.Count);
end;

procedure TItemCollectionTests.DragOriginTracksOtherMutations;
begin
  Populate(4);
  AssertTrue(Items.BeginDrag(3, 32));
  AssertTrue(Items.Delete(1));
  Items.SetPreview(0, 32);
  AssertTrue(Items.Add(5, 32));
  AssertEquals(int64(3), int64(Items.CancelDrag));
  CheckOrder([5, 2, 3, 4]);
end;

procedure TItemCollectionTests.ClearResetsPreviewAndDrag;
begin
  Populate(3);
  AssertTrue(Items.Delete(1));
  AssertTrue(Items.BeginDrag(2, 32));
  Items.Clear;
  AssertEquals(0, Items.Count);
  AssertEquals(0, Items.ViewCount);
  AssertEquals(int64(0), int64(Items.DraggedId));
  AssertEquals(NO_ITEM_INDEX, Items.PreviewIndex);
  AssertEquals(1, Items.DeletedCount);
  Items.ClearDeleted;
  AssertEquals(0, Items.DeletedCount);
end;

procedure TItemCollectionTests.ForgetDeletedPreservesOtherUndoEntries;
begin
  Populate(3);
  AssertTrue(Items.Delete(1));
  AssertTrue(Items.Delete(2));
  AssertTrue(Items.Delete(3));
  Items.ForgetDeleted(1);
  AssertEquals(2, Items.DeletedCount);
  AssertEquals(int64(3), int64(Items.RestoreLast));
  AssertEquals(int64(1), int64(Items.RestoreLast));
  CheckOrder([3, 1]);
end;

procedure TItemCollectionTests.FailedGrowthPreservesItemsAndPreview;
var raised: boolean;
begin
  Populate(128);
  Items.SetPreview(64, 32);
  TAllocationFailureCollection(Items).FailNextGrowth := true;
  raised := false;
  try
    Items.Add(129, 32);
  except
    on EOutOfMemory do raised := true;
  end;
  AssertTrue(raised);
  AssertEquals(128, Items.Count);
  AssertEquals(64, Items.PreviewIndex);
  AssertFalse(Items.Contains(129));
  AssertEquals(int64(65), int64(Items[65]^.Id));
  AssertTrue(Items.Add(129, 32));
end;

procedure TItemCollectionTests.FailedRestorationKeepsUndoEntry;
var raised: boolean;
begin
  Populate(3);
  AssertTrue(Items.Delete(2));
  TAllocationFailureCollection(Items).FailNextGrowth := true;
  raised := false;
  try
    Items.RestoreLast;
  except
    on EOutOfMemory do raised := true;
  end;
  AssertTrue(raised);
  CheckOrder([1, 3]);
  AssertEquals(1, Items.DeletedCount);
  AssertEquals(int64(2), int64(Items.DeletedId(0)));
  AssertEquals(int64(2), int64(Items.RestoreLast));
end;

procedure TItemCollectionTests.FailedDropPreservesDraggedItem;
var raised: boolean;
begin
  Populate(3);
  AssertTrue(Items.BeginDrag(2, 32));
  TAllocationFailureCollection(Items).FailNextGrowth := true;
  raised := false;
  try
    Items.DropDragged;
  except
    on EOutOfMemory do raised := true;
  end;
  AssertTrue(raised);
  AssertEquals(int64(2), int64(Items.DraggedId));
  AssertEquals(1, Items.PreviewIndex);
  AssertEquals(int64(2), int64(Items.DropDragged));
  CheckOrder([1, 2, 3]);
end;

procedure TItemCollectionTests.SavingIncludesDraggedItemWithoutPreview;
var i: integer;
begin
  Populate(3);
  AssertTrue(Items.BeginDrag(2, 32));
  Items.SetPreview(0, 32);
  AssertEquals(3, Items.SaveCount);
  for i := 0 to 2 do AssertEquals(int64(i + 1), int64(Items.SavedItems[i].Id));
  AssertEquals(1, Items.SaveIndexOf(2));
  Items.ClearPreview;
  AssertEquals(3, Items.SaveCount);
  AssertEquals(2, Items.SaveIndexOf(3));
  AssertEquals(NO_ITEM_INDEX, Items.SaveIndexOf(0));
end;

procedure TItemCollectionTests.SamePreviewPreservesGeometry;
begin
  Populate(3);
  Items.SetPreview(3, 32);
  Items[3]^.x := 96;
  Items.SetPreview(3, 32);
  AssertEquals(96, Items[3]^.x);
end;

procedure TItemCollectionTests.ForgetRemovesDestroyedOwnership;
begin
  Populate(3);
  Items.Delete(1);
  Items.BeginDrag(2, 32);
  AssertTrue('Destroyed dragged item must leave ownership', Items.Forget(2));
  AssertEquals(int64(0), int64(Items.DraggedId));
  AssertTrue(Items.Forget(3));
  AssertTrue(Items.Forget(1));
  AssertEquals(0, Items.Count);
  AssertEquals(0, Items.DeletedCount);
  AssertEquals(NO_ITEM_INDEX, Items.PreviewIndex);
end;

initialization
  RegisterTest(TItemCollectionTests);
end.
