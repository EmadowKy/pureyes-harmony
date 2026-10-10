<template>
  <a
    class="home-web-entry"
    href="/web/"
    target="_self"
    aria-label="网页版 Beta"
    aria-describedby="web-entry-description"
  >
    <svg
      class="web-entry-icon"
      viewBox="0 0 32 32"
      fill="none"
      aria-hidden="true"
    >
      <rect
        x="3"
        y="5"
        width="26"
        height="22"
        rx="4"
        stroke="currentColor"
        stroke-width="1.5"
      />
      <path
        d="M3 12h26M8 8.5h.1M12 8.5h.1M11 19h10m-4-4 4 4-4 4"
        stroke="currentColor"
        stroke-width="1.5"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
    <span class="web-entry-copy">
      <span class="web-entry-title"
        >网页版 <span class="web-entry-badge">Beta</span></span
      >
      <span id="web-entry-description" class="web-entry-description"
        >进入视频调查工作台</span
      >
    </span>
    <span class="web-entry-arrow" aria-hidden="true">→</span>
  </a>
</template>

<style scoped>
.home-web-entry {
  --entry-bg: #123a5a;
  --entry-hover: #194f7a;
  --entry-text: #f1f7ff;
  --entry-muted: #a9c2d8;
  --entry-badge: #ffeab6;
  --entry-badge-ink: #644711;
  display: flex;
  align-items: center;
  gap: 16px;
  width: min(100%, 370px);
  margin-top: 28px;
  padding: 16px 20px;
  border: 1px solid var(--entry-bg);
  border-radius: 12px;
  background: var(--entry-bg);
  color: var(--entry-text);
  transition:
    background-color 160ms ease,
    transform 160ms ease;
}
.home-web-entry:hover {
  background: var(--entry-hover);
  transform: translateY(-2px);
}
.home-web-entry:focus-visible {
  outline: 3px solid var(--vp-c-brand-1);
  outline-offset: 4px;
}
.web-entry-icon {
  width: 32px;
  height: 32px;
  flex-shrink: 0;
  color: var(--entry-muted);
}
.web-entry-copy {
  display: flex;
  flex-direction: column;
  min-width: 0;
  gap: 5px;
}
.web-entry-title {
  display: flex;
  align-items: center;
  gap: 10px;
  font-size: 17px;
  font-weight: 650;
  line-height: 24px;
}
.web-entry-badge {
  border-radius: 5px;
  padding: 0 7px;
  background: var(--entry-badge);
  color: var(--entry-badge-ink);
  font-size: 11px;
  font-weight: 700;
  line-height: 20px;
  letter-spacing: 0.02em;
}
.web-entry-description {
  color: var(--entry-muted);
  font-size: 13px;
  line-height: 20px;
}
.web-entry-arrow {
  margin-left: auto;
  padding-left: 8px;
  font-size: 24px;
  line-height: 32px;
}
@media (prefers-reduced-motion: reduce) {
  .home-web-entry {
    transition: none;
  }
  .home-web-entry:hover {
    transform: none;
  }
}
</style>

<style>
.VPNavBarMenuLink[href="/web/"] > span {
  padding: 5px 10px;
  border: 1px solid var(--vp-c-divider);
  border-radius: 7px;
  background: var(--vp-c-brand-soft);
  color: var(--vp-c-brand-1);
  line-height: 22px;
}
</style>
