@echo off
setlocal
setlocal enabledelayedexpansion
:: ============================================================================
:: Android Automation Script
::
:: Description:
:: This script automates a testing cycle on a connected Android device.
:: It performs the following steps in a continuous loop:
:: 1. Checks the NFC state. If it's off, it turns it on, waits 10 seconds,
::    and turns it back off, verifying each step.
:: 2. Captures a 1-minute logcat to a local file.
:: 3. Reboots the device and waits for it to be ready for the next cycle.
::
:: Prerequisites:
:: - Android Debug Bridge (adb) must be installed and in your system's PATH.
:: - The Android device must be connected via USB with USB debugging enabled.
:: - The device must be Android 12 or compatible with the adb commands used.
::
:: Usage:
:: 1. Save this file as "android_automation.bat".
:: 2. Connect your Android device.
:: 3. Double-click the file to run it.
:: 4. To stop the script, simply close the command prompt window.
:: ============================================================================

title Android Automation Script

:: --- Configuration ---
:: Set locale and language
set LANG=en_US.UTF-8
set LC_ALL=en_US.UTF-8

:: Set the total number of test cycles to run before the script exits.
set "MAX_CYCLES=300"

:: Initialize a counter for the loop
set "LOOP_COUNT=0"

:: Set the result of changing NFC state
set "RESULT=1"

set "CURRENT_STATE="

:main_loop
:: Increment the loop counter
set /a LOOP_COUNT+=1

echo.
echo ============================================================================
echo [%time%] Starting test cycle #%LOOP_COUNT% of %MAX_CYCLES%.
echo ============================================================================

:: Wait for a device to be connected and ready
echo [%time%] Waiting for device to be connected...
adb wait-for-device
echo [%time%] Device connected.
adb root
echo [%time%] Device rooted.

:: --- STEP 1: NFC State Check and Toggle ---
echo.
echo [%time%] [Step 1/3] Checking NFC state...
set "NFC_STATE="
for /f "tokens=2 delims==" %%a in ('adb shell dumpsys nfc ^| findstr /c:"mState="') do set "NFC_STATE=%%a"

:: Check the determined NFC state
if "%NFC_STATE%"=="off" (
    echo [%time%] NFC is OFF. Starting NFC toggle test.

    :: Turn NFC ON
    echo [%time%] Turning NFC ON...
    adb shell svc nfc enable
    timeout /t 3 >nul

    :: Verify NFC is ON
    set "CURRENT_STATE="
    for /f "tokens=2 delims==" %%a in ('adb shell dumpsys nfc ^| findstr /c:"mState="') do set "CURRENT_STATE=%%a"
    if "!CURRENT_STATE!"=="on" (
        echo [%time%] SUCCESS: NFC is now ON.
    ) else (
        echo [%time%] FAILED: Could not turn NFC ON.
        set "RESULT=0"
        goto logging
    )

    :: Wait 5 seconds
    echo [%time%] Waiting for 5 seconds...
    timeout /t 3 /nobreak >nul

    :: Turn NFC OFF
    echo [%time%] Turning NFC OFF...
    adb shell svc nfc disable
    timeout /t 3 >nul

    :: Verify NFC is OFF
    set "CURRENT_STATE="
    for /f "tokens=2 delims==" %%a in ('adb shell dumpsys nfc ^| findstr /c:"mState="') do set "CURRENT_STATE=%%a"
    if "!CURRENT_STATE!"=="off" (
        echo [%time%] SUCCESS: NFC is now OFF.
    ) else (
        echo [%time%] FAILED: Could not turn NFC OFF.
        set "RESULT=0"
        goto logging
    )
) else if "%NFC_STATE%"=="on" (
    echo [%time%] NFC is already ON. Skipping the toggle test for this cycle.
) else (
    echo [%time%] Could not determine NFC state. Skipping.
)

:: --- STEP 2: Logcat Capture ---
:logging
echo.
echo [%time%] [Step 2/3] Capturing logcat for 1 minute...
set "LOG_FILENAME=nfc_log_run_%LOOP_COUNT%_%date:~0,4%%date:~5,2%%date:~8,2%-%time:~0,2%%time:~3,2%%time:~6,2%.txt"
echo [%time%] Log file will be saved as: %LOG_FILENAME%

echo [%time%] Starting logcat capture directly to PC...
:: Start adb logcat in a new background process, redirecting its output to the file.
start "ADBCapture" /B adb logcat -b all > "%LOG_FILENAME%"

echo [%time%] Logging for 60 seconds...
timeout /t 60 /nobreak >nul

echo [%time%] Stopping logcat capture...
:: Killing the adb.exe process will stop the logcat stream.
:: This is a forceful method but effective for this script's purpose.
taskkill /IM adb.exe /F >nul 2>nul

echo [%time%] Logcat capture complete.

if %RESULT% EQU 0 (
    echo [%time%] FAILED: Test cycle #%LOOP_COUNT% failed.
    goto :end
)

:: --- STEP 3: Reboot Device ---
echo.
echo [%time%] [Step 3/3] Rebooting device...
adb reboot

echo [%time%] Waiting for device to come back online (this can take several minutes)...
timeout /t 60 /nobreak >nul
adb wait-for-device
echo [%time%] Device is online. Waiting 1 minute for system to stabilize...
timeout /t 60 /nobreak >nul

:: Check if the loop has run the maximum number of times
if %LOOP_COUNT% GEQ %MAX_CYCLES% (
    echo.
    echo [%time%] Completed %MAX_CYCLES% test cycles. Exiting script.
    timeout /t 5 >nul
    goto :end
)

echo [%time%] Cycle complete. Restarting process...
echo.
goto main_loop

:: End script
:end
endlocal
exit /b

:: ==================================================================
:: Subroutine: Verify NFC State
:: Parameter: %1 - The expected state (e.g., "STATE_ON" or "STATE_OFF")
:: ==================================================================
:verify_nfc_state
echo Verifying if the NFC state has been successfully switched...
set "EXPECTED_STATE=%~1"
set "VERIFY_COUNT=0"

set "CURRENT_STATE="
for /f "tokens=2 delims==" %%s in ('adb shell dumpsys nfc ^| findstr /c:"mState="') do (
    set "CURRENT_STATE=%%s"
)

if "%CURRENT_STATE%"=="%EXPECTED_STATE%" (
    echo [SUCCESS] NFC state has been successfully switched to: %EXPECTED_STATE%
) else (
    echo [FAIL] NFC state change timed out! Failed to switch to %EXPECTED_STATE%.
    set "RESULT=0"
)

goto :eof
