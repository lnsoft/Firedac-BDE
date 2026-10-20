//////////////////////////////////////////////////////////////////////////////////////
//
//    ----- BDE 4GB PATCH -----
//  Version 1.02 (adapted for Unicode Delphi, 32 bit)
//
//
//
//  FUNCTION
//
//    This unit is a patch for the famous 4Gb BDE Bug.  It is build to fix the
//    'Insufficient disk space'-error which can occur while using BDE when
//    the disk free space is near to a multiple of 4Gb.  For more information
//    please see BDE report# 7089 on Quality Central.
//
//  TECH DETAILS
//
//    The reason for the error in BDE is aparently a bug in idapi32.dll while
//    computing free disk space. Idapi32.dll  is using  the api function called
//    GetDiskFreeSpaceA exported by kernel32.dll.
//    The solution is to 'patch' GetDiskFreeSpaceA in kernel32.dll for the current
//    process, every call to this function is redirected to a new routine
//    (NewGetDiskFreeSpaceA).
//
//  USAGE
//
//    Just include this unit in your at the top of the uses clause in your project.
//
//
//  2004-02-26
//  (c) Reinaldo Roberto Yanez Arrey   (n with tilde in the original header)
//  Buenos Aires, Argentina
//  ryaayr@yahoo.com, ryaayr@arnet.com.ar
//  Any feedback is welcome!
//
//  Disclaimer:
//    The code and text in this unit are not associated with Borland. This unit is
//    provided "as is"! The author takes no responsibility for use, or misuse, of
//    this unit. Usage of this code is at your own risk.
//  License:
//    You are free to use this unit in any way, but beware that BDE is an
//    official Borland product, and therefore bound by the terms and conditions of
//    the Borland product license.
//
//////////////////////////////////////////////////////////////////////////////////////
// Thanks to:
//          Leonardo Mato & Manuel E. Parma
//                   for their encouragement to produce good code.
//////////////////////////////////////////////////////////////////////////////////////
//
// History: 2026-10-20    Version 1.02  Adapted for Delphi with Unicode strings (Firedac-BDE):
//                        - idapi32.dll calls the ANSI function, so the replacement takes a
//                          PAnsiChar path and calls GetDiskFreeSpaceExA (declared here: the
//                          Winapi.Windows declaration differs between Delphi versions);
//                        - UInt64 instead of ULARGE_INTEGER;
//                        - PAGE_EXECUTE_READWRITE while the 5 bytes are written;
//                        - range and overflow checks off, Win32 only;
//                        - FreeSpaceInfo for diagnostics.
//          2004-03-05    Version 1.01  (Fixes a problem on finalization if using packages)
//          2004-02-26    Version 1.00  (Created)
//
//////////////////////////////////////////////////////////////////////////////////////

unit FixBDE4GbBug;

{$R-,Q-}

{$IFNDEF CPU386}
  {$MESSAGE ERROR 'FixBDE4GbBug: the BDE is 32 bit only (Win32 target)'}
{$ENDIF}

interface

// Applies the patch (only once). It is called by the initialization section.
procedure PatchBDE;

// Restores the original bytes (called by the finalization section).
procedure UnpatchBDE;

// Free space of the drive of APath, as text: real value and value modulo 4 GB, which is
// what the BDE would see with the bug.
function FreeSpaceInfo(const APath: String): String;

implementation

uses
  Winapi.Windows, System.SysUtils;

type
  TRYPatch = record
    Patched: Boolean;
    OrgAddr: Pointer;
    OrgBytes: array[0..4] of Byte;
  end;

function GetDiskFreeSpaceExAnsi(lpDirectoryName: PAnsiChar;
  lpFreeBytesAvailableToCaller, lpTotalNumberOfBytes,
  lpTotalNumberOfFreeBytes: PUInt64): BOOL; stdcall;
  external 'kernel32.dll' name 'GetDiskFreeSpaceExA';

// Este metodo nunca lo vi escrito correctamente para contemplar los casos de
// usar packages o no.
// Si se utilizan packages HAY que preguntar por el $25FF y patchear el puntero a
// puntero a puntero
// Sino, no se patchea absolutamente nada !!!!
// Ry@2003.10.31
function RedirectByRY(OldPtr, NewPtr: Pointer): TRYPatch;
var
  OldProtect, Protect: DWORD;
begin
  FillChar(Result, SizeOf(Result), 0);
  if PWord(OldPtr)^ = $25FF then
    // JMP DWORD PTR [XXXXXXX] (stub of import table): follow it to the real function
    OldPtr := PPointer(PPointer(NativeUInt(OldPtr) + 2)^)^;
  if not VirtualProtect(OldPtr, 5, PAGE_EXECUTE_READWRITE, @OldProtect) then
    Exit;
  Result.OrgAddr := OldPtr;
  Move(OldPtr^, Result.OrgBytes[0], 5);
  PByte(OldPtr)^ := $E9;                                      // JMP rel32
  PInteger(NativeUInt(OldPtr) + 1)^ :=
    Integer(NativeUInt(NewPtr) - NativeUInt(OldPtr) - 5);
  VirtualProtect(OldPtr, 5, OldProtect, @Protect);
  FlushInstructionCache(GetCurrentProcess, OldPtr, 5);
  Result.Patched := True;
end;

procedure RestorePatch(const APatch: TRYPatch);
var
  OldProtect, Protect: DWORD;
begin
  if VirtualProtect(APatch.OrgAddr, 5, PAGE_EXECUTE_READWRITE, @OldProtect) then begin
    Move(APatch.OrgBytes[0], APatch.OrgAddr^, 5);
    VirtualProtect(APatch.OrgAddr, 5, OldProtect, @Protect);
    FlushInstructionCache(GetCurrentProcess, APatch.OrgAddr, 5);
  end;
end;

// Replacement of kernel32!GetDiskFreeSpaceA (the BDE uses the ANSI version).
// It returns 1 sector per cluster and 1 byte per sector, so "free clusters" is the
// number of free bytes (limited to 4 GB - 1, which the BDE can handle).
function NewGetDiskFreeSpaceA(lpPath: PAnsiChar; lpSectorsPerCluster,
  lpBytesPerSector, lpNoFreeClusters, lpTotalNoClusters: PDWORD): BOOL; stdcall;
var
  FreeToCaller, TotalBytes, TotalFree: UInt64;
begin
  Result := GetDiskFreeSpaceExAnsi(lpPath, @FreeToCaller, @TotalBytes, @TotalFree);
  if not Result then
    Exit;
  if lpSectorsPerCluster <> nil then
    lpSectorsPerCluster^ := 1;
  if lpBytesPerSector <> nil then
    lpBytesPerSector^ := 1;
  if lpNoFreeClusters <> nil then
    if FreeToCaller > $FFFFFFFF then
      lpNoFreeClusters^ := $FFFFFFFF
    else
      lpNoFreeClusters^ := DWORD(FreeToCaller);
  if lpTotalNoClusters <> nil then
    lpTotalNoClusters^ := $FFFFFFFF;
end;

var
  GPatch: TRYPatch;

procedure PatchBDE;
var
  K32: HMODULE;
  ProcAddr: Pointer;
begin
  if GPatch.Patched then
    Exit;
  K32 := GetModuleHandle('kernel32.dll');     // always loaded: no LoadLibrary / FreeLibrary
  if K32 = 0 then
    Exit;
  ProcAddr := GetProcAddress(K32, 'GetDiskFreeSpaceA');
  if ProcAddr = nil then
    Exit;
  GPatch := RedirectByRY(ProcAddr, @NewGetDiskFreeSpaceA);
end;

procedure UnpatchBDE;
begin
  {Leave everything as before, just in case...}
  if GPatch.Patched then begin
    RestorePatch(GPatch);
    GPatch.Patched := False;
  end;
end;

function FreeSpaceInfo(const APath: String): String;
var
  Free, Total, TotalFree: UInt64;
  sPath: AnsiString;
begin
  sPath := AnsiString(APath);
  if GetDiskFreeSpaceExAnsi(PAnsiChar(sPath), @Free, @Total, @TotalFree) then
    Result := Format('%.1f MB free, modulo 4 GB = %.1f MB (what the BDE sees with the bug)',
      [Free / 1048576, (Free mod 4294967296) / 1048576])
  else
    Result := 'not available';
end;

initialization
  PatchBDE;

finalization
  UnpatchBDE;

end.
