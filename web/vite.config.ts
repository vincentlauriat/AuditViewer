import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

const SERVER = process.env.VITE_SERVER_URL || "http://localhost:3001";

// Frontend dev server (5173) proxies API + SSE to the Express backend (3001).
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      "/api": { target: SERVER, changeOrigin: true },
    },
  },
  build: { outDir: "dist/web" },
});
