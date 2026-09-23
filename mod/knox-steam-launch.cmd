@echo off
setlocal DisableDelayedExpansion

rem Knox Survivors Steam bootstrap.
rem Changes environment variables only for this process tree. It does not edit
rem Windows, Steam, Project Zomboid config files, mods, or save data.

set "KNOX_AGENT=%~dp0java\knox-agent.jar"
if not exist "%KNOX_AGENT%" (
    echo [Knox Survivors] Missing runtime: "%KNOX_AGENT%"
    echo Let Steam finish or verify the Workshop download.
    exit /b 2
)

rem Steam normally starts Project Zomboid with the game directory as the working
rem directory. Fall back to the first command argument when it is the normal EXE.
set "PZ_HOME=%CD%"
if not exist "%PZ_HOME%\ProjectZomboid64.exe" (
    if /I "%~nx1"=="ProjectZomboid64.exe" set "PZ_HOME=%~dp1"
)
if not exist "%PZ_HOME%\ProjectZomboid64.exe" (
    echo [Knox Survivors] Could not locate ProjectZomboid64.exe.
    echo Use Steam's normal Project Zomboid launch option.
    exit /b 3
)
for %%I in ("%PZ_HOME%") do set "PZ_HOME=%%~fI"

for %%F in (
    "jre64\bin\java.dll"
    "jre64\bin\jli.dll"
    "jre64\bin\instrument.dll"
    "jre64\bin\server\jvm.dll"
) do (
    if not exist "%PZ_HOME%\%%~F" (
        echo [Knox Survivors] Missing bundled Java file: %%~F
        echo Verify Project Zomboid through Steam.
        exit /b 4
    )
)

rem Keep external/system Java installed, but make PZ's bundled runtime win DLL
rem lookup for this game process and its children only.
set "PATH=%PZ_HOME%\jre64\bin;%PZ_HOME%\jre64\bin\server;%PATH%"

rem Preserve any existing JAVA_TOOL_OPTIONS from other tools/mods and append Knox.
rem Users should remove an older Knox -javaagent Steam option before using this wrapper.
if defined JAVA_TOOL_OPTIONS (
    set "JAVA_TOOL_OPTIONS=%JAVA_TOOL_OPTIONS% -javaagent:\"%KNOX_AGENT%\"=pz-game"
) else (
    set "JAVA_TOOL_OPTIONS=-javaagent:\"%KNOX_AGENT%\"=pz-game"
)

if "%~1"=="" (
    echo [Knox Survivors] Steam did not provide a game command.
    exit /b 5
)

rem Forward the original Steam command and all existing launch options unchanged.
%*
exit /b %ERRORLEVEL%
