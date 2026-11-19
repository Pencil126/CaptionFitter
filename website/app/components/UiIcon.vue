<script setup lang="ts">
// Simple outline icons drawn for this site, so no icon package is needed.
const props = defineProps<{
  name:
    | "download"
    | "github"
    | "globe"
    | "menu"
    | "close"
    | "arrow-left"
    | "arrow-right"
    | "lock"
    | "film"
    | "transcript"
    | "subtitles"
    | "edit"
    | "palette"
    | "export"
    | "chip"
    | "language"
    | "search"
    | "chevron-down";
}>();

const paths: Record<typeof props.name, string[]> = {
  download: ["M12 4v11", "m7 10 5 5 5-5", "M5 20h14"],
  github: [],
  globe: [
    "M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18Z",
    "M3.6 9h16.8",
    "M3.6 15h16.8",
    "M12 3c2.5 2.6 3.7 5.6 3.7 9s-1.2 6.4-3.7 9",
    "M12 3c-2.5 2.6-3.7 5.6-3.7 9s1.2 6.4 3.7 9",
  ],
  menu: ["M4 7h16", "M4 12h16", "M4 17h16"],
  close: ["M6 6l12 12", "M18 6 6 18"],
  "arrow-left": ["M19 12H5", "m11 6-6 6 6 6"],
  "arrow-right": ["M5 12h14", "m13 6 6 6-6 6"],
  lock: ["M6 11h12v9H6z", "M8.5 11V8a3.5 3.5 0 0 1 7 0v3"],
  film: [
    "M4 5h16v14H4z",
    "M8 5v14",
    "M16 5v14",
    "M4 9.5h4",
    "M4 14.5h4",
    "M16 9.5h4",
    "M16 14.5h4",
  ],
  transcript: [
    "M7 3h7l4 4v14H7z",
    "M14 3v4h4",
    "M10 11h5",
    "M10 14.5h5",
    "M10 18h3",
  ],
  subtitles: ["M3 5h18v14H3z", "M7 14h4", "M13 14h4", "M7 10.5h10"],
  edit: ["M4 20h4L19 9l-4-4L4 16z", "m13.5 6.5 4 4"],
  palette: [
    "M12 3a9 9 0 0 0 0 18c1.1 0 1.6-.8 1.6-1.6 0-1.3-1-1.5-1-2.6 0-.9.7-1.6 1.6-1.6H16a5 5 0 0 0 5-5C21 6.4 17 3 12 3Z",
    "M7.5 11.5h.01",
    "M10 7.5h.01",
    "M15 7.5h.01",
  ],
  export: ["M12 15V4", "m7 9 5-5 5 5", "M5 14v6h14v-6"],
  chip: [
    "M7 7h10v10H7z",
    "M10 3v4",
    "M14 3v4",
    "M10 17v4",
    "M14 17v4",
    "M3 10h4",
    "M3 14h4",
    "M17 10h4",
    "M17 14h4",
  ],
  language: [
    "M4 5h8",
    "M8 3v2",
    "M10 5c-.7 3.5-2.9 6.4-6 8",
    "M6 9c1 1.8 2.6 3.3 4.5 4.2",
    "m12 21 4.5-10 4.5 10",
    "M13.5 18h6",
  ],
  search: ["M10.5 4a6.5 6.5 0 1 0 0 13 6.5 6.5 0 0 0 0-13Z", "m15.5 15.5 5 5"],
  "chevron-down": ["m6 9 6 6 6-6"],
};
</script>

<template>
  <svg
    v-if="name === 'github'"
    viewBox="0 0 24 24"
    fill="currentColor"
    aria-hidden="true"
    focusable="false"
  >
    <path
      d="M12 2C6.48 2 2 6.58 2 12.23c0 4.52 2.87 8.35 6.84 9.7.5.1.68-.22.68-.49l-.01-1.7c-2.78.62-3.37-1.37-3.37-1.37-.46-1.18-1.11-1.5-1.11-1.5-.91-.64.07-.62.07-.62 1 .07 1.53 1.06 1.53 1.06.9 1.57 2.35 1.12 2.92.85.09-.66.35-1.12.63-1.37-2.22-.26-4.56-1.14-4.56-5.07 0-1.12.39-2.04 1.03-2.76-.1-.26-.45-1.3.1-2.71 0 0 .84-.28 2.75 1.05A9.4 9.4 0 0 1 12 6.98c.85 0 1.7.12 2.5.34 1.9-1.33 2.74-1.05 2.74-1.05.55 1.41.2 2.45.1 2.71.64.72 1.03 1.64 1.03 2.76 0 3.94-2.34 4.8-4.57 5.06.36.32.68.94.68 1.9l-.01 2.81c0 .27.18.6.69.49A10.1 10.1 0 0 0 22 12.23C22 6.58 17.52 2 12 2Z"
    />
  </svg>
  <svg
    v-else
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    stroke-width="1.75"
    stroke-linecap="round"
    stroke-linejoin="round"
    aria-hidden="true"
    focusable="false"
  >
    <path v-for="d in paths[name]" :key="d" :d="d" />
  </svg>
</template>
