$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

$Project = "C:\Users\KENAAR\Documents\Codex\2026-10-13\create-a-new-github-repository-named\work\pharos-dapp-support-agent"
$Repo = "shoupeorg/pharos-dapp-support-agent"
$RepoUrl = "https://github.com/shoupeorg/pharos-dapp-support-agent.git"
$RepoPage = "https://github.com/shoupeorg/pharos-dapp-support-agent"
$CreateRepo = "https://github.com/new?owner=shoupeorg&name=pharos-dapp-support-agent&visibility=public"
$DbName = "pharos-dapp-support-agent"
$Demo = "https://pharos-dapp-support-agent.shoupeorg.workers.dev"

function Check([string]$Operation, [int]$Code) {
    if ($Code -ne 0) {
        throw "$Operation failed with exit code $Code."
    }
}

function WranglerJson([string[]]$Arguments, [string]$Operation) {
    $output = & npx wrangler @Arguments 2>&1
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        throw "$Operation failed with exit code $code.`n$($output -join "`n")"
    }

    try {
        return (($output -join "`n") | ConvertFrom-Json)
    }
    catch {
        throw "$Operation returned invalid JSON: $($_.Exception.Message)"
    }
}

if (-not (Test-Path -LiteralPath $Project -PathType Container)) {
    throw "Project directory is missing: $Project"
}

Set-Location -LiteralPath $Project

Write-Host "==> Verify Wrangler authentication"
& npx wrangler whoami
if ($LASTEXITCODE -ne 0) {
    Write-Host "Opening the normal Wrangler login flow..."
    & npx wrangler login
    Check "Wrangler login" $LASTEXITCODE

    & npx wrangler whoami
    Check "Wrangler authentication verification" $LASTEXITCODE
}

Write-Host "==> Reuse or create the exact D1 database"
$databases = @(WranglerJson @("d1", "list", "--json") "D1 list")
$matches = @($databases | Where-Object { $_.name -eq $DbName })

if ($matches.Count -gt 1) {
    throw "Multiple D1 databases are named $DbName; refusing to guess."
}

if ($matches.Count -eq 0) {
    & npx wrangler d1 create $DbName
    Check "D1 database creation" $LASTEXITCODE

    $databases = @(WranglerJson @("d1", "list", "--json") "D1 list after creation")
    $matches = @($databases | Where-Object { $_.name -eq $DbName })

    if ($matches.Count -ne 1) {
        throw "D1 creation succeeded, but the exact database could not be resolved."
    }
}

$database = $matches[0]
$databaseId = @(
    $database.uuid
    $database.id
    $database.database_id
) | Where-Object {
    $_ -is [string] -and $_ -match '^[0-9a-fA-F-]{36}$'
} | Select-Object -First 1

if (-not $databaseId) {
    throw "The D1 UUID was absent from Wrangler's successful JSON response."
}

Write-Host "==> Configure the DB binding"
$wranglerPath = Join-Path $Project "wrangler.jsonc"
$configuration = Get-Content -LiteralPath $wranglerPath -Raw | ConvertFrom-Json
$binding = @($configuration.d1_databases | Where-Object { $_.binding -eq "DB" })

if ($binding.Count -ne 1) {
    throw "Expected exactly one D1 binding named DB."
}

$binding[0].database_name = $DbName
$binding[0].database_id = $databaseId

$utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText(
    $wranglerPath,
    ($configuration | ConvertTo-Json -Depth 20),
    $utf8
)

Write-Host "==> Apply pending D1 migrations"
& npx wrangler d1 migrations apply $DbName --remote
Check "Remote D1 migration" $LASTEXITCODE

Write-Host "==> Deploy the already-tested production bundle"
$deployOutput = & npx wrangler deploy --no-bundle 2>&1
$deployCode = $LASTEXITCODE

if ($deployCode -ne 0) {
    throw "Deployment failed with exit code $deployCode.`n$($deployOutput -join "`n")"
}

$deployOutput | ForEach-Object { Write-Host $_ }
$deployText = $deployOutput -join "`n"
$versionMatch = [regex]::Match(
    $deployText,
    '(?im)(?:Current\s+)?Version\s+ID:\s*([0-9a-f-]{36})'
)
$deploymentVersion = if ($versionMatch.Success) {
    $versionMatch.Groups[1].Value
} else {
    "UNKNOWN"
}

Write-Host "==> Verify public UI and assets"
$page = Invoke-WebRequest -UseBasicParsing -Uri "$Demo/" -TimeoutSec 30
if (
    $page.StatusCode -ne 200 -or
    $page.Headers["Content-Type"] -notmatch "text/html" -or
    $page.Content -notmatch "Pharos dApp Support Agent" -or
    $page.Content -notmatch "Analyze Transaction"
) {
    throw "Public UI verification failed."
}

$logo = Invoke-WebRequest -UseBasicParsing -Uri "$Demo/pharos-logo.png" -TimeoutSec 30
if ($logo.StatusCode -ne 200 -or $logo.Headers["Content-Type"] -notmatch "image/") {
    throw "Public Pharos logo verification failed."
}

$css = Invoke-WebRequest -UseBasicParsing -Uri "$Demo/support.css" -TimeoutSec 30
if (
    $css.StatusCode -ne 200 -or
    $css.Content -notmatch "#0210ff" -or
    $css.Content -notmatch '@media\(max-width:700px\)'
) {
    throw "Public responsive stylesheet verification failed."
}

$meta = Invoke-RestMethod -Uri "$Demo/api/meta" -TimeoutSec 30
if (
    $meta.engineVersion -ne "dapp-support/1.0.0" -or
    [int]$meta.network.chainId -ne 1672 -or
    @($meta.examples).Count -ne 3 -or
    -not $meta.officialMcpRuntime
) {
    throw "Public API metadata verification failed."
}

Write-Host "==> Verify three real analyses, D1, exports and explorer links"
$examples = @(
    @{
        Hash = "0xfd9e2b56afea04980e35d9627e6ab822a8b4f73fd1859b4bc953784fb95bf5b4"
        Code = "SLIPPAGE_GUARD"
    },
    @{
        Hash = "0x2a60f5f0f636777e26661f6cc6c496494af4b118e31fcd23162f6988fc48e652"
        Code = "ZERO_INPUT_TOKEN_BALANCE"
    },
    @{
        Hash = "0x77a9d42826280512c22c55c279720985e62365bc43c7c1b27bbe4d3eb1d55528"
        Code = "APPLICATION_INVARIANT"
    }
)

$verifiedReports = @()

foreach ($example in $examples) {
    $payload = @{ hash = $example.Hash } | ConvertTo-Json -Compress

    $report = Invoke-RestMethod `
        -Method Post `
        -Uri "$Demo/api/analyze" `
        -ContentType "application/json" `
        -Body $payload `
        -TimeoutSec 90

    if (
        $report.outcome -ne "FAILED" -or
        $report.diagnosisCode -ne $example.Code -or
        $report.requestedHash -ne $example.Hash -or
        [int]$report.network.chainId -ne 1672
    ) {
        throw "Public analysis mismatch for $($example.Hash)."
    }

    $officialCalls = @(
        $report.toolTrace |
        Where-Object { $_.service -eq "Official Pharos Chain MCP" }
    )

    if ($officialCalls.Count -lt 3) {
        throw "Required official MCP trace is missing for $($example.Hash)."
    }

    $jsonExport = Invoke-RestMethod `
        -Uri "$Demo/api/report/$($report.id).json" `
        -TimeoutSec 30

    $markdownExport = Invoke-WebRequest `
        -UseBasicParsing `
        -Uri "$Demo/api/report/$($report.id).md" `
        -TimeoutSec 30

    if (
        $jsonExport.id -ne $report.id -or
        $jsonExport.requestedHash -ne $report.requestedHash
    ) {
        throw "JSON export mismatch for report $($report.id)."
    }

    if (
        $markdownExport.Content -notmatch [regex]::Escape($report.requestedHash) -or
        $markdownExport.Content -notmatch [regex]::Escape($report.explanation)
    ) {
        throw "Markdown export mismatch for report $($report.id)."
    }

    $explorer = Invoke-WebRequest `
        -UseBasicParsing `
        -Uri $report.explorerUrl `
        -TimeoutSec 30

    if (
        $explorer.StatusCode -ne 200 -or
        $explorer.Content -notmatch $example.Hash.Substring(2, 16)
    ) {
        throw "Explorer verification failed for $($example.Hash)."
    }

    $verifiedReports += $report
}

$history = Invoke-RestMethod -Uri "$Demo/api/reports" -TimeoutSec 30
if (@($history.reports).Count -lt 3) {
    throw "D1 persistence verification failed."
}

Write-Host "==> Record verified deployment status"
$statusPath = Join-Path $Project "STATUS.md"
$status = Get-Content -LiteralPath $statusPath -Raw
$status += @"

## Published deployment

- Demo: $Demo
- Cloudflare version: $deploymentVersion
- D1 database: $DbName ($databaseId)
- Public UI, assets, API, three real analyses, D1 persistence, exports and explorer pages verified.
"@
[IO.File]::WriteAllText($statusPath, $status, $utf8)

Write-Host "==> Commit intended configuration"
git config --global --add safe.directory $Project
Check "Git safe.directory configuration" $LASTEXITCODE

git add -A
Check "Git add" $LASTEXITCODE

git diff --cached --quiet
$diffCode = $LASTEXITCODE

if ($diffCode -eq 1) {
    git commit -m "Configure and deploy Pharos dApp Support Agent"
    Check "Git commit" $LASTEXITCODE
}
elseif ($diffCode -ne 0) {
    throw "Git staged-diff check failed with exit code $diffCode."
}
else {
    Write-Host "Nothing to commit; intended tree is already committed."
}

Write-Host "==> Create or verify the public GitHub repository"
$gh = Get-Command gh -ErrorAction SilentlyContinue

if ($gh) {
    & gh repo view $Repo --json nameWithOwner,isPrivate 1>$null 2>$null
    if ($LASTEXITCODE -ne 0) {
        & gh repo create $Repo --public --source $Project
        Check "GitHub repository creation" $LASTEXITCODE
    }
}
else {
    try {
        $repoCheck = Invoke-WebRequest `
            -UseBasicParsing `
            -Uri $RepoPage `
            -TimeoutSec 30 `
            -ErrorAction Stop
    }
    catch {
        throw "gh is unavailable and the public repository was not found. Create Owner=shoupeorg, Name=pharos-dapp-support-agent, Visibility=Public, with no starter files: $CreateRepo"
    }

    if ($repoCheck.StatusCode -ne 200) {
        throw "Expected public repository is unavailable: $RepoPage"
    }
}

$remotes = @(git remote)
Check "Git remote list" $LASTEXITCODE

if ($remotes -contains "origin") {
    git remote set-url origin $RepoUrl
    Check "Git origin update" $LASTEXITCODE
}
else {
    git remote add origin $RepoUrl
    Check "Git origin creation" $LASTEXITCODE
}

Write-Host "==> Preserve remote history and publish main"
git fetch origin
Check "Git fetch" $LASTEXITCODE

git show-ref --verify --quiet refs/remotes/origin/main
$remoteMainCode = $LASTEXITCODE

if ($remoteMainCode -eq 0) {
    git merge-base --is-ancestor origin/main HEAD
    if ($LASTEXITCODE -ne 0) {
        throw "origin/main is not an ancestor of local HEAD; refusing to overwrite or force-push."
    }
}
elseif ($remoteMainCode -ne 1) {
    throw "Remote main inspection failed with exit code $remoteMainCode."
}

git push -u origin main
Check "Git push" $LASTEXITCODE

git fetch origin main
Check "Post-push fetch" $LASTEXITCODE

$localHead = (git rev-parse HEAD).Trim()
Check "Local HEAD resolution" $LASTEXITCODE

$remoteHead = (git rev-parse origin/main).Trim()
Check "Remote main resolution" $LASTEXITCODE

if ($localHead -ne $remoteHead) {
    throw "Publication mismatch: local=$localHead remote=$remoteHead"
}

$remoteFiles = @(git ls-tree -r --name-only origin/main)
Check "Remote tree inspection" $LASTEXITCODE

$requiredFiles = @(
    "README.md",
    "SKILL.md",
    "STATUS.md",
    "src/worker.js",
    "src/engine.js",
    "src/mcp.js",
    "public/index.html",
    "public/pharos-logo.png",
    "evidence/manifest.json",
    "migrations/0001_initial.sql",
    "scripts/resume-publish-deploy.ps1",
    "wrangler.jsonc"
)

foreach ($file in $requiredFiles) {
    if ($remoteFiles -notcontains $file) {
        throw "Required remote file is missing: $file"
    }
}

Write-Host ""
Write-Host "PUBLICATION AND DEPLOYMENT VERIFIED" -ForegroundColor Green
Write-Host "Demo: $Demo"
Write-Host "Repository: $RepoPage"
Write-Host "Commit: $localHead"
Write-Host "Cloudflare version: $deploymentVersion"
Write-Host "D1 database ID: $databaseId"
Write-Host "Verified reports: $($verifiedReports.Count)"