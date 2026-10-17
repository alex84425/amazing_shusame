@echo off
chcp 65001 >nul
echo 九霄特效預覽器：關掉這個視窗就會停止
cd /d "%~dp0"
start "" http://localhost:8765/Tools/previewer/
python -m http.server 8765
