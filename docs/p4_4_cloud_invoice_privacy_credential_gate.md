# P4.4.3 Cloud Invoice Privacy and Credential Gate

最後更新：2026-06-14

關聯 Issue：#421

---

## 1. 目的

本文件定義雲端發票正式串接前的隱私與憑證安全門檻。任何 production API、載具帳號綁定、憑證儲存、背景同步或正式交易寫入，都必須先滿足本文件的要求。

本階段只做文件，不實作憑證、不串接 API、不做同步、不寫入交易。

---

## 2. 敏感資料分類

| 類型 | 範例 | 處理原則 |
| --- | --- | --- |
| carrierIdentifier | 手機條碼 / 自然人憑證載具識別 | UI 顯示需遮罩 |
| authorizationSecret | token / refresh token / session key | 不得進入一般 log |
| invoiceRawPayload | API 回傳原始資料 | 只允許本機暫存與 review |
| merchantMapping | seller identifier 到商家 master 的對應 | 只能作為建議，不可靜默寫入 |
| transactionDraft | 待確認交易草稿 | 需 final confirmation |

---

## 3. 憑證安全門檻

進入任何 credential implementation 前，必須先決定：

1. 儲存位置：是否使用 secure storage。
2. 加密策略：是否依平台提供安全儲存。
3. 撤銷流程：使用者可解除綁定。
4. 清除流程：使用者可清除本機暫存與授權狀態。
5. 錯誤處理：過期或失效時不可背景無限重試。
6. log policy：不得記錄完整 token、完整載具識別或完整 raw payload。

---

## 4. 使用者同意與控制權

正式串接前，UI / flow 必須提供：

- 明確說明會讀取哪些資料。
- 明確說明資料只會先進入 review / staging。
- 提供取消授權。
- 提供清除暫存資料。
- 提供手動輸入替代方案。
- 所有候選交易皆需使用者確認後才可建立正式紀錄。

---

## 5. Logging / Masking Rules

允許記錄：

```text
errorCategory
maskedCarrierId
invoiceNumber hash or partial display
retry hint
non-sensitive status
```

禁止記錄：

```text
full token
refresh token
full carrier id
full raw payload
credential headers
formal transaction details before confirmation
```

---

## 6. Production API 進場 Gate

若未來要串接 production API，必須另開獨立 issue / PR，並先完成：

1. API 文件與合法使用方式確認。
2. credential storage design。
3. privacy review checklist。
4. mock provider tests。
5. staging review flow tests。
6. error / revoke / clear data tests。
7. APK smoke validation plan。

---

## 7. 不可混入 train branch 的項目

以下不得混入長 train branch：

- production API 呼叫。
- token / credential 寫入。
- DB schema / migration。
- background sync。
- transaction store 寫入。
- merchant master 寫入。
- camera / OCR / permission。

---

## 8. 後續建議

下一步若仍維持低風險，可繼續文件化：

- production API readiness checklist。
- manual fallback / revoke flow。
- mock provider implementation split plan。

若要開始 runtime model 或 provider service，需先判斷是否獨立 PR。
