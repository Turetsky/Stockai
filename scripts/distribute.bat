@echo off
echo ============================================
echo  StockAI - Firebase App Distribution
echo ============================================
echo.

set APK="%~dp0..\app\build\app\outputs\flutter-apk\app-release.apk"
set APP_ID=1:494810929579:android:798b5dc63ed5efba231aee
set PROJECT=stockai-75833731-f9741

if not exist %APK% (
  echo ERROR: APK not found at %APK%
  echo Build it first: cd app ^&^& flutter build apk --release
  pause
  exit /b 1
)

echo Uploading to Firebase App Distribution...
echo App ID: %APP_ID%
echo.

firebase appdistribution:distribute %APK% ^
  --app %APP_ID% ^
  --project %PROJECT% ^
  --release-notes "v1.1.0 - Color wheel theme picker, per-element color customization, save custom presets, Data tab redesign (categories + import/export with Excel/CSV support)"

echo.
if %ERRORLEVEL%==0 (
  echo SUCCESS - APK distributed!
) else (
  echo FAILED - make sure you ran: firebase login
)
pause
