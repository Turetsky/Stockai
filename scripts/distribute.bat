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
  --testers "Yjturetsky@gmail.com" ^
  --release-notes "v1.2.0 - StockAI rebrand, animated splash screen, ElevenLabs TTS (12 free voices + sliders), voice settings, recycling bin, web export/import, about page, mobile AI chat full-screen overlay"

echo.
if %ERRORLEVEL%==0 (
  echo SUCCESS - APK distributed!
) else (
  echo FAILED - make sure you ran: firebase login
)
pause
