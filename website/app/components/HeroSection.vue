<script setup lang="ts">
const { t } = useI18n();
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
          class="mb-7 size-20 rounded-[22%] shadow-[0_18px_40px_-16px_rgb(21_23_43/0.55)] sm:size-22"
        />
        <h1
          class="text-4xl font-semibold tracking-tight text-balance sm:text-5xl"
        >
          {{ t("hero.title") }}
        </h1>
        <p
          class="mt-5 max-w-xl text-lg leading-relaxed text-navy/70 dark:text-white/70"
        >
          {{ t("hero.subtitle") }}
        </p>
        <div class="mt-8 flex flex-wrap gap-3">
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
          <GlassButton
            size="lg"
            href="https://github.com/Pencil126/CaptionFitter"
          >
            <template #icon>
              <UiIcon name="github" />
            </template>
            {{ t("hero.github") }}
          </GlassButton>
        </div>
        <p class="mt-5 text-sm text-navy/55 dark:text-white/50">
          {{ t("hero.requirements") }}
        </p>
      </div>

      <ScreenshotFrame :caption="t('screenshots.main')" />
    </div>
  </section>
</template>
