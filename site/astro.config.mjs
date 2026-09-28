import { defineConfig } from "astro/config";
import sitemap from "@astrojs/sitemap";

export default defineConfig({
  site: "https://open1000x.gergo.cc",
  integrations: [sitemap()],
});
