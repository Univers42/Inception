/* Inception Kit — copy buttons + docs table of contents. */
(function () {
	'use strict';

	/* Copy-to-clipboard on [cmd] blocks */
	document.addEventListener('click', function (e) {
		var btn = e.target.closest('.ik-copy');
		if (!btn) return;
		var text = btn.getAttribute('data-copy') || '';
		var done = function () {
			btn.classList.add('is-copied');
			window.setTimeout(function () { btn.classList.remove('is-copied'); }, 1600);
		};
		if (navigator.clipboard && navigator.clipboard.writeText) {
			navigator.clipboard.writeText(text).then(done, done);
		} else {
			var ta = document.createElement('textarea');
			ta.value = text;
			ta.setAttribute('readonly', '');
			ta.style.position = 'absolute';
			ta.style.left = '-9999px';
			document.body.appendChild(ta);
			ta.select();
			try { document.execCommand('copy'); } catch (err) { /* noop */ }
			document.body.removeChild(ta);
			done();
		}
	});

	/* Auto table of contents for docs pages (h2/h3 inside .ik-doc-content) */
	document.addEventListener('DOMContentLoaded', function () {
		var article = document.querySelector('.ik-doc-content');
		var tocHost = document.querySelector('.ik-toc');
		if (!article || !tocHost) return;

		var heads = article.querySelectorAll('h2, h3');
		if (heads.length < 2) { tocHost.hidden = true; return; }

		var list = document.createElement('ol');
		list.className = 'ik-toc-list';
		heads.forEach(function (h, i) {
			if (!h.id) {
				h.id = 'sec-' + (i + 1) + '-' +
					h.textContent.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
			}
			var li = document.createElement('li');
			li.className = 'ik-toc-' + h.tagName.toLowerCase();
			var a = document.createElement('a');
			a.href = '#' + h.id;
			a.textContent = h.textContent;
			li.appendChild(a);
			list.appendChild(li);
		});
		tocHost.appendChild(list);

		/* highlight current section */
		if ('IntersectionObserver' in window) {
			var links = tocHost.querySelectorAll('a');
			var map = {};
			links.forEach(function (a) { map[a.getAttribute('href').slice(1)] = a; });
			var observer = new IntersectionObserver(function (entries) {
				entries.forEach(function (entry) {
					var link = map[entry.target.id];
					if (!link) return;
					if (entry.isIntersecting) {
						links.forEach(function (a) { a.classList.remove('is-active'); });
						link.classList.add('is-active');
					}
				});
			}, { rootMargin: '0px 0px -70% 0px' });
			heads.forEach(function (h) { observer.observe(h); });
		}
	});
})();
