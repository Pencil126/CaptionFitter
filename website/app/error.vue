<script setup lang="ts">
import type { NuxtError } from "#app";

const props = defineProps<{ error: NuxtError }>();
const { t } = useI18n();
const notFound = computed(() => props.error.statusCode === 404);

useSeoMeta({
  title: () => (notFound.value ? t("error.notFound") : t("error.other")),
});
</script>

<template>
  <NuxtLayout>
    <section
      class="mx-auto flex max-w-2xl flex-col items-start px-4 py-24 sm:px-6"
    >
      <p class="font-mono text-sm text-navy/50 dark:text-white/50">
        {{ error.statusCode }}
      </p>
      <h1 class="mt-2 text-3xl font-semibold tracking-tight">
        {{ notFound ? t("error.notFound") : t("error.other") }}
      </h1>
      <p v-if="notFound" class="mt-3 text-navy/70 dark:text-white/70">
        {{ t("error.notFoundBody") }}
      </p>
      <GlassButton
        class="mt-8"
        variant="primary"
        @click="clearError({ redirect: $localePath('/') })"
      >
        {{ t("error.home") }}
      </GlassButton>
    </section>
  </NuxtLayout>
</template>
