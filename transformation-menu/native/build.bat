@echo off
rem Builds obmp_native.dll (x64, Release, static CRT) with the MSVC of Visual Studio 2026.
setlocal
set "VCVARS=C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat"
if not exist "%VCVARS%" (echo vcvars64.bat not found: %VCVARS% & exit /b 1)
call "%VCVARS%" >nul 2>nul || exit /b 1
cd /d "%~dp0"
if not exist out mkdir out
cl /nologo /O2 /MT /EHsc /W4 /WX /std:c++20 /Zi /LD obmp_native.cpp /Fo:out\ /Fd:out\ /Fe:out\obmp_native.dll /link /NOLOGO /DEBUG /OPT:REF /OPT:ICF || exit /b 1
echo OK: %~dp0out\obmp_native.dll
