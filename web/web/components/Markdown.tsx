import { useEffect, useState } from "react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import { api } from "../api.ts";

export function Markdown({ slug, file }: { slug: string; file: string }) {
  const [md, setMd] = useState<string>("");
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    setMd("");
    setErr(null);
    api
      .file(slug, file)
      .then(setMd)
      .catch(() => setErr(`Impossible de charger ${file}`));
  }, [slug, file]);

  if (err) return <div className="empty">{err}</div>;
  if (!md) return <div className="empty">Chargement…</div>;
  return (
    <div className="markdown">
      <ReactMarkdown remarkPlugins={[remarkGfm]}>{md}</ReactMarkdown>
    </div>
  );
}
