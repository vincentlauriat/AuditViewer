import type {
  AuditData,
  AuditEvent,
  AuditSummary,
  Manifest,
  SourcesFile,
} from "../shared/contract.ts";

const j = async <T>(url: string): Promise<T> => {
  const r = await fetch(url);
  if (!r.ok) throw new Error(`${r.status} ${url}`);
  return (await r.json()) as T;
};

export const api = {
  audits: () => j<AuditSummary[]>("/api/audits"),
  manifest: (slug: string) => j<Manifest>(`/api/audit/${slug}/manifest`),
  data: (slug: string) => j<AuditData>(`/api/audit/${slug}/data`),
  sources: (slug: string) => j<SourcesFile>(`/api/audit/${slug}/sources`),
  file: async (slug: string, name: string): Promise<string> => {
    const r = await fetch(`/api/audit/${slug}/file/${name}`);
    if (!r.ok) throw new Error(`${r.status} ${name}`);
    return r.text();
  },
};

/** S'abonne au flux d'événements SSE d'un audit. Renvoie une fonction de désabonnement. */
export function subscribeEvents(
  slug: string,
  onEvent: (ev: AuditEvent) => void,
  onError?: () => void,
): () => void {
  const es = new EventSource(`/api/audit/${slug}/events`);
  es.onmessage = (m) => {
    try {
      onEvent(JSON.parse(m.data) as AuditEvent);
    } catch {
      /* ligne non-JSON ignorée */
    }
  };
  es.onerror = () => onError?.();
  return () => es.close();
}
