program drag_test;
{$mode delphi}
uses Interfaces, Forms, ActiveX, Windows, SysUtils, dragformu;
var Main: TDragTestForm;
begin
  OleInitialize(nil);
  try
    Application.Initialize; Application.Scaled := False; Application.Title := 'tdock Drag Test';
    Application.CreateForm(TDragTestForm, Main);
    Main.Log.Add('Main form constructed');
    Main.Show;
    Windows.ShowWindow(Main.Handle, SW_SHOWNORMAL);
    Main.Log.Add('Window handle=' + IntToStr(Main.Handle) + ' visible=' + BoolToStr(IsWindowVisible(Main.Handle), True));
    Main.Log.Add('Main form shown; event loop starting');
    Application.Run;
  finally OleUninitialize; end;
end.
