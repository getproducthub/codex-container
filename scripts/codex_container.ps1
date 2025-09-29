[CmdletBinding(DefaultParameterSetName = 'Run')]
param(
    [switch]$Install,
    [switch]$Login,
    [switch]$Run,
    [string[]]$Exec,
    [switch]$Shell,
    [switch]$Push,
    [string]$Tag = 'gnosis/codex-service:dev',
[string]$Workspace,
[string]$CodexHome,
[string[]]$CodexArgs,
    [switch]$SkipUpdate,
    [switch]$NoAutoLogin,
    [switch]$Json,
    [switch]$JsonE
)

$ErrorActionPreference = 'Stop'

function Resolve-WorkspacePath {
    param(
        [string]$Workspace,
        [string]$CodexRoot,
        [System.Management.Automation.PathInfo]$CurrentLocation
    )

    if ($Workspace) {
        if ([System.IO.Path]::IsPathRooted($Workspace)) {
            try {
                return (Resolve-Path -LiteralPath $Workspace).ProviderPath
            } catch {
                throw "Workspace path '$Workspace' could not be resolved"
            }
        }

        $candidatePaths = @(
            Join-Path $CurrentLocation.ProviderPath $Workspace,
            Join-Path $CodexRoot $Workspace
        )

        foreach ($candidate in $candidatePaths) {
            if (Test-Path $candidate) {
                return (Resolve-Path -LiteralPath $candidate).ProviderPath
            }
        }

        throw "Workspace path '$Workspace' could not be resolved relative to $($CurrentLocation.ProviderPath) or $CodexRoot"
    }

    return $CurrentLocation.ProviderPath
}

function Resolve-CodexHomePath {
    param(
        [string]$Override
    )

    $candidate = $Override

    if (-not $candidate -and $env:CODEX_CONTAINER_HOME) {
        $candidate = $env:CODEX_CONTAINER_HOME
    }

    if (-not $candidate) {
        $userProfile = [Environment]::GetFolderPath('UserProfile')
        if (-not $userProfile) {
            $userProfile = $HOME
        }
        if (-not $userProfile) {
            throw 'Unable to determine a user profile directory for Codex home.'
        }
        $candidate = Join-Path $userProfile '.codex-service'
    }

    try {
        return (Resolve-Path -LiteralPath $candidate -ErrorAction Stop).ProviderPath
    } catch [System.Management.Automation.ItemNotFoundException] {
        return [System.IO.Path]::GetFullPath($candidate)
    }
}

function New-CodexContext {
    param(
        [string]$Tag,
        [string]$Workspace,
        [string]$ScriptRoot,
        [string]$CodexHomeOverride
    )

    $scriptDir = if ($ScriptRoot) { $ScriptRoot } else { throw "ScriptRoot is required" }
    $codexRoot = Resolve-Path (Join-Path $scriptDir '..')
    $currentLocation = Get-Location
    $dockerfilePath = Join-Path $codexRoot 'Dockerfile'

    if (-not (Test-Path $dockerfilePath)) {
        throw "Dockerfile not found at $dockerfilePath. Build artifacts may be missing."
    }

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'docker command not found. Install Docker Desktop or CLI and ensure it is on PATH.'
    }

    $workspacePath = Resolve-WorkspacePath -Workspace $Workspace -CodexRoot $codexRoot -CurrentLocation $currentLocation

    $codexHome = Resolve-CodexHomePath -Override $CodexHomeOverride
    if (-not (Test-Path $codexHome)) {
        New-Item -ItemType Directory -Path $codexHome -Force | Out-Null
    }

    $runArgs = @(
        'run',
        '--rm',
        '-it',
        '-p', '1455:1455',
        '-v', ("${codexHome}:/opt/codex-home"),
        '-e', 'HOME=/opt/codex-home',
        '-e', 'XDG_CONFIG_HOME=/opt/codex-home'
    )

    if ($workspacePath) {
        $runArgs += @('-v', ("${workspacePath}:/workspace"), '-w', '/workspace')
    }

    return [PSCustomObject]@{
        Tag = $Tag
        CodexRoot = $codexRoot
        CodexHome = $codexHome
        WorkspacePath = $workspacePath
        CurrentLocation = $currentLocation.ProviderPath
        RunArgs = $runArgs
    }
}

function Invoke-DockerBuild {
    param(
        $Context,
        [switch]$PushImage
    )

    $dockerfilePath = Join-Path $Context.CodexRoot 'Dockerfile'

    Write-Host 'Checking Docker daemon...' -ForegroundColor DarkGray
    docker info --format '{{.ID}}' 1>$null 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw 'Docker daemon not reachable. Start Docker Desktop (or the Docker service) and retry.'
    }

    Write-Host "Building Codex service image" -ForegroundColor Cyan
    Write-Host "  Dockerfile: $dockerfilePath" -ForegroundColor DarkGray
    Write-Host "  Tag:        $($Context.Tag)" -ForegroundColor DarkGray

    $buildArgs = @(
        'build',
        '-f', (Resolve-Path $dockerfilePath),
        '-t', $Context.Tag,
        (Resolve-Path $Context.CodexRoot)
    )

    docker @buildArgs

    if ($LASTEXITCODE -ne 0) {
        throw "docker build failed with exit code $LASTEXITCODE"
    }

    if ($PushImage) {
        Write-Host "Pushing image $($Context.Tag)" -ForegroundColor Cyan
        docker push $Context.Tag
        if ($LASTEXITCODE -ne 0) {
            throw "docker push failed with exit code $LASTEXITCODE"
        }
    }

    Write-Host 'Build complete.' -ForegroundColor Green
}

function Test-DockerImageExists {
    param(
        [string]$Tag
    )

    try {
        $null = docker image inspect $Tag 2>$null
        return $true
    } catch {
        return $false
    }
}

function Ensure-DockerImage {
    param(
        [string]$Tag
    )

    if (-not (Test-DockerImageExists -Tag $Tag)) {
        Write-Host "Docker image '$Tag' not found locally." -ForegroundColor Yellow
        Write-Host "Run .\\scripts\\codex_container.ps1 -Install to build it first." -ForegroundColor Yellow
        return $false
    }

    return $true
}

function New-DockerRunArgs {
    param(
        $Context
    )

    $args = @($Context.RunArgs + $Context.Tag)
    return $args
}

function Invoke-CodexContainer {
    param(
        $Context,
        [string[]]$CommandArgs
    )

    $runArgs = New-DockerRunArgs -Context $Context
    if ($CommandArgs) {
        $runArgs += $CommandArgs
    }

    docker @runArgs
}

function ConvertTo-ShellScript {
    param(
        [string[]]$Commands
    )

    return ($Commands -join '; ')
}

$script:CodexUpdateCompleted = $false

function Ensure-CodexCli {
    param(
        $Context,
        [switch]$Force,
        [switch]$Silent
    )

    if ($SkipUpdate -and -not $Force) {
        return
    }

    if ($script:CodexUpdateCompleted -and -not $Force) {
        return
    }

$updateScript = @'
set -euo pipefail
export PATH="$PATH:/usr/local/share/npm-global/bin"
echo "Ensuring Codex CLI is up to date..."
if npm install -g @openai/codex@latest --prefer-online >/tmp/codex-install.log 2>&1; then
  echo "Codex CLI updated."
else
  echo "Failed to install Codex CLI; see /tmp/codex-install.log."
  cat /tmp/codex-install.log
  exit 1
fi
cat /tmp/codex-install.log
'@

    if ($Silent) {
        Invoke-CodexContainer -Context $Context -CommandArgs @('/bin/bash', '-lc', $updateScript) | Out-Null
    } else {
        Invoke-CodexContainer -Context $Context -CommandArgs @('/bin/bash', '-lc', $updateScript)
    }
    $script:CodexUpdateCompleted = $true
}

function Invoke-CodexLogin {
    param(
        $Context
    )

    Ensure-CodexCli -Context $Context

    $loginHostPath = Join-Path $Context.CodexRoot 'scripts/codex_login.sh'
    if (-not (Test-Path $loginHostPath)) {
        throw "Expected login helper script missing at $loginHostPath."
    }

    Invoke-CodexContainer -Context $Context -CommandArgs @('/bin/bash', '/workspace/scripts/codex_login.sh')
}

function Invoke-CodexRun {
    param(
        $Context,
        [string[]]$Arguments,
        [switch]$Silent
    )

    Ensure-CodexCli -Context $Context -Silent:$Silent

    $cmd = @('codex')
    if ($Arguments) {
        $cmd += $Arguments
    }

    Invoke-CodexContainer -Context $Context -CommandArgs $cmd
}

function Invoke-CodexExec {
    param(
        $Context,
        [string[]]$Arguments
    )

    if (-not $Arguments) {
        throw 'Exec requires at least one argument to forward to codex.'
    }
    $cmdArguments = if ($Arguments[0] -eq 'exec') {
        $Arguments
    } else {
        @('exec') + $Arguments
    }

    $injectedFlags = @()
    if (-not ($cmdArguments -contains '--skip-git-repo-check')) {
        $injectedFlags += '--skip-git-repo-check'
    }

    if ($JsonE -and -not ($cmdArguments -contains '--experimental-json')) {
        $injectedFlags += '--experimental-json'
    } elseif ($Json -and -not ($cmdArguments -contains '--json')) {
        $injectedFlags += '--json'
    }

    if ($injectedFlags.Count -gt 0) {
        $first = $cmdArguments[0]
        $rest = @()
        if ($cmdArguments.Length -gt 1) {
            $rest = $cmdArguments[1..($cmdArguments.Length - 1)]
        }
        $cmdArguments = @($first) + $injectedFlags + $rest
    }

    Invoke-CodexRun -Context $Context -Arguments $cmdArguments -Silent:($Json -or $JsonE)
}

function Invoke-CodexShell {
    param(
        $Context
    )

    Ensure-CodexCli -Context $Context
    Invoke-CodexContainer -Context $Context -CommandArgs @('/bin/bash')
}

function Test-CodexAuthenticated {
    param(
        $Context
    )

    $authPath = Join-Path $Context.CodexHome '.codex/auth.json'
    if (-not (Test-Path $authPath)) {
        return $false
    }

    try {
        $content = Get-Content -LiteralPath $authPath -Raw -ErrorAction Stop
        return ($content.Trim().Length -gt 0)
    } catch {
        return $false
    }
}

function Ensure-CodexAuthentication {
    param(
        $Context,
        [switch]$Silent
    )

    if (Test-CodexAuthenticated -Context $Context) {
        return
    }

    if ($Silent) {
        throw 'Codex credentials not found. Re-run with -Login to authenticate.'
    }

    if ($NoAutoLogin) {
        throw 'Codex credentials not found. Re-run with -Login to authenticate.'
    }

    Write-Host 'No Codex credentials detected; starting login flow...' -ForegroundColor Yellow
    Invoke-CodexLogin -Context $Context

    if (-not (Test-CodexAuthenticated -Context $Context)) {
        throw 'Codex login did not complete successfully. Please retry with -Login.'
    }
}

$actions = @()
if ($Install) { $actions += 'Install' }
if ($Login) { $actions += 'Login' }
if ($Shell) { $actions += 'Shell' }
if ($Exec) { $actions += 'Exec' }
if ($Run) { $actions += 'Run' }

if (-not $actions) {
    $actions = @('Run')
}

if ($actions.Count -gt 1) {
    throw "Specify only one primary action (choose one of -Install, -Login, -Run, -Exec, -Shell)."
}

$action = $actions[0]

$jsonOutput = $Json -or $JsonE

$jsonFlagsSpecified = @()
if ($Json) { $jsonFlagsSpecified += '-Json' }
if ($JsonE) { $jsonFlagsSpecified += '-JsonE' }
if ($jsonFlagsSpecified.Count -gt 1) {
    throw "Specify only one of $($jsonFlagsSpecified -join ', ')."
}

$context = New-CodexContext -Tag $Tag -Workspace $Workspace -ScriptRoot $PSScriptRoot -CodexHomeOverride $CodexHome

if (-not $jsonOutput) {
    Write-Host "Codex container context" -ForegroundColor Cyan
    Write-Host "  Image:      $Tag" -ForegroundColor DarkGray
    Write-Host "  Codex home: $($context.CodexHome)" -ForegroundColor DarkGray
    Write-Host "  Workspace:  $($context.WorkspacePath)" -ForegroundColor DarkGray
}

if ($action -ne 'Install') {
    if (-not (Ensure-DockerImage -Tag $context.Tag)) {
        return
    }
}

switch ($action) {
    'Install' {
        Invoke-DockerBuild -Context $context -PushImage:$Push
        Ensure-CodexCli -Context $context -Force
    }
    'Login' {
        Invoke-CodexLogin -Context $context
    }
    'Shell' {
        Invoke-CodexShell -Context $context
    }
    'Exec' {
        Ensure-CodexAuthentication -Context $context -Silent:($Json -or $JsonE)
        Invoke-CodexExec -Context $context -Arguments $Exec
    }
    default { # Run
        Ensure-CodexAuthentication -Context $context -Silent:($Json -or $JsonE)
        Invoke-CodexRun -Context $context -Arguments $CodexArgs -Silent:($Json -or $JsonE)
    }
}
