<#
.SYNOPSIS
    Builds (and optionally publishes) the PHP 8.5 Wasmer package.

.DESCRIPTION
    Runs the PHP WASIX build inside the `wasmer-php-builder` container, stages the
    runtime in .\dist and packages it with the Wasmer CLI.

.PARAMETER Namespace
    Registry namespace of the package. Defaults to the logged in Wasmer user.

.PARAMETER PackageName
    Package name. Defaults to "php".

.PARAMETER PhpVersion
    Version of the PHP runtime, recorded in wasmer.toml.

.PARAMETER PhpBranch
    Branch of wasix-org/php carrying the WASIX patches.

.PARAMETER Port
    Force porting the WASIX patches onto the requested PHP version before building.
    It happens automatically when PhpBranch does not match PhpVersion.

.PARAMETER SkipBuild
    Reuse the artefacts already present in .\dist (do not run the container).

.PARAMETER Publish
    Publish the package to the Wasmer registry after building.

.PARAMETER DryRun
    Only validate the publish flow; nothing is uploaded.

.EXAMPLE
    .\build.ps1
    .\build.ps1 -Publish
    .\build.ps1 -SkipBuild -Publish -DryRun
#>
[CmdletBinding()]
param(
    [string] $Namespace = '',
    [string] $PackageName = 'php',
    [string] $PhpVersion = '8.5.10',
    [string] $PhpBranch = '8.5.7-wasix',
    [string] $ImageName = 'wasmer-php-builder:8.5',
    [switch] $Port,
    [switch] $SkipBuild,
    [switch] $Publish,
    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

function Write-Step([string] $Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Invoke-External([string] $Command, [string[]] $Arguments) {
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "'$Command $($Arguments -join ' ')' failed with exit code $LASTEXITCODE."
    }
}

if (-not (Get-Command wasmer -ErrorAction SilentlyContinue)) {
    throw 'The wasmer CLI is required: https://docs.wasmer.io/install'
}

if ($Namespace -eq '') {
    $whoami = (& wasmer whoami 2>$null | Select-Object -Last 1)
    $Namespace = ($whoami -split '\s+')[-1]
}

if ($Namespace -eq '') {
    throw 'Unable to detect the registry namespace; pass -Namespace explicitly.'
}

# wasix-org/php only branches the versions the Wasmer team released; a newer upstream
# patch release is built by porting the WASIX overlay onto php-src first.
$portOverlay = $Port -or ($PhpBranch -notlike "$PhpVersion-*")

if (-not $SkipBuild) {
    Write-Step "Building the build image ($ImageName)"

    # `wasixccenv download-*` resolves release assets over api.github.com; a token avoids
    # the anonymous rate limit (see docker/Dockerfile). Optional for local builds.
    $secretArguments = @()
    if ($env:GITHUB_TOKEN -or $env:GH_TOKEN) {
        if (-not $env:GITHUB_TOKEN) { $env:GITHUB_TOKEN = $env:GH_TOKEN }
        $secretArguments = @('--secret', 'id=github_token,env=GITHUB_TOKEN')
    }

    Invoke-External docker (@('build', '--tag', $ImageName) + $secretArguments + @((Join-Path $root 'docker')))

    if ($portOverlay) {
        Write-Step "Porting the WASIX overlay from $PhpBranch onto PHP $PhpVersion"
        Invoke-External docker @(
            'run', '--rm',
            '--volume', "${root}:/work",
            '--workdir', '/work',
            '--env', "PHP_VERSION=$PhpVersion",
            '--env', "PHP_BASE_BRANCH=$PhpBranch",
            '--env', 'FORCE=1',
            $ImageName,
            'bash', 'scripts/port-wasix-version.sh'
        )
    }

    Write-Step "Compiling PHP $PhpVersion for WASIX"
    $compileArguments = @(
        'run', '--rm',
        '--volume', "${root}:/work",
        '--volume', 'wasix-sources:/src',
        '--workdir', '/work',
        '--env', "PHP_BRANCH=$PhpBranch",
        '--env', "PHP_VERSION=$PhpVersion"
    )

    if ($portOverlay) {
        $compileArguments += @('--env', "PHP_SOURCE_DIR=/work/.work/php-$PhpVersion")
    }

    $compileArguments += @($ImageName, 'bash', 'scripts/build-runtime.sh')
    Invoke-External docker $compileArguments
}

if (-not (Test-Path (Join-Path $root 'dist/modules/php'))) {
    throw 'dist/modules/php is missing: run without -SkipBuild first.'
}

Write-Step "Packaging $Namespace/$PackageName@$PhpVersion"
$manifest = Get-Content -Raw (Join-Path $root 'package/wasmer.toml')
$manifest = $manifest.Replace('__NAMESPACE__', $Namespace).Replace('__PACKAGE_NAME__', $PackageName).Replace('__VERSION__', $PhpVersion)
[IO.File]::WriteAllText((Join-Path $root 'dist/wasmer.toml'), $manifest)
Copy-Item (Join-Path $root 'package/README.md') (Join-Path $root 'dist/README.md') -Force
Copy-Item (Join-Path $root 'package/LICENSE.txt') (Join-Path $root 'dist/LICENSE') -Force

$outDirectory = Join-Path $root 'build'
New-Item -ItemType Directory -Force $outDirectory | Out-Null
$webc = Join-Path $outDirectory "$PackageName-$PhpVersion.webc"

# `wasmer package build` refuses to overwrite an existing artefact.
if (Test-Path -LiteralPath $webc) {
    Remove-Item -LiteralPath $webc -Force
}

Invoke-External wasmer @('package', 'build', (Join-Path $root 'dist'), '--out', $webc)
Write-Host "Package written to $webc" -ForegroundColor Green

if ($Publish) {
    if ($DryRun) {
        # `wasmer publish --dry-run` cannot tag a version that is not on the registry yet, so
        # validate the package locally instead: `--check` runs the whole packaging flow.
        Write-Step 'Validating the package (dry run)'
        Invoke-External wasmer @('package', 'build', (Join-Path $root 'dist'), '--check')
        Write-Host 'Dry run succeeded: the package builds, nothing was uploaded.' -ForegroundColor Green
    } else {
        Write-Step 'Publishing to the Wasmer registry'
        Invoke-External wasmer @('publish', (Join-Path $root 'dist'), '--non-interactive')
        Write-Host "Published $Namespace/$PackageName@$PhpVersion" -ForegroundColor Green
    }
}