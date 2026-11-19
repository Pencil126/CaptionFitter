<script setup lang="ts">
const { t } = useI18n();

const steps = [
  { key: "open", icon: "film" },
  { key: "transcript", icon: "transcript" },
  { key: "align", icon: "subtitles" },
] as const;
</script>

<template>
  <section class="mx-auto max-w-6xl px-4 py-16 sm:px-6">
    <h2 class="text-2xl font-semibold tracking-tight sm:text-3xl">
      {{ t("steps.title") }}
    </h2>
    <ol class="mt-8 grid gap-4 md:grid-cols-3">
      <li
        v-for="(step, index) in steps"
        :key="step.key"
        class="rounded-2xl border border-navy/8 bg-white/70 p-6 dark:border-white/10 dark:bg-white/[0.04]"
      >
        <div class="flex items-center gap-3">
          <span
            class="flex size-9 items-center justify-center rounded-full bg-amber text-sm font-semibold text-navy"
          >
            {{ index + 1 }}
          </span>
          <UiIcon
            :name="step.icon"
            class="size-6 text-navy/50 dark:text-white/50"
          />
        </div>
        <h3 class="mt-5 text-lg font-semibold">
          {{ t(`steps.${step.key}.title`) }}
        </h3>
        <p class="mt-2 leading-relaxed text-navy/70 dark:text-white/70">
          {{ t(`steps.${step.key}.body`) }}
        </p>
      </li>
    </ol>
  </section>
</template>
