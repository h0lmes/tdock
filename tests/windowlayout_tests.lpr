program windowlayout_tests;

{$mode delphi}

uses Windows, SysUtils, simpletestrunner, windowlayouttests;

var Runner: TTestRunner; Desktop, OriginalDesktop: HDESK;
  Id: TGUID; DesktopName: UnicodeString;
begin
  // Refuse to run if Windows cannot provide an invisible test desktop.
  if CreateGUID(Id) <> S_OK then raise Exception.Create('Cannot create a test desktop identifier');
  DesktopName := 'TDockWindowLayoutSuite' + UnicodeString(GUIDToString(Id));
  OriginalDesktop := GetThreadDesktop(GetCurrentThreadId);
  Desktop := CreateDesktopW(PWideChar(DesktopName), nil, nil, 0, GENERIC_ALL, nil);
  if Desktop = 0 then RaiseLastOSError;
  try
    if not SetThreadDesktop(Desktop) then RaiseLastOSError;
    Runner := TTestRunner.Create(nil);
    try
      Runner.Initialize;
      Runner.Run;
    finally
      Runner.Free;
    end;
  finally
    SetThreadDesktop(OriginalDesktop);
    CloseDesktop(Desktop);
  end;
end.
