# 在學證明：實際校務流程查核

查核日期：2026-09-29。使用者授權私人Cookie進行唯讀導覽與本人證明下載；本文不保存憑證、學號、姓名或PDF內容。

## 已實際確認

- 入口：教務系統→學籍及畢審→註冊作業→查詢註冊。
- 功能頁：`https://acade.niu.edu.tw/NIU/Application/ENR/ENR50/ENR5020_01.aspx`。
- 按鈕：`input#GoToPrint`，標籤「列印在學證明」，`onclick=return doGoToPrint();`。
- 頁面函式檢查 `Q_STNO` 非空及 `valideMessage("Q_")`，再以 `window.open` 開啟下列校方網址：

```text
GET https://ccsys.niu.edu.tw/MvcTeam/AcadeExport/StudyProved/{目前登入者學號}
```

- 本次已請求目前登入者的實際URL：HTTP200、Content-Type `application/pdf`、檔案起始 `%PDF-`、99009 bytes。
- 未提供Content-Disposition；用戶端需自行產生不含學號的預設檔名。
- 本次瀏覽器只注入 `acade.niu.edu.tw` Cookie，證明網址跨到 `ccsys.niu.edu.tw` 仍直接回PDF，未跳登入。**這只證明本次請求行為，不推論所有帳號或校方授權規則；不得測試其他學號。**
- 本次所見按鈕直接下載，未出現付費／申請提交步驟；未驗證英文版、歷史學期或其他在學狀態。

## 實作規劃

後續功能實作記錄：[registration-feature-0.5.0.md](registration-feature-0.5.0.md)。

1. 沿用已驗證校務帳號，從查詢註冊頁目前身分欄位確認本人學號，保留校方有效性檢核。
2. 功能提供「瀏覽PDF」與「下載PDF」；只操作目前帳號，不提供任意學號輸入。
3. URL包含個人識別，不寫入診斷日誌、分享連結或公開下載頁。
4. 分網域管理Cookie，不將教務Cookie複製到不同網域。下載檢查HTTP／Content-Type／PDF magic，HTML登入頁不能當成成功PDF。
5. PDF儲存在App私有暫存，預覽／分享走本機檔案；下載透過Android系統選檔保存，不要求全檔案權限。
6. 依帳號與Session generation丟棄舊回應；登出清暫存，使用者另存的副本由使用者管理。
7. 使用者未選擇下載時不把證明自動存到公開資料夾，也不透過開發者伺服器代理。

## 測試界線

### Flutter 實作查核補充

- 已以實際頁面執行 `registrationExtractScript`，確認取得一列本人資料，查詢學號與資料列學號一致，校方 `valideMessage('Q_')` 檢核通過。
- 資料來源為 `#Q_STNO` 與 `#DataGrid`。實際表頭包含註冊學年期、學號、姓名、系所、年級、班別、在學狀態、註冊狀態、註冊日期、超商繳費收據、收據上傳日期、特殊身分、備註。
- 校方腳本另外宣告 `PAY1`＝學雜費、`PAY2`＝前學期學分費、`PAY3`＝就學貸款、`PAY4`＝請註冊假應註冊日期、`PAY5`＝欠書欠款，以及 `REGISTER_CMPLT_DATE`＝本學期註冊日期。但這是欄位設定，不是資料值；本次學生頁表格沒有這些明細，App 顯示「校方未提供」，不以不同表格的索引套用，也不將 0 視為完成。
- Android 使用 `niulife/registration` channel；瀏覽透過 FileProvider＋ACTION_VIEW，另存透過 ACTION_CREATE_DOCUMENT，皆不傳遞個人下載 URL 給外部 App。
- Flutter 四項單元／Widget 測試、feature 靜態分析及 Android `:app:compileDebugKotlin` 通過。原生 PDF 閱讀器與系統另存對話框尚需裝置端互動驗證。

本次只確認頁面、按鈕、本人PDFHTTP回應及檔案簽名，未讀取／展示PDF中的個人欄位。
原始HTML與PDF只曾存放於 `/tmp/opencode` 權限600暫存，查核完成刪除；使用者提供的原始Cookie檔保留供使用者管理。
