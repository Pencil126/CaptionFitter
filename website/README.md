# CaptionFitter 網站

CaptionFitter 的介紹頁與說明文件，用 [Nuxt](https://nuxt.com) 與 [Tailwind CSS](https://tailwindcss.com) 製作。

這份文件說明網站的架構與維護方式。App 本身的說明請看 repo 根目錄的 [README](../README.md)。

## 快速開始

需要 Node.js 24 以上（版本寫在 [`.nvmrc`](.nvmrc)）。以下指令都在 `website/` 資料夾中執行。

安裝套件：

```bash
npm install
```

啟動開發伺服器：

```bash
npm run dev
```

推送前整理格式、檢查兩種語言是否一致，並建置一次：

```bash
npm run format
```

```bash
npm run check-locales
```

```bash
npm run generate
```

建置結果在 `.output/public/`。如果建置結果看起來沒有套用 `nuxt.config.ts` 的改動，刪除 `node_modules/.cache/nuxt` 與 `.output` 後再建置一次。

### 程式碼格式

格式由 [Prettier](https://prettier.io) 統一，使用預設值；`prettier-plugin-tailwindcss` 會把 Tailwind class 依固定順序排列。

- `npm run format`：整理所有檔案的格式。
- `npm run format:check`：只檢查，不修改。

設定在 `.prettierrc.json`，略過的檔案在 `.prettierignore`。

## 運作方式

```
Markdown／Vue 原始碼 ── npm run generate ──▶ 靜態 HTML（.output/public）── Workers Builds ──▶ Cloudflare Worker
```

建置時就把每一頁預先產生成 HTML，上線後沒有伺服器在執行。瀏覽器載入頁面後，Vue 才接手處理互動（切換語言、手機選單、按鈕折射），這個步驟叫做 hydration。

推送到 `main` 且改到 `website/` 時，Cloudflare 的 Workers Builds 會自動建置，再用 [`wrangler.jsonc`](wrangler.jsonc) 的設定部署成只放靜態檔案的 Worker。

### 部署設定

第一次設定時，在 Cloudflare 後台的 Workers & Pages 選「建立」，匯入這個 GitHub repo，填入：

| 欄位           | 值                                                    |
| -------------- | ----------------------------------------------------- |
| 專案名稱       | `captionfitter`（與 `wrangler.jsonc` 的 `name` 相同） |
| 根目錄（Path） | `website`                                             |
| 建置指令       | `npm run check-locales && npm run generate`           |
| 部署指令       | `npx wrangler deploy`                                 |
| 正式分支       | `main`                                                |
| 建置監看路徑   | 只包含 `website/*`，其他資料夾的改動不觸發建置        |

推送到 `main` 以外的分支時，Workers Builds 預設會上傳一個預覽版本，不影響正式網站，並在 GitHub 的提交狀態附上預覽網址，可以在合併前檢查。這項設定在後台的「非正式分支建置」，預設的部署指令是 `npx wrangler versions upload`。

網站網址寫在 `nuxt.config.ts` 的 `siteUrl`，用於搜尋引擎的語言對照與分享預覽圖。

## 目錄結構

```
website/
├─ nuxt.config.ts          總設定：網站網址、語系、要產生哪些頁面
├─ content.config.ts       說明文件的集合定義
├─ package.json            套件與指令
├─ wrangler.jsonc          Cloudflare Worker 設定
├─ app/
│  ├─ app.vue              最外層：<head> 的標題、語言與 SEO
│  ├─ error.vue            404 與錯誤頁
│  ├─ assets/css/main.css  Tailwind 入口與品牌色
│  ├─ layouts/
│  │  ├─ default.vue       一般頁面的外框（頁首、內容、頁尾）
│  │  └─ docs.vue          說明文件的外框（多了側欄）
│  ├─ pages/               每個檔案對應一個網址
│  │  ├─ index.vue         /
│  │  └─ docs/
│  │     ├─ index.vue      /docs（轉到第一頁）
│  │     └─ [...slug].vue  /docs/<名稱>，讀取對應的 Markdown
│  ├─ components/          可重複使用的區塊
│  └─ composables/         可重複使用的邏輯
├─ content/
│  ├─ en/docs/             英文說明文件
│  └─ zh-TW/docs/          繁體中文說明文件
├─ i18n/locales/
│  ├─ en.json              英文介面字串
│  └─ zh-TW.json           繁體中文介面字串
├─ public/                 原樣複製到網站的檔案（例如截圖）
│  └─ _headers             Cloudflare 回應時加上的標頭（安全設定），不會當成網頁提供
└─ scripts/
   └─ check-locales.mjs    檢查兩種語言是否一一對應
```

`node_modules/`、`.nuxt/`、`.output/`、`.data/` 都是自動產生的，不會提交。

### 元件

| 元件                                                      | 用途                                                                |
| --------------------------------------------------------- | ------------------------------------------------------------------- |
| `GlassButton`                                             | 網站上所有按鈕。膠囊形狀的 liquid glass 效果，Chromium 上有邊緣折射 |
| `GlowBackground`                                          | 固定在視窗上、緩慢飄動的背景光暈                                    |
| `AppHeader`、`AppFooter`                                  | 頁首與頁尾                                                          |
| `LanguageSwitcher`                                        | 切換英文／繁體中文                                                  |
| `HeroSection`、`HowItWorks`、`FeatureGrid`、`PrivacyNote` | 介紹頁的各個區塊                                                    |
| `ScreenshotFrame`                                         | 截圖外框；沒有圖片時顯示佔位                                        |
| `DocsSidebar`                                             | 說明文件的側欄目錄                                                  |
| `UiIcon`                                                  | 網站用的線條圖示                                                    |

### Composables

| 名稱           | 用途                                        |
| -------------- | ------------------------------------------- |
| `useDocsNav()` | 取得目前語言的說明文件清單，依 `order` 排序 |

## Nuxt 的基本觀念

- **檔案即網址**：`pages/` 裡的檔案就是網址。`[...slug]` 是萬用字元，`/docs/export`、`/docs/speech-models` 都由 `[...slug].vue` 處理。
- **自動匯入**：`components/` 的元件可以直接用名字（`<GlassButton>`），`composables/` 的函式可以直接呼叫，不用寫 `import`。Vue 與 Nuxt 內建的 `ref`、`computed`、`useI18n` 等也是。
- **版面**：頁面預設套用 `layouts/default.vue`；說明文件頁用 `definePageMeta({ layout: 'docs' })` 改用 `docs.vue`。版面中的 `<slot />` 是頁面內容的位置。
- **`.vue` 檔**：分成 `<script setup>`（邏輯）、`<template>`（畫面）、`<style scoped>`（只作用在這個元件的 CSS）。樣式大多直接用 Tailwind class，很少需要 `<style>`。

## 樣式 - Tailwind CSS

直接在 HTML 上寫 class，例如 `text-2xl font-semibold`。品牌色定義在 [`app/assets/css/main.css`](app/assets/css/main.css) 的 `@theme`，取自 App 圖示：

| class               | 顏色      | 用途                         |
| ------------------- | --------- | ---------------------------- |
| `navy`              | `#15172B` | 文字、深色區塊               |
| `amber`             | `#FFC53D` | 填色、強調                   |
| `amber-ink`         | `#CC8F00` | 淺色背景上的琥珀色文字或圖示 |
| `page`、`page-dark` |           | 淺色與深色模式的頁面背景     |

`dark:` 開頭的 class 只在深色模式生效。深淺色跟隨系統設定。

## 介面文字與翻譯

- 介紹頁、頁首、頁尾等文字在 `i18n/locales/en.json` 與 `zh-TW.json`，兩個檔案的 key 要完全相同。程式中用 `t('hero.title')` 取用。
- 英文網址沒有前綴（`/docs/export`），繁體中文加上 `/zh-TW`（`/zh-TW/docs/export`）。
- 第一次造訪首頁時會依瀏覽器語言導向，使用者切換語言後會記住選擇。

## 說明文件

每頁是一個 Markdown 檔，英文與繁體中文各一份，檔名相同：

```markdown
---
title: Export
description: Save an SRT subtitle file, a video with subtitles, or both.
order: 5
---

內文從這裡開始，不要再寫一次標題（頁面會自動顯示 title）。
```

- `title`：頁面標題，也是側欄顯示的名稱
- `description`：標題下方的說明，也用於搜尋引擎摘要
- `order`：側欄排序，兩種語言要相同

## 常見維護工作

| 想做的事       | 怎麼做                                                                                                              |
| -------------- | ------------------------------------------------------------------------------------------------------------------- |
| 改介紹頁文字   | 改 `en.json` 與 `zh-TW.json` 中同一個 key                                                                           |
| 改說明文件     | 直接改 `content/<語言>/docs/` 中的 `.md`                                                                            |
| 新增說明文件頁 | 在 `content/en/docs/` 與 `content/zh-TW/docs/` 各新增一個同檔名的 `.md`，設好 `order`。不用改設定，建置時會自動列入 |
| 新增介紹頁區塊 | 在 `components/` 新增元件，放進 `pages/index.vue`，文字加進兩個 json                                                |
| 加截圖         | 圖片放進 `public/screenshots/`，在 `ScreenshotFrame` 加上 `src`（見下方）                                           |
| 改品牌色       | 改 `main.css` 的 `@theme`                                                                                           |
| 新增按鈕       | 用 `<GlassButton>`（見下方）                                                                                        |
| 新增圖示       | 在 `UiIcon.vue` 的 `paths` 加一筆 24×24 格線的 SVG 路徑，並把名稱加進 `name` 的型別                                 |

### 加上截圖

截圖依語言命名，例如 `main-window.en.png`、`main-window.zh-TW.png`，放在 `public/screenshots/`。然後在使用 `ScreenshotFrame` 的地方加上 `src`：

```vue
<script setup lang="ts">
const { t, locale } = useI18n();
</script>

<template>
  <ScreenshotFrame
    :caption="t('screenshots.main')"
    :src="`/screenshots/main-window.${locale}.png`"
  />
</template>
```

`src` 以 `/` 開頭，`public/` 就是網站的根目錄。

### 使用 GlassButton

```vue
<!-- 站內連結：to 會自動加上目前語言的前綴 -->
<GlassButton variant="primary" size="lg" to="/docs">
  <template #icon><UiIcon name="arrow-right" /></template>
  Read the docs
</GlassButton>

<!-- 站外連結 -->
<GlassButton
  href="https://github.com/Pencil126/CaptionFitter"
>GitHub</GlassButton>

<!-- 只有圖示時要加 label，給螢幕閱讀器使用 -->
<GlassButton size="sm" label="Open menu" @click="open = true">
  <template #icon><UiIcon name="menu" /></template>
</GlassButton>
```

| 屬性         | 值                             | 說明                                                 |
| ------------ | ------------------------------ | ---------------------------------------------------- |
| `variant`    | `primary`、`secondary`（預設） | 琥珀色或中性的玻璃                                   |
| `size`       | `sm`、`md`（預設）、`lg`       | 高度 32／40／48 px                                   |
| `to`         | 站內路徑                       | 會加上語言前綴；路徑已含前綴時加 `:localize="false"` |
| `href`       | 網址                           | 站外連結                                             |
| `refraction` | 數字，預設 `1`                 | 折射強度，`0` 為關閉                                 |
| `label`      | 文字                           | 只有圖示時必填                                       |

文字請寫在 i18n 的 json 中，上面範例直接寫英文只是為了簡短。

## 注意事項

1. **站內連結與檔案路徑**：站內連結要用 `NuxtLinkLocale` 或 `GlassButton` 的 `to`，才會加上語言前綴。`public/` 中的檔案用 `/` 開頭的路徑，例如 `src="/CaptionFitter.png"`。
2. **兩種語言要一一對應**：json 的 key、說明文件的檔名與 `order` 少一個，`npm run check-locales` 就會失敗，部署也會停止。
3. **說明文件的路徑不含語系**：兩種語言的文件在 Nuxt Content 中都是 `/docs/...`，語言前綴由 i18n 加上。原因是 Nuxt Content 會把路徑轉成小寫，`zh-TW` 會變成 `zh-tw`，跟網址對不上。
4. **網址不加結尾斜線**：網站的連結都不帶結尾的 `/`（`/zh-TW`、`/docs/export`）。為了讓 Cloudflare 照這個網址直接回傳頁面，兩個設定要搭配：
   - `nuxt.config.ts` 的 `autoSubfolderIndex: false`：每頁存成 `zh-TW.html`，而不是 `zh-TW/index.html`。
   - `wrangler.jsonc` 的 `html_handling: "auto-trailing-slash"`：`/zh-TW` 回傳 `zh-TW.html`；`/zh-TW/` 轉回 `/zh-TW`。

   如果網址多了結尾斜線，Vue 接手時算出的連結和選取狀態會和預先產生的 HTML 不同（hydration 不一致），造成連結錯誤或畫面閃動。本機的 `npm run dev` 不會遇到這個問題，要在部署後的網址上確認。

5. **`<style scoped>` 中的動畫**：`animation` 要直接寫出 `@keyframes` 的名稱。scoped 樣式會改掉 keyframes 的名稱，經由 CSS 變數傳入的名稱對不上，動畫就不會播放。

## 參考文件

- Nuxt：<https://nuxt.com/docs>
- Nuxt Content：<https://content.nuxt.com>
- Nuxt i18n：<https://i18n.nuxtjs.org>
- Tailwind CSS：<https://tailwindcss.com/docs>
