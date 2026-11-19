<script setup lang="ts">
definePageMeta({ layout: "docs" });

const { t, locale } = useI18n();
const route = useRoute();
const collection = computed(() =>
  locale.value === "zh-TW" ? "docs_zh" : "docs_en",
);
// Content paths have no language prefix or trailing slash.
const contentPath = computed(
  () => `/docs/${[route.params.slug].flat().filter(Boolean).join("/")}`,
);

const { data: page } = await useAsyncData(
  () => `docs-page-${collection.value}-${contentPath.value}`,
  () => queryCollection(collection.value).path(contentPath.value).first(),
  { watch: [contentPath, collection] },
);

if (!page.value) {
  throw createError({
    statusCode: 404,
    statusMessage: "Page not found",
    fatal: true,
  });
}

const { data: pages } = await useDocsNav();
const neighbours = computed(() => {
  const list = pages.value ?? [];
  const index = list.findIndex((p) => p.path === contentPath.value);
  return { previous: list[index - 1], next: list[index + 1] };
});

useSeoMeta({
  title: () => page.value?.title,
  description: () => page.value?.description,
  ogTitle: () => page.value?.title,
  ogDescription: () => page.value?.description,
});
</script>

<template>
  <article v-if="page">
    <h1 class="text-3xl font-semibold tracking-tight sm:text-4xl">
      {{ page.title }}
    </h1>
    <p
      v-if="page.description"
      class="mt-3 text-lg text-navy/65 dark:text-white/65"
    >
      {{ page.description }}
    </p>

    <ContentRenderer
      :value="page"
      class="prose mt-8 max-w-3xl prose-neutral dark:prose-invert prose-headings:tracking-tight prose-a:text-amber-ink dark:prose-a:text-amber prose-code:rounded-md prose-code:bg-navy/5 prose-code:px-1.5 prose-code:py-0.5 prose-code:font-medium prose-code:before:content-none prose-code:after:content-none dark:prose-code:bg-white/10 prose-th:text-left"
    />

    <nav
      class="mt-14 flex max-w-3xl flex-wrap justify-between gap-3 border-t border-navy/10 pt-6 dark:border-white/10"
    >
      <GlassButton v-if="neighbours.previous" :to="neighbours.previous.path">
        <template #icon>
          <UiIcon name="arrow-left" />
        </template>
        <span class="sr-only">{{ t("docs.previous") }}: </span
        >{{ neighbours.previous.title }}
      </GlassButton>
      <span v-else />
      <GlassButton v-if="neighbours.next" :to="neighbours.next.path">
        <span class="sr-only">{{ t("docs.next") }}: </span
        >{{ neighbours.next.title }}
        <UiIcon name="arrow-right" class="size-[1.15em]" aria-hidden="true" />
      </GlassButton>
    </nav>

    <p class="mt-8 text-sm">
      <a
        :href="`https://github.com/Pencil126/CaptionFitter/blob/main/website/content/${page.stem}.${page.extension}`"
        class="text-navy/55 underline-offset-4 hover:text-navy hover:underline dark:text-white/50 dark:hover:text-white"
        >{{ t("docs.edit") }}</a
      >
    </p>
  </article>
</template>
