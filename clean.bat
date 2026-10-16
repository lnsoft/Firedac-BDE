@echo off
rem Pulisce i file generati dalla compilazione (Dcu, Exe, __history, .local, .~*).
rem Non tocca i sorgenti ne' i dati di prova.

setlocal
pushd "%~dp0"

if exist "Dcu" rmdir /s /q "Dcu"
if exist "Exe" rmdir /s /q "Exe"
for /d /r %%D in (__history __recovery) do if exist "%%D" rmdir /s /q "%%D"
for /r %%F in (*.local *.~* *.dcu *.rsm *.map *.identcache) do del /q "%%F" 2>nul

echo Pulizia completata.
popd
endlocal
exit /b 0
