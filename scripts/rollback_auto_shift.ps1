# Rollback of the intercity auto-shift (autoUpdateDepartureTime).
#
# What it does: deploys the PRE-FEATURE source of that ONE function (by name)
# from a temporary git worktree at -BaseCommit (default aface01 = the commit
# before the feature), then removes the worktree. It does not touch other
# functions, rules, hosting or data.
#
# What it does NOT undo (by design, no data migration needed):
#   - listings / bookings already shifted keep their new time;
#   - docs in intercity_auto_shifts (server-only counters) and taxi_reschedules
#     (audit, source=auto_shift) stay as history.
#
# Note: the pre-feature function read intercity_drivers.departureTime, which
# nothing writes, so after rollback auto-shift simply does nothing again.
#
# Usage (from anywhere):
#   powershell -File scripts\rollback_auto_shift.ps1 -DryRun   # prepare + verify, no deploy
#   powershell -File scripts\rollback_auto_shift.ps1           # deploy the rollback
param(
  [string]$BaseCommit = 'aface01',
  [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$Main = Split-Path -Parent $PSScriptRoot
$Work = Join-Path $env:TEMP ('ava-rollback-' + [guid]::NewGuid().ToString('N').Substring(0, 8))

Push-Location $Main
try {
  git rev-parse --verify "$BaseCommit^{commit}" | Out-Null
  git worktree add --detach $Work $BaseCommit | Out-Null

  # Gitignored runtime files the CLI needs for discovery (never printed).
  cmd /c mklink /J "$Work\functions\node_modules" "$Main\functions\node_modules" | Out-Null
  if (Test-Path "$Main\functions\.env") { Copy-Item "$Main\functions\.env" "$Work\functions\.env" }

  $src = Get-Content "$Work\functions\index.js" -Raw
  if ($src -match 'intercity_auto_shift') { throw "BaseCommit $BaseCommit already contains the feature" }
  if ($src -notmatch 'exports\.autoUpdateDepartureTime') { throw 'old autoUpdateDepartureTime not found in BaseCommit' }
  Write-Host "Worktree ready at $BaseCommit : old function source verified."

  if ($DryRun) { Write-Host 'DryRun: nothing deployed.'; return }

  $env:FUNCTIONS_DISCOVERY_TIMEOUT = '60'
  firebase deploy --only functions:default:autoUpdateDepartureTime --config "$Work\firebase.json"
  if ($LASTEXITCODE -ne 0) { throw "deploy failed (exit $LASTEXITCODE)" }
  Write-Host 'Rollback deployed. Verify: firebase functions:log --only autoUpdateDepartureTime -n 5'
}
finally {
  if (Test-Path "$Work\functions\node_modules") { cmd /c rmdir "$Work\functions\node_modules" | Out-Null }
  if (Test-Path $Work) { git worktree remove --force $Work | Out-Null }
  Pop-Location
}
