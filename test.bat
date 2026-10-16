@echo off
rem Compila (se serve) ed esegue BDETest sui dati di prova SINTETICI.
rem Lavora su una COPIA dei dati (%TEMP%\FDBDE_test), cosi' i test di scrittura
rem non toccano Demos\Data.
rem
rem Uso:   test.bat [Debug|Release]
rem
rem Servono: il BDE installato e, per rigenerare i dati di prova, Python 3.

setlocal
pushd "%~dp0"

set "CFG=%~1"
if "%CFG%"=="" set "CFG=Debug"

if not exist "Exe\Win32\BDETest.exe" (
  call "build.bat" %CFG% || goto :fail
)

if not exist "Demos\Data\SAMPLE.DBF" (
  where python >nul 2>nul && python "Tools\make_sample_dbf.py" "Demos\Data"
)
if not exist "Demos\Data\SAMPLE.DBF" (
  echo ERRORE: Demos\Data\SAMPLE.DBF mancante e Python non disponibile.
  goto :fail
)

set "WORK=%TEMP%\FDBDE_test"
if exist "%WORK%" rmdir /s /q "%WORK%"
mkdir "%WORK%"
copy /y "Demos\Data\SAMPLE.*" "%WORK%\" >nul

echo.
echo === BDETest su %WORK% ===
"Exe\Win32\BDETest.exe" "%WORK%" SAMPLE.DBF ID NAME NOTES 3 DUE < nul
set "RC=%ERRORLEVEL%"

rmdir /s /q "%WORK%"
popd
endlocal & exit /b %RC%

:fail
popd
endlocal
exit /b 1
