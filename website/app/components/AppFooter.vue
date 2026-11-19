<script setup lang="ts">
const { t } = useI18n();
</script>

<template>
  <footer class="border-t border-navy/5 dark:border-white/10">
    <div
      class="mx-auto flex max-w-6xl flex-col gap-4 px-4 py-10 text-sm text-navy/60 sm:flex-row sm:items-center sm:justify-between sm:px-6 dark:text-white/60"
    >
      <p>{{ t("footer.made") }}</p>
      <nav class="flex gap-5">
        <NuxtLinkLocale
          to="/docs"
          class="hover:text-navy dark:hover:text-white"
        >
          {{ t("footer.docs") }}
        </NuxtLinkLocale>
        <a
          href="https://github.com/Pencil126/CaptionFitter"
          class="hover:text-navy dark:hover:text-white"
          >{{ t("footer.github") }}</a
        >
        <a
          href="https://github.com/Pencil126/CaptionFitter/releases"
          class="hover:text-navy dark:hover:text-white"
          >{{ t("footer.releases") }}</a
        >
      </nav>
    </div>
  </footer>
</template>
