[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [string]$CodexHome,
    [switch]$RemoveDockerImage,
    [string]$Tag = 'gnosis/codex-service:dev'
)

$ErrorActionPreference = 'Stop'

function Resolve-CodexHomePath {
    param([string]$Override)

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

$homePath = Resolve-CodexHomePath -Override $CodexHome

if (Test-Path $homePath) {
    if ($PSCmdlet.ShouldProcess($homePath, 'Remove Codex home directory')) {
        Remove-Item -LiteralPath $homePath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "Removed $homePath"
    }
} else {
    Write-Host "Codex home not found at $homePath"
}

if ($RemoveDockerImage) {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Warning 'docker command not found; skipping image removal.'
        return
    }
    if ($PSCmdlet.ShouldProcess($Tag, 'Remove Docker image')) {
        docker image rm $Tag | Out-String | ForEach-Object { if ($_){ Write-Host $_ } }
    }
}
