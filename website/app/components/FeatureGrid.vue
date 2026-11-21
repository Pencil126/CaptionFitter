<script setup lang="ts">
const { t } = useI18n();

const features = [
  { key: "sources", icon: "transcript" },
  { key: "editor", icon: "edit" },
  { key: "review", icon: "search" },
  { key: "style", icon: "palette" },
  { key: "export", icon: "export" },
  { key: "models", icon: "chip" },
] as const;
</script>

<template>
  <section class="mx-auto max-w-6xl px-4 py-16 sm:px-6">
    <h2
      v-reveal
      class="max-w-2xl text-2xl font-semibold tracking-tight sm:text-3xl"
    >
      {{ t("features.title") }}
    </h2>
    <div class="mt-8 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
      <div
        v-for="(feature, index) in features"
        :key="feature.key"
        v-reveal="(index % 3) * 90"
        class="rounded-2xl border border-navy/8 bg-white/70 p-6 dark:border-white/10 dark:bg-white/[0.04]"
      >
        <UiIcon
          :name="feature.icon"
          class="size-6 text-amber-ink dark:text-amber"
        />
        <h3 class="mt-4 font-semibold">
          {{ t(`features.${feature.key}.title`) }}
        </h3>
        <p
          class="mt-2 text-[0.9375rem] leading-relaxed text-navy/70 dark:text-white/70"
        >
          {{ t(`features.${feature.key}.body`) }}
        </p>
      </div>
    </div>
  </section>
</template>
