unit frmDebugU;

{$mode delphi}
interface
uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, loggeru;

type
  TfrmDebug = class(TForm)
    memo: TMemo;
    procedure FormShow(Sender: TObject);
  private
  public
    class procedure Open;
  end; 

var
  frmDebug: TfrmDebug;

implementation
uses frmmainu, toolu;
{$R *.lfm}
//------------------------------------------------------------------------------
class procedure TfrmDebug.Open;
begin
  if not assigned(frmDebug) then Application.CreateForm(self, frmDebug);
  frmDebug.ShowModal;
  frmDebug.Free;
  frmDebug := nil;
end;
//------------------------------------------------------------------------------
procedure TfrmDebug.FormShow(Sender: TObject);
var
  log: TStrings;
begin
  memo.clear;
  memo.lines.add('<< Fullscreen windows >>');
  memo.lines.add('');
  memo.lines.add(frmmain.ListFullScreenApps);
  memo.lines.add('<< Log >>');
  memo.lines.add('');
  log := TStringList.Create;
  try
    log.LoadFromFile(loggeru.GetLogFileName);
    memo.lines.AddText(AnsiToUTF8(log.Text));
  except
    on e: Exception do memo.lines.add('>>> ' + e.message);
  end;
  log.free;
end;
//------------------------------------------------------------------------------
end.

