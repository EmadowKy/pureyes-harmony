<template>
  <nav class="home-app-entries" aria-label="使用清眸">
    <a
      class="home-app-entry home-web-entry"
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
    <a
      class="home-app-entry home-harmony-entry"
      href="https://github.com/EmadowKy/pureyes-harmony/releases/latest"
      target="_blank"
      rel="noopener noreferrer"
      aria-label="鸿蒙版下载（新窗口）"
      aria-describedby="harmony-entry-description"
    >
      <svg
        class="web-entry-icon"
        viewBox="0 0 32 32"
        fill="none"
        aria-hidden="true"
      >
        <rect
          x="7"
          y="2"
          width="18"
          height="28"
          rx="4"
          stroke="currentColor"
          stroke-width="1.5"
        />
        <path
          d="M13 5h6M16 11v10m-4-4 4 4 4-4M14 27h4"
          stroke="currentColor"
          stroke-width="1.5"
          stroke-linecap="round"
          stroke-linejoin="round"
        />
      </svg>
      <span class="web-entry-copy">
        <span class="web-entry-title"
          >鸿蒙版 <span class="web-entry-badge">HAP</span></span
        >
        <span id="harmony-entry-description" class="web-entry-description"
          >下载鸿蒙安装包</span
        >
      </span>
      <span class="web-entry-arrow" aria-hidden="true">↓</span>
    </a>
  </nav>
</template>

<style scoped>
.home-app-entries {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 16px;
  width: min(100%, 756px);
  margin-top: 28px;
  text-align: left;
}
.home-app-entry {
  --entry-bg: #123a5a;
  --entry-hover: #194f7a;
  --entry-text: #f1f7ff;
  --entry-muted: #a9c2d8;
  --entry-badge: #ffeab6;
  --entry-badge-ink: #644711;
  display: flex;
  align-items: center;
  gap: 16px;
  min-width: 0;
  padding: 16px 20px;
  border: 1px solid var(--entry-bg);
  border-radius: 12px;
  background: var(--entry-bg);
  color: var(--entry-text);
  transition:
    background-color 160ms ease,
    transform 160ms ease;
}
.home-app-entry:hover {
  background: var(--entry-hover);
  transform: translateY(-2px);
}
.home-app-entry:focus-visible {
  outline: 3px solid var(--vp-c-brand-1);
  outline-offset: 4px;
}
.home-harmony-entry {
  --entry-badge: #bde8ff;
  --entry-badge-ink: #114d6d;
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
@media (max-width: 639px) {
  .home-app-entries {
    grid-template-columns: minmax(0, 1fr);
    max-width: 370px;
  }
}
@media (prefers-reduced-motion: reduce) {
  .home-app-entry {
    transition: none;
  }
  .home-app-entry:hover {
    transform: none;
  }
}
</style>

<style>
@media (min-width: 768px) and (max-width: 959px) {
  .VPNavBarSearch {
    padding-left: 12px;
  }
  .VPNavBarSearch .DocSearch-Button {
    justify-content: center;
    width: 44px;
    padding: 0;
  }
  .VPNavBarSearch .DocSearch-Button-Placeholder,
  .VPNavBarSearch .DocSearch-Button-Keys {
    display: none;
  }
  .VPNavBarSearch .DocSearch-Search-Icon {
    margin-right: 0;
  }
}
.VPNavBarMenuLink[href="/web/"] > span {
  padding: 5px 10px;
  border: 1px solid var(--vp-c-divider);
  border-radius: 7px;
  background: var(--vp-c-brand-soft);
  color: var(--vp-c-brand-1);
  line-height: 22px;
}
</style>
