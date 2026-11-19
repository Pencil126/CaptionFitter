/** The docs pages of the current language, in sidebar order. */
export function useDocsNav() {
  const { locale } = useI18n();
  const collection = computed(() =>
    locale.value === "zh-TW" ? "docs_zh" : "docs_en",
  );

  return useAsyncData(
    () => `docs-nav-${collection.value}`,
    () =>
      queryCollection(collection.value)
        .select("title", "path", "order")
        .order("order", "ASC")
        .all(),
    { watch: [collection] },
  );
}
