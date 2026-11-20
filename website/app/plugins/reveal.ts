// v-reveal fades an element in when it scrolls into view; the value is an extra delay in
// milliseconds for staggering. Elements are only hidden after the app has started and only when
// they are still below the fold, so nothing stays invisible if JavaScript fails and nothing on
// screen flickers. The fade itself is in main.css.
export default defineNuxtPlugin((nuxtApp) => {
  let observer: IntersectionObserver | undefined;

  nuxtApp.vueApp.directive<HTMLElement, number | undefined>("reveal", {
    getSSRProps: () => ({}),

    mounted(el, { value: delay = 0 }) {
      if (
        !("IntersectionObserver" in window) ||
        matchMedia("(prefers-reduced-motion: reduce)").matches ||
        el.getBoundingClientRect().top < window.innerHeight
      ) {
        return;
      }

      observer ??= new IntersectionObserver(
        (entries) => {
          for (const entry of entries) {
            if (!entry.isIntersecting) continue;
            entry.target.classList.add("revealed");
            observer?.unobserve(entry.target);
          }
        },
        { rootMargin: "0px 0px -10% 0px" },
      );

      el.style.setProperty("--reveal-delay", `${delay}ms`);
      el.classList.add("reveal");
      observer.observe(el);
    },

    unmounted(el) {
      observer?.unobserve(el);
    },
  });
});
