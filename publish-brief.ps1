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
$head = (git rev-parse HEAD).Substring(0,7)

# git 把進度寫到 stderr，在 ErrorActionPreference=Stop 之下會被當成終止錯誤，
# 讓後面整段驗證完全沒機會執行。2026-08-16 就是這樣：push 因網路暫時失敗，
# 腳本當場中止，本機有 commit、遠端沒有，而畫面上看不出發生了什麼。
$ErrorActionPreference = 'Continue'

function Get-RemoteHead {
    $r = git ls-remote origin main 2>$null
    if ($r) { return ($r -split "`t")[0].Substring(0,7) }
    return $null
}

# 推送是否成功，以「遠端 SHA 是否等於本機」為準，不看指令有沒有印錯誤——
# 這與確認後標記是同一個原則：驗證產物，不驗證動作。
$pushed = $false
foreach ($attempt in 1..2) {
    git push origin main 2>&1 | Out-Null
    if ((Get-RemoteHead) -eq $head) { $pushed = $true; break }
    if ($attempt -eq 1) { Write-Host '  推送未生效，10 秒後重試一次（多半是暫時性網路問題）...'; Start-Sleep -Seconds 10 }
}
if (-not $pushed) {
    Write-Host ''
    Write-Host '*** 推送失敗，晨報沒有上線 ***'
    Write-Host ("   本機已有 commit $head，遠端仍停在 " + (Get-RemoteHead))
    Write-Host '   內容不會遺失：網路恢復後再執行一次本腳本即可（會直接推送既有 commit）。'
    Write-Host ''
    exit 1
}
Write-Host ('已推送 ' + $head + '，複製 ' + $copied.Count + ' 個檔案。開始確認是否真的上線...')

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
  # 需要重新觸發的有兩種情況，先前只處理了第一種：
  #   (1) 卡在 building 太久
  #   (2) 顯示 built 但停在舊 commit —— 代表這次推送根本沒觸發建置
  elseif (-not $retriggered -and ((Get-Date) - $started).TotalMinutes -ge 1.5 -and
          ($b.status -eq 'building' -or ($b.status -eq 'built' -and $b.commit -ne $head))) {
    $why = if ($b.status -eq 'building') { '卡在 building' } else { "停在舊 commit $($b.commit)" }
    Write-Host "  建置$why -> 重新觸發一次"
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
