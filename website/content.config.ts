import { defineCollection, defineContentConfig, z } from "@nuxt/content";

const schema = z.object({
  order: z.number(),
});

// One collection per language. Both use /docs/… paths; the language prefix is added by i18n
// when linking (Nuxt Content lowercases paths, which would turn zh-TW into zh-tw).
export default defineContentConfig({
  collections: {
    docs_en: defineCollection({
      type: "page",
      source: { include: "en/docs/**/*.md", prefix: "/docs" },
      schema,
    }),
    docs_zh: defineCollection({
      type: "page",
      source: { include: "zh-TW/docs/**/*.md", prefix: "/docs" },
      schema,
    }),
  },
});
