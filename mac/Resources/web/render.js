(function () {
    'use strict';

    const target = document.getElementById('content');

    const md = window.markdownit({
        html: false,
        xhtmlOut: false,
        breaks: false,
        linkify: true,
        typographer: true,
        highlight: function (str, lang) {
            if (lang === 'mermaid') {
                return '<pre><code class="language-mermaid">' + md.utils.escapeHtml(str) + '</code></pre>';
            }
            if (window.hljs && lang && hljs.getLanguage(lang)) {
                try {
                    return '<pre><code class="hljs language-' + lang + '">' +
                        hljs.highlight(str, { language: lang, ignoreIllegals: true }).value +
                        '</code></pre>';
                } catch (_) { /* fall through */ }
            }
            return '<pre><code class="hljs">' + md.utils.escapeHtml(str) + '</code></pre>';
        }
    });

    if (window.markdownitTaskLists) {
        md.use(window.markdownitTaskLists, { enabled: true, label: true, lineNumber: false });
    }

    if (window.mermaid) {
        mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: 'default' });
    }

    function setHTML(el, html) {
        const safe = window.DOMPurify ? DOMPurify.sanitize(html) : html;
        const parser = new DOMParser();
        const doc = parser.parseFromString(safe, 'text/html');
        el.replaceChildren(...doc.body.childNodes);
    }

    let mermaidCounter = 0;
    function transformMermaid() {
        if (!window.mermaid) return;
        const blocks = target.querySelectorAll('pre > code.language-mermaid');
        blocks.forEach(function (code) {
            const wrapper = document.createElement('div');
            wrapper.className = 'mermaid';
            wrapper.id = 'mermaid-' + (++mermaidCounter);
            wrapper.textContent = code.textContent;
            code.parentElement.replaceWith(wrapper);
        });
        if (target.querySelectorAll('.mermaid').length) {
            mermaid.run({ querySelector: '#content .mermaid' }).catch(function () { /* ignore */ });
        }
    }

    function renderMath() {
        if (!window.renderMathInElement) return;
        renderMathInElement(target, {
            delimiters: [
                { left: '$$', right: '$$', display: true },
                { left: '\\[', right: '\\]', display: true },
                { left: '$', right: '$', display: false },
                { left: '\\(', right: '\\)', display: false }
            ],
            throwOnError: false,
            ignoredTags: ['script', 'noscript', 'style', 'textarea', 'pre', 'code']
        });
    }

    function extractFrontmatter(text) {
        // Bloc YAML délimité par --- au début du fichier (Obsidian / Tolaria / Jekyll)
        const m = text.match(/^---\s*\r?\n([\s\S]*?)\r?\n---\s*(?:\r?\n|$)/);
        if (!m) return { yaml: null, body: text };
        return { yaml: m[1], body: text.slice(m[0].length) };
    }

    function escapeHtml(s) {
        return s
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    }

    let lastHadFrontmatter = false;

    window.renderMarkdown = function (text) {
        const { yaml, body } = extractFrontmatter(text || '');
        lastHadFrontmatter = yaml !== null;
        let html = '';
        if (yaml !== null) {
            html += '<aside class="frontmatter"><pre><code class="language-yaml">'
                  + escapeHtml(yaml)
                  + '</code></pre></aside>';
        }
        html += md.render(body);
        setHTML(target, html);
        // Re-highlight YAML block specifically (markdown-it.highlight ne s'applique
        // pas sur le HTML qu'on injecte nous-mêmes)
        if (window.hljs && yaml !== null) {
            const code = target.querySelector('.frontmatter code.language-yaml');
            if (code) hljs.highlightElement(code);
        }
        renderMath();
        transformMermaid();
    };

    window.setFrontmatterVisible = function (visible) {
        document.body.classList.toggle('hide-frontmatter', !visible);
    };

    window.hasFrontmatter = function () {
        return lastHadFrontmatter;
    };

    window.setTheme = function (theme) {
        document.body.dataset.theme = theme;
        document.documentElement.dataset.theme = theme;
        const dark = document.getElementById('hljs-dark');
        const light = document.getElementById('hljs-light');
        if (dark && light) {
            dark.disabled = theme !== 'dark';
            light.disabled = theme === 'dark';
        }
        if (window.mermaid) {
            mermaid.initialize({
                startOnLoad: false,
                securityLevel: 'strict',
                theme: theme === 'dark' ? 'dark' : 'default'
            });
        }
    };

    document.addEventListener('DOMContentLoaded', function () {
        if (!target.firstChild) {
            const placeholder = document.createElement('p');
            placeholder.style.opacity = '0.6';
            placeholder.style.fontStyle = 'italic';
            placeholder.textContent = 'Waiting for markdown content…';
            target.appendChild(placeholder);
        }
    });
})();
