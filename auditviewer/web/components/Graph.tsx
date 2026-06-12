import { useEffect, useRef, useState } from "react";
import type { Manifest, Source } from "../../shared/contract.ts";

// ---- Types internes ----
interface SimNode {
  id: string;
  type: "center" | "dimension" | "source";
  label: string;
  tag?: string;
  url?: string;
  x: number; y: number; vx: number; vy: number;
  pinned: boolean;
}
interface SimEdge { id: string; s: string; t: string }

// ---- Constantes simulation ----
const NODE_R: Record<SimNode["type"], number> = { center: 28, dimension: 18, source: 8 };
const DIM_DIST = 195;
const SRC_DIST = 105;
const REPULSION = 1400;
const SPRING_K = 0.05;
const CENTER_K = 0.012;
const DAMPING = 0.80;
const MAX_V = 8;
const STILL = 0.12;

// ---- Couleurs ----
function nodeColor(n: SimNode): string {
  if (n.type === "center") return "#1a2540";
  if (n.type === "dimension") return "var(--panel-2)";
  if (n.tag === "Officielle") return "rgba(91,140,255,0.2)";
  if (n.tag === "Analyste") return "rgba(176,124,240,0.2)";
  return "rgba(87,183,196,0.2)";
}
function nodeStroke(n: SimNode): string {
  if (n.type === "center") return "var(--accent)";
  if (n.type === "dimension") return "var(--accent)";
  if (n.tag === "Officielle") return "var(--off)";
  if (n.tag === "Analyste") return "var(--ana)";
  return "var(--press)";
}

// ---- Construction du graphe ----
function buildGraph(
  manifest: Manifest | null,
  sources: Source[],
  dimFiles: string[],
  subject: string,
  w: number, h: number,
): { nodes: SimNode[]; edges: SimEdge[] } {
  const nodes: SimNode[] = [];
  const edges: SimEdge[] = [];
  const cx = w / 2, cy = h / 2;

  nodes.push({ id: "center", type: "center", label: subject, x: cx, y: cy, vx: 0, vy: 0, pinned: false });

  const dims: { id: string; key: string }[] = [];
  if (manifest?.dimensions?.length) {
    manifest.dimensions.forEach(d => dims.push({ id: `dim:${d.key}`, key: d.key }));
  } else {
    dimFiles.forEach(f => {
      const key = f.replace(/^\d+_/, "").replace(/\.md$/i, "").toLowerCase();
      if (key) dims.push({ id: `dim:${key}`, key });
    });
  }

  dims.forEach((d, i) => {
    const angle = (2 * Math.PI * i) / dims.length - Math.PI / 2;
    nodes.push({
      id: d.id, type: "dimension", label: d.key,
      x: cx + Math.cos(angle) * DIM_DIST,
      y: cy + Math.sin(angle) * DIM_DIST,
      vx: 0, vy: 0, pinned: false,
    });
    edges.push({ id: `e:c-${d.id}`, s: "center", t: d.id });
  });

  const dimMap = new Map(dims.map(d => [d.key, d.id]));

  // Grouper les sources par dimension principale pour une distribution uniforme
  const srcByDim = new Map<string, Source[]>();
  sources.forEach(src => {
    const key = src.dimensions?.[0] ?? "__";
    if (!srcByDim.has(key)) srcByDim.set(key, []);
    srcByDim.get(key)!.push(src);
  });
  const dimSrcIdx = new Map<string, number>();

  sources.forEach(src => {
    const sid = `src:${src.id}`;
    const mainKey = src.dimensions?.[0] ?? "__";
    const mainDimId = dimMap.get(mainKey) ?? dims[0]?.id ?? "center";
    const anchor = nodes.find(n => n.id === mainDimId);
    const bx = anchor?.x ?? cx, by = anchor?.y ?? cy;

    // Répartition uniforme en anneau autour de la dimension
    const group = srcByDim.get(mainKey)!;
    const idx = dimSrcIdx.get(mainKey) ?? 0;
    dimSrcIdx.set(mainKey, idx + 1);
    const total = group.length;
    const dimAngle = Math.atan2(by - cy, bx - cx);
    const spread = (2 * Math.PI * idx) / Math.max(total, 1);
    const angle = dimAngle + spread;
    const r = 35 + 14 * Math.ceil(Math.sqrt(total));

    nodes.push({
      id: sid, type: "source", label: src.title, tag: src.tag, url: src.url,
      x: bx + Math.cos(angle) * r,
      y: by + Math.sin(angle) * r,
      vx: 0, vy: 0, pinned: false,
    });

    const linked = src.dimensions?.filter(dk => dimMap.has(dk)) ?? [];
    if (linked.length) {
      linked.forEach(dk => edges.push({ id: `e:${dimMap.get(dk)}-${sid}-${dk}`, s: dimMap.get(dk)!, t: sid }));
    } else if (mainDimId) {
      edges.push({ id: `e:${mainDimId}-${sid}`, s: mainDimId, t: sid });
    }
  });

  return { nodes, edges };
}

// ---- Simulation (un tick) ----
function simStep(nodes: SimNode[], edges: SimEdge[], w: number, h: number): boolean {
  // Répulsion (Coulomb)
  for (let i = 0; i < nodes.length; i++) {
    for (let j = i + 1; j < nodes.length; j++) {
      const a = nodes[i], b = nodes[j];
      if (a.pinned && b.pinned) continue;
      const dx = b.x - a.x, dy = b.y - a.y;
      const d2 = dx * dx + dy * dy + 1;
      const d = Math.sqrt(d2);
      const f = REPULSION / d2;
      const fx = (dx / d) * f, fy = (dy / d) * f;
      if (!a.pinned) { a.vx -= fx; a.vy -= fy; }
      if (!b.pinned) { b.vx += fx; b.vy += fy; }
    }
  }
  // Ressorts (Hooke)
  const map = new Map(nodes.map(n => [n.id, n]));
  for (const e of edges) {
    const a = map.get(e.s), b = map.get(e.t);
    if (!a || !b) continue;
    const dx = b.x - a.x, dy = b.y - a.y;
    const d = Math.sqrt(dx * dx + dy * dy) || 1;
    const rest = (a.type === "center" || b.type === "center") ? DIM_DIST : SRC_DIST;
    const s = (d - rest) * SPRING_K;
    const fx = (dx / d) * s, fy = (dy / d) * s;
    if (!a.pinned) { a.vx += fx; a.vy += fy; }
    if (!b.pinned) { b.vx -= fx; b.vy -= fy; }
  }
  // Centrage + intégration
  let moving = false;
  for (const n of nodes) {
    if (n.pinned) continue;
    n.vx += (w / 2 - n.x) * CENTER_K;
    n.vy += (h / 2 - n.y) * CENTER_K;
    n.vx = Math.max(-MAX_V, Math.min(MAX_V, n.vx * DAMPING));
    n.vy = Math.max(-MAX_V, Math.min(MAX_V, n.vy * DAMPING));
    n.x = Math.max(12, Math.min(w - 12, n.x + n.vx));
    n.y = Math.max(12, Math.min(h - 12, n.y + n.vy));
    if (Math.abs(n.vx) > STILL || Math.abs(n.vy) > STILL) moving = true;
  }
  return moving;
}

// ---- Composant ----
export function Graph({
  manifest, sources, dimFiles, subject, onDimOpen,
}: {
  manifest: Manifest | null;
  sources: Source[];
  dimFiles: string[];
  subject: string;
  onDimOpen?: (key: string) => void;
}) {
  const wrapRef = useRef<HTMLDivElement>(null);
  const [size, setSize] = useState({ w: 800, h: 520 });
  const sizeRef = useRef(size);
  const simRef = useRef<{ nodes: SimNode[]; edges: SimEdge[] }>({ nodes: [], edges: [] });
  const nmRef = useRef<Map<string, SimNode>>(new Map());
  const nodeGRefs = useRef<Map<string, SVGGElement>>(new Map());
  const edgeLRefs = useRef<Map<string, SVGLineElement>>(new Map());
  const rafRef = useRef(0);
  const dragRef = useRef<{ id: string; ox: number; oy: number } | null>(null);
  const animAlive = useRef(false);
  const [tooltip, setTooltip] = useState<{ node: SimNode; x: number; y: number } | null>(null);
  const [graphKey, setGraphKey] = useState(0);

  useEffect(() => { sizeRef.current = size; }, [size]);

  const updateDOM = () => {
    for (const n of simRef.current.nodes) {
      nodeGRefs.current.get(n.id)?.setAttribute("transform", `translate(${n.x.toFixed(1)},${n.y.toFixed(1)})`);
    }
    for (const e of simRef.current.edges) {
      const line = edgeLRefs.current.get(e.id);
      if (!line) continue;
      const a = nmRef.current.get(e.s), b = nmRef.current.get(e.t);
      if (a && b) {
        line.setAttribute("x1", a.x.toFixed(1)); line.setAttribute("y1", a.y.toFixed(1));
        line.setAttribute("x2", b.x.toFixed(1)); line.setAttribute("y2", b.y.toFixed(1));
      }
    }
  };

  const startLoop = () => {
    cancelAnimationFrame(rafRef.current);
    animAlive.current = true;
    const loop = (): void => {
      if (!animAlive.current) return;
      const { w, h } = sizeRef.current;
      const moving = simStep(simRef.current.nodes, simRef.current.edges, w, h);
      updateDOM();
      if (moving || dragRef.current) rafRef.current = requestAnimationFrame(loop);
      else animAlive.current = false;
    };
    rafRef.current = requestAnimationFrame(loop);
  };

  const dataKey = `${manifest?.slug ?? ""}|${sources.length}|${dimFiles.length}`;
  useEffect(() => {
    const { w, h } = sizeRef.current;
    const { nodes, edges } = buildGraph(manifest, sources, dimFiles, subject, w, h);
    simRef.current = { nodes, edges };
    nmRef.current = new Map(nodes.map(n => [n.id, n]));
    nodeGRefs.current.clear();
    edgeLRefs.current.clear();
    setGraphKey(k => k + 1);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [dataKey, subject]);

  useEffect(() => {
    const el = wrapRef.current;
    if (!el) return;
    const ro = new ResizeObserver(([entry]) => {
      const { width, height } = entry.contentRect;
      if (width > 100 && height > 100) setSize({ w: width, h: height });
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  useEffect(() => {
    startLoop();
    return () => { animAlive.current = false; cancelAnimationFrame(rafRef.current); };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [graphKey]);

  // ---- Drag ----
  const handleNodeDown = (e: React.MouseEvent<SVGGElement>, n: SimNode) => {
    e.preventDefault(); e.stopPropagation();
    const svg = e.currentTarget.closest("svg") as SVGSVGElement;
    const r = svg.getBoundingClientRect();
    dragRef.current = { id: n.id, ox: e.clientX - r.left - n.x, oy: e.clientY - r.top - n.y };
    n.pinned = true;
    setTooltip(null);
    startLoop();
  };

  const handleSvgMove = (e: React.MouseEvent<SVGSVGElement>) => {
    if (!dragRef.current) return;
    const r = e.currentTarget.getBoundingClientRect();
    const { w, h } = sizeRef.current;
    const n = nmRef.current.get(dragRef.current.id);
    if (!n) return;
    n.x = Math.max(12, Math.min(w - 12, e.clientX - r.left - dragRef.current.ox));
    n.y = Math.max(12, Math.min(h - 12, e.clientY - r.top - dragRef.current.oy));
    n.vx = 0; n.vy = 0;
  };

  const handleSvgUp = () => {
    if (!dragRef.current) return;
    const n = nmRef.current.get(dragRef.current.id);
    if (n) n.pinned = false;
    dragRef.current = null;
    startLoop();
  };

  const handleDblClick = (n: SimNode) => {
    if (n.type === "source" && n.url) {
      window.open(n.url, "_blank", "noopener,noreferrer");
    } else if (n.type === "dimension") {
      onDimOpen?.(n.label);
    }
  };

  const handleNodeEnter = (e: React.MouseEvent<SVGGElement>, n: SimNode) => {
    if (dragRef.current) return;
    const wr = wrapRef.current!.getBoundingClientRect();
    setTooltip({ node: n, x: e.clientX - wr.left, y: e.clientY - wr.top });
  };

  const { nodes, edges } = simRef.current;

  return (
    <div ref={wrapRef} className="graph-wrap">
      <svg
        width={size.w}
        height={size.h}
        onMouseMove={handleSvgMove}
        onMouseUp={handleSvgUp}
        onMouseLeave={handleSvgUp}
      >
        <g>
          {edges.map(e => {
            const a = nmRef.current.get(e.s), b = nmRef.current.get(e.t);
            if (!a || !b) return null;
            const isCenterEdge = a.type === "center" || b.type === "center";
            return (
              <line
                key={e.id}
                ref={el => { if (el) edgeLRefs.current.set(e.id, el); else edgeLRefs.current.delete(e.id); }}
                x1={a.x} y1={a.y} x2={b.x} y2={b.y}
                stroke="var(--border)"
                strokeWidth={isCenterEdge ? 1.5 : 1}
                opacity={isCenterEdge ? 0.7 : 0.35}
              />
            );
          })}
        </g>
        <g>
          {nodes.map(n => (
            <g
              key={n.id}
              ref={el => { if (el) nodeGRefs.current.set(n.id, el as SVGGElement); else nodeGRefs.current.delete(n.id); }}
              transform={`translate(${n.x.toFixed(1)},${n.y.toFixed(1)})`}
              style={{ cursor: "grab" }}
              onMouseDown={ev => handleNodeDown(ev, n)}
              onDoubleClick={() => handleDblClick(n)}
              onMouseEnter={ev => handleNodeEnter(ev, n)}
              onMouseLeave={() => { if (!dragRef.current) setTooltip(null); }}
            >
              <circle
                r={NODE_R[n.type]}
                fill={nodeColor(n)}
                stroke={nodeStroke(n)}
                strokeWidth={n.type === "center" ? 2.5 : 1.5}
              />
              {n.type !== "source" && (
                <text
                  y={NODE_R[n.type] + 14}
                  textAnchor="middle"
                  fontSize={n.type === "center" ? 13 : 11}
                  fontWeight={n.type === "center" ? 700 : 500}
                  fill="var(--text)"
                  style={{ pointerEvents: "none", userSelect: "none", textTransform: "capitalize" }}
                >
                  {n.label.length > 16 ? n.label.slice(0, 15) + "…" : n.label}
                </text>
              )}
            </g>
          ))}
        </g>
      </svg>

      {tooltip && (
        <div
          className="graph-tooltip"
          style={{ left: tooltip.x + 14, top: tooltip.y - 14 }}
          onMouseEnter={() => setTooltip(null)}
        >
          <div className="gt-label">
            {tooltip.node.label.length > 90 ? tooltip.node.label.slice(0, 89) + "…" : tooltip.node.label}
          </div>
          {tooltip.node.tag && <div className="gt-tag">{tooltip.node.tag}</div>}
          {tooltip.node.url && (
            <div className="gt-url">
              {(() => { try { return new URL(tooltip.node.url).hostname; } catch { return tooltip.node.url.slice(0, 40); } })()}
            </div>
          )}
          {(tooltip.node.type === "source" && tooltip.node.url) && (
            <div className="gt-hint">Double-clic pour ouvrir</div>
          )}
          {tooltip.node.type === "dimension" && (
            <div className="gt-hint">Double-clic pour voir le contenu</div>
          )}
        </div>
      )}

      <div className="graph-legend">
        <span className="gl-center">● Audit</span>
        <span className="gl-dim">● Dimension</span>
        <span className="gl-off">● Officielle</span>
        <span className="gl-ana">● Analyste</span>
        <span className="gl-press">● Presse</span>
        <span className="gl-count">{sources.length} sources · {nodes.filter(n => n.type === "dimension").length} dimensions</span>
      </div>
    </div>
  );
}
