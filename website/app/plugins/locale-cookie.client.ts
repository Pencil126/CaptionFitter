// Remembers the language the visitor switched to, so the next visit to the home page opens in it.
// The script in nuxt.config.ts reads the cookie before the app starts.
export default defineNuxtPlugin((nuxtApp) => {
  const cookie = useCookie(useRuntimeConfig().public.localeCookie, {
    maxAge: 60 * 60 * 24 * 30,
    sameSite: "lax",
  });

  nuxtApp.hook("i18n:localeSwitched", ({ newLocale }) => {
    cookie.value = newLocale;
  });
});
