<script setup lang="ts">
import { NuxtLink } from "#components";

/**
 * A pill-shaped "liquid glass" button used for every button on the site.
 *
 * The glass is built from a translucent fill, a backdrop blur and inset highlights, which every
 * modern browser supports. On Chromium browsers it also bends the backdrop along the rim with an
 * SVG displacement filter (`backdrop-filter: url(#…)`); Safari and Firefox ignore filter
 * references in `backdrop-filter`, so they keep the plain glass.
 */
const props = withDefaults(
  defineProps<{
    variant?: "primary" | "secondary";
    size?: "sm" | "md" | "lg";
    /** A route inside the site. */
    to?: string;
    /** Adds the current language prefix to `to`; turn off for paths that already have one. */
    localize?: boolean;
    /** An address outside the site. */
    href?: string;
    type?: "button" | "submit" | "reset";
    /** Strength of the rim refraction; 0 turns it off. */
    refraction?: number;
    /** Needed when the button only shows an icon. */
    label?: string;
  }>(),
  {
    variant: "secondary",
    size: "md",
    type: "button",
    localize: true,
    refraction: 1,
  },
);

const localePath = useLocalePath();

const tag = computed(() => (props.to ? NuxtLink : props.href ? "a" : "button"));
const linkAttrs = computed(() => {
  if (props.to) return { to: props.localize ? localePath(props.to) : props.to };
  if (props.href) return { href: props.href, rel: "noopener" };
  return { type: props.type };
});

const root = ref<{ $el?: HTMLElement } | HTMLElement | null>(null);
const element = (): HTMLElement | null => {
  const value = root.value;
  if (!value) return null;
  return value instanceof HTMLElement ? value : (value.$el ?? null);
};

// The filter is only added after mounting, so the prerendered HTML and the first client render
// are identical.
const filterId = `glass-${useId().replace(/[^\w-]/g, "")}`;
const refracting = ref(false);
const map = ref<{ url: string; width: number; height: number } | null>(null);

const displacement = computed(() => {
  if (!map.value) return 0;
  // Proportional to height, so small and large buttons bend by a similar share of their rim.
  return Math.round(map.value.height * 0.42 * props.refraction);
});

const glassStyle = computed(() =>
  refracting.value && map.value
    ? { backdropFilter: `url(#${filterId}) blur(3px) saturate(175%)` }
    : undefined,
);

/**
 * Draws a displacement map for a pill of the given size. Red and green hold the x and y offsets
 * (0.5 = no offset). The centre is left untouched; within the rim, pixels sample the backdrop
 * from further inside, so it looks magnified and bent like the edge of a thick lens.
 */
function drawMap(width: number, height: number): string {
  const scale = Math.min(2, window.devicePixelRatio || 1);
  const w = Math.max(1, Math.round(width * scale));
  const h = Math.max(1, Math.round(height * scale));
  const canvas = document.createElement("canvas");
  canvas.width = w;
  canvas.height = h;
  const context = canvas.getContext("2d")!;
  const image = context.createImageData(w, h);

  const radius = h / 2;
  const rim = Math.min(radius, 22 * scale);
  const halfInnerX = w / 2 - radius;
  const halfInnerY = h / 2 - radius;

  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const px = x + 0.5 - w / 2;
      const py = y + 0.5 - h / 2;
      // Signed distance to a rounded rectangle; negative inside.
      const qx = Math.abs(px) - halfInnerX;
      const qy = Math.abs(py) - halfInnerY;
      const ox = Math.max(qx, 0);
      const oy = Math.max(qy, 0);
      const outside = Math.hypot(ox, oy);
      const distance = outside + Math.min(Math.max(qx, qy), 0) - radius;
      const depth = -distance;

      let dx = 0;
      let dy = 0;
      if (depth > 0 && depth < rim) {
        // Outward normal of the nearest edge.
        let nx: number;
        let ny: number;
        if (outside > 0) {
          nx = (ox / outside) * Math.sign(px);
          ny = (oy / outside) * Math.sign(py);
        } else if (qx > qy) {
          nx = Math.sign(px);
          ny = 0;
        } else {
          nx = 0;
          ny = Math.sign(py);
        }
        // A circular lens profile: flat in the middle, steepest at the very edge.
        const t = 1 - depth / rim;
        const strength = 1 - Math.sqrt(1 - t * t);
        dx = -nx * strength;
        dy = -ny * strength;
      }

      const i = (y * w + x) * 4;
      image.data[i] = Math.round(127.5 + dx * 127.5);
      image.data[i + 1] = Math.round(127.5 + dy * 127.5);
      image.data[i + 2] = 128;
      image.data[i + 3] = 255;
    }
  }

  context.putImageData(image, 0, 0);
  return canvas.toDataURL();
}

function supportsRefraction(): boolean {
  if (props.refraction <= 0) return false;
  if (window.matchMedia("(prefers-reduced-transparency: reduce)").matches)
    return false;
  // Only Chromium applies SVG filters inside backdrop-filter. CSS.supports() can't tell, because
  // other engines accept the syntax and then draw nothing.
  const brands = (
    navigator as Navigator & {
      userAgentData?: { brands?: { brand: string }[] };
    }
  ).userAgentData?.brands;
  return !!brands?.some((b) => b.brand === "Chromium");
}

let observer: ResizeObserver | undefined;
let frame = 0;

function updateMap() {
  const el = element();
  if (!el) return;
  // offsetWidth ignores the press-down transform, so pressing doesn't redraw the map.
  const width = el.offsetWidth;
  const height = el.offsetHeight;
  if (!width || !height) return;
  if (map.value && map.value.width === width && map.value.height === height)
    return;
  map.value = { url: drawMap(width, height), width, height };
}

onMounted(() => {
  if (!supportsRefraction()) return;
  refracting.value = true;
  updateMap();
  observer = new ResizeObserver(() => {
    cancelAnimationFrame(frame);
    frame = requestAnimationFrame(updateMap);
  });
  const el = element();
  if (el) observer.observe(el);
});

onBeforeUnmount(() => {
  observer?.disconnect();
  cancelAnimationFrame(frame);
});

// The sheen follows the pointer; CSS turns this off for reduced motion.
function onPointerMove(event: PointerEvent) {
  const el = event.currentTarget as HTMLElement;
  const rect = el.getBoundingClientRect();
  el.style.setProperty(
    "--sheen-x",
    `${Math.round(event.clientX - rect.left)}px`,
  );
  el.style.setProperty(
    "--sheen-y",
    `${Math.round(event.clientY - rect.top)}px`,
  );
}

function onPointerLeave(event: PointerEvent) {
  const el = event.currentTarget as HTMLElement;
  el.style.removeProperty("--sheen-x");
  el.style.removeProperty("--sheen-y");
}
</script>

<template>
  <component
    :is="tag"
    ref="root"
    v-bind="linkAttrs"
    :aria-label="label"
    class="glass-button"
    :class="[
      `glass-${variant}`,
      `glass-${size}`,
      { 'glass-icon-only': !$slots.default },
    ]"
    :style="glassStyle"
    @pointermove="onPointerMove"
    @pointerleave="onPointerLeave"
  >
    <svg
      v-if="refracting && map"
      class="glass-defs"
      aria-hidden="true"
      focusable="false"
    >
      <filter
        :id="filterId"
        x="0"
        y="0"
        :width="map.width"
        :height="map.height"
        filterUnits="userSpaceOnUse"
        color-interpolation-filters="sRGB"
      >
        <feImage
          :href="map.url"
          x="0"
          y="0"
          :width="map.width"
          :height="map.height"
          preserveAspectRatio="none"
          result="map"
        />
        <!-- Each colour channel is bent by a slightly different amount for a faint
             chromatic fringe along the rim. -->
        <feDisplacementMap
          in="SourceGraphic"
          in2="map"
          :scale="displacement"
          xChannelSelector="R"
          yChannelSelector="G"
          result="bentRed"
        />
        <feColorMatrix
          in="bentRed"
          type="matrix"
          values="1 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 1 0"
          result="red"
        />
        <feDisplacementMap
          in="SourceGraphic"
          in2="map"
          :scale="displacement * 0.94"
          xChannelSelector="R"
          yChannelSelector="G"
          result="bentGreen"
        />
        <feColorMatrix
          in="bentGreen"
          type="matrix"
          values="0 0 0 0 0  0 1 0 0 0  0 0 0 0 0  0 0 0 1 0"
          result="green"
        />
        <feDisplacementMap
          in="SourceGraphic"
          in2="map"
          :scale="displacement * 0.88"
          xChannelSelector="R"
          yChannelSelector="G"
          result="bentBlue"
        />
        <feColorMatrix
          in="bentBlue"
          type="matrix"
          values="0 0 0 0 0  0 0 0 0 0  0 0 1 0 0  0 0 0 1 0"
          result="blue"
        />
        <feBlend in="red" in2="green" mode="screen" result="redGreen" />
        <feBlend in="redGreen" in2="blue" mode="screen" />
      </filter>
    </svg>
    <span v-if="$slots.icon" class="glass-icon" aria-hidden="true"
      ><slot name="icon"
    /></span>
    <span v-if="$slots.default" class="glass-label"><slot /></span>
  </component>
</template>

<style scoped>
.glass-button {
  --glass-fill: rgb(255 255 255 / 0.38);
  --glass-text: #15172b;
  --glass-border: rgb(255 255 255 / 0.6);
  --glass-top: rgb(255 255 255 / 0.85);
  --glass-bottom: rgb(21 23 43 / 0.1);
  --glass-shadow: rgb(21 23 43 / 0.14);
  --glass-sheen: rgb(255 255 255 / 0.55);
  --glass-solid: #ffffff;

  position: relative;
  isolation: isolate;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 0.5em;
  border-radius: 9999px;
  border: 1px solid var(--glass-border);
  background: var(--glass-fill);
  color: var(--glass-text);
  font-weight: 500;
  line-height: 1;
  white-space: nowrap;
  text-decoration: none;
  cursor: pointer;
  user-select: none;
  -webkit-backdrop-filter: blur(14px) saturate(175%);
  backdrop-filter: blur(14px) saturate(175%);
  box-shadow:
    inset 0 1px 0 var(--glass-top),
    inset 0 -1px 0 var(--glass-bottom),
    0 8px 24px -8px var(--glass-shadow),
    0 1px 2px var(--glass-shadow);
  transition:
    transform 160ms ease,
    box-shadow 160ms ease,
    background-color 160ms ease;
}

/* A soft highlight that follows the pointer. */
.glass-button::before {
  content: "";
  position: absolute;
  inset: 0;
  z-index: -1;
  border-radius: inherit;
  background: radial-gradient(
    140px circle at var(--sheen-x, 30%) var(--sheen-y, 0%),
    var(--glass-sheen),
    transparent 65%
  );
  opacity: 0.75;
  transition: opacity 160ms ease;
  pointer-events: none;
}

.glass-button:hover::before {
  opacity: 1;
}

.glass-button:active {
  transform: scale(0.97);
}

.glass-primary {
  --glass-fill: rgb(255 197 61 / 0.68);
  --glass-text: #15172b;
  --glass-border: rgb(255 236 186 / 0.75);
  --glass-top: rgb(255 248 228 / 0.9);
  --glass-bottom: rgb(120 80 0 / 0.2);
  --glass-shadow: rgb(160 110 0 / 0.3);
  --glass-sheen: rgb(255 255 255 / 0.6);
  --glass-solid: #ffc53d;
}

@media (prefers-color-scheme: dark) {
  .glass-secondary {
    --glass-fill: rgb(255 255 255 / 0.1);
    --glass-text: #ffffff;
    --glass-border: rgb(255 255 255 / 0.2);
    --glass-top: rgb(255 255 255 / 0.32);
    --glass-bottom: rgb(0 0 0 / 0.3);
    --glass-shadow: rgb(0 0 0 / 0.45);
    --glass-sheen: rgb(255 255 255 / 0.22);
    --glass-solid: #262a45;
  }

  /* More opaque over dark backdrops so navy text keeps enough contrast. */
  .glass-primary {
    --glass-fill: rgb(255 197 61 / 0.84);
    --glass-shadow: rgb(0 0 0 / 0.45);
  }
}

.glass-sm {
  height: 2rem;
  padding: 0 0.875rem;
  font-size: 0.8125rem;
}

.glass-md {
  height: 2.5rem;
  padding: 0 1.25rem;
  font-size: 0.875rem;
}

.glass-lg {
  height: 3rem;
  padding: 0 1.625rem;
  font-size: 1rem;
}

.glass-icon-only {
  aspect-ratio: 1;
  padding: 0;
}

.glass-icon {
  display: inline-flex;
  width: 1.15em;
  height: 1.15em;
}

.glass-icon :deep(svg) {
  width: 100%;
  height: 100%;
}

.glass-defs {
  position: absolute;
  width: 0;
  height: 0;
  overflow: hidden;
}

/* Without backdrop blur the translucent fill would be hard to read, so use a solid one. */
@supports not (
  (backdrop-filter: blur(1px)) or (-webkit-backdrop-filter: blur(1px))
) {
  .glass-button {
    background: var(--glass-solid);
  }
}

@media (prefers-reduced-transparency: reduce) {
  .glass-button {
    background: var(--glass-solid);
  }
}

@media (prefers-reduced-motion: reduce) {
  .glass-button,
  .glass-button::before {
    transition: none;
  }

  .glass-button:active {
    transform: none;
  }

  .glass-button::before {
    background: radial-gradient(
      140px circle at 30% 0%,
      var(--glass-sheen),
      transparent 65%
    );
  }
}
</style>
