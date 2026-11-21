<script setup lang="ts">
const { t } = useI18n();

useSeoMeta({ title: () => t("meta.title") });
</script>

<template>
  <div>
    <HeroSection />
    <HowItWorks />
    <FeatureGrid />
    <PrivacyNote />
  </div>
</template>
