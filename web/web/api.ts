import type {
  AppConfig,
  AuditData,
  AuditEvent,
  AuditSummary,
  ControlAction,
  FilesList,
  LaunchRequest,
  Manifest,
  QuestionFile,
  Recon,
  SourcesFile,
} from "../shared/contract.ts";

const j = async <T>(url: string): Promise<T> => {
  const r = await fetch(url);
  if (!r.ok) throw new Error(`${r.status} ${url}`);
  return (await r.json()) as T;
};

/** POST/PUT JSON ; lève une Error avec le message serveur si !ok. */
const send = async <T>(url: string, method: string, body: unknown): Promise<T> => {
  const r = await fetch(url, {
    method,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const data = (await r.json().catch(() => ({}))) as T & { error?: string };
  if (!r.ok) throw new Error(data.error || `${r.status} ${url}`);
  return data;
};

export const api = {
  audits: () => j<AuditSummary[]>("/api/audits"),
  manifest: (slug: string) => j<Manifest>(`/api/audit/${slug}/manifest`),
  recon: (slug: string) => j<Recon>(`/api/audit/${slug}/recon`),
  files: (slug: string) => j<FilesList>(`/api/audit/${slug}/files`),
  data: (slug: string) => j<AuditData>(`/api/audit/${slug}/data`),
  sources: (slug: string) => j<SourcesFile>(`/api/audit/${slug}/sources`),
  file: async (slug: string, name: string): Promise<string> => {
    const r = await fetch(`/api/audit/${slug}/file/${name}`);
    if (!r.ok) throw new Error(`${r.status} ${name}`);
    return r.text();
  },
  config: () => j<AppConfig>("/api/config"),
  setConfig: (auditsRoot: string) =>
    send<AppConfig>("/api/config", "PUT", { auditsRoot }),
  launch: (req: LaunchRequest) =>
    send<{ slug: string; pid: number }>("/api/audits/launch", "POST", req),
  question: (slug: string) =>
    j<QuestionFile>(`/api/audit/${slug}/question`),
  answer: (slug: string, value: string, id?: string) =>
    send<{ ok: true }>(`/api/audit/${slug}/answer`, "POST", { value, id }),
  control: (slug: string, action: ControlAction, dimension?: string) =>
    send<{ ok: true }>(`/api/audit/${slug}/control`, "POST", { action, dimension }),
  status: (slug: string) =>
    j<{ running: boolean; pid?: number }>(`/api/audit/${slug}/status`),
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
