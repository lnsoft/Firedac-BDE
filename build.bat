@echo off
rem Compila FDBDERun, FDBDEDesign e BDETest (Win32) da riga di comando.
rem
rem Uso:   build.bat [Debug|Release]        (default: Debug)
rem
rem Risultato:
rem   Dcu\13_2\Win32\<Config>\          unit compilate (tutti i progetti)
rem   Exe\Win32\BDETest.exe             programma di test
rem   Exe\Win32\LocalSQLTest.exe        esperimento Local SQL sopra il driver
rem   FDBDERun.bpl / FDBDEDesign.bpl    nella cartella Bpl di RAD Studio
rem                                     (%BDSCOMMONDIR%\Bpl)
rem
rem Il tag della versione (13_2) si cambia con:  set DELPHI_TAG=12_3
rem Le cartelle di output sono passate a msbuild come percorsi assoluti: non
rem dipendono da $(Config)/$(Platform) dei .dproj.

setlocal
pushd "%~dp0"

set "CFG=%~1"
if "%CFG%"=="" set "CFG=Debug"
if not defined DELPHI_TAG set "DELPHI_TAG=13_2"
set "ROOT=%CD%"

call "Tools\delphi-env.bat" || goto :fail

set "COMMON=/t:Build /p:Config=%CFG% /p:Platform=Win32 /v:minimal /nologo"
set "DCUDIR=%ROOT%\Dcu\%DELPHI_TAG%\Win32\%CFG%"
set "EXEDIR=%ROOT%\Exe\Win32"

if not exist "%DCUDIR%" mkdir "%DCUDIR%"
if not exist "%EXEDIR%" mkdir "%EXEDIR%"

echo.
echo === FDBDERun [%CFG%, Win32] ===
msbuild "Packages\d132\FDBDERun.dproj" %COMMON% "/p:DCC_DcuOutput=%DCUDIR%"
if errorlevel 1 goto :fail

echo.
echo === FDBDEDesign [%CFG%, Win32] ===
msbuild "Packages\d132\FDBDEDesign.dproj" %COMMON% "/p:DCC_DcuOutput=%DCUDIR%"
if errorlevel 1 goto :fail

echo.
echo === BDETest [%CFG%, Win32] ===
msbuild "Demos\BDETest.dproj" %COMMON% "/p:DCC_DcuOutput=%DCUDIR%" "/p:DCC_ExeOutput=%EXEDIR%"
if errorlevel 1 goto :fail

echo.
echo === LocalSQLTest [%CFG%, Win32] ===
msbuild "Demos\LocalSQLTest.dproj" %COMMON% "/p:DCC_DcuOutput=%DCUDIR%" "/p:DCC_ExeOutput=%EXEDIR%"
if errorlevel 1 goto :fail

echo.
echo === Compilazione riuscita ===
popd
endlocal
exit /b 0

:fail
echo.
echo *** Compilazione FALLITA ***
popd
endlocal
exit /b 1
