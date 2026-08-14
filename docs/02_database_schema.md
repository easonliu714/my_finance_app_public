# 02 Database Schema - My Finance App

## 設計原則

- 交易主表使用 `transactions`，以 `type` 區分收入、支出、轉帳、借貸。
- 分類使用 `categories`，支援 parent-child 結構。
- 帳戶餘額可由交易推導，但初期保留 `accounts.balance` 以方便快速顯示；後續需建立一致性更新規則。
- 所有主要資料表保留 `deleted_at`，支援軟刪除與回收站。
- 所有時間欄位使用 ISO-8601 字串。

## books

帳本資料。

| 欄位 | 說明 |
|---|---|
| id | 主鍵 |
| name | 帳本名稱 |
| currency_code | 幣別，預設 TWD |
| month_start_day | 月起始日 |
| created_at | 建立時間 |
| updated_at | 更新時間 |
| deleted_at | 軟刪除時間 |

## accounts

帳戶資料。

| 欄位 | 說明 |
|---|---|
| id | 主鍵 |
| book_id | 所屬帳本 |
| name | 帳戶名稱 |
| type | cash, bank, credit_card, ewallet, stored_value, voucher, investment |
| balance | 目前餘額 |
| initial_balance | 初始餘額 |
| currency_code | 幣別 |
| icon | 圖示 |
| color_hex | 顏色 |
| sort_order | 排序 |
| is_archived | 是否封存 |

## categories

分類資料。

| 欄位 | 說明 |
|---|---|
| id | 主鍵 |
| book_id | 所屬帳本 |
| parent_id | 父分類 |
| transaction_type | income, expense, transfer, loan |
| name | 分類名稱 |
| icon | 圖示 |
| color_hex | 顏色 |
| sort_order | 排序 |
| is_system | 是否系統預設 |
| is_archived | 是否封存 |

## merchants

商家資料。

| 欄位 | 說明 |
|---|---|
| id | 主鍵 |
| book_id | 所屬帳本 |
| name | 商家名稱 |
| normalized_name | 正規化名稱 |
| address | 地址 |
| latitude | 緯度 |
| longitude | 經度 |
| place_provider | manual, osm, google |
| place_id | 外部地點 ID |
| use_count | 使用次數 |
| last_used_at | 最近使用時間 |

## transactions

交易主表。

| 欄位 | 說明 |
|---|---|
| id | 主鍵 |
| book_id | 所屬帳本 |
| type | income, expense, transfer, loan |
| amount | 金額 |
| currency_code | 幣別 |
| category_id | 分類 |
| account_id | 一般收支帳戶 |
| from_account_id | 轉出帳戶 |
| to_account_id | 轉入帳戶 |
| member_id | 成員 |
| merchant_id | 商家 |
| counterparty_name | 借貸對象 |
| note | 備註 |
| transaction_time | 交易時間 |
| reimbursable_flag | 是否可報銷 |
| reimbursement_status | 報銷狀態 |
| source | manual, recurring, invoice, imported |
| source_ref_id | 外部來源 ID |

## budgets

預算資料。

| 欄位 | 說明 |
|---|---|
| id | 主鍵 |
| book_id | 所屬帳本 |
| period_type | monthly, yearly, custom |
| category_id | 可為 null，代表整體預算 |
| amount | 預算金額 |
| start_date | 起始日 |
| end_date | 結束日 |
| alert_threshold | 提醒門檻 |

## recurring_rules

週期帳規則。

| 欄位 | 說明 |
|---|---|
| id | 主鍵 |
| book_id | 所屬帳本 |
| name | 規則名稱 |
| transaction_template_json | 交易模板 |
| frequency | daily, weekly, monthly, yearly |
| interval_count | 間隔 |
| start_date | 起始日 |
| end_date | 結束日 |
| next_run_at | 下次執行時間 |
| auto_post | 是否自動入帳 |
| is_active | 是否啟用 |
