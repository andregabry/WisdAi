@echo off
setlocal enabledelayedexpansion

echo =======================================================
echo          WisdAI Desktop - Compilador Windows           
echo =======================================================
echo.

set SCRIPT_DIR=%~dp0
set REPO_ROOT=%SCRIPT_DIR%..\..
set BIN_DEST=%SCRIPT_DIR%bin
set DIST_OUT=%REPO_ROOT%\dist\windows

:: 1. Verificar Node.js e npm
echo [1/5] Verificando dependencias do ambiente...
where node >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERRO] Node.js nao encontrado no PATH. Instale o Node.js v20+ em https://nodejs.org
    exit /b 1
)

where cargo >nul 2>nul
if %errorlevel% neq 0 (
    echo [AVISO] Cargo/Rust nao encontrado no PATH.
    echo Se voce ja compilou os binarios codex.exe e codex-code-mode-host.exe,
    echo certifique-se de coloca-los na pasta: %BIN_DEST%
) else (
    echo [2/5] Compilando motor nativo Rust (codex e code-mode-host)...
    cd /d "%REPO_ROOT%\codex-rs"
    cargo build --release -p codex-cli -p codex-code-mode-host
    if %errorlevel% neq 0 (
        echo [AVISO] Falha na compilacao local do Rust. Continuando com binarios existentes...
    ) else (
        echo [OK] Binarios Rust compilados com sucesso.
        if not exist "%BIN_DEST%" mkdir "%BIN_DEST%"
        copy /y "%REPO_ROOT%\codex-rs\target\release\codex.exe" "%BIN_DEST%\" >nul 2>nul
        copy /y "%REPO_ROOT%\codex-rs\target\release\codex-code-mode-host.exe" "%BIN_DEST%\" >nul 2>nul
    )
)

:: 3. Instalar dependencias do cliente desktop
echo [3/5] Instalando dependencias do Electron...
cd /d "%SCRIPT_DIR%"
call npm install
if %errorlevel% neq 0 (
    echo [ERRO] Falha ao executar npm install.
    exit /b 1
)

:: 4. Empacotar aplicativo para Windows
echo [4/5] Empacotando WisdAI Desktop (NSIS e Portable)...
call npm run dist:win
if %errorlevel% neq 0 (
    echo [AVISO] Tentando empacotamento em diretorio descompactado (pack:win)...
    call npm run pack:win
)

:: 5. Mover instaladores gerados para pasta dist
echo [5/5] Organizando artefatos finais em %DIST_OUT%...
if not exist "%DIST_OUT%" mkdir "%DIST_OUT%"
if exist "%SCRIPT_DIR%dist\*.exe" copy /y "%SCRIPT_DIR%dist\*.exe" "%DIST_OUT%\" >nul 2>nul
if exist "%SCRIPT_DIR%dist\*.zip" copy /y "%SCRIPT_DIR%dist\*.zip" "%DIST_OUT%\" >nul 2>nul

echo.
echo =======================================================
echo     Compilacao para Windows concluida com sucesso!     
echo     Instaladores disponiveis em:                       
echo     %DIST_OUT%                                         
echo =======================================================
echo.
pause
