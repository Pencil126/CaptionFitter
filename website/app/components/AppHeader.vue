<script setup lang="ts">
const { t } = useI18n();
const route = useRoute();
const menuOpen = ref(false);

watch(
  () => route.fullPath,
  () => {
    menuOpen.value = false;
  },
);
</script>

<template>
  <header
    class="sticky top-0 z-40 border-b border-navy/5 bg-page/70 backdrop-blur-xl dark:border-white/10 dark:bg-page-dark/70"
  >
    <div class="mx-auto flex h-16 max-w-6xl items-center gap-3 px-4 sm:px-6">
      <NuxtLinkLocale
        to="/"
        class="flex items-center gap-2.5 rounded-lg font-semibold"
        :aria-label="t('nav.home')"
      >
        <img
          src="/CaptionFitter.png"
          alt=""
          width="32"
          height="32"
          class="size-8 rounded-[22%]"
        />
        <span>CaptionFitter</span>
      </NuxtLinkLocale>

      <nav class="ml-auto hidden items-center gap-2 sm:flex">
        <GlassButton
          variant="primary"
          size="sm"
          href="https://github.com/Pencil126/CaptionFitter/releases/latest"
          :label="t('hero.download')"
        >
          <template #icon>
            <UiIcon name="download" />
          </template>
        </GlassButton>
        <GlassButton size="sm" to="/docs">
          {{ t("nav.docs") }}
        </GlassButton>
        <LanguageSwitcher />
        <GlassButton
          size="sm"
          href="https://github.com/Pencil126/CaptionFitter"
          :label="t('nav.github')"
        >
          <template #icon>
            <UiIcon name="github" />
          </template>
        </GlassButton>
      </nav>

      <div class="ml-auto sm:hidden">
        <GlassButton
          size="sm"
          :label="menuOpen ? t('nav.close') : t('nav.menu')"
          :aria-expanded="menuOpen"
          aria-controls="mobile-menu"
          @click="menuOpen = !menuOpen"
        >
          <template #icon>
            <UiIcon :name="menuOpen ? 'close' : 'menu'" />
          </template>
        </GlassButton>
      </div>
    </div>

    <div
      v-if="menuOpen"
      id="mobile-menu"
      class="border-t border-navy/5 px-4 pt-2 pb-4 sm:hidden dark:border-white/10"
    >
      <div class="mt-2 flex flex-col items-center gap-2">
        <GlassButton
          variant="primary"
          size="lg"
          href="https://github.com/Pencil126/CaptionFitter/releases/latest"
          class="w-full"
        >
          <template #icon>
            <UiIcon name="download" />
          </template>
          {{ t("nav.download") }}
        </GlassButton>
        <GlassButton size="lg" to="/docs" class="w-full">
          {{ t("nav.docs") }}
        </GlassButton>
        <LanguageSwitcher size="lg" class="w-full" />
        <GlassButton
          size="lg"
          href="https://github.com/Pencil126/CaptionFitter"
          class="w-full"
        >
          <template #icon>
            <UiIcon name="github" />
          </template>
          GitHub
        </GlassButton>
      </div>
    </div>
  </header>
</template>
