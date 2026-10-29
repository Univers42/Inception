/*
 * Small behaviours, none of which the page needs to be read:
 *  - the reading-progress line under the header on posts and wiki pages;
 *  - cards fade in once (CSS hides them only when this script runs);
 *  - Escape closes the phone menu; the wiki tree folds on narrow screens;
 *  - diagrams: Mermaid draws every <pre class="mermaid">;
 *  - a Copy button on every other code block of an article.
 */
(function () {
    'use strict';

    // Read now: a deferred classic script knows its own URL only while it runs.
    var here = document.currentScript && document.currentScript.src;

    var bar = document.querySelector('.reading-progress');
    var article = document.querySelector('.prose');
    if (bar && article && document.body.classList.contains('single')) {
        var update = function () {
            var box = article.getBoundingClientRect();
            var span = Math.max(1, box.height - window.innerHeight * 0.6);
            var p = Math.min(1, Math.max(0, -box.top / span));
            bar.style.setProperty('--progress', p.toFixed(3));
        };
        var queued = false;
        window.addEventListener('scroll', function () {
            if (queued) return;
            queued = true;
            requestAnimationFrame(function () { queued = false; update(); });
        }, { passive: true });
        update();
    }

    var cards = document.querySelectorAll('.reveal');
    if ('IntersectionObserver' in window) {
        var io = new IntersectionObserver(function (entries) {
            entries.forEach(function (e) {
                if (!e.isIntersecting) return;
                e.target.classList.add('is-visible');
                io.unobserve(e.target);
            });
        }, { rootMargin: '0px 0px -8% 0px' });
        cards.forEach(function (c, i) {
            c.style.transitionDelay = Math.min(i % 6, 5) * 40 + 'ms';
            io.observe(c);
        });
    } else {
        cards.forEach(function (c) { c.classList.add('is-visible'); });
    }

    // A print or a saved PDF has no scrolling to reveal the rest of the cards.
    window.addEventListener('beforeprint', function () {
        cards.forEach(function (c) { c.classList.add('is-visible'); });
    });

    // Escape closes the phone menu and gives focus back to its button: closing
    // it unmounts the focused link, which used to drop focus onto <body>.
    var menu = document.querySelector('details.nav-mobile');
    if (menu) {
        menu.addEventListener('keydown', function (e) {
            if (e.key !== 'Escape' || !menu.open) return;
            menu.open = false;
            menu.querySelector('summary').focus();
        });
    }

    // Under 60rem the wiki tree sits above the article: open, it pushed the
    // page title to the bottom of a phone's first screen. It stays open in the
    // HTML for readers without this script.
    var tree = document.querySelector('.wiki-tree');
    if (tree && window.matchMedia('(max-width: 60rem)').matches) tree.open = false;

    var toc = document.querySelector('#ez-toc-container nav');
    if (toc) toc.setAttribute('aria-label', 'On this page');

    // A <pre class="mermaid"> comes from a ```mermaid fence (tools/wiki) or a
    // Code block given the class "mermaid" in the editor. Mermaid loads from the
    // theme only on a page that has one, is coloured from the page's own tokens
    // (resolved through a probe, since it cannot read var()), and redraws when
    // the colour scheme flips or the width changes a lot.
    //
    // Mermaid fits a diagram to its box, which shrank a wide left-to-right flow
    // to 7 px labels on a phone (9 px on a desktop). A flow needing over a
    // third more room than it has is redrawn top to bottom; a diagram that
    // still does not fit keeps its natural size and scrolls sideways, as a
    // focusable region so the keyboard can scroll it too.
    var diagrams = Array.prototype.slice.call(document.querySelectorAll('pre.mermaid'));
    if (diagrams.length && here) {
        var sources = diagrams.map(function (pre) { return pre.textContent; });
        var leftToRight = /^(\s*(?:flowchart|graph)\s+)LR\b/m;
        var probe = document.createElement('span');
        probe.hidden = true;
        document.body.appendChild(probe);
        var colour = function (name) {
            probe.style.color = 'var(' + name + ')';
            return getComputedStyle(probe).color;
        };
        var room = function (pre) {
            var style = getComputedStyle(pre);
            return pre.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight);
        };
        var natural = function (pre) {
            var svg = pre.querySelector('svg');
            return svg && svg.viewBox.baseVal ? svg.viewBox.baseVal.width : 0;
        };
        var fit = function (pre) {
            var svg = pre.querySelector('svg');
            var width = natural(pre);
            if (!width) return;
            var wide = width > room(pre);
            svg.style.width = wide ? width + 'px' : '';
            svg.style.maxWidth = wide ? 'none' : width + 'px';
            if (wide) {
                pre.tabIndex = 0;
                pre.setAttribute('role', 'region');
                pre.setAttribute('aria-label', 'Diagram, scrolls sideways');
            } else {
                pre.removeAttribute('tabindex');
                pre.removeAttribute('role');
                pre.removeAttribute('aria-label');
            }
        };
        var render = function (mermaid, list) {
            list.forEach(function (d) {
                d.pre.removeAttribute('data-processed');
                d.pre.textContent = d.text;
            });
            return mermaid.run({ nodes: list.map(function (d) { return d.pre; }) });
        };
        var drawnAt = 0;
        var draw = function (mermaid) {
            drawnAt = window.innerWidth;
            var bg = (colour('--bg').match(/\d+/g) || [0, 0, 0]).map(Number);
            mermaid.initialize({
                startOnLoad: false,
                securityLevel: 'strict',
                theme: 'base',
                fontFamily: getComputedStyle(document.body).fontFamily,
                themeVariables: {
                    darkMode: bg[0] * 0.299 + bg[1] * 0.587 + bg[2] * 0.114 < 128,
                    background: colour('--surface'),
                    primaryColor: colour('--surface-raised'),
                    primaryTextColor: colour('--text'),
                    primaryBorderColor: colour('--line-strong'),
                    secondaryColor: colour('--surface-sunken'),
                    tertiaryColor: colour('--surface'),
                    lineColor: colour('--text-muted'),
                    textColor: colour('--text'),
                    edgeLabelBackground: colour('--surface-sunken'),
                    clusterBkg: colour('--surface-sunken'),
                    clusterBorder: colour('--line-strong')
                }
            });
            var all = diagrams.map(function (pre, i) { return { pre: pre, text: sources[i] }; });
            return render(mermaid, all).then(function () {
                var cramped = all.filter(function (d) {
                    return leftToRight.test(d.text) && natural(d.pre) > room(d.pre) * 1.33;
                });
                cramped.forEach(function (d) { d.text = d.text.replace(leftToRight, '$1TB'); });
                return cramped.length ? render(mermaid, cramped) : null;
            }).then(function () { diagrams.forEach(fit); });
        };
        import(new URL('vendor/mermaid/mermaid.esm.min.mjs', here).href).then(function (m) {
            draw(m.default);
            window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', function () { draw(m.default); });
            var settle;
            window.addEventListener('resize', function () {
                clearTimeout(settle);
                settle = setTimeout(function () {
                    if (Math.abs(window.innerWidth - drawnAt) > 80) draw(m.default);
                }, 250);
            });
        }).catch(function () {
            diagrams.forEach(function (pre) { pre.classList.add('mermaid-failed'); });
        });
    }

    if (navigator.clipboard) {
        document.querySelectorAll('.prose pre').forEach(function (pre) {
            // Diagrams, Code Block Pro (its own button) and command output are not copied.
            if (pre.classList.contains('mermaid') || pre.classList.contains('ik-out') || pre.closest('.wp-block-kevinbatdorf-code-block-pro')) return;
            var button = document.createElement('button');
            button.type = 'button';
            button.className = 'copy-code';
            button.textContent = 'Copy';
            button.addEventListener('click', function () {
                var clean = pre.cloneNode(true);
                clean.querySelector('.copy-code').remove();
                navigator.clipboard.writeText(clean.textContent).then(function () {
                    button.textContent = 'Copied';
                    setTimeout(function () { button.textContent = 'Copy'; }, 1600);
                });
            });
            pre.appendChild(button);
        });
    }
})();
