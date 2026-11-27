@echo off
setlocal

:: WisdAI Windows CLI Launcher
set SCRIPT_DIR=%~dp0
set NODE_EXE=node
set PYTHON_EXE=python

where node >nul 2>nul
if %errorlevel% equ 0 (
    node "%SCRIPT_DIR%wisdai-agent.js" %*
    exit /b %errorlevel%
)

where python >nul 2>nul
if %errorlevel% equ 0 (
    python "%SCRIPT_DIR%wisdai-agent.py" %*
    exit /b %errorlevel%
)

echo [ERRO] Nem Node.js nem Python foram encontrados no PATH do Windows.
echo Por favor, instale o Node.js v20+ ou Python 3.9+ para executar o agente CLI.
exit /b 1
