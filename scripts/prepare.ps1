# Windows wrapper for scripts/prepare.sh, using the bash that ships with
# Git for Windows. Same arguments: an optional destination directory.
$ErrorActionPreference = 'Stop'
$bash = Join-Path (Split-Path (Split-Path (Get-Command git).Source)) 'bin\bash.exe'
if (-not (Test-Path $bash)) { throw "bash.exe not found next to git ($bash). Install Git for Windows." }
& $bash (Join-Path $PSScriptRoot 'prepare.sh') @args
exit $LASTEXITCODE
