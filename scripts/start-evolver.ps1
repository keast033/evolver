param(
  [ValidateSet("review", "run", "loop")]
  [string]$Mode = "review",
  [ValidateSet("balanced", "innovate", "harden", "repair-only")]
  [string]$Strategy = "balanced",
  [string]$EvolverRoot = "",
  [string]$CursorProjectId = "",
  [string]$AgentName = "main",
  [switch]$Approve,
  [switch]$Reject,
  [switch]$DisableOpenClawMirror,
  [switch]$Init,
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = (Resolve-Path $ScriptDir).Path
$ConfigPath = Join-Path $ProjectRoot ".evolver.start.json"
$ProjectInfoPath = Join-Path $ProjectRoot ".evolver.project.json"

function Write-Info([string]$Message) {
  Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Ok([string]$Message) {
  Write-Host "[OK]   $Message" -ForegroundColor Green
}

function Write-WarnLine([string]$Message) {
  Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Get-DefaultProjectId([string]$RootPath) {
  $leaf = Split-Path $RootPath -Leaf
  if ([string]::IsNullOrWhiteSpace($leaf)) { return "project" }
  $safe = ($leaf -replace "[^a-zA-Z0-9\-_]", "-").ToLowerInvariant()
  if ([string]::IsNullOrWhiteSpace($safe)) { return "project" }
  return $safe
}

function Load-Or-CreateConfig([string]$PathValue, [string]$RootPath) {
  if (Test-Path -LiteralPath $PathValue) {
    try {
      $obj = Get-Content -LiteralPath $PathValue -Raw | ConvertFrom-Json
      if ($null -ne $obj) { return $obj }
    } catch {
      throw "Failed to parse config: $PathValue"
    }
  }

  $created = @{
    project_id = (Get-DefaultProjectId -RootPath $RootPath)
    project_root = $RootPath
    evolver_root = ""
    cursor_project_id = ""
    agent_name = "main"
    memory_dir = (Join-Path $RootPath "memory")
    bridge_dir = (Join-Path (Join-Path $RootPath "memory") "cursor-session-bridge")
  }
  $created | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $PathValue -Encoding UTF8
  return $created
}

function Save-Config([string]$PathValue, $Cfg) {
  $json = $Cfg | ConvertTo-Json -Depth 8
  [System.IO.File]::WriteAllText($PathValue, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
}

function Resolve-EvolverRoot($Cfg, [string]$Override, [string]$RootPath) {
  $candidates = @()
  if (-not [string]::IsNullOrWhiteSpace($Override)) { $candidates += $Override }
  if (-not [string]::IsNullOrWhiteSpace($Cfg.evolver_root)) { $candidates += $Cfg.evolver_root }
  if (-not [string]::IsNullOrWhiteSpace($env:EVOLVER_ROOT)) { $candidates += $env:EVOLVER_ROOT }
  $candidates += (Join-Path $RootPath "evolver")
  $candidates += $RootPath

  foreach ($cand in $candidates) {
    try {
      $resolved = (Resolve-Path -LiteralPath $cand -ErrorAction Stop).Path
      $entry = Join-Path $resolved "index.js"
      if (Test-Path -LiteralPath $entry) {
        return $resolved
      }
    } catch {}
  }
  return $null
}

function Assert-Command([string]$Name) {
  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if (-not $cmd) {
    throw "Missing required command: $Name"
  }
}

function Ensure-Directory([string]$PathValue, [string]$Label) {
  if ([string]::IsNullOrWhiteSpace($PathValue)) {
    throw "$Label is empty"
  }
  if (-not (Test-Path -LiteralPath $PathValue)) {
    Write-WarnLine "$Label not found, creating: $PathValue"
    New-Item -ItemType Directory -Path $PathValue -Force | Out-Null
  }
}

function Build-OpenClawSessionsDir([string]$AgentNameValue) {
  if ([string]::IsNullOrWhiteSpace($AgentNameValue)) { $AgentNameValue = "main" }
  $userHomeDir = [Environment]::GetFolderPath("UserProfile")
  return Join-Path $userHomeDir ".openclaw\agents\$AgentNameValue\sessions"
}

function Write-ProjectInfo([string]$PathValue, $Cfg, [string]$ResolvedEvolverRoot) {
  $info = @{
    project_id = $Cfg.project_id
    project_root = $Cfg.project_root
    evolver_root = $ResolvedEvolverRoot
    cursor_project_id = $Cfg.cursor_project_id
    agent_name = $Cfg.agent_name
    memory_dir = $Cfg.memory_dir
    bridge_dir = $Cfg.bridge_dir
    updated_at = (Get-Date).ToString("s")
  }
  $json = $info | ConvertTo-Json -Depth 8
  [System.IO.File]::WriteAllText($PathValue, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
}

try {
  Assert-Command "node"
  Assert-Command "git"
  $nodeVersion = node -v
  Write-Ok "node detected: $nodeVersion"
} catch {
  Write-Error $_
  exit 2
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
  Write-WarnLine "Config not found, initializing: $ConfigPath"
}

$cfg = Load-Or-CreateConfig -PathValue $ConfigPath -RootPath $ProjectRoot
if (-not [string]::IsNullOrWhiteSpace($CursorProjectId)) { $cfg.cursor_project_id = $CursorProjectId }
if (-not [string]::IsNullOrWhiteSpace($AgentName)) { $cfg.agent_name = $AgentName }
if ($cfg.project_root -ne $ProjectRoot) { $cfg.project_root = $ProjectRoot }

$resolvedEvolverRoot = Resolve-EvolverRoot -Cfg $cfg -Override $EvolverRoot -RootPath $ProjectRoot
if (-not $resolvedEvolverRoot) {
  Write-Error "Cannot resolve Evolver root. Use -EvolverRoot <path with index.js> once, it will be persisted to $ConfigPath"
  exit 2
}
$cfg.evolver_root = $resolvedEvolverRoot

if ([string]::IsNullOrWhiteSpace($cfg.project_id)) {
  $cfg.project_id = Get-DefaultProjectId -RootPath $ProjectRoot
}
if ([string]::IsNullOrWhiteSpace($cfg.memory_dir)) {
  $cfg.memory_dir = Join-Path $ProjectRoot "memory"
}
if ([string]::IsNullOrWhiteSpace($cfg.bridge_dir)) {
  $cfg.bridge_dir = Join-Path $cfg.memory_dir "cursor-session-bridge"
}
if ([string]::IsNullOrWhiteSpace($cfg.agent_name)) {
  $cfg.agent_name = "main"
}

Save-Config -PathValue $ConfigPath -Cfg $cfg
Write-ProjectInfo -PathValue $ProjectInfoPath -Cfg $cfg -ResolvedEvolverRoot $resolvedEvolverRoot

if ($Init) {
  Write-Ok "Init completed."
  Write-Info "Config path         : $ConfigPath"
  Write-Info "Project info path   : $ProjectInfoPath"
  Write-Info "Project id          : $($cfg.project_id)"
  Write-Info "Project root        : $ProjectRoot"
  Write-Info "Evolver root        : $resolvedEvolverRoot"
  exit 0
}

$entryFile = Join-Path $resolvedEvolverRoot "index.js"
Ensure-Directory -PathValue $cfg.memory_dir -Label "memory_dir"
Ensure-Directory -PathValue $cfg.bridge_dir -Label "bridge_dir"

$openClawSessionsDir = Build-OpenClawSessionsDir -AgentNameValue $cfg.agent_name
Ensure-Directory -PathValue $openClawSessionsDir -Label "openclaw_sessions_dir"

Push-Location $resolvedEvolverRoot
try {
  $isGitRepo = $false
  try {
    $probe = git rev-parse --is-inside-work-tree 2>$null
    $isGitRepo = ($LASTEXITCODE -eq 0 -and "$probe".Trim() -eq "true")
  } catch {
    $isGitRepo = $false
  }
  if (-not $isGitRepo) {
    Write-Error "evolver_root is not a git work tree: $resolvedEvolverRoot"
    exit 2
  }

  $env:EVOLVE_STRATEGY = $Strategy
  $env:EVOLVER_PROJECT_ID = $cfg.project_id
  $env:EVOLVER_TARGET_PROJECT_ROOT = $ProjectRoot
  $env:EVOLVE_BRIDGE = "true"
  $env:EVOLVER_SESSION_LOGS_DIR = $cfg.bridge_dir
  $env:AGENT_SESSIONS_DIR = $openClawSessionsDir
  if (-not [string]::IsNullOrWhiteSpace($cfg.cursor_project_id)) {
    $env:EVOLVER_CURSOR_PROJECT_ID = $cfg.cursor_project_id
  }
  if ($DisableOpenClawMirror) {
    $env:EVOLVER_DISABLE_OPENCLAW_MIRROR = "1"
  } else {
    $env:EVOLVER_DISABLE_OPENCLAW_MIRROR = "0"
  }

  $args = @($entryFile)
  switch ($Mode) {
    "loop" { $args += "--loop" }
    "run" { }
    "review" {
      if ($Approve -and $Reject) {
        Write-Error "Cannot use -Approve and -Reject together."
        exit 2
      }
      if ($Approve) {
        $args += "review"
        $args += "--approve"
      } elseif ($Reject) {
        $args += "review"
        $args += "--reject"
      } else {
        $args += "--review"
      }
    }
  }

  Write-Info "Project id         : $($cfg.project_id)"
  Write-Info "Project root       : $ProjectRoot"
  Write-Info "Evolver root       : $resolvedEvolverRoot"
  Write-Info "Memory dir         : $($cfg.memory_dir)"
  Write-Info "Bridge logs dir    : $($cfg.bridge_dir)"
  Write-Info "OpenClaw sessions  : $openClawSessionsDir"
  Write-Info "Strategy           : $Strategy"
  Write-Info "Mode               : $Mode"
  if ($Mode -eq "review" -and $Approve) { Write-Info "Review action      : approve" }
  if ($Mode -eq "review" -and $Reject) { Write-Info "Review action      : reject" }
  Write-Info "Loop bridge        : $($env:EVOLVE_BRIDGE)"
  Write-Info "Disable OC mirror  : $($env:EVOLVER_DISABLE_OPENCLAW_MIRROR)"
  if (-not [string]::IsNullOrWhiteSpace($cfg.cursor_project_id)) {
    Write-Info "Cursor project id  : $($cfg.cursor_project_id)"
  }

  if ($DryRun) {
    Write-WarnLine "DryRun enabled. Command preview only:"
    Write-Host "node $($args -join ' ')"
    exit 0
  }

  Write-Ok "Starting Evolver..."
  & node @args
  exit $LASTEXITCODE
} finally {
  Pop-Location
}
