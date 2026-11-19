<script setup lang="ts">
// Soft brand-coloured glows pinned to the viewport, so they stay in place while the page
// scrolls. They give the glass buttons something to refract.
defineProps<{
  /** Fainter glows for pages that are mostly reading, such as the docs. */
  subtle?: boolean;
}>();
</script>

<template>
  <div
    aria-hidden="true"
    class="glow-background"
    :class="{ 'glow-subtle': subtle }"
  >
    <div class="glow glow-amber" />
    <div class="glow glow-violet" />
    <div class="glow glow-navy" />
  </div>
</template>

<style scoped>
.glow-background {
  position: fixed;
  inset: 0;
  z-index: -10;
  overflow: hidden;
  pointer-events: none;
}

.glow {
  position: absolute;
  border-radius: 9999px;
  filter: blur(64px);
  will-change: transform;
}

.glow-amber {
  animation: drift-amber 26s ease-in-out infinite alternate;
  top: -8rem;
  left: 6%;
  width: min(28rem, 80vw);
  aspect-ratio: 1;
  background: rgb(255 197 61 / 0.45);
}

.glow-violet {
  animation: drift-violet 32s ease-in-out infinite alternate;
  top: 18%;
  right: 2%;
  width: min(30rem, 85vw);
  aspect-ratio: 1;
  background: rgb(91 91 214 / 0.25);
}

.glow-navy {
  animation: drift-navy 38s ease-in-out infinite alternate;
  bottom: -10rem;
  left: 34%;
  width: min(26rem, 75vw);
  aspect-ratio: 1;
  background: rgb(21 23 43 / 0.1);
}

@media (prefers-color-scheme: dark) {
  .glow-amber {
    background: rgb(255 197 61 / 0.25);
  }

  .glow-violet {
    background: rgb(91 91 214 / 0.35);
  }

  .glow-navy {
    background: rgb(42 47 107 / 0.6);
  }
}

.glow-subtle .glow {
  opacity: 0.55;
}

/* Each glow wanders on its own path and period, so the pattern never visibly repeats.
   The names are written out in each `animation` rather than passed through a CSS variable:
   scoped styles rename keyframes and can't follow a variable. */
@keyframes drift-amber {
  0% {
    transform: translate(0, 0) scale(1);
  }
  50% {
    transform: translate(18vw, 10vh) scale(1.15);
  }
  100% {
    transform: translate(6vw, 28vh) scale(0.9);
  }
}

@keyframes drift-violet {
  0% {
    transform: translate(0, 0) scale(1);
  }
  50% {
    transform: translate(-22vw, 14vh) scale(0.85);
  }
  100% {
    transform: translate(-8vw, -10vh) scale(1.1);
  }
}

@keyframes drift-navy {
  0% {
    transform: translate(0, 0) scale(1);
  }
  50% {
    transform: translate(-16vw, -18vh) scale(1.2);
  }
  100% {
    transform: translate(14vw, -6vh) scale(0.95);
  }
}

@media (prefers-reduced-motion: reduce) {
  .glow {
    animation: none;
  }
}
</style>
