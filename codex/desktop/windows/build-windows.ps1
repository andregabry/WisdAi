<#
.SYNOPSIS
    Compilador e empacotador automatizado do WisdAI Desktop para Windows.
.DESCRIPTION
    Verifica dependências (Node.js, Rust/Cargo), compila os binários do motor nativo
    e gera o instalador executável (NSIS / Portable) do WisdAI Desktop.
#>

param (
    [switch]$SkipRust = $false,
    [switch]$PortableOnly = $false
)

$ErrorActionPreference = "Stop"

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "          WisdAI Desktop - Compilador Windows           " -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = (Resolve-Path "$ScriptDir\..\..").Path
$BinDest = Join-Path $ScriptDir "bin"
$DistOut = Join-Path $RepoRoot "dist\windows"

# 1. Verificar dependências
Write-Host "[1/5] Verificando dependências do sistema..." -ForegroundColor Yellow
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Error "Node.js não foi encontrado. Instale o Node.js v20+ em https://nodejs.org"
}

if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    Write-Error "npm não foi encontrado no PATH."
}

# 2. Compilar motor Rust
if (-not $SkipRust) {
    if (Get-Command cargo -ErrorAction SilentlyContinue) {
        Write-Host "[2/5] Compilando motor Rust (codex-cli e codex-code-mode-host)..." -ForegroundColor Yellow
        Push-Location "$RepoRoot\codex-rs"
        try {
            cargo build --release -p codex-cli -p codex-code-mode-host
            Write-Host "[OK] Binários Rust compilados com sucesso." -ForegroundColor Green
            
            if (-not (Test-Path $BinDest)) { New-Item -ItemType Directory -Path $BinDest -Force | Out-Null }
            Copy-Item "$RepoRoot\codex-rs\target\release\codex.exe" -Destination "$BinDest\codex.exe" -Force -ErrorAction SilentlyContinue
            Copy-Item "$RepoRoot\codex-rs\target\release\codex-code-mode-host.exe" -Destination "$BinDest\codex-code-mode-host.exe" -Force -ErrorAction SilentlyContinue
        } catch {
            Write-Warning "Falha ao compilar binários Rust: $_"
        } finally {
            Pop-Location
        }
    } else {
        Write-Warning "Cargo/Rust não encontrado no PATH. Pulando compilação do motor."
    }
} else {
    Write-Host "[2/5] Compilação do motor Rust ignorada (-SkipRust)." -ForegroundColor Gray
}

# 3. Instalar dependências Electron
Write-Host "[3/5] Instalando dependências npm do cliente desktop..." -ForegroundColor Yellow
Push-Location $ScriptDir
try {
    npm install
} catch {
    Write-Error "Falha ao executar npm install."
} finally {
    Pop-Location
}

# 4. Empacotar Desktop
Write-Host "[4/5] Empacotando WisdAI Desktop..." -ForegroundColor Yellow
Push-Location $ScriptDir
try {
    if ($PortableOnly) {
        npx electron-builder --win portable --x64
    } else {
        npx electron-builder --win nsis portable zip --x64
    }
    Write-Host "[OK] Empacotamento concluído." -ForegroundColor Green
} catch {
    Write-Warning "Falha no empacotamento completo. Tentando empacotar diretório descompactado..."
    npx electron-builder --win --dir
} finally {
    Pop-Location
}

# 5. Organizar artefatos
Write-Host "[5/5] Organizando arquivos de saída em $DistOut..." -ForegroundColor Yellow
if (-not (Test-Path $DistOut)) {
    New-Item -ItemType Directory -Path $DistOut -Force | Out-Null
}

Get-ChildItem -Path "$ScriptDir\dist" -Filter "*.exe" -ErrorAction SilentlyContinue | ForEach-Object {
    Copy-Item $_.FullName -Destination $DistOut -Force
    Write-Host "  -> Instalador gerado: $($_.Name)" -ForegroundColor Green
}

Get-ChildItem -Path "$ScriptDir\dist" -Filter "*.zip" -ErrorAction SilentlyContinue | ForEach-Object {
    Copy-Item $_.FullName -Destination $DistOut -Force
    Write-Host "  -> Pacote ZIP gerado: $($_.Name)" -ForegroundColor Green
}

Write-Host ""
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "     Compilação para Windows concluída com sucesso!     " -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
