<template>
  <div class="flex min-h-dvh flex-col">
    <GlowBackground />
    <AppHeader />
    <main class="flex-1">
      <slot />
    </main>
    <AppFooter />
  </div>
</template>
