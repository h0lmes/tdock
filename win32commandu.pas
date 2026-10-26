unit win32commandu;

{$mode delphi}

interface

uses Windows, dockcommandu;

type
  TWin32CommandAdapter = class
  private
    FWindow, FLastWindow: HWND;
  public
    constructor Create(Window: HWND);
    function Execute(Action: TApplicationAction; Parameters: string): Boolean;
  end;

implementation

uses SysUtils, Math, ShellAPI, MMSystem, ComObj, toolu, processhlp, mixeru, loggeru;

constructor TWin32CommandAdapter.Create(Window: HWND);
begin inherited Create; FWindow := Window; end;

function TWin32CommandAdapter.Execute(Action: TApplicationAction; Parameters: string): Boolean;
var Params, Str1, Str2: string; I1, I2, I3, I4: Integer;
  Lpsz1, Lpsz2: PChar; Pt: Windows.TPoint;
begin
  Params := Parameters;
  Result := True;
  case Action of
    aaSetVolume: begin
    if trystrtoint(Trim(params), i1) then
      TMixer.SetVolumePercent(i1);
  end;
    aaLogoff: ProcessHelper.Shutdown(ifthen(params = 'force', 4, 0));
    aaShutdown: ProcessHelper.Shutdown(ifthen(params = 'force', 5, 1));
    aaReboot: ProcessHelper.Shutdown(ifthen(params = 'force', 6, 2));
    aaSuspend: ProcessHelper.SetSuspendState(false);
    aaHibernate: ProcessHelper.SetSuspendState(true);
    aaKill: ProcessHelper.Kill(params);
    aaDisplayOff: sendmessage(FWindow, WM_SYSCOMMAND, SC_MONITORPOWER, 2);
    aaEmptyBin: SHEmptyRecycleBin(FWindow, nil, 0);
    aaPlay: sndPlaySound(pchar(UnzipPath(params)), SND_ASYNC or SND_FILENAME);
    aaSetClipboard: SetClipboard(params);
    aaGuid: SetClipboard(CreateClassId);
    aaLogWindow: begin
    if trystrtoint(Trim(params), i1) then
      LogWindow(THandle(i1));
  end;
    aaSetDisplayMode: begin
    if not trystrtoint(Trim(fetch(params, ',', true)), i1) then i1 := 1024;
    if not trystrtoint(Trim(fetch(params, ',', true)), i2) then i2 := 768;
    if not trystrtoint(Trim(fetch(params, ',', true)), i3) then i3 := 32;
    if not trystrtoint(Trim(fetch(params, ',', true)), i4) then i4 := 60;
    setdisplaymode(i1, i2, i3, i4);
  end;
    aaBroadcastMessage: begin
    if not trystrtoint(Trim(fetch(params, ',', true)), i1) then i1 := 0;
    if not trystrtoint(Trim(fetch(params, ',', true)), i2) then i2 := 0;
    if not trystrtoint(Trim(fetch(params, ',', true)), i3) then i3 := 0;
    bsm(i1, i2, i3);
  end;
    aaWindowFromPoint: begin
    GetCursorPos(pt);
    FLastWindow := WindowFromPoint(pt);
    SetClipboard(inttohex(FLastWindow, 8));
  end;
    aaFindWindow: begin
    str1 := Trim(fetch(params, ',', true));
    str2 := Trim(fetch(params, ',', true));
    if str1 = '' then lpsz1 := nil else lpsz1 := pchar(str1);
    if str2 = '' then lpsz2 := nil else lpsz2 := pchar(str2);
    FLastWindow := findwindow(lpsz1, lpsz2);
    SetClipboard(inttohex(FLastWindow, 8));
  end;
    aaFindWindowEx: begin
    str1 := Trim(fetch(params, ',', true));
    str2 := Trim(fetch(params, ',', true));
    if str1 = '' then lpsz1 := nil else lpsz1 := pchar(str1);
    if str2 = '' then lpsz2 := nil else lpsz2 := pchar(str2);
    FLastWindow := findwindowex(FLastWindow, 0, lpsz1, lpsz2);
    SetClipboard(inttohex(FLastWindow, 8));
  end;
    aaShowWindow: showwindow(THandle(FLastWindow), strtoint(params));
    aaSendMessage: begin
    if not trystrtoint(Trim(fetch(params, ',', true)), i2) then i2 := 0;
    if not trystrtoint(Trim(fetch(params, ',', true)), i3) then i3 := 0;
    if not trystrtoint(Trim(fetch(params, ',', true)), i4) then i4 := 0;
    sendmessage(THandle(FLastWindow), uint(i2), i3, i4);
  end;
    else Result := False;
  end;
end;

end.
