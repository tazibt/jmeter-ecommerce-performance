@echo off

REM 1. Configuration JMeter
if not defined JMETER_HOME set JMETER_HOME=C:\apache-jmeter-5.6.3

REM 2. Choix de l'environnement / du profil de tir (validation, charge)
set PROFIL=%1
if "%PROFIL%"=="" set PROFIL=validation

set EXTRA=
:args
shift
if "%~1"=="" goto run
set EXTRA=%EXTRA% %1
goto args
:run

REM 3. Fichiers du tir
set RESULTS=results\%PROFIL%
if exist %RESULTS% rmdir /s /q %RESULTS%
mkdir %RESULTS%

REM 4. Exécution en mode non-GUI + rapport HTML
call "%JMETER_HOME%\bin\jmeter.bat" -n -t tests\ecommerce.jmx -q config\%PROFIL%.properties -l %RESULTS%\result.jtl -j %RESULTS%\jmeter.log -e -o %RESULTS%\report %EXTRA%

echo Rapport : %RESULTS%\report\index.html
