(function () {
    'use strict';

    const canvas = document.getElementById('canvas');
    const legendEl = document.getElementById('legend');
    const emptyEl = document.getElementById('empty');
    const ctx = canvas.getContext('2d');

    // ── Thème ──────────────────────────────────────────────────────────────
    const THEMES = {
        light: {
            bg: 'transparent',
            edge: 'rgba(120,120,130,0.28)',
            label: '#2b2b30',
            labelHalo: 'rgba(255,255,255,0.85)',
            types: {
                subject: '#ff7847',
                section: '#4c8dff',
                source:  '#19c3a6',
                entity:  '#b06bff',
                audit:   '#ff7847'
            }
        },
        dark: {
            bg: 'transparent',
            edge: 'rgba(170,170,185,0.22)',
            label: '#e6e6ea',
            labelHalo: 'rgba(20,20,24,0.75)',
            types: {
                subject: '#ff8a5c',
                section: '#6aa6ff',
                source:  '#34d6b8',
                entity:  '#c089ff',
                audit:   '#ff8a5c'
            }
        }
    };
    const TYPE_LABELS = {
        subject: 'Sujet', section: 'Section', source: 'Source',
        entity: 'Acteur', audit: 'Audit'
    };
    let theme = THEMES.light;

    // ── État ───────────────────────────────────────────────────────────────
    let nodes = [];
    let edges = [];
    let adjacency = new Map();          // id -> Set(ids voisins)
    const view = { x: 0, y: 0, scale: 1 };
    let dpr = window.devicePixelRatio || 1;
    let hoverId = null;
    let dragNode = null;
    let panning = false;
    let lastMouse = { x: 0, y: 0 };
    let downPos = null;
    let moved = false;
    let alpha = 1;                      // « température » de la simulation
    let selectedId = null;              // nœud mis en évidence via window.focusNode

    function radiusOf(n) {
        return 6 + Math.sqrt(n.weight || 1) * 3;
    }

    // ── Mise en page / canvas ────────────────────────────────────────────────
    function resize() {
        dpr = window.devicePixelRatio || 1;
        canvas.width = Math.floor(window.innerWidth * dpr);
        canvas.height = Math.floor(window.innerHeight * dpr);
        canvas.style.width = window.innerWidth + 'px';
        canvas.style.height = window.innerHeight + 'px';
    }
    window.addEventListener('resize', function () { resize(); });

    function buildAdjacency() {
        adjacency = new Map();
        nodes.forEach(function (n) { adjacency.set(n.id, new Set()); });
        edges.forEach(function (e) {
            if (adjacency.has(e.source) && adjacency.has(e.target)) {
                adjacency.get(e.source).add(e.target);
                adjacency.get(e.target).add(e.source);
            }
        });
    }

    // ── Simulation force-directed (O(n²), suffisant pour < ~150 nœuds) ────────
    function tick() {
        if (alpha < 0.02 && !dragNode) { draw(); return; }
        const cx = window.innerWidth / 2;
        const cy = window.innerHeight / 2;
        const k = 9000;                 // répulsion
        const spring = 0.012;           // attraction des arêtes
        const restLen = 90;
        const gravity = 0.015;

        // Répulsion entre toutes les paires
        for (let i = 0; i < nodes.length; i++) {
            const a = nodes[i];
            for (let j = i + 1; j < nodes.length; j++) {
                const b = nodes[j];
                let dx = a.x - b.x, dy = a.y - b.y;
                let d2 = dx * dx + dy * dy;
                if (d2 < 1) { d2 = 1; dx = (Math.random() - 0.5); dy = (Math.random() - 0.5); }
                const d = Math.sqrt(d2);
                const f = (k / d2) * alpha;
                const fx = (dx / d) * f, fy = (dy / d) * f;
                a.vx += fx; a.vy += fy;
                b.vx -= fx; b.vy -= fy;
            }
        }
        // Ressorts sur les arêtes
        edges.forEach(function (e) {
            const a = nodeById.get(e.source), b = nodeById.get(e.target);
            if (!a || !b) return;
            const dx = b.x - a.x, dy = b.y - a.y;
            const d = Math.sqrt(dx * dx + dy * dy) || 1;
            const f = (d - restLen) * spring * alpha;
            const fx = (dx / d) * f, fy = (dy / d) * f;
            a.vx += fx; a.vy += fy;
            b.vx -= fx; b.vy -= fy;
        });
        // Gravité centrale + intégration
        nodes.forEach(function (n) {
            n.vx += (cx - n.x) * gravity * alpha;
            n.vy += (cy - n.y) * gravity * alpha;
            if (n === dragNode) { n.vx = 0; n.vy = 0; return; }
            n.vx *= 0.85; n.vy *= 0.85;
            n.x += n.vx; n.y += n.vy;
        });

        alpha *= 0.985;
        draw();
    }

    let nodeById = new Map();

    // ── Rendu ────────────────────────────────────────────────────────────────
    function draw() {
        ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
        ctx.clearRect(0, 0, window.innerWidth, window.innerHeight);
        ctx.save();
        ctx.translate(view.x, view.y);
        ctx.scale(view.scale, view.scale);

        // Nœud focalisé : survol prioritaire, sinon sélection persistante (focusNode).
        const focusId = hoverId || selectedId;
        const focusNeighbors = focusId ? adjacency.get(focusId) : null;

        // Arêtes (courbes légères)
        edges.forEach(function (e) {
            const a = nodeById.get(e.source), b = nodeById.get(e.target);
            if (!a || !b) return;
            const active = focusId && (e.source === focusId || e.target === focusId);
            ctx.beginPath();
            ctx.moveTo(a.x, a.y);
            const mx = (a.x + b.x) / 2, my = (a.y + b.y) / 2;
            ctx.quadraticCurveTo(mx, my, b.x, b.y);
            ctx.strokeStyle = active ? theme.types.section : theme.edge;
            ctx.lineWidth = (active ? 1.6 : 0.9) / view.scale;
            ctx.stroke();
        });

        // Nœuds
        nodes.forEach(function (n) {
            const r = radiusOf(n);
            const color = theme.types[n.type] || theme.types.section;
            const dim = focusId && n.id !== focusId && !(focusNeighbors && focusNeighbors.has(n.id));

            ctx.globalAlpha = dim ? 0.25 : 1;
            // Halo
            ctx.beginPath();
            ctx.arc(n.x, n.y, r + 3 / view.scale, 0, Math.PI * 2);
            ctx.fillStyle = color;
            ctx.globalAlpha = dim ? 0.06 : 0.18;
            ctx.fill();

            ctx.globalAlpha = dim ? 0.25 : 1;
            ctx.beginPath();
            ctx.arc(n.x, n.y, r, 0, Math.PI * 2);
            ctx.fillStyle = color;
            ctx.fill();
            if (n.id === focusId) {
                // Contour plus marqué pour la sélection persistante (focusNode).
                ctx.lineWidth = (n.id === selectedId && n.id !== hoverId ? 3 : 2) / view.scale;
                ctx.strokeStyle = theme.label;
                ctx.stroke();
            }
            ctx.globalAlpha = 1;
        });

        // Libellés (seulement si zoom suffisant ou nœud important / survolé)
        nodes.forEach(function (n) {
            const r = radiusOf(n);
            const important = n.type === 'subject' || n.type === 'audit' || (n.weight || 1) >= 3;
            const show = n.id === focusId || view.scale > 0.85 || important;
            if (!show) return;
            const dim = focusId && n.id !== focusId && !(focusNeighbors && focusNeighbors.has(n.id));
            const fontSize = (n.type === 'subject' ? 14 : 11);
            ctx.font = (n.type === 'subject' || n.type === 'audit' ? '600 ' : '400 ') + fontSize + 'px -apple-system, sans-serif';
            ctx.textAlign = 'center';
            ctx.textBaseline = 'top';
            const label = n.label.length > 34 ? n.label.slice(0, 33) + '…' : n.label;
            const ty = n.y + r + 3;
            ctx.globalAlpha = dim ? 0.3 : 1;
            ctx.lineWidth = 3 / view.scale;
            ctx.strokeStyle = theme.labelHalo;
            ctx.strokeText(label, n.x, ty);
            ctx.fillStyle = theme.label;
            ctx.fillText(label, n.x, ty);
            ctx.globalAlpha = 1;
        });

        ctx.restore();
    }

    // ── Interactions ───────────────────────────────────────────────────────
    function screenToWorld(sx, sy) {
        return { x: (sx - view.x) / view.scale, y: (sy - view.y) / view.scale };
    }
    function nodeAt(sx, sy) {
        const p = screenToWorld(sx, sy);
        for (let i = nodes.length - 1; i >= 0; i--) {
            const n = nodes[i];
            const r = radiusOf(n) + 4;
            if ((p.x - n.x) ** 2 + (p.y - n.y) ** 2 <= r * r) return n;
        }
        return null;
    }

    canvas.addEventListener('mousedown', function (e) {
        downPos = { x: e.clientX, y: e.clientY };
        moved = false;
        lastMouse = { x: e.clientX, y: e.clientY };
        const n = nodeAt(e.clientX, e.clientY);
        if (n) { dragNode = n; }
        else { panning = true; canvas.classList.add('dragging'); }
    });
    window.addEventListener('mousemove', function (e) {
        if (downPos && (Math.abs(e.clientX - downPos.x) > 3 || Math.abs(e.clientY - downPos.y) > 3)) moved = true;
        if (dragNode) {
            const p = screenToWorld(e.clientX, e.clientY);
            dragNode.x = p.x; dragNode.y = p.y;
            alpha = Math.max(alpha, 0.4);
        } else if (panning) {
            view.x += e.clientX - lastMouse.x;
            view.y += e.clientY - lastMouse.y;
            lastMouse = { x: e.clientX, y: e.clientY };
            draw();
        } else {
            const n = nodeAt(e.clientX, e.clientY);
            const id = n ? n.id : null;
            if (id !== hoverId) { hoverId = id; canvas.style.cursor = n ? 'pointer' : 'grab'; draw(); }
        }
    });
    // Envoi d'un geste (simple ou double clic) sur un nœud vers Swift.
    function postNodeGesture(gesture, n) {
        window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.graph &&
            window.webkit.messageHandlers.graph.postMessage({
                gesture: gesture,
                id: n.id,
                type: n.type,
                label: n.label || null,
                sectionId: (typeof n.sectionId === 'number') ? n.sectionId : null,
                auditPath: n.auditPath || null
            });
    }

    window.addEventListener('mouseup', function (e) {
        if (dragNode && !moved) {
            postNodeGesture('single', dragNode);
        }
        dragNode = null;
        panning = false;
        downPos = null;
        canvas.classList.remove('dragging');
    });
    canvas.addEventListener('dblclick', function (e) {
        const n = nodeAt(e.clientX, e.clientY);
        if (n) { postNodeGesture('double', n); }
    });
    canvas.addEventListener('wheel', function (e) {
        e.preventDefault();
        const factor = Math.exp(-e.deltaY * 0.0015);
        const newScale = Math.min(4, Math.max(0.2, view.scale * factor));
        // Zoom centré sur le curseur
        view.x = e.clientX - (e.clientX - view.x) * (newScale / view.scale);
        view.y = e.clientY - (e.clientY - view.y) * (newScale / view.scale);
        view.scale = newScale;
        draw();
    }, { passive: false });

    // ── Légende ──────────────────────────────────────────────────────────────
    function renderLegend() {
        const present = {};
        nodes.forEach(function (n) { present[n.type] = true; });
        legendEl.innerHTML = '';
        Object.keys(TYPE_LABELS).forEach(function (t) {
            if (!present[t]) return;
            const item = document.createElement('div');
            item.className = 'legend-item';
            const dot = document.createElement('span');
            dot.className = 'dot';
            dot.style.background = theme.types[t];
            const txt = document.createElement('span');
            txt.textContent = TYPE_LABELS[t];
            item.appendChild(dot); item.appendChild(txt);
            legendEl.appendChild(item);
        });
        legendEl.style.display = nodes.length ? 'flex' : 'none';
    }

    // ── API exposée à Swift ───────────────────────────────────────────────────
    window.renderGraph = function (data) {
        resize();
        nodes = (data && data.nodes ? data.nodes : []).map(function (n) {
            return Object.assign({}, n, {
                x: window.innerWidth / 2 + (Math.random() - 0.5) * 300,
                y: window.innerHeight / 2 + (Math.random() - 0.5) * 300,
                vx: 0, vy: 0
            });
        });
        edges = (data && data.edges ? data.edges : []).slice();
        nodeById = new Map(nodes.map(function (n) { return [n.id, n]; }));
        buildAdjacency();
        // Réinitialiser la vue
        view.x = 0; view.y = 0; view.scale = 1;
        hoverId = null; dragNode = null; selectedId = null;
        alpha = 1;
        emptyEl.style.display = nodes.length ? 'none' : 'block';
        renderLegend();
    };

    window.setTheme = function (t) {
        theme = THEMES[t] || THEMES.light;
        document.body.dataset.theme = t;
        renderLegend();
        draw();
    };

    // Met en évidence un nœud (+ ses voisins) et le ramène au centre.
    // id null → efface la sélection persistante.
    window.focusNode = function (id) {
        if (id == null || !nodeById.has(id)) { selectedId = null; draw(); return; }
        selectedId = id;
        const n = nodeById.get(id);
        // Recentrer la vue sur le nœud (sans changer l'échelle).
        view.x = window.innerWidth / 2 - n.x * view.scale;
        view.y = window.innerHeight / 2 - n.y * view.scale;
        draw();
    };

    // ── Boucle d'animation ─────────────────────────────────────────────────
    resize();
    (function loop() { tick(); requestAnimationFrame(loop); })();
})();
