# DailyBrief 專案筆記

晨報閱讀站（公開）：https://lolopodcast.github.io/daily-brief/ ｜ repo：lolopodcast/daily-brief（public）

## 發布流程（半自動，使用者審後放行）

1. heartbeat 每日將 `Brief_YYYYMMDD.md` 寫入 `ReviewInbox\_reports\briefings\`（不自動發布）
2. 使用者審閱後，雙擊本資料夾的 `publish-brief.cmd`（或對 Claude 說「發布晨報」）
3. 腳本以確定性程式碼複製新晨報 → 重建 `briefs/manifest.json` → commit → push → Pages 自動部署

## 快取規則（與教材站不同！）

`sw.js` 的 `CACHE_NAME` 目前是 **`brief-shell-v3`**（2026-07-29 補上智慧型前端防禦：文字可選、Ctrl+P/S 開放、圖片與空白處右鍵攔截＋版權提示、F12 系列攔截）。晨報內容（`briefs/` 底下）走 **network-first**，**每日新增內容不需要升版**；只有改動外殼（`index.html`、`manifest.json`、`icons/`、`sw.js` 本身）才要把版本號 +1。

## 語言鐵則

一律繁體台灣用語（架構≠框架、構面≠維度、策略≠戰略、總體≠宏觀、資訊≠信息、品質≠質量、最佳化≠優化；「收官」僅用於圍棋）。

## 設計備忘

- 決策建議節由閱讀器自動注入「非投資決策建議」提醒框（使用者決策：內容公開＋加註提醒）
- 訂閱派送（email/LINE）暫緩；日後若做，優先評估 Google 表單＋Apps Script 或 LINE OA
