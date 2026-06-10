// Types du contrat machine v1 du skill audit-report.
// Référence : PLAN.md à la racine du dépôt.

export type SourceTag = "Officielle" | "Analyste" | "Presse";

export interface Manifest {
  v: number;
  subject: string;
  subject_type: string;
  slug: string;
  output_dir: string;
  audit_date: string;
  depth: "quick" | "full";
  mode: "parallel" | "sequential" | "solo";
  options: string[];
  status: "complete" | "partial" | "canceled";
  dimensions: { key: string; file: string; status: string; sources_count?: number }[];
  files: { name: string; kind: string }[];
  sources_count: number | null;
  data_file?: string;
  sources_file?: string;
  report_file?: string;
}

export interface Kpi {
  key: string;
  label: string;
  value: number | string | null;
  unit?: string;
  period?: string;
  source_id?: number;
  estimated?: boolean;
}

export interface AuditData {
  v: number;
  subject: string;
  subject_type: string;
  as_of: string;
  kpis: Kpi[];
  financials?: Record<string, number | null>;
  market?: Record<string, number | null>;
  sources_count?: number | null;
  competitors_count?: number | null;
}

export interface Source {
  id: number;
  url: string;
  title: string;
  tag: SourceTag;
  date?: string;
  dimensions: string[];
  stale?: boolean;
}

export interface SourcesFile {
  v: number;
  sources: Source[];
}

export type AuditEventType =
  | "audit_start"
  | "phase_start"
  | "phase_done"
  | "dimension_start"
  | "dimension_done"
  | "progress"
  | "search"
  | "source"
  | "file_written"
  | "question"
  | "answer"
  | "error"
  | "audit_complete"
  | "audit_canceled";

export interface AuditEvent {
  v: number;
  ts: string;
  type: AuditEventType;
  // payload libre selon le type
  [k: string]: unknown;
}

// Configuration serveur : racine des audits (lecture + écriture).
export interface AppConfig {
  auditsRoot: string;
  source: "env" | "file" | "default";
  editable: boolean;
}

// --- Pilotage V2 ---

export type ControlAction = "cancel" | "pause" | "resume" | "rerun";

export interface LaunchRequest {
  subject: string;
  depth?: "quick" | "full";
  mode?: "parallel" | "sequential" | "solo";
  lang?: string;
  options?: string[]; // sous-ensemble de "swot" | "esg" | "rh"
}

// _question.json écrit par le skill : { v, id, text, options }.
export interface Question {
  v?: number;
  id: string;
  text: string;
  options?: string[];
}

// Réponse de GET /api/audit/:slug/question.
export type QuestionFile = Question | { question: null };

// _recon.json — métadonnées de reconnaissance (présent même sur les audits "legacy"
// générés avant le contrat v1, qui n'ont pas de _manifest.json).
export interface Recon {
  subject?: string;
  subject_type?: string;
  sector?: string;
  key_players?: string[];
  audit_date?: string;
  depth?: string;
  sources_count?: number;
  [k: string]: unknown;
}

// Liste des fichiers d'un dossier d'audit (GET /api/audit/:slug/files).
export interface FilesList {
  files: string[];
}

// Résumé d'un audit pour la liste (dérivé du manifest ou du recon).
export interface AuditSummary {
  slug: string;
  subject: string;
  subject_type?: string;
  status?: string;
  audit_date?: string;
  depth?: string;
  dir: string;
  hasManifest: boolean;
}
