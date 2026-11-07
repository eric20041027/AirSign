# AirSign 多輪測試計畫

這份測試要回答三個問題：
1. **不可模仿性**：別人模仿得出你的空中簽名嗎？
2. **系統安全**：加密和防護在真實攻擊下有沒有守住？
3. **最佳門檻**：門檻倍數設多少，最能兼顧「本人好過」和「模仿者過不了」？

可以拿去給評審的說法：**模仿 100 次、0 次通過，就能說「有 95% 的把握，模仿成功率低於 3%」**（統計上的三分之一法則：0 次成功、n 次嘗試時，95% 信賴上限約為 3/n）。

## 準備（每台 Mac 各一次）

1. 安裝最新版：
   ```bash
   cd airsign && scripts/install.sh
   ```
2. 先用 ⌘Q 關掉 AirSign，再用測試模式啟動：
   ```bash
   open -a AirSign --args --test-mode
   ```
   畫面頂端會出現紅色的 TEST MODE 橫幅。一般方式開啟（雙擊、右鍵）時，App 完全不會進入測試模式。
3. 按「Open test lab」，**由本人簽一次**才能進入測試實驗室。
4. 每個時段開始前，本人先按 **Re-enroll owner (logged)** 重新註冊 3 次。這樣註冊時的原始資料也會被記錄，C 分析時才能用不同參數重算分數。

**測試實驗室的規則**：嘗試只做驗證、不會開任何檔案，所以**不會計入連錯鎖定**。解鎖檔案、救援碼、更換簽名這些正常流程仍然有鎖定保護。

## 角色

| Mac | 本人 | AirPods | 模仿者 |
|---|---|---|---|
| Mac 1 MacBook Pro | Eric | AirPods Pro 3，右耳 | B、C |
| Mac 2 MacBook Air | B | AirPods 4，用 B 的慣用手那一側 | Eric、C |

如果能找現場其他參賽者當模仿者更好：模仿者越多，證據越有說服力。

## A. 不可模仿性（每次嘗試都會自動記錄）

在測試實驗室填好 **Owner**、**Tester**、**Session**、**Scenario**，按空白鍵簽名。畫面會顯示每個場景已經測了幾次（目前次數／目標次數）。

| 場景 | 誰簽 | 怎麼做 | 每人每時段的目標次數 |
|---|---|---|---|
| A1-owner | 本人 | 自己的簽名，照平常的方式 | 20 |
| A2-zero-effort | 模仿者 | 簽自己的名字，不模仿 | 10 |
| A3-watched-once | 模仿者 | 在旁邊看本人簽一次，然後模仿 | 10 |
| A4-skilled | 模仿者 | 用手機在 1 公尺外錄下本人簽名、看 3 次，事先被告知握法和簽名平面，再自己練 5 分鐘（練習時不開實驗室） | 25 |
| A5-other-bud | 本人 | 自己的簽名，但換用另一顆 AirPod | 10 |
| A5-other-pair | 本人 | 自己的簽名，但換用另一副 AirPods（兩台 Mac 的 AirPods 互換） | 10 |

**公平規則：**
- 除了 A5 以外，模仿者都用**本人那一顆** AirPod。另一顆放在充電盒裡，手指要蓋住感測器。
- A4 的模仿者在實驗室裡看得到分數和燈號，這比真實攻擊者拿到的資訊還多，所以這是**偏嚴格的測試**。
- 如果出現「Discarded」（手指滑開、太短），那次不會被記錄，重簽就好。

**時段：**

| 時段 | 時間（美東） | 要做什麼 |
|---|---|---|
| S1-tonight | 19:00–21:00 | 全部場景 |
| S2-midnight | 00:00 前後 | 只做 A1，每位本人 20 次 |
| S3-morning | 07:30 | A1 每位本人 20 次，再補完還沒達標的場景 |

S1、S2、S3 的 A1 結果放在一起比較，就能知道**睡醒後本人的通過率會不會下降**，也就是握持角度要不要校正。

## B. 系統安全檢查（逐項記錄結果）

把結果填在這張表，完成後 commit 這份文件（只有文字，不含任何資料）。

| # | 測試 | 怎麼做 | 預期結果 | 實際結果 | 誰／何時 |
|---|---|---|---|---|---|
| B1 | 換一台電腦開檔 | 把 Mac 1 上鎖的 `.airsign` 用 AirDrop 傳到 Mac 2，用 B 的簽名解鎖 | 打不開，顯示「locked on another Mac」 | 通過：簽名通過（score 0.439 vs 0.700），但因本機無對應金鑰而拒絕解鎖，顯示 `locked on another Mac. Use that Mac's recovery code.` | Leo (Mac 2) / 11-07 16:43 ET |
| B2 | 救援碼 | 接著在 Mac 2 用 Eric 的救援碼解鎖 | 打得開，內容一樣 | | |
| B3 | 竄改檔案 | `printf '\x00' \| dd of=測試檔.airsign bs=1 seek=400 conv=notrunc` 改掉一個位元組，再解鎖 | 拒絕打開 | 通過：以 `dd` 竄改第 400 byte 後，AES-GCM 驗證失敗，拒絕解鎖還原 | Leo (Mac 2) / 11-07 17:23 ET |
| B4 | 暴力嘗試 | 用正常方式開啟（不是測試模式），模仿者連續解鎖失敗 5 次 | 出現 5 分鐘倒數 | 通過：一般模式下連續失敗達 5 次後，按鈕鎖定並顯示 `Too many tries. Try again in 281 s.` | Leo (Mac 2) / 11-07 17:31 ET |
| B5 | 假檔案不能重設次數 | 把任意檔案改名成 `x.airsign`，在倒數前用救援碼試它 | 失敗次數不會被歸零 | 通過：先失敗 4 次後對 `fake.airsign` 送出救援碼（顯示 `not a valid .airsign file`），再失敗 1 次即立刻觸發 5 分鐘鎖定，確認計數未歸零 | Leo (Mac 2) / 11-07 17:31 ET |
| B6 | 刪除設定檔 | 刪掉 `~/Library/Application Support/AirSign/profile.bin`，重新註冊 | 舊的 `.airsign` 只能用救援碼開 | 通過：刪除 `profile.bin` 重新註冊 3 次後，`masterKey` 已輪替，舊的 `MakeUC.pdf.airsign` 無法以新簽名直接打開，需使用原救援碼 | Leo (Mac 2) / 11-07 17:43 ET |
| B7 | 聲音輸出不是 AirPods | 把聲音輸出切到 Mac 喇叭後簽名 | 顯示「不計入」，不能解鎖 | 通過：切到 MacBook Air 喇叭後簽名，拒絕解鎖並顯示 `Set the sound output to your AirPods (Control Center → Sound), then sign again. This try was not counted.` | Leo (Mac 2) / 11-07 17:25 ET |
| B8 | 沒有網路連線 | AirSign 開著時執行 `lsof -i -a -p $(pgrep -f AirSign.app/Contents/MacOS/AirSign)` | 沒有任何輸出 | 通過：對執行中的 AirSign (PID 26001) 執行 `lsof -i -a -p 26001`，完全無輸出（0 個網路連線） | Leo (Mac 2) / 11-07 17:15 ET |

## 資料怎麼交給 C

每個時段結束後，在每台 Mac 執行：
```bash
cd ~/Library/Application\ Support/AirSign && zip -rq ~/Desktop/airsign-test-logs-$(hostname -s)-S1.zip test-logs
```
（S1 換成當下的時段）用 Discord **私訊**傳給 C。這些是簽名資料，**絕對不能 commit 進 repo**。

## C 的分析要產出什麼

寫進 `docs/evaluation.md`：
1. **各場景的通過率**：A1 本人通過率（分時段）；A2–A4 模仿者通過率；A5 應該 100% 擋下。
2. **最佳門檻倍數**：在 `thresholdFactor` 1.0–2.0 之間，選出「每位本人、每個時段通過率 ≥ 95%」的前提下，模仿者通過率最低的倍數。另外把目前設定和「手腕節奏權重加倍」（`FeatureScale.rotation` 3 → 1.5）兩種都算一遍，比較結果。
3. **可以引用的結論**：例如「A4 練習過的模仿 100 次中 0 次通過，95% 信賴上限 3%」，以及錯誤接受率等於錯誤拒絕率的那一點（EER）。
4. **兩張圖**（給 Devpost 和簡報用）：本人和模仿者的分數分布圖、門檻倍數對通過率的曲線。

每筆記錄都有 `enrollment` 欄位（註冊樣本的指紋），驗證時要拿同一個 `enrollment` 的 `mode: "enroll"` 記錄當作樣本。
