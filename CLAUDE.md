# DailyBrief 專案筆記

晨報閱讀站（公開）：https://lolopodcast.github.io/daily-brief/ ｜ repo：lolopodcast/daily-brief（public）

## 發布流程（半自動，使用者審後放行）

1. heartbeat 每日將 `Brief_YYYYMMDD.md` 寫入 `ReviewInbox\_reports\briefings\`（不自動發布）
2. 使用者審閱後，雙擊本資料夾的 `publish-brief.cmd`（或對 Claude 說「發布晨報」）
3. 腳本以確定性程式碼複製新晨報 → 重建 `briefs/manifest.json` → commit → push → 建置 → 上線

### 三個確認點（2026-08-16 補強，因為每一個都真的失敗過）

腳本不以「指令有沒有報錯」判斷成敗，一律**比對產物**：

| 環節 | 確認方式 | 失敗時的行為 |
| :--- | :--- | :--- |
| 推送 | **比對遠端 SHA 是否等於本機** | 自動重試一次；仍失敗則印「推送失敗，晨報沒有上線」並以退出碼 1 結束 |
| 建置 | 輪詢建置狀態（最多 6 分鐘） | 卡在 building **或停在舊 commit** 都會重新觸發一次 |
| 上線 | 回讀線上 `manifest.json` 是否含最新一期 | 未確認就印 `*** NOT CONFIRMED LIVE ***`，並說明重跑即可、內容不會遺失 |

**推送失敗不會遺失任何東西**——commit 已在本機，網路恢復後重跑腳本會直接推送既有 commit。

### 改這支腳本時的兩個地雷

- **`$ErrorActionPreference` 的位置**：若在 push 之前設為 `Stop`，git 寫入標準錯誤會被當成終止錯誤，**後面整段驗證完全不會執行**（2026-08-16 就是這樣失敗的）。驗證區段之前必須先設回 `Continue`。
- **含中文的 `.ps1` 必須存成 UTF-8 with BOM**：PowerShell 5.1 讀無 BOM 的檔案會當成 ANSI，中文變亂碼導致解析失敗。用 `[System.IO.File]::WriteAllText($p, $text, (New-Object System.Text.UTF8Encoding $true))` 寫回。

## 快取規則（與教材站不同！）

`sw.js` 的 `CACHE_NAME` 目前是 **`brief-shell-v12`**（2026-08-07 語音導覽：播完回到本次朗讀範圍的起點）。晨報內容（`briefs/` 底下）走 **network-first**，**每日新增內容不需要升版**；只有改動外殼（`index.html`、`manifest.json`、`icons/`、`sw.js` 本身）才要把版本號 +1。

> ⚠️ 本行一度停在 `v3` 而實際已是 `v12`（2026-08-08 發現）。**改 `sw.js` 時要同時更新這裡**，否則這份筆記會從「記錄」退化成「誤導」。

## 中文用語規則

**完整對照表在 `~/.claude/CLAUDE.md` 的「中文用語規則」一節**——此處不複製，避免兩份各自演化。

晨報特有的一點：**巡檢來源與引述的原文若本身是簡體或中國用語，照實引用不改寫**（那是被引用的事實）；規則約束的是本站自己的敘述文字。

## 設計備忘

- 決策建議節由閱讀器自動注入「非投資決策建議」提醒框（使用者決策：內容公開＋加註提醒）
- 訂閱派送（email/LINE）暫緩；日後若做，優先評估 Google 表單＋Apps Script 或 LINE OA
