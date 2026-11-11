# CaptionFitter

把文稿對齊到影片的人聲，產生字幕的 macOS App。一般人聲影片與歌曲都適用，全部在本機處理，不會上傳影片。

## 功能

- **文稿來源**：貼上文稿、自動轉錄（沒有文稿時由模型聽寫）、搜尋歌詞（LRCLIB）
- **語系可選**，提升辨識準確度
- **預覽與字幕編輯器**：修改文字、調整時間、分割／合併、整體平移，支援復原
- **輸出**：SRT 字幕檔，或把字幕燒入影片另存 MP4
- **模型管理**（設定，⌘,）：下載、刪除本機語音模型，選擇使用的模型

## 需求

- macOS 15 以上、Apple Silicon
- Xcode 16 以上

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

核心套件附一個命令列工具，可不開 App 測試對齊：

```bash
cd Packages/CaptionFitterCore && swift run captionfitter-cli
```

## 上傳到 YouTube

YouTube Studio → 字幕 → 選影片 → 新增字幕 → 上傳檔案 → 選「含時間碼」→ 選擇 SRT。
