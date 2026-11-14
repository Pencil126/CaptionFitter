# CaptionFitter

把逐字稿對齊到影片的人聲，產生字幕的 macOS App。一般人聲影片與歌曲都適用，全部在本機進行處理，不會上傳影片。

## 功能

- **文稿來源**：貼上文稿、自動轉錄（沒有文稿時由模型聽寫）、搜尋歌詞（LRCLIB）
- **語系可選**，提升辨識準確度
- **預覽與字幕編輯器**：修改文字、調整時間、分割／合併、整體平移，支援復原
- **輸出**：SRT 字幕檔，或把字幕嵌入影片另存為新影片
- **模型管理**：下載、刪除本機語音模型，選擇使用的模型

## 需求

- macOS 26 以上、Apple Silicon
- Xcode 26 以上

## 建置

用 Xcode 開啟 `CaptionFitter.xcodeproj` 後執行，或：

```bash
xcodebuild -project CaptionFitter.xcodeproj -scheme CaptionFitter -configuration Debug -derivedDataPath .build/xcode build
```

第一次使用請先到設定（⌘,）下載一個語音模型。

## 專案結構

- `App/`：SwiftUI 介面
- `Packages/CaptionFitterCore/`：核心邏輯（對齊、文稿斷行、歌詞搜尋、模型管理、SRT、燒入輸出），唯一的第三方依賴是 [WhisperKit](https://github.com/argmaxinc/WhisperKit)

## 測試

```bash
cd Packages/CaptionFitterCore && swift test
```

核心套件附一個命令列工具，可不開 App 測試：

```bash
cd Packages/CaptionFitterCore && swift run captionfitter-cli
```

## 輸出

對齊並檢查字幕後，可以輸出成以下兩種格式。標示為「在聲音中找不到」的行（紅點）和沒有文字的行不會輸出。

### SRT 字幕檔

純文字的字幕檔，使用 UTF-8 編碼。影片本身不會被修改，多數播放器與影音平台都能讀取。

每一段字幕由序號、起訖時間（`時:分:秒,毫秒`）和文字組成，段落之間空一行：

```
1
00:00:11,700 --> 00:00:14,250
第一行字幕

2
00:00:14,250 --> 00:00:17,800
第二行字幕
```

### 嵌入字幕的影片（MP4）

把字幕直接畫在畫面上，另存成新的影片檔，預設檔名為「原檔名-字幕.mp4」。

字幕的字型、大小、文字與描邊顏色、位置可以在輸出前設定，預覽畫面顯示的樣子即為輸出結果。嵌入後輸出的字幕無法關閉或再修改，需要調整時請回到 App 重新輸出。只有音訊的檔案不支援使用此選項。
