# 03 BDD Scenarios - My Finance App

## Feature: 首次啟動

```gherkin
Scenario: 首次啟動 App
  Given 使用者首次安裝 App
  When 使用者開啟 App
  Then 系統應建立本地 SQLite 資料庫
  And 顯示首頁
  And 本月收入、本月支出、本月結餘皆為 0
```

## Feature: 新增支出

```gherkin
Scenario: 新增早餐支出
  Given 使用者已有帳戶「一卡通 Money」
  And 使用者已有分類「早餐」
  When 使用者新增一筆 72 元早餐支出
  And 選擇帳戶「一卡通 Money」
  And 選擇商家「OK便利商店」
  Then 首頁本月支出應增加 72 元
  And 明細列表應顯示該筆交易
  And 商家統計應累計 OK便利商店支出
```

## Feature: 新增收入

```gherkin
Scenario: 新增薪資收入
  Given 使用者已有帳戶「銀行帳戶」
  And 使用者已有分類「工資薪水」
  When 使用者新增一筆 44041 元收入
  Then 首頁本月收入應增加 44041 元
  And 本月結餘應同步更新
```

## Feature: 轉帳

```gherkin
Scenario: 銀行轉入一卡通 Money
  Given 「銀行帳戶」餘額為 10000
  And 「一卡通 Money」餘額為 100
  When 使用者新增一筆 500 元轉帳
  And 轉出帳戶為「銀行帳戶」
  And 轉入帳戶為「一卡通 Money」
  Then 「銀行帳戶」餘額應為 9500
  And 「一卡通 Money」餘額應為 600
  And 本月支出不應增加 500
```

## Feature: 借貸

```gherkin
Scenario: 借出金額給朋友
  Given 使用者有借貸對象「傑哥」
  When 使用者新增一筆借出 1000 元
  And 設定還款日為下個月 5 日
  Then 系統應建立一筆應收款
  And 該筆不應被視為一般支出
```

## Feature: 月預算

```gherkin
Scenario: 月預算超支
  Given 使用者設定本月支出預算為 25000
  And 本月支出已達 26000
  When 使用者進入首頁
  Then 系統應顯示已超支 1000
  And 預算進度條應顯示超支狀態
```

## Feature: 雲端發票交易合併

```gherkin
Scenario: 發票紀錄與手動記帳疑似相同
  Given 使用者已有一筆 72 元早餐支出
  And 該筆交易時間為 08:19
  When 系統同步到一筆 08:21 的雲端發票
  And 發票金額為 72 元
  Then 系統應建立疑似重複提示
  And 顯示左右對照畫面
  When 使用者選擇「合併並更新發票資訊」
  Then 系統應保留原交易
  And 將發票號碼與發票明細補入原交易
  And 不新增第二筆支出
```
