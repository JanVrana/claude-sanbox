# install.ps1 - Windows installer for Claude Code Sandbox (delegates to WSL2)
#
# Usage:
#   irm https://raw.githubusercontent.com/JanVrana/claude-sanbox/main/install.ps1 | iex
#
# Or locally:
#   .\install.ps1

$ErrorActionPreference = "Stop"

function Write-Info($msg)  { Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)    { Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Warn($msg)  { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Err($msg)   { Write-Host "[ERROR] $msg" -ForegroundColor Red }

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Claude Code Sandbox - Windows Setup"
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# --- 1. Check WSL2 ---

Write-Info "Checking WSL2..."

try {
    $wslStatus = wsl --status 2>&1
    if ($LASTEXITCODE -ne 0) { throw "WSL not available" }
    Write-Ok "WSL2 is installed."
} catch {
    Write-Err "WSL2 is not installed or not configured."
    Write-Host "  Install WSL2: wsl --install"
    Write-Host "  Then restart your computer and re-run this script."
    exit 1
}

# Check that a default distro exists
try {
    $distros = wsl --list --quiet 2>&1
    if (-not $distros -or $distros.Length -eq 0) {
        Write-Err "No WSL2 distribution found."
        Write-Host "  Install one: wsl --install -d Ubuntu"
        exit 1
    }
    Write-Ok "WSL2 distribution found."
} catch {
    Write-Err "Could not list WSL2 distributions."
    exit 1
}

# --- 2. Check Docker Desktop ---

Write-Info "Checking Docker Desktop..."

try {
    $dockerVersion = docker --version 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Docker not found" }
    Write-Ok "Docker found: $dockerVersion"
} catch {
    Write-Err "Docker Desktop is not installed or not in PATH."
    Write-Host "  Install from: https://docs.docker.com/desktop/install/windows-install/"
    Write-Host "  Make sure 'Use the WSL 2 based engine' is enabled in Docker Desktop settings."
    exit 1
}

# Verify Docker is running
try {
    docker info 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Docker not running" }
    Write-Ok "Docker Desktop is running."
} catch {
    Write-Err "Docker Desktop is not running. Please start it first."
    exit 1
}

# --- 3. Run install.sh inside WSL2 ---

Write-Info "Running installation inside WSL2..."
Write-Host ""

$installCmd = "curl -fsSL https://raw.githubusercontent.com/JanVrana/claude-sanbox/main/install.sh | bash"

wsl -- bash -c $installCmd

if ($LASTEXITCODE -ne 0) {
    Write-Err "Installation inside WSL2 failed."
    exit 1
}

# --- 4. Done ---

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Installation complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  IMPORTANT: Run claude-sandbox from a WSL2 terminal:" -ForegroundColor Yellow
Write-Host "    1. Open Windows Terminal"
Write-Host "    2. Select your WSL2 distribution (e.g. Ubuntu)"
Write-Host "    3. cd /path/to/project"
Write-Host "    4. claude-sandbox"
Write-Host ""
