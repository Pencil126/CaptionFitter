# AGENTS.md

給在這個 repo 工作的 AI 開發助理。使用說明請看 [README.md](README.md)；這份文件只寫 README 沒有、但動手前需要知道的事。

## 專案是什麼

CaptionFitter 是原生 Swift／SwiftUI 的 macOS App：把使用者提供的逐字稿（講稿、歌詞等既有的文字）對齊到影片的人聲，產生字幕，輸出 SRT 或把字幕嵌入影片。一般人聲影片與歌曲都要能用，全部在本機處理。

## 不能違反的決定

這些是專案擁有者明確決定過的，不要自行更改：

- **原生 Swift**。不引入 Python、Electron 或網頁介面。
- **唯一的第三方依賴是 WhisperKit**。新增其他依賴前先徵求同意。
- **不用 XcodeGen、Tuist 等專案產生工具**，直接維護 `CaptionFitter.xcodeproj`。
- **介面用詞是「逐字稿」與「字幕」**，不要寫「文稿」。「歌詞」只出現在「搜尋歌詞」這個來源選項，其他地方不強調歌曲。
- **使用者提供的逐字稿不做簡轉繁**，照原樣使用。自動辨識出來的文字則在語系為繁體中文時轉成繁體。
- **Repo 是公開的**。不要提交影音檔、字幕檔、歌詞、模型檔，也不要把個人路徑、帳號或金鑰寫進程式或文件。`.gitignore` 已排除常見的副檔名。

## 協作方式

- 一律用**繁體中文（台灣）**回覆。
- 需求不只一種做法時，**先列方案並等確認，再實作**。
- **只在被要求時提交**。提交前先把訊息給對方看過；對方只修改訊息而沒說要提交時，不算確認。
- 提交訊息用繁體中文，第一行加類型前綴，例如 `Feature: …`、`Chore: …`。內文如實寫出哪些部分驗證過、哪些沒有。
- 回報結果要誠實：沒重現的問題就說沒重現，沒驗證的介面就說沒驗證。

## 結構

```
App/                        SwiftUI 介面（Xcode 的資料夾同步群組）
  Models/                   AppModel（主視窗狀態）、ModelManager、FontCatalog、AlignmentLog
  Views/                    各面板、設定、輸出視窗、字型清單、播放快捷鍵
Packages/CaptionFitterCore/ 核心邏輯的 Swift Package，不依賴介面
  Sources/CaptionFitterCore/
  Sources/captionfitter-cli/ 命令列工具，用來不開 App 測試核心
  Tests/CaptionFitterCoreTests/CoreTests.swift
CaptionFitter.xcodeproj
```

- `App/` 是資料夾同步群組：**新增或刪除檔案不需要改專案檔**，放進資料夾就會被編譯。
- 專案檔最初是手寫的。改 `project.pbxproj` 前請對方先在 Xcode 關閉專案，否則修改可能被蓋掉。
- 邏輯盡量放在核心套件並寫測試；`App/` 只放介面與狀態。

### 核心套件的重點檔案

| 檔案 | 內容 |
|---|---|
| `ForcedAligner.swift` | 強制對齊：限制解碼器只能依序輸出逐字稿的 token，用注意力時間戳取得每行時間；以 30 秒視窗推進 |
| `CrossCheck.swift` | 交叉檢查：用自由聽寫的結果找出「逐字稿以外的講話」，並判斷每段的起始行 |
| `Aligner.swift` | `WhisperRecognizer`（模型載入、自由聽寫）、`CaptionBuilder`、`Alignment` |
| `SequenceAligner.swift` | 先聽寫再比對文字的舊做法，自動轉錄仍在使用 |
| `SubtitleDocument.swift` | 字幕行模型、`LineConfidence`、編輯操作 |
| `SubtitleBurner.swift` | `SubtitleStyle`、字幕繪製、影片輸出、`FontFaces` |
| `ModelStore.swift` | 模型清單、下載、刪除 |

`LineConfidence` 的意思：`good` 對上、`partial` 待檢查、`interpolated` 聲音中找不到（沒有時間，不顯示也不輸出）、`transcribed` 自動辨識（不在逐字稿中）、`manual` 使用者改過或標記為已檢查。

## 建置與測試

```bash
cd Packages/CaptionFitterCore && swift test
```

```bash
xcodebuild -project CaptionFitter.xcodeproj -scheme CaptionFitter -configuration Debug -derivedDataPath .build/xcode build
```

改動後兩者都要通過。專案擁有者通常從 Xcode 執行 App，所以你建置成功不代表對方看到的是新版，要請對方重新執行。

### 命令列工具

```bash
cd Packages/CaptionFitterCore && swift run -c release captionfitter-cli
```

不帶參數會印出用法。常用的環境變數：

- `CAPTIONFITTER_MODELS`：模型資料夾。App 在沙盒中，模型存在它自己的容器 `~/Library/Containers/<bundle id>/Data/Library/Application Support/CaptionFitter/Models`，要讓命令列使用同一份模型就指到這裡。
- `CAPTIONFITTER_DEBUG=1`：印出自由聽寫的每一句、信心值與偵測到的區段。

對齊相關的改動請用真實影片透過命令列驗證，並且**多跑幾次**（原因見下一節）。測試用的影音與逐字稿放在 repo 之外。

## 動手前要知道的坑

- **模型輸出每次執行都不同**。即使設定完全相同，不同程序的自由聽寫結果也會有差異；同一個程序內重複執行則相同。任何依賴聽寫結果的判斷都要跑多次看成功率，不能跑一次就下結論。命令列的 `--repeat` 可在同一程序內重複對齊。
- **`CrossCheck` 的門檻是依單一支現場演唱影片調出來的**，偵測偶爾會漏抓或邊界偏移。調整門檻前先收集多次執行的紀錄再離線評估，不要憑感覺改數字。
- **自由聽寫不重試（`retries: 0`）是刻意的**。重試會用隨機取樣，使唱歌的誤聽也得到高信心值，造成誤判。
- **已知未解的問題**：專案擁有者回報「開啟 App 後第一次對齊常偵測不到講話」，目前無法重現。App 會把每次對齊寫成診斷紀錄，放在容器的 `Library/Logs/CaptionFitter/`（只留最近 30 筆，內含逐字稿，只在本機讀取）。對方回報失效時先讀這些紀錄。
- **介面無法自動驗證**。能編譯不等於畫面正確；排版、快捷鍵、浮動面板的行為都要請對方實際操作確認，並在回報中寫明沒驗證過。
- **播放快捷鍵不是選單快捷鍵**。方向鍵由 `PlaybackKeys` 攔截，編輯文字時必須放行，否則游標移動與選取會壞掉。新增不帶修飾鍵的快捷鍵時沿用這個做法。
- **`SubtitleStyle` 會存進使用者設定**。新增欄位要在自訂的解碼中給預設值，否則舊設定會讀不回來；改預設值不會影響已存在的設定。
- **預覽與輸出共用 `SubtitleRenderer`**，尺寸都是影片高度的比例。改字幕外觀時兩邊會一起變，這是刻意的。
- **影片輸出不放大也不補格**。輸出選項只列出低於原始影片的畫質與幀率。
- **App 在沙盒中**，只能讀寫使用者透過對話框或拖放選取的檔案；一次輸出多個檔案時每個都要各自詢問位置。

## 程式風格

- 程式碼與註解用英文，介面文字用繁體中文。
- 註解寫「為什麼」，不要複述程式在做什麼。
- 介面文字目前直接寫在程式裡，沒有使用字串目錄。
- 核心套件的公開 API 變動時，同步更新命令列工具與 App 的呼叫處。
