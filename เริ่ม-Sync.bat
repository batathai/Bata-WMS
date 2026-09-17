@echo off
cd /d "%~dp0"
echo Starting Bata MySQL -> Supabase sync...
node sync.js
pause
