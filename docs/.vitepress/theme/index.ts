import DefaultTheme from "vitepress/theme";
import { h } from "vue";
import HomeWebEntry from "./HomeWebEntry.vue";
import "./screenshots.css";

export default {
  ...DefaultTheme,
  Layout: () =>
    h(DefaultTheme.Layout, null, {
      "home-hero-info-after": () => h(HomeWebEntry),
    }),
};
