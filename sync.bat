@echo off
rem River Royale: pull the latest code and assets, then open the project in Godot.
rem First run: put the full path to your Godot exe in tools\godot_path.txt (one line).
cd /d "%~dp0"
echo Pulling latest...
git pull --ff-only
if errorlevel 1 (
  echo Pull failed. If Godot has the project open, close it and try again.
  pause
  exit /b 1
)
if exist tools\godot_path.txt (
  set /p GODOT=<tools\godot_path.txt
  echo Opening Godot...
  start "" "%GODOT%" --path "%~dp0" -e
) else (
  echo Done. Open the project in Godot ^(or add tools\godot_path.txt to auto-launch^).
  pause
)
