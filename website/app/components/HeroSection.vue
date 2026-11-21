<script setup lang="ts">
const { t, locale } = useI18n();
</script>

<template>
  <section>
    <div
      class="mx-auto grid max-w-6xl items-center gap-12 px-4 pt-14 pb-16 sm:px-6 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.15fr)] lg:pt-24 lg:pb-24"
    >
      <div>
        <img
          src="/CaptionFitter.png"
          alt=""
          width="88"
          height="88"
          class="hero-enter mb-7 size-20 rounded-[22%] shadow-[0_18px_40px_-16px_rgb(21_23_43/0.55)] sm:size-22"
        />
        <h1
          class="hero-enter text-4xl font-semibold tracking-tight text-balance sm:text-5xl"
        >
          {{ t("hero.title") }}
        </h1>
        <p
          class="hero-enter mt-5 max-w-xl text-lg leading-relaxed text-navy/70 dark:text-white/70"
        >
          {{ t("hero.subtitle") }}
        </p>
        <div class="hero-enter mt-8 flex flex-wrap gap-3">
          <GlassButton
            variant="primary"
            size="lg"
            href="https://github.com/Pencil126/CaptionFitter/releases/latest"
          >
            <template #icon>
              <UiIcon name="download" />
            </template>
            {{ t("hero.download") }}
          </GlassButton>
          <GlassButton size="lg" to="/docs">
            <template #icon>
              <UiIcon name="transcript" />
            </template>
            {{ t("hero.docs") }}
          </GlassButton>
        </div>
        <p class="hero-enter mt-5 text-sm text-navy/55 dark:text-white/50">
          {{ t("hero.requirements") }}
        </p>
      </div>

      <ScreenshotFrame
        :label="t('screenshots.main')"
        :src="`/screenshots/main-window.${locale}.webp`"
        :width="1974"
        :height="1344"
        class="hero-enter hero-enter-late"
      />
    </div>
  </section>
</template>

<style scoped>
/* The hero eases in piece by piece on load. Only the starting frame is kept while waiting
   (backwards), so once the animation ends nothing stays applied: an opacity below 1 on an
   ancestor would stop the glass buttons from blurring what is behind them. */
.hero-enter {
  animation: hero-enter 0.6s cubic-bezier(0.2, 0.7, 0.2, 1) backwards;
}

.hero-enter:nth-child(2) {
  animation-delay: 80ms;
}

.hero-enter:nth-child(3) {
  animation-delay: 160ms;
}

.hero-enter:nth-child(4) {
  animation-delay: 240ms;
}

.hero-enter:nth-child(5) {
  animation-delay: 320ms;
}

/* The screenshot is the second item of its own row, so it needs its own delay. */
.hero-enter.hero-enter-late {
  animation-delay: 280ms;
}

@keyframes hero-enter {
  from {
    opacity: 0;
    transform: translateY(12px);
  }
}

@media (prefers-reduced-motion: reduce) {
  .hero-enter {
    animation: none;
  }
}
</style>
