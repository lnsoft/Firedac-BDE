@echo off
rem Registra (o rimuove) il package design-time FDBDEDesign.bpl nell'IDE di Delphi.
rem Chiudi RAD Studio prima di eseguirlo. Build prima con build.bat.
rem
rem Uso:   install-ide.bat            registra il package
rem        install-ide.bat remove     rimuove la registrazione

setlocal
pushd "%~dp0"

call "Tools\delphi-env.bat" || goto :fail

set "BPL=%BDSCOMMONDIR%\Bpl\FDBDEDesign.bpl"
set "KEY=HKCU\Software\Embarcadero\BDS\%BDSVER%\Known Packages"

if /i "%~1"=="remove" (
  reg delete "%KEY%" /v "%BPL%" /f
  echo Package rimosso dall'IDE.
  goto :end
)

if not exist "%BPL%" (
  echo ERRORE: %BPL% non trovato. Esegui prima build.bat.
  goto :fail
)

reg add "%KEY%" /v "%BPL%" /d "FireDAC BDE driver (design-time)" /f
echo Package registrato. Riavvia RAD Studio.

:end
popd
endlocal
exit /b 0

:fail
popd
endlocal
exit /b 1
