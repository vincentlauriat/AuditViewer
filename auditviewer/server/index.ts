import express from "express";
import cors from "cors";
import fs from "node:fs";
import fsp from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import type { AuditSummary, Manifest } from "../shared/contract.ts";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.PORT) || 3001;

// Racine où chercher les dossiers d'audit. Par défaut : viewer-fixtures/ du dépôt.
// Un dossier d'audit = un répertoire contenant _manifest.json ou _recon.json.
const REPO_ROOT = path.resolve(__dirname, "..", "..");
const AUDITS_ROOT = path.resolve(
  process.env.AUDITS_ROOT || path.join(REPO_ROOT, "viewer-fixtures"),
);

const isAuditDir = (dir: string) =>
  fs.existsSync(path.join(dir, "_manifest.json")) ||
  fs.existsSync(path.join(dir, "_recon.json"));

/** Trouve les dossiers d'audit jusqu'à 2 niveaux sous AUDITS_ROOT. */
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
  await scan(AUDITS_ROOT, 2);
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
  if (!match) return null;
  const resolved = path.resolve(match.dir);
  if (!resolved.startsWith(AUDITS_ROOT)) return null; // garde-fou
  return resolved;
}

const app = express();
app.use(cors());

app.get("/api/health", (_req, res) => res.json({ ok: true, auditsRoot: AUDITS_ROOT }));

app.get("/api/audits", async (_req, res) => {
  res.json(await findAudits());
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
  console.log(`[auditviewer] API sur http://localhost:${PORT}`);
  console.log(`[auditviewer] AUDITS_ROOT = ${AUDITS_ROOT}`);
});
