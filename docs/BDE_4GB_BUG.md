# "Insufficient disk space" (BDE 4 GB bug)

## Symptom

A query suddenly fails with an error like

```
Insufficient disk space ... _QSQL000.DBF ... Table does not exist
```

although the disk has plenty of free space. It often hits `TQuery` opens (the BDE writes the result of every
query to an answer table in the temp folder, which the driver keeps in `%TEMP%\FDBDE_<guid>`). It comes and goes:
it may disappear after a restart, or after some files are deleted, and then come back.

## Cause

It is a bug of the BDE itself (`idapi32.dll`), not of the driver. To check the free space the BDE calls the
ANSI API `GetDiskFreeSpaceA` and mishandles the result when the free space of the drive is close to a multiple of
4 GB. The condition depends only on the free space at that moment, which is why the error looks random. It is
the well-known "BDE 4 GB bug" (Quality Central report 7089).

## Check

`FreeSpaceInfo(Path)` of the unit below returns the real free space and the same value modulo 4 GB:

```pascal
ShowMessage(FreeSpaceInfo(TPath.GetTempPath));
```

If the second value is close to 0 or to 4 GB while the error appears, it is this bug.

## Fix

Add `Demos\FixBDE4GbBug.pas` to the program (it is only needed by programs that use the BDE, with or without this
driver) and put it **first** in the `uses` clause of the `.dpr`, before any unit that can load the BDE:

```pascal
program MyApp;

uses
  FixBDE4GbBug,   // must be the first one
  Vcl.Forms,
  ...
```

The unit redirects `kernel32!GetDiskFreeSpaceA` for the current process only: the replacement uses
`GetDiskFreeSpaceExA` and reports the free space in a form the BDE handles. It needs no DLL (only
`kernel32.dll`), changes nothing on disk and restores the original code when the program ends.

- Win32 only (the BDE is 32 bit only); the unit refuses to compile for other targets.
- It is a port for Delphi with Unicode strings of the 2004 unit by Reinaldo Roberto Yañez Arrey. The author's
  header and license are kept in the file.
- It patches the process, so it is not part of the driver and the driver does not need it. The decision to
  include it is up to the application.
- Verified: the error that reappeared in the tests on a table of 22,323 rows disappeared after adding the unit.
