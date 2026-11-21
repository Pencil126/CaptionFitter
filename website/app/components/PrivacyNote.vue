<script setup lang="ts">
const { t } = useI18n();
</script>

<template>
  <section class="mx-auto max-w-6xl px-4 py-16 sm:px-6">
    <div
      class="flex flex-col gap-5 rounded-3xl bg-navy p-8 text-white sm:flex-row sm:items-start sm:p-10"
    >
      <span
        class="flex size-12 shrink-0 items-center justify-center rounded-full bg-white/10"
      >
        <UiIcon name="lock" class="size-6 text-amber" />
      </span>
      <div>
        <h2 class="text-2xl font-semibold tracking-tight">
          {{ t("privacy.title") }}
        </h2>
        <p class="mt-3 max-w-3xl leading-relaxed text-white/75">
          {{ t("privacy.body") }}
        </p>
      </div>
    </div>
  </section>
</template>
