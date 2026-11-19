<script setup lang="ts">
const { t } = useI18n();
const route = useRoute();
const { data: pages } = await useDocsNav();

const current = computed(() => {
  const slug = [route.params.slug].flat().filter(Boolean).join("/");
  return pages.value?.find((p) => p.path === `/docs/${slug}`);
});
</script>

<template>
  <div class="flex min-h-dvh flex-col">
    <GlowBackground subtle />
    <AppHeader />
    <div
      class="mx-auto w-full max-w-6xl flex-1 px-4 sm:px-6 lg:grid lg:grid-cols-[13rem_minmax(0,1fr)] lg:gap-12"
    >
      <!-- On small screens the contents collapse into a disclosure above the page. -->
      <details
        class="group mt-6 rounded-2xl border border-navy/10 lg:hidden dark:border-white/10"
      >
        <summary
          class="flex cursor-pointer list-none items-center justify-between px-4 py-3 text-sm font-medium"
        >
          <span>{{ current?.title ?? t("docs.contents") }}</span>
          <UiIcon
            name="chevron-down"
            class="size-4 transition group-open:rotate-180"
          />
        </summary>
        <DocsSidebar :pages="pages ?? []" class="px-2 pb-3" />
      </details>

      <aside class="hidden lg:block">
        <div class="sticky top-16 py-10">
          <p
            class="mb-3 px-3 text-xs font-semibold tracking-wide text-navy/50 uppercase dark:text-white/50"
          >
            {{ t("docs.title") }}
          </p>
          <DocsSidebar :pages="pages ?? []" />
        </div>
      </aside>

      <main class="min-w-0 py-8 lg:py-10">
        <slot />
      </main>
    </div>
    <AppFooter />
  </div>
</template>
