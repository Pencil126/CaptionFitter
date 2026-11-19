<script setup lang="ts">
const { t } = useI18n();

useSeoMeta({ title: () => t("meta.title") });
</script>

<template>
  <div>
    <HeroSection />
    <HowItWorks />
    <FeatureGrid />
    <section class="mx-auto max-w-6xl px-4 py-16 sm:px-6">
      <h2 class="text-2xl font-semibold tracking-tight sm:text-3xl">
        {{ t("screenshots.title") }}
      </h2>
      <div class="mt-8 grid gap-8 md:grid-cols-2">
        <ScreenshotFrame :caption="t('screenshots.editor')" />
        <ScreenshotFrame :caption="t('screenshots.export')" />
      </div>
    </section>
    <PrivacyNote />
  </div>
</template>
