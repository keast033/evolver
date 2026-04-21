param(
  [string]$ProjectId = "big-a",
  [ValidateSet("loop", "run", "review")]
  [string]$Mode = "loop",
  [ValidateSet("balanced", "innovate", "harden", "repair-only")]
  [string]$Strategy = "balanced",
  [switch]$DisableOpenClawMirror,
  [switch]$ListProjects,
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# One-file multi-project registry.
# Handover rule:
# 1) Copy one block.
# 2) Update project_id/repo_root/memory_dir.
# 3) Run with -ProjectId <project_id>.
$Projects = @(
  @{
    project_id = "big-a"
    repo_root = "E:\git project\evolver\evolver"
    memory_dir = "E:\git project\evolver\evolver\memory"
    cursor_project_id = "e-bigA-big-a"
    agent_name = "main"
    notes = "default profile"
  },
  @{
    project_id = "demo"
    repo_root = "E:\git project\evolver\evolver"
    memory_dir = "E:\git project\evolver\evolver\memory"
    cursor_project_id = ""
    agent_name = "main"
    notes = "copy this block for new project"
  }
)

function Write-Info([string]$Message) {
  Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Ok([string]$Message) {
  Write-Host "[OK]   $Message" -ForegroundColor Green
}

function Write-WarnLine([string]$Message) {
  Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Resolve-Project([string]$Id) {
  $hits = @($Projects | Where-Object { $_.project_id -eq $Id })
  if ($hits.Count -ne 1) {
    return $null
  }
  return $hits[0]
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

function Build-OpenClawSessionsDir([string]$AgentName) {
  if ([string]::IsNullOrWhiteSpace($AgentName)) {
    $AgentName = "main"
  }
  $userHomeDir = [Environment]::GetFolderPath("UserProfile")
  return Join-Path $userHomeDir ".openclaw\agents\$AgentName\sessions"
}

if ($ListProjects) {
  Write-Host "Available projects:"
  foreach ($p in $Projects) {
    $desc = if ([string]::IsNullOrWhiteSpace($p.notes)) { "" } else { " - $($p.notes)" }
    Write-Host "  - $($p.project_id)$desc"
  }
  exit 0
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

$project = Resolve-Project -Id $ProjectId
if (-not $project) {
  Write-Error "ProjectId '$ProjectId' not found. Run with -ListProjects to check available IDs."
  exit 2
}

$repoRoot = $project.repo_root
$memoryDir = $project.memory_dir
$cursorProjectId = $project.cursor_project_id
$agentName = $project.agent_name

if ([string]::IsNullOrWhiteSpace($repoRoot)) {
  Write-Error "repo_root is empty for project '$ProjectId'"
  exit 2
}

if (-not (Test-Path -LiteralPath $repoRoot)) {
  Write-Error "repo_root does not exist: $repoRoot"
  exit 2
}

$entryFile = Join-Path $repoRoot "index.js"
if (-not (Test-Path -LiteralPath $entryFile)) {
  Write-Error "index.js not found: $entryFile"
  exit 2
}

Ensure-Directory -PathValue $memoryDir -Label "memory_dir"
$bridgeDir = Join-Path $memoryDir "cursor-session-bridge"
Ensure-Directory -PathValue $bridgeDir -Label "bridge_dir"

$openClawSessionsDir = Build-OpenClawSessionsDir -AgentName $agentName
Ensure-Directory -PathValue $openClawSessionsDir -Label "openclaw_sessions_dir"

Push-Location $repoRoot
try {
  $isGitRepo = $false
  try {
    $probe = git rev-parse --is-inside-work-tree 2>$null
    $isGitRepo = ($LASTEXITCODE -eq 0 -and "$probe".Trim() -eq "true")
  } catch {
    $isGitRepo = $false
  }
  if (-not $isGitRepo) {
    Write-Error "repo_root is not a git work tree: $repoRoot"
    exit 2
  }

  $env:EVOLVE_STRATEGY = $Strategy
  $env:EVOLVER_SESSION_LOGS_DIR = $bridgeDir
  $env:AGENT_SESSIONS_DIR = $openClawSessionsDir
  if (-not [string]::IsNullOrWhiteSpace($cursorProjectId)) {
    $env:EVOLVER_CURSOR_PROJECT_ID = $cursorProjectId
  }
  if ($DisableOpenClawMirror) {
    $env:EVOLVER_DISABLE_OPENCLAW_MIRROR = "1"
  } else {
    $env:EVOLVER_DISABLE_OPENCLAW_MIRROR = "0"
  }

  $args = @("index.js")
  switch ($Mode) {
    "loop" { $args += "--loop" }
    "run" { }
    "review" { $args += "--review" }
  }

  Write-Info "Project            : $ProjectId"
  Write-Info "Repo root          : $repoRoot"
  Write-Info "Memory dir         : $memoryDir"
  Write-Info "Bridge logs dir    : $bridgeDir"
  Write-Info "OpenClaw sessions  : $openClawSessionsDir"
  Write-Info "Strategy           : $Strategy"
  Write-Info "Mode               : $Mode"
  Write-Info "Disable OC mirror  : $($env:EVOLVER_DISABLE_OPENCLAW_MIRROR)"
  if (-not [string]::IsNullOrWhiteSpace($cursorProjectId)) {
    Write-Info "Cursor project id  : $cursorProjectId"
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
