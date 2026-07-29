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
Write-Host ('Published. Copied: ' + $copied.Count + ' file(s). Pages will update in ~1-2 min.')
Write-Host 'URL: https://lolopodcast.github.io/daily-brief/'
