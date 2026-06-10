import express from "express";
import cors from "cors";
import fs from "node:fs";
import fsp from "node:fs/promises";
import path from "node:path";
import os from "node:os";
import { spawn, type ChildProcess } from "node:child_process";
import { fileURLToPath } from "node:url";
import type { AuditSummary, Manifest } from "../shared/contract.ts";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.PORT) || 3001;
// Binaire du runner headless (surchargeable pour les tests via CLAUDE_BIN).
const CLAUDE_BIN = process.env.CLAUDE_BIN || "claude";

/**
 * Slug déterministe, réplique de la règle Python du skill (SKILL.md étape 0) :
 * NFKD → ASCII (accents retirés) → non-alphanumérique = "-" → trim/compression
 * des tirets → minuscules → défaut "sujet".
 */
function slugify(subject: string): string {
  const ascii = subject
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "") // diacritiques combinants
    .replace(/[^\x00-\x7f]/g, ""); // tout reste non-ASCII
  const s = ascii
    .replace(/[^a-zA-Z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .toLowerCase();
  return s || "sujet";
}

/** Processus runner en cours, indexés par slug. */
const running = new Map<string, ChildProcess>();

/** Écrit un JSON atomiquement (.tmp + rename) dans un dossier d'audit. */
async function writeJsonAtomic(dir: string, file: string, data: unknown): Promise<void> {
  const target = path.join(dir, file);
  const tmp = `${target}.tmp`;
  await fsp.writeFile(tmp, JSON.stringify(data));
  await fsp.rename(tmp, target);
}

// Racine où chercher ET écrire les dossiers d'audit. Un dossier d'audit = un
// répertoire contenant _manifest.json ou _recon.json.
//
// Résolution dynamique par ordre de priorité :
//   1. variable d'env AUDITS_ROOT (prioritaire, non écrasable depuis l'UI),
//   2. fichier de config local `.auditviewer.config.json` ({ auditsRoot }),
//   3. défaut : ~/Documents/Research (dossier où sont rangés les audits).
const CONFIG_PATH = path.resolve(__dirname, "..", ".auditviewer.config.json");
const DEFAULT_ROOT = path.join(os.homedir(), "Documents", "Research");
const ENV_ROOT = process.env.AUDITS_ROOT
  ? path.resolve(process.env.AUDITS_ROOT)
  : null;

type RootSource = "env" | "file" | "default";

/** Lit le auditsRoot persisté dans le fichier de config, ou null. */
function readConfigRoot(): string | null {
  try {
    const raw = fs.readFileSync(CONFIG_PATH, "utf-8");
    const cfg = JSON.parse(raw) as { auditsRoot?: unknown };
    if (typeof cfg.auditsRoot === "string" && cfg.auditsRoot.trim()) {
      return path.resolve(cfg.auditsRoot);
    }
  } catch {
    /* pas de config / illisible → ignorer */
  }
  return null;
}

/** Résout la racine courante et sa provenance, à chaud (jamais figée au boot). */
function resolveRoot(): { root: string; source: RootSource } {
  if (ENV_ROOT) return { root: ENV_ROOT, source: "env" };
  const fromFile = readConfigRoot();
  if (fromFile) return { root: fromFile, source: "file" };
  return { root: path.resolve(DEFAULT_ROOT), source: "default" };
}

/** Racine courante (recalculée à chaque appel pour rester dynamique). */
const auditsRoot = (): string => resolveRoot().root;

const isAuditDir = (dir: string) =>
  fs.existsSync(path.join(dir, "_manifest.json")) ||
  fs.existsSync(path.join(dir, "_recon.json"));

/** Trouve les dossiers d'audit jusqu'à 2 niveaux sous la racine courante. */
async function findAudits(): Promise<AuditSummary[]> {
  const out: AuditSummary[] = [];
  const scan = async (dir: string, depth: number) => {
    let entries: fs.Dirent[];
    try {
      entries = await fsp.readdir(dir, { withFileTypes: true });
    } catch {
      return;
    }
    if (isAuditDir(dir)) out.push(await summarize(dir));
    if (depth <= 0) return;
    for (const e of entries) {
      if (e.isDirectory() && !e.name.startsWith(".") && e.name !== "node_modules") {
        await scan(path.join(dir, e.name), depth - 1);
      }
    }
  };
  await scan(auditsRoot(), 2);
  // dédup par chemin
  return [...new Map(out.map((a) => [a.dir, a])).values()];
}

async function summarize(dir: string): Promise<AuditSummary> {
  const slug = path.basename(dir);
  const summary: AuditSummary = { slug, subject: slug, dir, hasManifest: false };
  try {
    const m = JSON.parse(await fsp.readFile(path.join(dir, "_manifest.json"), "utf-8")) as Manifest;
    Object.assign(summary, {
      hasManifest: true,
      subject: m.subject ?? slug,
      slug: m.slug ?? slug,
      subject_type: m.subject_type,
      status: m.status,
      audit_date: m.audit_date,
      depth: m.depth,
    });
  } catch {
    try {
      const r = JSON.parse(await fsp.readFile(path.join(dir, "_recon.json"), "utf-8"));
      summary.subject = r.subject ?? slug;
      summary.subject_type = r.subject_type;
      summary.audit_date = r.audit_date;
      summary.depth = r.depth;
    } catch {
      /* dossier minimal */
    }
  }
  return summary;
}

/** Résout le dossier d'un slug en empêchant tout path traversal. */
async function resolveAuditDir(slug: string): Promise<string | null> {
  const audits = await findAudits();
  const match = audits.find((a) => a.slug === slug);
  if (match) {
    const resolved = path.resolve(match.dir);
    if (!resolved.startsWith(auditsRoot())) return null; // garde-fou
    return resolved;
  }
  // Audit fraîchement lancé : le dossier existe mais n'a pas encore de
  // _manifest.json / _recon.json. On le résout par nom (basename), avec le
  // même garde-fou path-traversal.
  return resolveDirByName(slug);
}

/** Résout un dossier d'audit par son nom de base directement sous la racine. */
async function resolveDirByName(slug: string): Promise<string | null> {
  if (!/^[A-Za-z0-9_.-]+$/.test(slug)) return null; // pas de séparateur de chemin
  const root = auditsRoot();
  const resolved = path.resolve(root, slug);
  if (!resolved.startsWith(root)) return null; // garde-fou
  try {
    const stat = await fsp.stat(resolved);
    if (stat.isDirectory()) return resolved;
  } catch {
    /* absent */
  }
  return null;
}

const app = express();
app.use(cors());
app.use(express.json());

app.get("/api/health", (_req, res) => res.json({ ok: true, auditsRoot: auditsRoot() }));

// Configuration de la racine des audits (lecture + écriture partagées).
app.get("/api/config", (_req, res) => {
  const { root, source } = resolveRoot();
  res.json({ auditsRoot: root, source, editable: source !== "env" });
});

app.put("/api/config", async (req, res) => {
  if (ENV_ROOT) {
    return res.status(409).json({
      error: "AUDITS_ROOT est imposé par l'environnement et non modifiable.",
    });
  }
  const input = (req.body as { auditsRoot?: unknown }).auditsRoot;
  if (typeof input !== "string" || !input.trim()) {
    return res.status(400).json({ error: "auditsRoot manquant ou invalide" });
  }
  const target = path.resolve(input.trim());
  try {
    await fsp.mkdir(target, { recursive: true });
    // Vérifie l'accès en écriture.
    await fsp.access(target, fs.constants.W_OK);
  } catch {
    return res
      .status(400)
      .json({ error: `Dossier inaccessible en écriture : ${target}` });
  }
  try {
    const tmp = `${CONFIG_PATH}.tmp`;
    await fsp.writeFile(tmp, JSON.stringify({ auditsRoot: target }, null, 2));
    await fsp.rename(tmp, CONFIG_PATH);
  } catch {
    return res.status(500).json({ error: "Échec de l'écriture de la config" });
  }
  const { root, source } = resolveRoot();
  res.json({ auditsRoot: root, source, editable: source !== "env" });
});

app.get("/api/audits", async (_req, res) => {
  res.json(await findAudits());
});

// ---------------------------------------------------------------------------
// Pilotage V2 : lancer un audit, répondre aux questions, contrôler le runner.
// ---------------------------------------------------------------------------

// Lance un audit headless via `claude -p`. Écrit dans <auditsRoot>/<slug>.
app.post("/api/audits/launch", async (req, res) => {
  const body = req.body as {
    subject?: unknown;
    depth?: unknown;
    mode?: unknown;
    lang?: unknown;
    options?: unknown;
  };
  const subject = typeof body.subject === "string" ? body.subject.trim() : "";
  if (!subject) {
    return res.status(400).json({ error: "subject manquant" });
  }
  // Garde-fou : pas de retour ligne / caractère de contrôle, longueur raisonnable.
  if (subject.length > 200 || Array.from(subject).some((c) => c.charCodeAt(0) < 0x20)) {
    return res.status(400).json({ error: "subject invalide" });
  }
  const slug = slugify(subject);
  const dirName = `audit-${slug}`;
  if (running.has(dirName)) {
    return res.status(409).json({ error: "Un audit avec ce slug est déjà en cours." });
  }

  const root = auditsRoot();
  const dir = path.join(root, dirName);
  try {
    await fsp.mkdir(dir, { recursive: true });
  } catch {
    return res.status(500).json({ error: `Impossible de créer ${dir}` });
  }

  // Construit la commande slash du skill.
  const flags: string[] = [];
  const depth = body.depth === "quick" || body.depth === "full" ? body.depth : null;
  if (depth) flags.push(`--depth ${depth}`);
  const mode =
    body.mode === "parallel" || body.mode === "sequential" || body.mode === "solo"
      ? body.mode
      : null;
  if (mode) flags.push(`--mode ${mode}`);
  const lang = typeof body.lang === "string" && body.lang.trim() ? body.lang.trim() : null;
  if (lang) flags.push(`--lang ${lang}`);
  if (Array.isArray(body.options)) {
    for (const o of body.options) {
      if (o === "swot" || o === "esg" || o === "rh") flags.push(`--${o}`);
    }
  }
  // Le sujet est entouré de guillemets et échappé : un sujet contenant des "--flags"
  // reste UN seul argument pour le skill et ne peut pas injecter d'options.
  const q = (s: string) => `"${s.replace(/"/g, '\\"')}"`;
  const parts = [
    "/audit-report",
    q(subject),
    ...flags,
    "--app-mode",
    "--output",
    q(dir),
  ];
  const prompt = parts.join(" ");

  let child: ChildProcess;
  try {
    const log = fs.openSync(path.join(dir, "_runner.log"), "a");
    child = spawn(CLAUDE_BIN, ["-p", prompt], {
      cwd: dir,
      detached: true,
      stdio: ["ignore", log, log],
    });
  } catch {
    return res
      .status(500)
      .json({ error: `Échec du lancement de "${CLAUDE_BIN}". Vérifiez CLAUDE_BIN.` });
  }

  child.on("error", () => running.delete(dirName));
  child.on("exit", () => running.delete(dirName));
  if (child.pid === undefined) {
    return res
      .status(500)
      .json({ error: `Échec du lancement de "${CLAUDE_BIN}". Vérifiez CLAUDE_BIN.` });
  }
  running.set(dirName, child);
  child.unref();
  res.json({ slug: dirName, pid: child.pid });
});

// Écrit la réponse à une question (atomique) : { v, id, value }.
app.post("/api/audit/:slug/answer", async (req, res) => {
  const dir = await resolveAuditDir(req.params.slug);
  if (!dir) return res.status(404).json({ error: "audit introuvable" });
  const body = req.body as { value?: unknown; id?: unknown };
  if (body.value === undefined) {
    return res.status(400).json({ error: "value manquante" });
  }
  const id = typeof body.id === "string" ? body.id : undefined;
  await writeJsonAtomic(dir, "_answer.json", { v: 1, id, value: body.value });
  res.json({ ok: true });
});

// Écrit un ordre de contrôle (atomique) : { v, action, dimension? }.
app.post("/api/audit/:slug/control", async (req, res) => {
  const dir = await resolveAuditDir(req.params.slug);
  if (!dir) return res.status(404).json({ error: "audit introuvable" });
  const body = req.body as { action?: unknown; dimension?: unknown };
  const action = body.action;
  if (action !== "cancel" && action !== "pause" && action !== "resume" && action !== "rerun") {
    return res.status(400).json({ error: "action invalide" });
  }
  const dimension = typeof body.dimension === "string" ? body.dimension : undefined;
  await writeJsonAtomic(dir, "_control.json", { v: 1, action, dimension });
  if (action === "cancel") {
    const child = running.get(req.params.slug);
    if (child?.pid) {
      try {
        process.kill(-child.pid); // tue le groupe (detached)
      } catch {
        try {
          child.kill();
        } catch {
          /* déjà mort */
        }
      }
      running.delete(req.params.slug);
    }
  }
  res.json({ ok: true });
});

// Question en attente, ou { question: null }.
app.get("/api/audit/:slug/question", async (req, res) => {
  const dir = await resolveAuditDir(req.params.slug);
  if (!dir) return res.status(404).json({ error: "audit introuvable" });
  try {
    const raw = await fsp.readFile(path.join(dir, "_question.json"), "utf-8");
    res.type("application/json").send(raw);
  } catch {
    res.json({ question: null });
  }
});

// État du runner pour un slug.
app.get("/api/audit/:slug/status", (req, res) => {
  const child = running.get(req.params.slug);
  res.json({ running: !!child, pid: child?.pid });
});

// Fichiers JSON structurés (manifest / data / sources / recon).
const jsonRoute = (name: string, file: string) =>
  app.get(`/api/audit/:slug/${name}`, async (req, res) => {
    const dir = await resolveAuditDir(req.params.slug);
    if (!dir) return res.status(404).json({ error: "audit introuvable" });
    try {
      const raw = await fsp.readFile(path.join(dir, file), "utf-8");
      res.type("application/json").send(raw);
    } catch {
      res.status(404).json({ error: `${file} absent` });
    }
  });

jsonRoute("manifest", "_manifest.json");
jsonRoute("data", "_data.json");
jsonRoute("sources", "_sources.json");
jsonRoute("recon", "_recon.json");

// Contenu d'un fichier markdown du dossier (lecture seule, nom validé).
app.get("/api/audit/:slug/file/:name", async (req, res) => {
  const dir = await resolveAuditDir(req.params.slug);
  if (!dir) return res.status(404).json({ error: "audit introuvable" });
  const name = req.params.name;
  if (!/^[A-Za-z0-9_.-]+\.md$/.test(name)) {
    return res.status(400).json({ error: "nom de fichier invalide" });
  }
  try {
    const raw = await fsp.readFile(path.join(dir, name), "utf-8");
    res.type("text/markdown").send(raw);
  } catch {
    res.status(404).json({ error: "fichier absent" });
  }
});

// Flux d'événements en SSE : envoie l'historique de _events.jsonl puis suit les ajouts.
app.get("/api/audit/:slug/events", async (req, res) => {
  const dir = await resolveAuditDir(req.params.slug);
  if (!dir) return res.status(404).json({ error: "audit introuvable" });
  const file = path.join(dir, "_events.jsonl");

  res.writeHead(200, {
    "Content-Type": "text/event-stream",
    "Cache-Control": "no-cache",
    Connection: "keep-alive",
  });
  res.write(": connected\n\n");

  let offset = 0;
  let buffer = "";
  const flush = (chunk: string) => {
    buffer += chunk;
    const lines = buffer.split("\n");
    buffer = lines.pop() ?? "";
    for (const line of lines) {
      const trimmed = line.trim();
      if (trimmed) res.write(`data: ${trimmed}\n\n`);
    }
  };
  const readFrom = async () => {
    try {
      const stat = await fsp.stat(file);
      if (stat.size <= offset) return;
      const stream = fs.createReadStream(file, { start: offset, encoding: "utf-8" });
      for await (const chunk of stream) flush(chunk as string);
      offset = stat.size;
    } catch {
      /* fichier pas encore là */
    }
  };

  await readFrom();
  // Suivi des ajouts (audit en cours). Pour un audit terminé, ne renvoie rien de plus.
  const watcher = fs.watch(dir, async (_e, fname) => {
    if (fname === "_events.jsonl") await readFrom();
  });
  const heartbeat = setInterval(() => res.write(": ping\n\n"), 15000);

  req.on("close", () => {
    clearInterval(heartbeat);
    watcher.close();
    res.end();
  });
});

app.listen(PORT, () => {
  const { root, source } = resolveRoot();
  console.log(`[auditviewer] API sur http://localhost:${PORT}`);
  console.log(`[auditviewer] AUDITS_ROOT = ${root} (${source})`);
});
