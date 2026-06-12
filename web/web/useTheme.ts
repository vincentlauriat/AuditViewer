import { useEffect, useState } from "react";

export type Theme = "dark" | "light" | "auto";

function applyTheme(theme: Theme) {
  const mq = window.matchMedia("(prefers-color-scheme: dark)");
  const isDark = theme === "dark" || (theme === "auto" && mq.matches);
  document.documentElement.classList.toggle("theme-light", !isDark);
}

export function useTheme(): [Theme, (t: Theme) => void] {
  const [theme, setTheme] = useState<Theme>(() => {
    return (localStorage.getItem("av-theme") as Theme) ?? "auto";
  });

  useEffect(() => {
    localStorage.setItem("av-theme", theme);
    applyTheme(theme);

    if (theme !== "auto") return;
    const mq = window.matchMedia("(prefers-color-scheme: dark)");
    const handler = () => applyTheme("auto");
    mq.addEventListener("change", handler);
    return () => mq.removeEventListener("change", handler);
  }, [theme]);

  return [theme, setTheme];
}
