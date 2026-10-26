unit dragsamplesu;
{$mode delphi}
{$codepage utf8}

interface

uses Windows, Classes, SysUtils, Contnrs, ActiveX, ShlObj, Graphics, dragdatau;

type
  TDragSample = class
    Group, Name, Payload, Expected: string;
    Profile: TDragProfile;
  end;

procedure CreateSamples(const Root: UnicodeString; Samples: TObjectList);
procedure LoadInstalledApps(Samples: TObjectList);

implementation

function ShellName(ID: PItemIDList; Kind: DWORD; out Name: PWideChar): HRESULT; stdcall;
  external 'shell32.dll' name 'SHGetNameFromIDList';

procedure Add(Samples: TObjectList; const Group, Name: string;
  Profile: TDragProfile; const Payload, Expected: string);
var Sample: TDragSample;
begin
  Sample := TDragSample.Create;
  Sample.Group := Group; Sample.Name := Name; Sample.Profile := Profile;
  Sample.Payload := Payload; Sample.Expected := Expected;
  Samples.Add(Sample);
end;

procedure MakeLink(const Filename, Target, Arguments: UnicodeString);
var Link: IShellLinkW; Persist: IPersistFile;
begin
  if GetFileAttributesW(PWideChar(Filename)) <> INVALID_FILE_ATTRIBUTES then Exit;
  CheckHR(CoCreateInstance(CLSID_ShellLink, nil, CLSCTX_INPROC_SERVER, IID_IShellLinkW, Link), 'Create shortcut');
  CheckHR(Link.SetPath(PWideChar(Target)), 'Set shortcut target');
  if Arguments <> '' then CheckHR(Link.SetArguments(PWideChar(Arguments)), 'Set shortcut arguments');
  Persist := Link as IPersistFile;
  CheckHR(Persist.Save(PWideChar(Filename), True), 'Save shortcut');
end;

procedure MakeImages(const Root: UnicodeString);
var Image: TPortableNetworkGraphic; Icon: TIcon; Name: UnicodeString;
begin
  Name := Root + '\sample.png';
  if GetFileAttributesW(PWideChar(Name)) = INVALID_FILE_ATTRIBUTES then
  begin
    Image := TPortableNetworkGraphic.Create;
    try
      Image.SetSize(48, 48); Image.Canvas.Brush.Color := $00C88A26;
      Image.Canvas.FillRect(0, 0, 48, 48);
      Image.Canvas.Brush.Color := clWhite; Image.Canvas.Ellipse(12, 12, 36, 36);
      Image.SaveToFile(UTF8Encode(Name));
    finally Image.Free; end;
  end;
  Name := Root + '\sample.ico';
  if GetFileAttributesW(PWideChar(Name)) = INVALID_FILE_ATTRIBUTES then
  begin
    Icon := TIcon.Create;
    try
      Icon.Handle := CopyIcon(Windows.LoadIcon(0, IDI_APPLICATION));
      Icon.SaveToFile(UTF8Encode(Name));
    finally Icon.Free; end;
  end;
end;

procedure CreateSamples(const Root: UnicodeString; Samples: TObjectList);
var Folder, SystemFolder, WindowsFolder: UnicodeString; Buffer: array[0..32767] of WideChar;
  UnicodeFile, PlainFile: string; I: Integer;
const
  Extensions: array[0..3] of string = ('.bat', '.cmd', '.ps1', '.py');
  ScriptBodies: array[0..3] of RawByteString = (
    '@echo off'#13#10'echo tdock drag-test script'#13#10'pause'#13#10,
    '@echo off'#13#10'echo tdock drag-test script'#13#10'pause'#13#10,
    'Write-Host "tdock drag-test script"'#13#10,
    'print("tdock drag-test script")'#13#10);
begin
  Folder := Root + '\samples';
  MakeDirectory(Folder); MakeDirectory(Folder + '\Sample Folder');
  GetSystemDirectoryW(@Buffer, Length(Buffer)); SystemFolder := PWideChar(@Buffer);
  GetWindowsDirectoryW(@Buffer, Length(Buffer)); WindowsFolder := PWideChar(@Buffer);
  WriteNewFile(Folder + '\sample.txt', 'tdock drag-test document'#13#10);
  WriteNewFile(Folder + '\文档 with spaces-Ж.txt', RawByteString(UTF8Encode('Unicode filename sample: 文档 Ж')));
  WriteNewFile(Folder + '\one;two.txt', 'Semicolon path sample'#13#10);
  WriteNewFile(Folder + '\sample.tdock-unknown', 'No file association is required for this fixture.'#13#10);
  for I := 0 to High(Extensions) do WriteNewFile(Folder + '\sample' + UTF8Decode(Extensions[I]), ScriptBodies[I]);
  WriteNewFile(Folder + '\sample.js', 'WScript.Echo("tdock drag-test script");'#13#10);
  WriteNewFile(Folder + '\sample.url', '[InternetShortcut]'#13#10'URL=https://example.com/'#13#10);
  WriteNewFile(Folder + '\sample.website', '[InternetShortcut]'#13#10'URL=https://example.com/'#13#10);
  WriteNewFile(Folder + '\sample.rdp', 'full address:s:localhost'#13#10'prompt for credentials:i:1'#13#10);
  MakeLink(Folder + '\Notepad.lnk', SystemFolder + '\notepad.exe', '');
  MakeLink(Folder + '\Notepad with document.lnk', SystemFolder + '\notepad.exe', '"' + Folder + '\sample.txt"');
  MakeImages(Folder);
  PlainFile := UTF8Encode(Folder + '\sample.txt');
  UnicodeFile := UTF8Encode(Folder + '\文档 with spaces-Ж.txt');
  Add(Samples, 'Format checks', 'URL only: Unicode', dpURLW, 'https://example.com/', 'One URL launcher. Open it to check browser activation.');
  Add(Samples, 'Format checks', 'URL only: ANSI', dpURLA, 'https://example.com/', 'One URL launcher. The source offers no filename alternative.');
  Add(Samples, 'Format checks', 'Custom URI only', dpURLW, 'ms-settings:display', 'One launcher. Opening it should show Display settings.');
  Add(Samples, 'Format checks', 'Text: Unicode path with spaces', dpTextW, '"' + UnicodeFile + '"', 'One launcher for the complete quoted path.');
  Add(Samples, 'Format checks', 'Text: multiple targets', dpTextW, PlainFile + LineEnding + 'https://example.com/', 'Two launchers. Each line supplies one target.');
  Add(Samples, 'Format checks', 'Text: ANSI CP1252 locale', dpText1252, 'https://example.com/café', 'CF_TEXT uses CP1252. CF_LOCALE identifies its encoding without changing Windows settings.');
  Add(Samples, 'Format checks', 'Text: command rejection', dpTextW, '"' + UTF8Encode(SystemFolder + '\notepad.exe') + '" --flag', 'The current text importer should reject command arguments.');
  Add(Samples, 'Format checks', 'FileNameW only', dpFilenameWGlobal, UnicodeFile, 'One Unicode file launcher. No HDROP or Shell-ID alternative is offered.');
  Add(Samples, 'Format checks', 'FileName only: ANSI', dpFilenameAGlobal, PlainFile, 'One file launcher through the legacy filename format.');
  Add(Samples, 'Format checks', 'FileNameW: temporary file medium', dpFilenameWFile, UnicodeFile, 'tdock should save a persistent copy before medium cleanup.');
  Add(Samples, 'Format checks', 'Virtual text file: IStream', dpVirtualWStream, 'virtual document-Ж.txt', 'tdock should save the contents in ImportedFiles. Test opening after restarting tdock.');
  Add(Samples, 'Format checks', 'Virtual files: duplicate names', dpVirtualWGlobal, 'same.txt' + LineEnding + 'same.txt' + LineEnding + 'SAME.TXT', 'Three distinct files. Contents include their item numbers.');
  Add(Samples, 'Format checks', 'Virtual compound storage', dpVirtualWStorage, 'sample.stg', 'One compound file with a Contents stream. Windows may have no default viewer.');
  Add(Samples, 'Format checks', 'Mixed formats: priority check', dpMixed, PlainFile, 'HDROP should win despite its enumeration position. Expect one file launcher.');
  Add(Samples, 'Format checks', 'Unsupported format', dpUnsupported, 'unsupported', 'The importer should report failure and create no launcher.');
  Add(Samples, 'Files and documents', 'EXE executable', dpNativeShell, UTF8Encode(SystemFolder + '\notepad.exe'), 'A real Windows executable. Opening the launcher starts Notepad.');
  Add(Samples, 'Files and documents', 'COM executable', dpNativeShell, UTF8Encode(SystemFolder + '\more.com'), 'A real Windows COM executable. Its console behavior depends on its arguments.');
  Add(Samples, 'Files and documents', 'Folder', dpNativeShell, UTF8Encode(Folder + '\Sample Folder'), 'A folder launcher. Opening it should show the folder.');
  Add(Samples, 'Files and documents', 'Drive', dpNativeShell, UTF8Encode(ExtractFileDrive(WindowsFolder) + '\'), 'A drive launcher.');
  Add(Samples, 'Files and documents', 'Document', dpNativeShell, PlainFile, 'A document launcher. Opening uses its registered handler.');
  Add(Samples, 'Files and documents', 'Unicode document', dpNativeShell, UnicodeFile, 'The filename should remain complete through saving and restart.');
  Add(Samples, 'Files and documents', 'Document without known association', dpNativeShell, UTF8Encode(Folder + '\sample.tdock-unknown'), 'Import should work. Windows may request a handler when opening.');
  Add(Samples, 'Files and documents', 'Multiple files', dpHDropW, PlainFile + LineEnding + UnicodeFile, 'Two file launchers from one HDROP selection.');
  Add(Samples, 'Files and documents', 'Shortcut (.lnk)', dpNativeShell, UTF8Encode(Folder + '\Notepad.lnk'), 'Import the real shortcut. Opening should start Notepad.');
  Add(Samples, 'Files and documents', 'Shortcut with arguments', dpNativeShell, UTF8Encode(Folder + '\Notepad with document.lnk'), 'Opening should start Notepad with the sample document.');
  Add(Samples, 'Files and documents', 'Internet shortcut (.url)', dpNativeShell, UTF8Encode(Folder + '\sample.url'), 'Import the shortcut file. Opening should use the browser.');
  Add(Samples, 'Files and documents', 'Website shortcut (.website)', dpNativeShell, UTF8Encode(Folder + '\sample.website'), 'InternetShortcut payload. Opening depends on the registered .website handler.');
  for I := 0 to High(Extensions) do
    Add(Samples, 'Files and documents', 'Script (' + Extensions[I] + ')', dpNativeShell,
      UTF8Encode(Folder + '\sample') + Extensions[I], 'Opening follows the registered handler. Import does not select a script host.');
  Add(Samples, 'Files and documents', 'Script (.js)', dpNativeShell, UTF8Encode(Folder + '\sample.js'), 'Opening follows the registered JavaScript handler.');
  Add(Samples, 'Files and documents', 'Remote Desktop file (.rdp)', dpNativeShell, UTF8Encode(Folder + '\sample.rdp'), 'A localhost RDP configuration. Opening invokes its registered handler.');
  Add(Samples, 'Files and documents', 'Management console (.msc)', dpNativeShell, UTF8Encode(SystemFolder + '\services.msc'), 'A real Services console file.');
  Add(Samples, 'Files and documents', 'Control Panel file (.cpl)', dpNativeShell, UTF8Encode(SystemFolder + '\desk.cpl'), 'A real Control Panel file. Windows controls its activation.');
  Add(Samples, 'Files and documents', 'DLL file', dpNativeShell, UTF8Encode(SystemFolder + '\version.dll'), 'A real DLL. A DLL has no general standalone open operation.');
  Add(Samples, 'Shell objects', 'This PC', dpShellID, '::{20D04FE0-3AEA-1069-A2D8-08002B30309D}', 'A Shell-ID-only drop. Opening should show This PC.');
  Add(Samples, 'Shell objects', 'Recycle Bin', dpShellID, '::{645FF040-5081-101B-9F08-00AA002F954E}', 'A Shell-ID-only drop. Opening should show Recycle Bin.');
  Add(Samples, 'Shell objects', 'Control Panel', dpShellID, '::{26EE0668-A00A-44D7-9371-BEB064C98683}', 'A real Shell namespace object.');
  Add(Samples, 'Shell objects', 'Network', dpShellID, '::{F02C1A0D-BE21-4350-88B0-7367FC96EF3C}', 'A real Shell namespace object. Available content depends on Windows configuration.');
  Add(Samples, 'Shell objects', 'AppsFolder', dpShellID, 'shell:AppsFolder', 'A Shell folder containing installed application entries.');
  Add(Samples, 'Shell objects', 'Desktop', dpShellID, 'shell:Desktop', 'The Desktop Shell root.');
  Add(Samples, 'Shell objects', 'Downloads', dpShellID, 'shell:Downloads', 'A known-folder Shell alias.');
  Add(Samples, 'Shell objects', 'Printers', dpShellID, 'shell:PrintersFolder', 'A Shell folder. Add a specific installed printer through the editable target field.');
  Add(Samples, 'Shell objects', 'Devices', dpShellID, '::{A8A91A66-3A7D-4424-8D24-04E180695C7A}', 'Devices and Printers. Installed providers control their child objects.');
  Add(Samples, 'Shell objects', 'Task Scheduler console', dpNativeShell, UTF8Encode(SystemFolder + '\taskschd.msc'), 'A management console, rather than an individual scheduled task identifier.');
  Add(Samples, 'Custom targets', 'Custom file or Shell parsing name', dpNativeShell, PlainFile, 'Edit the target or use Browse. Native Shell data comes from the selected object.');
  Add(Samples, 'Custom targets', 'UNC path', dpHDropW, '\\server\share\sample.txt', 'Replace this placeholder with an accessible network file or folder.');
  Add(Samples, 'Custom targets', 'Installer (.msi)', dpNativeShell, '', 'Browse to a real installer. No installer is generated or run by this app.');
  Add(Samples, 'Custom targets', 'Application reference (.appref-ms)', dpNativeShell, '', 'Browse to a real installed application reference.');
  Add(Samples, 'Custom targets', 'Browser or PWA shortcut', dpNativeShell, '', 'Browse to a real browser or PWA shortcut.');
  Add(Samples, 'Custom targets', 'Shell extension object', dpNativeShell, '', 'Enter a parsing name supplied by the installed provider.');
  Add(Samples, 'Custom targets', 'Application identity as text', dpTextW, '', 'Enter a bare application ID. Plain-text identity support remains outside the approved text rules.');
  Add(Samples, 'Boundary checks', 'Semicolon path', dpHDropW, UTF8Encode(Folder + '\one;two.txt'), 'Import and launch diagnostics for the separate semicolon issue, WO-08.');
  Add(Samples, 'Boundary checks', 'Semicolon URL', dpURLW, 'https://example.com/one;two', 'The new URL reader should reject this target while WO-08 remains open.');
  Add(Samples, 'Boundary checks', 'Long URL', dpURLW, 'https://example.com/' + StringOfChar('a', 1100), 'The new importer should reject targets beyond 1023 UTF-16 units.');
  Add(Samples, 'Images', 'PNG image', dpNativeShell, UTF8Encode(Folder + '\sample.png'), 'Empty space adds a launcher. Existing icons may use the image as their artwork.');
  Add(Samples, 'Images', 'ICO image', dpNativeShell, UTF8Encode(Folder + '\sample.ico'), 'Empty space adds a launcher. Existing icons may use the image as their artwork.');
  // The editable target field covers provider-specific objects and objects absent from this host.
end;

procedure LoadInstalledApps(Samples: TObjectList);
var Root, Child, Absolute: PItemIDList; Desktop, Folder: IShellFolder; Enumerator: IEnumIDList;
  Count: ULONG; Caption, Parsing: PWideChar; Friendly, Target: string; HR: HRESULT;
begin
  Root := nil;
  CheckHR(SHParseDisplayName('shell:AppsFolder', nil, Root, 0, nil), 'Parse AppsFolder');
  try
    CheckHR(SHGetDesktopFolder(Desktop), 'Get Desktop');
    CheckHR(Desktop.BindToObject(Root, nil, IID_IShellFolder, Folder), 'Bind AppsFolder');
    HR := Folder.EnumObjects(0, SHCONTF_NONFOLDERS or SHCONTF_FOLDERS, Enumerator);
    if (HR = S_FALSE) or (LongWord(HR) = $80070490) then Exit;
    CheckHR(HR, 'Enumerate installed applications');
    if Enumerator = nil then Exit;
    while Enumerator.Next(1, Child, Count) = S_OK do
    try
      Absolute := ILCombine(Root, Child);
      if Absolute = nil then Continue;
      try
        Caption := nil; Parsing := nil;
        try
          if ShellName(Absolute, $80028000, Parsing) <> S_OK then Continue;
          Target := UTF8Encode(UnicodeString(Parsing));
          if ShellName(Absolute, 0, Caption) = S_OK then Friendly := UTF8Encode(UnicodeString(Caption))
          else Friendly := Target;
          Add(Samples, 'Installed applications', Friendly, dpShellID, Target,
            'A real AppsFolder child. Test import, metadata, opening, and persistence.');
        finally CoTaskMemFree(Caption); CoTaskMemFree(Parsing); end;
      finally CoTaskMemFree(Absolute); end;
    finally CoTaskMemFree(Child); end;
  finally CoTaskMemFree(Root); end;
end;

end.
