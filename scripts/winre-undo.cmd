@echo off
rem Undo native NVMe from the Windows Recovery command prompt (Troubleshoot > Advanced options > Command Prompt).
rem Removes EnableNativeNVMeUserSetting from EVERY controller in the offline Windows registry.
rem Copy this file to the root of your Windows drive BEFORE you enable anything, e.g. C:\winre-undo.cmd
rem Test on running Windows (changes nothing):  winre-undo.cmd test
setlocal EnableDelayedExpansion
if /i "%~1"=="test" (set "ROOT=HKLM\SYSTEM" & goto :select)
set WIN=
for %%L in (C D E F G H I J K) do if not defined WIN if exist %%L:\Windows\System32\config\SYSTEM set WIN=%%L:
if "%WIN%"=="" (echo Windows folder not found on any drive & exit /b 1)
echo Windows found on %WIN%
reg load HKLM\OFF %WIN%\Windows\System32\config\SYSTEM || (echo reg load failed & exit /b 1)
set "ROOT=HKLM\OFF"
:select
for /f "tokens=3" %%A in ('reg query "%ROOT%\Select" /v Current ^| find "Current"') do set /a CS=%%A
set "CSK=%ROOT%\ControlSet00%CS%"
echo Control set: %CSK%
for /f "delims=" %%K in ('reg query "%CSK%\Enum\PCI" /s /f EnableNativeNVMeUserSetting /v ^| find "HKEY_"') do (
  if /i "%~1"=="test" (echo found: %%K) else (reg delete "%%K" /v EnableNativeNVMeUserSetting /f)
)
if /i "%~1"=="test" (echo TEST ONLY - nothing changed. & exit /b 0)
reg unload HKLM\OFF
echo DONE. Close this window and choose Continue. Every controller is back on the stock driver.
