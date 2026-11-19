<script setup lang="ts">
const { t } = useI18n();
const head = useLocaleHead();
const { siteUrl } = useRuntimeConfig().public;

useHead(() => ({
  htmlAttrs: { lang: head.value.htmlAttrs?.lang },
  link: [...(head.value.link || [])],
  meta: [...(head.value.meta || [])],
  titleTemplate: (title) =>
    title && title !== t("meta.title")
      ? `${title} · CaptionFitter`
      : t("meta.title"),
}));

useSeoMeta({
  description: () => t("meta.description"),
  ogTitle: () => t("meta.title"),
  ogDescription: () => t("meta.description"),
  ogImage: `${siteUrl}/CaptionFitter.png`,
  twitterCard: "summary",
});
</script>

<template>
  <NuxtLayout>
    <NuxtPage />
  </NuxtLayout>
</template>
