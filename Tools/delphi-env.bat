@echo off
rem Imposta l'ambiente del compilatore Delphi (rsvars.bat).
rem Cerca, nell'ordine: variabile BDS gia' impostata (RAD Studio Command Prompt),
rem poi Studio\%BDSVER% in Program Files (x86) e Program Files.
rem Delphi 13 = 37.0. Per un'altra versione/percorso: set BDSVER=...  oppure
rem set RSVARS=percorso\completo\rsvars.bat   prima di lanciare gli script.

if not defined BDSVER set "BDSVER=37.0"

if not defined RSVARS if defined BDS if exist "%BDS%\bin\rsvars.bat" set "RSVARS=%BDS%\bin\rsvars.bat"
if not defined RSVARS if exist "%ProgramFiles(x86)%\Embarcadero\Studio\%BDSVER%\bin\rsvars.bat" set "RSVARS=%ProgramFiles(x86)%\Embarcadero\Studio\%BDSVER%\bin\rsvars.bat"
if not defined RSVARS if exist "%ProgramFiles%\Embarcadero\Studio\%BDSVER%\bin\rsvars.bat" set "RSVARS=%ProgramFiles%\Embarcadero\Studio\%BDSVER%\bin\rsvars.bat"

if not defined RSVARS (
  echo ERRORE: rsvars.bat non trovato. Imposta BDSVER oppure RSVARS, ad esempio:
  echo   set RSVARS=D:\Embarcadero\Studio\37.0\bin\rsvars.bat
  exit /b 1
)

call "%RSVARS%"
if errorlevel 1 exit /b 1
exit /b 0
