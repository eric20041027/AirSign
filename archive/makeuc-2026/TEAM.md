# AirSign 團隊協作指南（MakeUC 2026）

交件期限：**2026-11-08 12:00（美東時間）**。評審是同一天 13:00–16:00，在 Discord 上進行。

開工前先讀這兩份：
- 設計：[superpowers/specs/2026-11-07-airsign-design.md](superpowers/specs/2026-11-07-airsign-design.md)
- 計畫（10 個任務）：[superpowers/plans/2026-11-07-airsign.md](superpowers/plans/2026-11-07-airsign.md)

## 分工

| 角色 | 人和設備 | 負責什麼 | 負責的檔案（其他人不要改） |
|---|---|---|---|
| **A 核心** | 隊友 A + Claude Code，MacBook Pro，AirPods Pro 3 | 計畫的 Task 1–9：比對、加密、上鎖解鎖、讀 AirPods、註冊和解鎖流程（16:00 起 A 接手 Task 7 和簽名畫面元件） | `airsign/` 底下除了 B 那兩個檔案以外的全部 |
| **B Finder 與第二台 Mac** | 隊友 B + Antigravity，MacBook Air M1，AirPods 4 | Task 10（右鍵選單、安裝腳本）、第二台 Mac 的驗證、收集公平的模仿資料 | `airsign/Sources/AirSign/ServicesProvider.swift`、`airsign/scripts/install.sh` |
| **C 調校與交件** | 隊友 C + Claude Max，Windows 11 | 用 Python 調比對參數、Devpost 文案、簡報、demo 腳本、剪影片、填評審報名表 | `docs/tuning.md`、`docs/devpost.md`、`docs/demo-script.md`、`tools/tuning/` |

**跟計畫不同的地方**：計畫裡 Task 7 和 Task 10 會改到 `AirSignApp.swift`。為了避免衝突，B 把探測模式寫在 `ProbeMode.swift`、右鍵服務寫在 `ServicesProvider.swift`，再由 A 在 `AirSignApp.swift` 加一行呼叫。

**介面就是合約**：每個任務的 Interfaces 區塊寫了函式名稱和型別。要改介面，先在 Discord 說，對方同意再改。

## 時間表（美東時間）

| 時間 | A 核心 | B 硬體與 Finder | C 調校與交件 |
|---|---|---|---|
| 現在 – 16:30 | 推上專案骨架（Task 1） | 確認 `sw_vers` ≥ 14；在 Xcode 建立 Apple Development 憑證；用原型收集公平的模仿資料 | 寫 Python 版的比對，等 A 私下傳資料 |
| 16:30 – 19:00 | Task 2–6（核心邏輯和測試） | Task 7，接著做 `SignaturePad` | 調參報告寫進 `docs/tuning.md` |
| 18:00 – 19:00 | 晚餐 | 晚餐 | 晚餐 |
| 19:00 – 23:00 | Task 8–9（註冊、解鎖、救援碼） | Task 10（右鍵選單、安裝） | Devpost 和簡報草稿 |
| 23:00 – 01:00 | 整合，在兩台 Mac 上跑完整流程 | 第二台 Mac 驗證 | demo 腳本定稿 |
| 01:00 – 06:30 | 睡覺（輪流，至少一人留意 Discord） | 睡覺 | 睡覺 |
| 07:00 – 09:30 | 全隊一起調門檻、修 bug | 同左 | README、Devpost 定稿 |
| 09:30 – 11:00 | 錄 demo 影片 | 錄 demo 影片 | 剪片、上字幕 |
| **11:45 前** | **交件**，最後 15 分鐘留給意外 | | 確認評審報名表已填 |

## Git 規則

1. **開工前先同步**：`git pull --rebase origin main`
2. **一個任務一個分支**：分支名稱例如 `feat/t7-motion-source`、`docs/devpost`
3. **送 PR 前先測試**：
   ```bash
   cd airsign && swift build && swift test
   ```
   C 只改文件，可以跳過這步。
4. **PR 要小**：通過測試就自己合併，不用等別人審。合併後在 Discord 說一聲「T7 done」。
5. **至少每小時 commit 並 push 一次**：commit 時間是證明「24 小時內從零開始做」的證據。
6. **commit 訊息**：`feat: …`、`fix: …`、`docs: …`、`test: …`
7. **絕對不能 commit**：簽名資料（`spikes/airpods-motion/sessions/`、`*.csv`）、`*.airsign`、憑證或密碼。這個 repo 是公開的，簽名資料是類似生物特徵的個人資料。

## 給隊友 AI 的開場指令（直接貼）

**B 的 Antigravity**：
```
You're helping build AirSign for MakeUC 2026. Read TEAM.md, then
docs/superpowers/specs/2026-11-07-airsign-design.md and
docs/superpowers/plans/2026-11-07-airsign.md.
I am role B. Only edit the files TEAM.md assigns to role B.
Role A already owns Task 7 and Views/SignaturePad.swift; do not edit them.
Do plan Task 10, with the
services provider in Sources/AirSign/ServicesProvider.swift as
`final class ServicesProvider: NSObject` exposing lockFiles/unlockFiles and
calling a closure `onFiles: ([URL]) -> Void`.
Work on a feature branch. Run `cd airsign && swift build && swift test`
before every PR. Never commit spikes/airpods-motion/sessions or any .csv.
```

**C 的 Claude Max**：
```
You're helping tune AirSign's signature matcher for MakeUC 2026. Read
docs/superpowers/plans/2026-11-07-airsign.md, Task 3. In tools/tuning/,
write Python (standard library only, or numpy) that loads the attempt-*.json
files I give you. Each file has "mode", "who", "dur", "loc", and "rows" with
columns t,qx,qy,qz,qw,rot_x,rot_y,rot_z,acc_x,acc_y,acc_z,grav_x,grav_y,grav_z.
Reproduce Task 3's matcher: features rot/3, acc/0.5, grav; banded DTW with
band 0.25 normalized by n+m; duration factor 1+0.5*|ln ratio|; minimum over
3 templates; threshold = factor x worst pairwise template distance.
Only use imitator attempts made with the same bud side as the templates.
Grid-search thresholdFactor 1.0–2.0, durationWeight 0–1, band 0.1–0.4, and
per-group weights for gyro/acc/grav. Report the settings that reach owner
accepted >= 9/10 with the fewest imitators accepted. Write a short table to
docs/tuning.md. Do not commit the data files.
```

## 開始之前（各做一次）

- **A**：
  - 到 GitHub 的 Settings → Collaborators → Add people 加入 B 和 C，他們要到信箱接受邀請
  - 把 `spikes/airpods-motion/sessions/` 壓縮，**私下**傳給 C（例如 Discord 私訊），不要放進 repo
- **B**：
  - 到 Xcode → Settings → Accounts → 自己的 Apple ID → Manage Certificates → + → Apple Development
  - `git clone https://github.com/eric20041027/AirSign.git`
- **C**：`git clone` 這個 repo，把 A 傳來的資料放在 repo 外面的資料夾
