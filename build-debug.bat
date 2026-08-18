@echo off
setlocal

pushd "%~dp0"
cmake --preset windows-x64
if errorlevel 1 goto :error

cmake --build --preset windows-x64-debug
if errorlevel 1 goto :error

set "EXIT_CODE=%ERRORLEVEL%"
popd
exit /b %EXIT_CODE%

:error
set "EXIT_CODE=%ERRORLEVEL%"
popd
exit /b %EXIT_CODE%
