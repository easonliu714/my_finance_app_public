# Overall UI Blueprint

最後更新：2026-06-13  
階段：P4.10.22 Overall Delivery Architecture Viewer  
Issue：#378

---

## 1. 目的

本文件以最終 App 使用者外觀為主，列出五大分頁、主要功能區塊、展開畫面、資料來源與驗收目標。

這份 blueprint 先用 wireframe 文字表示。共識確認後，可再轉為 PNG mockup。

---

## 2. 全域導航

```text
底部五分頁：帳戶｜計劃｜首頁｜報表｜我的

首頁 FAB：新增記帳
首頁 compact shortcuts：速記｜發票｜拍照｜還款｜對獎
```

### 「對獎」快捷鍵

預期功能：開啟發票對獎入口。

對獎入口應支援：

- 手輸入發票候選。
- 掃描 / 影像 / 匯入的發票候選。
- 開獎日下午約 15:00 後，確認財政部公告資訊可用。
- 若資訊可用，提醒使用者進行對獎。
- 對獎結果只進入 review-first 狀態，不自動領獎或建立交易。

原先「全部」快捷鍵進入完整帳單明細，但底部「報表」分頁已承接完整帳單與統計查詢，因此首頁不再需要重複一個「全部」入口。

---

## 3. 帳戶分頁

### 3.1 主畫面

```text
[帳戶]
- 總資產摘要
- 帳戶清單
  - 現金
  - 銀行帳戶
  - 信用卡
  - 電子錢包
  - 儲值卡
- 新增帳戶 FAB / button
- 帳戶封存入口
```

| UI block | Route / action | Data | Acceptance |
|---|---|---|---|
| 帳戶清單 | AccountPage | accounts | 顯示未封存帳戶，排序穩定 |
| 新增帳戶 | account editor | accounts | 可新增名稱、類型、初始餘額 |
| 帳戶明細 | account detail | transactions, account_events | 顯示帳戶交易與事件 |
| 信用卡帳單設定 | card detail | credit_card_statement_events, bank_rule_profiles | 可檢視帳單日、繳款日、銀行規則 |

### 3.2 新增 / 編輯帳戶展開畫面

```text
[新增帳戶]
- 帳戶名稱
- 類型：現金 / 銀行 / 信用卡 / 電子錢包 / 儲值卡
- 初始餘額
- 排序
- 封存狀態
- 保存
```

---

## 4. 計劃分頁

### 4.1 主畫面

```text
[計劃]
- 本期應付款 / 待處理摘要
- 信用卡分期清單
- 貸款 / 還款計劃
- 固定支出或週期性計劃
- 本期還款入口
```

| UI block | Route / action | Data | Acceptance |
|---|---|---|---|
| 信用卡分期 | RepaymentPlanPage / installment detail | installment_plans, schedule_items | 顯示期數、狀態、應繳金額 |
| 本期還款 | PlanPaymentEntryFlow | schedule_items, transactions | 建立還款紀錄並更新期別狀態 |
| 分期來源交易 | TransactionEntryPage / installment sheet | transactions | 可從信用卡消費建立分期 |
| 計劃設定 | planned move to My settings center | plan settings | 通用設定應移出計劃頁 |

### 4.2 信用卡分期展開畫面

```text
[信用卡分期]
- 原始消費交易
- 分期期數
- 手續費模式
- 每期金額
- 已繳 / 未繳狀態
- 撤銷繳款
- 刪除原消費時的保護提示
```

---

## 5. 首頁分頁

### 5.1 主畫面

```text
[首頁 / 日常帳本]
- 本月支出摘要
- 月份 sticky summary
- compact shortcuts
  - 速記
  - 發票
  - 拍照
  - 還款
  - 對獎
- 支出月預算
- 日常紀錄
- 底部新增記帳 FAB
```

| UI block | Route / action | Data | Acceptance |
|---|---|---|---|
| 本月摘要 | DashboardPage | transactions | 正確聚合本月收入、支出、結餘 |
| compact shortcuts | DashboardPage | route actions | 保留緊湊入口，不顯示大型重複功能區 |
| 速記 | TransactionEntryPage | transactions | 快速新增交易 |
| 發票 | ManualInvoiceEntryPage short term | manual_invoice_drafts | 可手輸入發票，後續整合 scan |
| 拍照 | planned capture route | image_staging_items | 進入拍商品/拍收據候選流程 |
| 還款 | PlanPaymentEntryFlow | installment schedule | 首次點擊即載入信用卡、分期與借貸資料，不需先進計劃頁 |
| 對獎 | planned award route / #380 | invoice_award_candidates, invoice_award_periods | 開啟對獎入口，提醒與結果皆 review-first |
| 月預算 | planned budget editor | budgets, categories | 顯示預算進度與設定入口 |
| 日常紀錄 | transaction list | transactions | 儲存後立即刷新 |

### 5.2 發票入口展開畫面

```text
[發票]
短期：手輸入發票
- 發票號碼
- 發票日期與時間
- 賣方 / 商家
- 金額
- 付款帳戶下拉
- 備註
- 建立草稿 / 審核 / 轉交易候選

中期：掃描發票
- QR code scan
- 文字型發票號碼輸入
- 解析候選
- staging list
- 人工確認
```

### 5.3 拍照入口展開畫面

```text
[拍照]
- 拍商品
- 拍收據
- 從相簿選擇
- 建立本機 image staging item
- Gemini 分析候選
- 商品 / 發票 / 商家候選審核
- 轉交易草稿
```

### 5.4 對獎入口展開畫面

```text
[對獎]
- 顯示目前可對獎期別
- 顯示發票候選數量
- 開獎日下午約 15:00 後確認官方資訊可用
- 若可用，提醒使用者進行對獎
- 顯示中獎候選與未中獎候選
- 使用者確認後才標記結果
- 不自動領獎
```

---

## 6. 報表分頁

### 6.1 主畫面

```text
[報表 / 帳單明細]
- 期間切換：全部 / 年 / 月
- 期間導航
- 收入 / 支出 / 結餘 summary cards
- 月群組或日群組明細
- 搜尋 / 篩選
```

| UI block | Route / action | Data | Acceptance |
|---|---|---|---|
| 帳單明細 | LedgerDetailPage | transactions | 期間切換穩定 |
| 回首頁 | Dashboard route | router | 不黑屏 |
| 篩選 | planned | transactions, accounts, categories | 可按帳戶、類別、商家、成員篩選 |
| 圖表 | planned | transactions | 收支趨勢、類別分布、帳戶分布 |

---

## 7. 我的分頁

### 7.1 主畫面

```text
[我的]
- 目前可用功能摘要
- 備份與換機移轉中心
- 備份提醒
- 備份通知
- 完整備份 / 完整還原
- readable 匯出 / 匯入
- 設定中心
```

### 7.2 設定中心展開畫面

```text
[設定中心]
- AI / Gemini 設定
  - Google AI Studio 教學
  - Gemini API key 輸入
  - 模型選擇
  - 模型測試
- Google Places 設定
  - Places API key 輸入
  - 查詢次數 / 費用警示
- 雲端發票設定
  - 官方平台入口
  - 匯入 / 對獎治理
  - 背景同步狀態與限制
- 計劃設定
  - 信用卡分期預設
  - 還款提醒
  - 週期性計劃預設
- 類別與預設值
  - 類別管理
  - 依時間預選早餐 / 午餐 / 下午茶 / 晚餐
```

| UI block | Route / action | Data | Acceptance |
|---|---|---|---|
| AI / Gemini | settings route | api_key_settings, ai_model_settings | key 遮罩、手動測試、使用者觸發 |
| Places | settings route | places_settings, usage_warning_settings | 費用/次數警示可設定 |
| 雲端發票 | settings route | cloud_invoice_settings | 官方入口、無靜默同步 |
| 計劃設定 | settings route | plan settings | 從計劃頁移入我的頁 |
| 備份還原 | BackupMigrationCenter | backup settings, restore grants | 預覽、確認、可回復 |

---

## 8. 待審核資料入口

最終交付應有一致的候選資料模式：

```text
外部 / 半自動來源
  -> staging item
  -> review candidate
  -> user confirm
  -> draft or formal transaction
```

適用來源：

- 手輸入發票
- 掃發票
- 拍商品
- Google Places 商家候選
- 雲端發票匯入候選
- 發票對獎結果
- readable 匯入交易

---

## 9. UI Blueprint 驗收條件

- 五大分頁的主要區塊都可對應到 route / data source / acceptance。
- 首頁 compact shortcuts 功能定義明確。
- 「對獎」明確定義為發票對獎入口。
- 完整帳單明細由底部「報表」分頁承接。
- 我的頁設定中心收斂 AI、Places、雲端發票與計劃設定。
- 發票、拍照、AI、Places、對獎都以候選審核為共同模式。
