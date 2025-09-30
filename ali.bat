@echo off
setlocal
:: ============================================================================ 
:: Android Automation Script
::
:: Description:
:: This script automates a testing cycle on a connected Android device.
:: It performs the following steps in a continuous loop:
:: 1. Checks the NFC state. If it's off, it turns it on, waits 10 seconds,
::    and turns it back off.
:: 2. Captures a logcat during the NFC test.
:: 3. Reboots the device and waits for it to be ready for the next cycle.
::
:: Prerequisites:
:: - Android Debug Bridge (adb) must be installed and in your system's PATH.
:: - A single Android device must be connected via USB with USB debugging enabled.
::
:: Usage:
:: 1. Save this file as "android_automation.bat".
:: 2. Connect your Android device.
:: 3. Double-click the file to run it.
:: 4. To stop the script, simply close the command prompt window.
:: ============================================================================

title Android Automation Script

:: --- Configuration ---
:: Set the total number of test cycles to run before the script exits.
set "MAX_CYCLES=2"

:: Set the timeout in seconds for verifying NFC state changes.
set "NFC_VERIFY_TIMEOUT=10"

:: Initialize a counter for the loop
set "LOOP_COUNT=0"

:: --- Subroutine Prototypes (for readability) ---
goto :main

:main
setlocal enabledelayedexpansion

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

:: Attempt to restart adb with root permissions. This is crucial.
adb root
adb wait-for-device
echo [%time%] Checking root access...
for /f "delims=" %%i in ('adb shell "whoami"') do set "WHOAMI=%%i"
if /i "!WHOAMI!" NEQ "root" (
    echo [%time%] ERROR: Failed to gain root access. 'whoami' returned '!WHOAMI!'.
    echo [%time%] Please ensure the device is a debug build and can be rooted.
    goto :end
)
echo [%time%] Root access confirmed.

:: --- STEP 1: Logcat Capture ---
echo.
echo [%time%] [Step 1/4] Capturing logcat...
set "LOG_FILENAME=nfc_log_run_%LOOP_COUNT%_%date:~0,4%%date:~5,2%%date:~8,2%-%time:~0,2%%time:~3,2%%time:~6,2%.txt"
echo [%time%] Log file will be saved as: %LOG_FILENAME%

echo [%time%] Starting logcat capture directly to PC...
:: Start adb logcat in background (Windows doesn't easily provide PIDs for started processes)
adb logcat -b all > "%LOG_FILENAME%" 2>&1 &
echo [%time%] Logcat started in background.

:: --- STEP 2: NFC State Check and Toggle ---
echo.
echo [%time%] [Step 2/4] Checking NFC state...
call :get_nfc_state NFC_STATE

:: Check the determined NFC state
if "%NFC_STATE%"=="off" (
    echo [%time%] NFC is OFF. Starting NFC toggle test.

    call :toggle_nfc "on"
    if errorlevel 1 goto stop_logging

    echo [%time%] Waiting for 5 seconds before turning off...
    timeout /t 5 /nobreak >nul

    call :toggle_nfc "off"
    if errorlevel 1 goto stop_logging

) else if "%NFC_STATE%"=="on" (
    echo [%time%] NFC is already ON. Skipping the toggle test for this cycle.
) else (
    echo [%time%] Could not determine NFC state. Skipping.
)

:: --- STEP 3: Stop Logcat Capture ---
:stop_logging
echo.
echo [%time%] [Step 3/4] Stopping logcat capture...
:: Since we can't easily track the PID, we'll kill all adb logcat processes
for /f "tokens=2" %%i in ('tasklist ^| findstr "adb.exe" 2^>nul') do (
    taskkill /PID %%i /F >nul 2>nul
)
echo [%time%] Killed adb logcat processes.

echo [%time%] Logcat capture complete.

:: The script now exits on failure, so this check is for loop completion.
:: Failures are handled by `goto :end` inside the subroutines.

:: Check if the loop has run the maximum number of times
if %LOOP_COUNT% GEQ %MAX_CYCLES% (
    echo.
    echo [%time%] Completed %MAX_CYCLES% test cycles. Exiting script.
    timeout /t 5 >nul
    goto :end
)

:: --- STEP 4: Reboot Device ---
echo.
echo [%time%] [Step 4/4] Rebooting device...
adb reboot >nul
if errorlevel 1 (
    echo [%time%] ERROR: 'adb reboot' command failed.
    goto :end
)

:: Kill and restart ADB server
adb kill-server
timeout /t 10 /nobreak >nul
adb start-server
timeout /t 20 /nobreak >nul

echo [%time%] Waiting for device to come back online (this can take several minutes)...
adb wait-for-device
echo [%time%] Device is online. Waiting 30 seconds for system to stabilize...
timeout /t 30 /nobreak >nul

echo [%time%] Cycle complete. Restarting process...
echo.
endlocal
goto main_loop

:: End script
:end
echo.
echo [%time%] Script finished or an error occurred.
endlocal
exit /b

:: ==================================================================
:: Subroutine: get_nfc_state
:: Description: Gets the current NFC state from the device.
:: Output: Sets the variable named in %1 to "on", "off", or "unknown".
:: ==================================================================
:get_nfc_state
set "%1=unknown"
for /f "tokens=2 delims==" %%s in ('adb shell dumpsys nfc ^| findstr /c:"mState="') do (
    set "%1=%%s"
)
goto :eof

:: ==================================================================
:: Subroutine: toggle_nfc
:: Description: Turns NFC on or off and verifies the change.
:: Parameter 1: The desired state ("on" or "off").
:: Returns: ERRORLEVEL 0 on success, 1 on failure.
:: ==================================================================
:toggle_nfc
set "TARGET_STATE=%~1"
set "COMMAND="
if /i "%TARGET_STATE%"=="on" set "COMMAND=enable"
if /i "%TARGET_STATE%"=="off" set "COMMAND=disable"

if not defined COMMAND (
    echo [%time%] INTERNAL SCRIPT ERROR: Invalid target state '%TARGET_STATE%' for :toggle_nfc.
    exit /b 1
)

echo [%time%] Turning NFC %TARGET_STATE%...
adb shell svc nfc %COMMAND%

echo [%time%] Verifying NFC is %TARGET_STATE% (timeout: %NFC_VERIFY_TIMEOUT%s)...
for /L %%i in (1,1,%NFC_VERIFY_TIMEOUT%) do (
    call :get_nfc_state CURRENT_NFC_STATE
    if "!CURRENT_NFC_STATE!"=="%TARGET_STATE%" (
        echo [%time%] SUCCESS: NFC is now %TARGET_STATE%.
        exit /b 0
    )
    timeout /t 1 /nobreak >nul
)

:: If the loop finishes, it means we timed out
echo [%time%] FAILED: Could not verify NFC state is '%TARGET_STATE%' after %NFC_VERIFY_TIMEOUT% seconds.
call :get_nfc_state FINAL_STATE
echo [%time%] Final state was: !FINAL_STATE!
echo [%time%] FAILED: Test cycle #%LOOP_COUNT% failed.
exit /b 1

goto :eof