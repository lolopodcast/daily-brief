# Daily Brief semi-automatic publisher.
# Run AFTER reviewing the brief (double-click publish-brief.cmd or tell Claude).
# Steps: copy new/changed Brief_*.md from ReviewInbox -> briefs/, regenerate
# briefs/manifest.json, git commit + push (GitHub Pages auto-deploys).
$ErrorActionPreference = 'Stop'
$Src  = 'C:\Users\jimmy\Dropbox\ReviewInbox\_reports\briefings'
$Repo = 'C:\Users\jimmy\Dropbox\DailyBrief'
$Dst  = Join-Path $Repo 'briefs'

if (-not (Test-Path -LiteralPath $Dst)) { New-Item -ItemType Directory -Force $Dst | Out-Null }

# 1) copy new or changed briefs
$copied = @()
Get-ChildItem -LiteralPath $Src -Filter 'Brief_*.md' | ForEach-Object {
  $target = Join-Path $Dst $_.Name
  if (-not (Test-Path -LiteralPath $target) -or ((Get-Item -LiteralPath $target).Length -ne $_.Length)) {
    Copy-Item -LiteralPath $_.FullName -Destination $target -Force
    $copied += $_.Name
  }
}

# 2) regenerate manifest (newest first) -- deterministic code, not AI
$entries = Get-ChildItem -LiteralPath $Dst -Filter 'Brief_*.md' | Sort-Object Name -Descending | ForEach-Object {
  $d = $_.BaseName -replace '^Brief_(\d{4})(\d{2})(\d{2})$', '$1-$2-$3'
  [pscustomobject]@{ date = $d; file = $_.Name }
}
$json = @{ briefs = @($entries) } | ConvertTo-Json -Depth 3
[System.IO.File]::WriteAllText((Join-Path $Dst 'manifest.json'), $json, [System.Text.UTF8Encoding]::new($false))

# 3) commit + push
Set-Location $Repo
git add -A
$pending = git status --porcelain
if (-not $pending) { Write-Host 'Nothing new to publish.'; exit 0 }
$msg = 'Publish brief: ' + ($(if ($copied.Count) { $copied -join ', ' } else { 'manifest refresh' }))
git -c user.name="Shihmin Lo" -c user.email="smlo@ncnu.edu.tw" commit -q -m $msg
git push origin main
$head = (git rev-parse HEAD).Substring(0,7)
Write-Host ('Pushed ' + $head + '. Copied: ' + $copied.Count + ' file(s). Now verifying it actually goes live...')

# 4) VERIFY the build reaches the public site -- never just assume.
#    Observed three times (2026-07-30, 08-04, 08-07): the push succeeds but the
#    GitHub Pages build sits in "building" for hours, so the site silently keeps
#    serving the previous issue. Reporting "Published" at step 3 was an optimistic
#    marker: it announced an outcome nobody had confirmed. This step polls the
#    build, retriggers a stuck one, and finally reads the LIVE manifest back.
$ErrorActionPreference = 'Continue'   # a verification hiccup must not kill the run
# NOTE: pass jq expressions WITHOUT embedded quotes/spaces -- quoting them through
# PowerShell -> gh.exe on Windows mangles the expression. ".status,.commit" yields
# two plain lines, which needs no escaping at all.
function Get-BuildState {
  try {
    $r = @(gh api repos/lolopodcast/daily-brief/pages/builds/latest --jq .status,.commit 2>$null)
    if ($r.Count -ge 2) { return @{ status = $r[0]; commit = $r[1].Substring(0,7) } }
  } catch {}
  return $null
}
$newest = Get-ChildItem -LiteralPath $Dst -Filter 'Brief_*.md' | Sort-Object Name -Descending | Select-Object -First 1
$liveOk = $false
$retriggered = $false
$started = Get-Date
while (((Get-Date) - $started).TotalMinutes -lt 6) {
  Start-Sleep -Seconds 15
  $b = Get-BuildState
  if (-not $b) { Write-Host '  build: (status unavailable)'; continue }
  Write-Host ('  build: ' + $b.status + ' ' + $b.commit)
  if ($b.status -eq 'built' -and $b.commit -eq $head) {
    $live = (curl.exe -s ('https://lolopodcast.github.io/daily-brief/briefs/manifest.json?cb=' + (Get-Random))) -join ''
    if ($live -match [regex]::Escape($newest.Name)) { $liveOk = $true; break }
    Write-Host '  build done but live manifest still stale; waiting for CDN...'
  }
  elseif (-not $retriggered -and $b.status -eq 'building' -and ((Get-Date) - $started).TotalMinutes -ge 2) {
    Write-Host '  build stuck in "building" for 2+ min -> retriggering once'
    try { gh api repos/lolopodcast/daily-brief/pages/builds -X POST 2>&1 | Out-Null } catch {}
    $retriggered = $true
  }
}

if ($liveOk) {
  Write-Host ''
  Write-Host ('CONFIRMED LIVE: ' + $newest.Name + ' is being served at')
  Write-Host '  https://lolopodcast.github.io/daily-brief/'
} else {
  Write-Host ''
  Write-Host '*** NOT CONFIRMED LIVE ***'
  Write-Host ('The push succeeded (' + $head + ') but the site did not update within 6 minutes.')
  Write-Host 'The GitHub Pages build is probably stuck. Retry with:'
  Write-Host '  gh api repos/lolopodcast/daily-brief/pages/builds -X POST'
  Write-Host 'or just run this publisher again -- nothing is lost, the commit is already pushed.'
}
# NOTE: no Read-Host here on purpose -- publish-brief.cmd already pauses, and a
# prompt would block forever when this script is invoked non-interactively.
