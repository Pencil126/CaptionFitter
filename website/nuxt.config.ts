import { readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import tailwindcss from "@tailwindcss/vite";

// Where the Cloudflare Worker serves the site. Used for absolute links such as hreflang and og:image.
const siteUrl = "https://captionfitter.pencil126.cc";

// Remembers the language chosen with the language switcher; read by the script in app.head and
// written by plugins/locale-cookie.client.ts through the runtime config.
const localeCookie = "captionfitter_locale";

// Every docs page is listed up front: /docs only redirects, so the crawler would never reach them.
const docsRoutes = [
  ["en", "/docs"],
  ["zh-TW", "/zh-TW/docs"],
].flatMap(([folder, prefix]) =>
  readdirSync(new URL(`./content/${folder}/docs`, import.meta.url))
    .filter((file) => file.endsWith(".md"))
    .map((file) => `${prefix}/${file.replace(/\.md$/, "")}`),
);

export default defineNuxtConfig({
  compatibilityDate: "2025-07-15",
  modules: ["@nuxt/content", "@nuxtjs/i18n"],
  css: ["~/assets/css/main.css"],
  vite: {
    plugins: [tailwindcss()],
  },

  runtimeConfig: {
    public: { siteUrl, localeCookie },
  },

  app: {
    head: {
      link: [
        { rel: "icon", type: "image/png", href: "/CaptionFitter.png" },
        { rel: "apple-touch-icon", href: "/CaptionFitter.png" },
      ],
      meta: [
        {
          name: "theme-color",
          content: "#FAFAF7",
          media: "(prefers-color-scheme: light)",
        },
        {
          name: "theme-color",
          content: "#0E1020",
          media: "(prefers-color-scheme: dark)",
        },
      ],
      script: [
        {
          // Picks the home page language before the app starts, so the prerendered English page
          // never hydrates with Traditional Chinese. Mirrors the app, which follows the system
          // language: the first preferred language the site supports wins, and English is the
          // fallback. A choice made with the language switcher (the cookie) comes first.
          innerHTML: `(function () {
  if (location.pathname !== "/") return;
  var saved = document.cookie.match(/(?:^|; )${localeCookie}=([^;]*)/);
  var locale = saved ? saved[1] : "en";
  if (!saved) {
    var languages = navigator.languages || [navigator.language];
    for (var i = 0; i < languages.length; i++) {
      var tag = String(languages[i]).toLowerCase();
      if (/^zh-(hant|tw|hk|mo)(-|$)/.test(tag)) { locale = "zh-TW"; break; }
      if (/^en(-|$)/.test(tag)) break;
    }
  }
  if (locale === "zh-TW") location.replace("/zh-TW" + location.search + location.hash);
})();`,
          tagPosition: "head",
        },
      ],
    },
  },

  content: {
    // Node 22.5+ ships SQLite, so no native add-on has to be installed.
    experimental: { sqliteConnector: "native" },
  },

  i18n: {
    baseUrl: siteUrl,
    defaultLocale: "en",
    strategy: "prefix_except_default",
    locales: [
      { code: "en", language: "en", name: "English", file: "en.json" },
      {
        code: "zh-TW",
        language: "zh-Hant-TW",
        name: "繁體中文",
        file: "zh-TW.json",
      },
    ],
    // The home page picks the language with the script in app.head instead. i18n detects it only
    // after the English page has loaded, which leaves hydration mismatches behind.
    detectBrowserLanguage: false,
  },

  nitro: {
    // Plain static files served by wrangler.jsonc. Without this, Nitro sees Cloudflare's build
    // environment and switches to its Workers server preset, which expects server code that
    // `nuxt generate` doesn't produce.
    preset: "static",
    // Serve the app icon straight from the Xcode project instead of keeping a second copy.
    publicAssets: [
      {
        dir: fileURLToPath(
          new URL("../App/AppIcon.icon/Assets", import.meta.url),
        ),
        baseURL: "/",
      },
    ],
    prerender: {
      crawlLinks: false,
      routes: [
        "/",
        "/zh-TW",
        "/docs",
        "/zh-TW/docs",
        ...docsRoutes,
        "/404.html",
      ],
      failOnError: true,
      // Write docs/export.html rather than docs/export/index.html. Cloudflare serves a file at
      // /docs/export but a folder index at /docs/export/, and the app links without the
      // trailing slash.
      autoSubfolderIndex: false,
    },
  },
});
