<script setup lang="ts">
// Shows an app screenshot in a window frame. Until there is a screenshot, and while one is still
// downloading, the frame shows a sheen sweeping across it.
// Screenshots live in public/screenshots/ as <name>.<locale>.webp; pass src as /screenshots/….
// width and height are the image's pixel size: the frame takes the same shape before the image
// arrives, so nothing jumps and nothing gets cropped. Without them the frame is 16:9.
// The label is not shown; it is what screen readers announce for the screenshot.
const {
  label,
  src,
  width = 16,
  height = 9,
} = defineProps<{
  label: string;
  src?: string;
  width?: number;
  height?: number;
}>();

const image = ref<HTMLImageElement>();
// Only set once the app is running: before that the image shows as soon as the browser has it,
// so it never stays hidden if JavaScript fails.
const loading = ref(false);
const failed = ref(false);

onMounted(() => {
  const img = image.value;
  if (img && !(img.complete && img.naturalWidth > 0)) loading.value = true;
});

const showPlaceholder = computed(() => !src || loading.value || failed.value);
</script>

<template>
  <div
    role="img"
    :aria-label="label"
    class="relative overflow-hidden rounded-2xl border border-navy/10 bg-white/60 shadow-[0_24px_60px_-30px_rgb(21_23_43/0.45)] dark:border-white/10 dark:bg-white/5"
    :style="{ aspectRatio: `${width} / ${height}` }"
  >
    <div
      class="placeholder absolute inset-0"
      :class="{ shimmer: showPlaceholder }"
    />
    <img
      v-if="src && !failed"
      ref="image"
      :src="src"
      alt=""
      :width="width"
      :height="height"
      class="absolute inset-0 size-full object-cover"
      :class="loading ? 'opacity-0' : 'transition-opacity duration-500'"
      loading="lazy"
      @load="loading = false"
      @error="failed = true"
    />
  </div>
</template>

<style scoped>
.shimmer::after {
  content: "";
  position: absolute;
  inset: 0;
  background: linear-gradient(
    100deg,
    transparent 30%,
    rgb(255 255 255 / 0.7) 50%,
    transparent 70%
  );
  transform: translateX(-100%);
  animation: shimmer 2.4s ease-in-out infinite;
}

@media (prefers-color-scheme: dark) {
  .shimmer::after {
    background: linear-gradient(
      100deg,
      transparent 30%,
      rgb(255 255 255 / 0.07) 50%,
      transparent 70%
    );
  }
}

@keyframes shimmer {
  to {
    transform: translateX(100%);
  }
}

@media (prefers-reduced-motion: reduce) {
  .shimmer::after {
    display: none;
  }
}
</style>
