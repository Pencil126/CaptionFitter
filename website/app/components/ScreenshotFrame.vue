<script setup lang="ts">
// Shows an app screenshot in a window frame, or a placeholder until one is provided.
// Screenshots live in public/screenshots/ as <name>.<locale>.png; pass src as /screenshots/….
const props = defineProps<{
  caption: string;
  src?: string;
}>();

const { t } = useI18n();
</script>

<template>
  <figure class="flex flex-col gap-3">
    <div
      class="overflow-hidden rounded-2xl border border-navy/10 bg-white/60 shadow-[0_24px_60px_-30px_rgb(21_23_43/0.45)] dark:border-white/10 dark:bg-white/5"
    >
      <img
        v-if="props.src"
        :src="props.src"
        :alt="caption"
        class="block h-auto w-full"
        loading="lazy"
      />
      <div
        v-else
        class="flex aspect-[16/10] items-center justify-center bg-[repeating-linear-gradient(135deg,transparent_0_12px,rgb(21_23_43/0.03)_12px_24px)] text-sm text-navy/50 dark:bg-[repeating-linear-gradient(135deg,transparent_0_12px,rgb(255_255_255/0.03)_12px_24px)] dark:text-white/40"
        role="img"
        :aria-label="caption"
      >
        {{ t("screenshots.placeholder") }}
      </div>
    </div>
    <figcaption class="text-sm text-navy/60 dark:text-white/60">
      {{ caption }}
    </figcaption>
  </figure>
</template>
