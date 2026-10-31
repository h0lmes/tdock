unit docklayouttests;

{$mode delphi}

interface

uses Types, Windows, SysUtils, fpcunit, testregistry, docklayoutu, stackmodeu;

type
  TDockLayoutTests = class(TTestCase)
  private
    Input: TDockLayoutInput;
    Items: TDockLayoutItems;
  protected
    procedure SetUp; override;
  published
    procedure BottomGeometryPreservesMonitorAndOddSpacing;
    procedure GeometryKeepsAllFourEdges;
    procedure EmptyDockKeepsNegativeDivisionRounding;
    procedure FullMonitorKeepsZoomExtent;
    procedure ItemLayoutKeepsFourEdgesAndSeparatorMargin;
    procedure FractionalZoomKeepsRoundingAtBubbleBoundary;
    procedure LayoutDoesNotMutateInput;
    procedure BoundsIncludeZoomOnEachEdge;
    procedure PositionHitTestKeepsInclusiveDockBoundary;
    procedure RectangleHitTestKeepsExclusiveRightAndBottom;
    procedure StackReversalKeepsVisibleGeometry;
  end;

implementation

procedure TDockLayoutTests.StackReversalKeepsVisibleGeometry;
const ProgressSamples: array[0..4] of Double = (0.1, 0.3, 0.5, 0.7, 0.9);
var Mode, Site, Index, Sample: Integer; Opening, Closing: TStackItemData;
  Controller: TStackModeController; Context: string;
begin
  Controller := TStackModeController.Create;
  try
    for Mode := 0 to MODE_COUNT do
      for Site := 0 to 3 do
        for Index := 0 to 4 do
          for Sample := 0 to High(ProgressSamples) do
          begin
            Context := Format('Mode %d, edge %d, child %d, progress %.1f',
              [Mode, Site, Index, ProgressSamples[Sample]]);
            Opening := Controller.GetItemData(Mode, True, True,
              ProgressSamples[Sample], Index, 5, Site, 48, 10, 2);
            Closing := Controller.GetItemData(Mode, False, True,
              ProgressSamples[Sample], Index, 5, Site, 48, 10, 2);
            AssertEquals(Context + ': horizontal position', Opening.x, Closing.x);
            AssertEquals(Context + ': vertical position', Opening.y, Closing.y);
            AssertEquals(Context + ': size', Opening.s, Closing.s);
            AssertEquals(Context + ': opacity', Opening.alpha, Closing.alpha);
            AssertEquals(Context + ': rotation', Opening.angle, Closing.angle, 0.0001);
          end;
  finally Controller.Free; end;
end;

procedure TDockLayoutTests.SetUp;
begin
  FillChar(Input, SizeOf(Input), 0);
  Input.Site := DOCK_BOTTOM;
  Input.MonitorRect := Types.Rect(-1920, 120, 0, 1200);
  Input.ItemsArea := Types.Rect(3, 5, 7, 11);
  Input.ItemsArea2 := Types.Rect(2, 3, 4, 6);
  Input.ItemSize := 32;
  Input.BigItemSize := 64;
  Input.ItemSpacing := 5;
  Input.ZoomWidth := 4;
  Input.CenterOffsetPercent := 25;
  Input.Margin := 9;
  Input.Margin2 := 4;
  Input.WndOffset := 13;
  Input.EdgeOffset := -3;
  SetLength(Items, 3);
  Items[0].X := -1466;
  Items[1].X := -1429;
  Items[2].X := -1392;
  Items[0].Size := 32;
  Items[1].Size := 32;
  Items[2].Size := 32;
end;

procedure TDockLayoutTests.BottomGeometryPreservesMonitorAndOddSpacing;
var Geometry: TDockGeometry;
begin
  Geometry := CalculateDockGeometry(Input, Items);
  AssertEquals('Image X', 447, Geometry.BaseImageRect.X);
  AssertEquals('Image width', 127, Geometry.BaseImageRect.Width);
  AssertEquals('Image height', 57, Geometry.BaseImageRect.Height);
  AssertEquals('Window X', -1920, Geometry.BaseWindowRect.X);
  AssertEquals('Window Y', 1167, Geometry.BaseWindowRect.Y);
  AssertEquals('Window width', 1920, Geometry.BaseWindowRect.Width);
  AssertEquals('Window height', 49, Geometry.BaseWindowRect.Height);
end;

procedure TDockLayoutTests.GeometryKeepsAllFourEdges;
var Geometry: TDockGeometry;
begin
  Items[0].Y := 364;
  Items[1].Y := 401;
  Items[2].Y := 438;
  Input.Site := DOCK_LEFT;
  Geometry := CalculateDockGeometry(Input, Items);
  AssertEquals(4, Geometry.X);
  AssertEquals(234, Geometry.Y);
  AssertEquals(48, Geometry.Width);
  AssertEquals(136, Geometry.Height);
  AssertEquals(-1936, Geometry.BaseWindowRect.X);
  AssertEquals(1080, Geometry.BaseWindowRect.Height);
  Input.Site := DOCK_RIGHT;
  Geometry := CalculateDockGeometry(Input, Items);
  AssertEquals(0, Geometry.X);
  AssertEquals(234, Geometry.Y);
  AssertEquals(-30, Geometry.BaseWindowRect.X);
  AssertEquals(46, Geometry.BaseWindowRect.Width);
  Input.Site := DOCK_TOP;
  Geometry := CalculateDockGeometry(Input, Items);
  AssertEquals(447, Geometry.X);
  AssertEquals(1, Geometry.Y);
  AssertEquals(104, Geometry.BaseWindowRect.Y);
  AssertEquals(57, Geometry.BaseWindowRect.Height);
end;

procedure TDockLayoutTests.EmptyDockKeepsNegativeDivisionRounding;
var Geometry: TDockGeometry;
begin
  SetLength(Items, 0);
  Geometry := CalculateDockGeometry(Input, Items);
  AssertEquals(457, Geometry.X);
  AssertEquals(48, Geometry.Width);
  Input.Site := DOCK_LEFT;
  Geometry := CalculateDockGeometry(Input, Items);
  AssertEquals(244, Geometry.Y);
  AssertEquals(57, Geometry.Height);
end;

procedure TDockLayoutTests.FullMonitorKeepsZoomExtent;
var Geometry: TDockGeometry;
begin
  Input.OccupyFullMonitor := true;
  Input.ZoomSizeDiff := 32;
  Geometry := CalculateDockGeometry(Input, Items);
  AssertEquals(0, Geometry.X);
  AssertEquals(1920, Geometry.Width);
  AssertEquals(81, Geometry.HeightZoomed);
  Input.Site := DOCK_LEFT;
  Geometry := CalculateDockGeometry(Input, Items);
  AssertEquals(0, Geometry.Y);
  AssertEquals(1080, Geometry.Height);
  AssertEquals(69, Geometry.WidthZoomed);
end;

procedure TDockLayoutTests.ItemLayoutKeepsFourEdgesAndSeparatorMargin;
const
  ExpectedX: array[0..3] of integer = (-1923, -1466, -29, -1466);
  ExpectedY: array[0..3] of integer = (364, 117, 364, 1171);
  SeparatorX: array[0..3] of integer = (-1927, -1429, -25, -1429);
  SeparatorY: array[0..3] of integer = (401, 113, 401, 1175);
var Actual: TDockLayoutItems; Site: integer;
begin
  Items[1].IsSeparator := true;
  for Site := DOCK_LEFT to DOCK_BOTTOM do
  begin
    Input.Site := Site;
    Actual := CalculateItemLayout(Input, Items);
    AssertEquals('Item X at edge ' + IntToStr(Site), ExpectedX[Site], Actual[0].X);
    AssertEquals('Item Y at edge ' + IntToStr(Site), ExpectedY[Site], Actual[0].Y);
    AssertEquals('Separator X', SeparatorX[Site], Actual[1].X);
    AssertEquals('Separator Y', SeparatorY[Site], Actual[1].Y);
    AssertEquals(32, Actual[2].Size);
  end;
end;

procedure TDockLayoutTests.FractionalZoomKeepsRoundingAtBubbleBoundary;
const Sizes: array[0..4] of integer = (42, 62, 64, 53, 33);
var Actual: TDockLayoutItems; I: integer;
begin
  SetLength(Items, 5);
  Input.ZoomSizeDiff := 32;
  Input.ZoomPosition := 2.25;
  Actual := CalculateItemLayout(Input, Items);
  for I := 0 to 4 do AssertEquals('Zoom size', Sizes[I], Actual[I].Size);
  AssertEquals(-1532, Actual[0].X);
  AssertEquals(-1486, Actual[1].X);
  AssertEquals(-1419, Actual[2].X);
  AssertEquals(-1350, Actual[3].X);
  AssertEquals('Legacy far-edge correction', -1291, Actual[4].X);
  AssertEquals(-1291.568406801659, Actual[4].ExactX, 0.000001);
  Input.Site := DOCK_LEFT;
  Actual := CalculateItemLayout(Input, Items);
  AssertEquals(298, Actual[0].Y);
  AssertEquals(344, Actual[1].Y);
  AssertEquals(411, Actual[2].Y);
  AssertEquals(480, Actual[3].Y);
  AssertEquals(539, Actual[4].Y);
end;

procedure TDockLayoutTests.LayoutDoesNotMutateInput;
var Actual: TDockLayoutItems;
begin
  Items[0].ExactX := 7.25;
  Items[0].ExactY := 8.5;
  Actual := CalculateItemLayout(Input, Items);
  Actual[0].X := 123;
  AssertEquals(-1466, Items[0].X);
  AssertEquals(7.25, Actual[0].ExactX, 0.000001);
  AssertEquals(8.5, Actual[0].ExactY, 0.000001);
end;

procedure TDockLayoutTests.BoundsIncludeZoomOnEachEdge;
var Geometry: TDockGeometry; Bounds: Windows.TRect;
begin
  Items[0].Y := 364;
  Items[2].Y := 438;
  Input.ZoomSizeDiff := 32;
  Input.Site := DOCK_LEFT;
  Geometry := CalculateDockGeometry(Input, Items);
  Bounds := DockBounds(Input, Geometry);
  AssertEquals(-1863, Bounds.Right);
  Input.Site := DOCK_RIGHT;
  Geometry := CalculateDockGeometry(Input, Items);
  Bounds := DockBounds(Input, Geometry);
  AssertEquals(-57, Bounds.Left);
  Input.Site := DOCK_TOP;
  Geometry := CalculateDockGeometry(Input, Items);
  Bounds := DockBounds(Input, Geometry);
  AssertEquals(177, Bounds.Bottom);
  Input.Site := DOCK_BOTTOM;
  Geometry := CalculateDockGeometry(Input, Items);
  Bounds := DockBounds(Input, Geometry);
  AssertEquals(1143, Bounds.Top);
end;

procedure TDockLayoutTests.PositionHitTestKeepsInclusiveDockBoundary;
var Geometry: TDockGeometry; Bounds: Windows.TRect;
begin
  Geometry := CalculateDockGeometry(Input, Items);
  Bounds := Types.Rect(0, 0, 0, 0);
  AssertEquals(55 / 37, ItemPositionFromPoint(Input, Geometry, 3, -1413, 1175, 0, Bounds), 0.000001);
  AssertEquals(55 / 37, ItemPositionFromPoint(Input, Geometry, 3, -1413, 1216, 0, Bounds), 0.000001);
  AssertTrue(ItemPositionFromPoint(Input, Geometry, 3, -1413, 1174, 0, Bounds) = NO_LAYOUT_ITEM);
  AssertTrue(ItemPositionFromPoint(Input, Geometry, 3, -1413, 1217, 0, Bounds) = NO_LAYOUT_ITEM);
  AssertEquals(-1.0, ItemPositionFromPoint(Input, Geometry, 3, -1505, 1176, 0, Bounds), 0.000001);
end;

procedure TDockLayoutTests.RectangleHitTestKeepsExclusiveRightAndBottom;
var Rects: array of Windows.TRect; Empty: Windows.TRect;
begin
  Empty := Types.Rect(0, 0, 10, 10);
  Rects := nil;
  AssertEquals(0, ItemRectIndexFromPoint(Rects, 9, 9, Empty));
  AssertEquals(NO_LAYOUT_ITEM, ItemRectIndexFromPoint(Rects, 10, 9, Empty));
  SetLength(Rects, 2);
  Rects[0] := Types.Rect(0, 0, 10, 10);
  Rects[1] := Types.Rect(10, 0, 20, 10);
  AssertEquals(1, ItemRectIndexFromPoint(Rects, 10, 9, Empty));
  AssertEquals(NO_LAYOUT_ITEM, ItemRectIndexFromPoint(Rects, 19, 10, Empty));
end;

initialization
  RegisterTest(TDockLayoutTests);
end.
