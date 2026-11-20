<script setup lang="ts">
const { size = "sm" } = defineProps<{ size?: "sm" | "md" | "lg" }>();

const { locale, locales } = useI18n();
const switchLocalePath = useSwitchLocalePath();

// Only two languages, so the button simply offers the other one.
const other = computed(() =>
  locales.value.find((l) => l.code !== locale.value)!,
);
</script>

<template>
  <GlassButton
    :size="size"
    :to="switchLocalePath(other.code)"
    :localize="false"
    :lang="other.language"
    :hreflang="other.language"
  >
    <template #icon>
      <UiIcon name="globe" />
    </template>
    {{ other.name }}
  </GlassButton>
</template>
