<script setup lang="ts">
defineProps<{
  pages: { title: string; path: string }[];
}>();
</script>

<template>
  <nav>
    <ul class="flex flex-col gap-0.5">
      <li v-for="page in pages" :key="page.path">
        <NuxtLinkLocale
          :to="page.path"
          class="block rounded-lg px-3 py-2 text-[0.9375rem] text-navy/70 transition hover:bg-navy/5 hover:text-navy dark:text-white/70 dark:hover:bg-white/5 dark:hover:text-white"
          exact-active-class="!bg-amber/25 !text-navy font-medium dark:!bg-amber/15 dark:!text-amber"
        >
          {{ page.title }}
        </NuxtLinkLocale>
      </li>
    </ul>
  </nav>
</template>
