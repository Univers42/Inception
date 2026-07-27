/* Inception Terminal v2 — session boot reveal + pointer spotlight.
   Everything collapses to static under prefers-reduced-motion. */
(function () {
	'use strict';
	document.addEventListener('DOMContentLoaded', function () {
		var reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

		/* The session types itself in, line by line */
		var boot = document.querySelector('[data-boot]');
		if (boot) {
			var lines = boot.querySelectorAll('.boot-line');
			if (reduced) {
				lines.forEach(function (l) { l.classList.add('is-shown'); });
			} else {
				lines.forEach(function (line, i) {
					window.setTimeout(function () {
						line.classList.add('is-shown');
					}, 250 + i * 300);
				});
			}
		}

		/* Phosphor spotlight follows the pointer over the session
		   (pointer devices only; rAF-throttled) */
		var session = document.querySelector('.session');
		if (session && !reduced && window.matchMedia('(hover: hover) and (pointer: fine)').matches) {
			var raf = null;
			session.addEventListener('pointermove', function (e) {
				if (raf) return;
				raf = window.requestAnimationFrame(function () {
					var r = session.getBoundingClientRect();
					session.style.setProperty('--mx', ((e.clientX - r.left) / r.width * 100).toFixed(2) + '%');
					session.style.setProperty('--my', ((e.clientY - r.top) / r.height * 100).toFixed(2) + '%');
					session.style.setProperty('--spot', '1');
					raf = null;
				});
			});
			session.addEventListener('pointerleave', function () {
				session.style.setProperty('--spot', '0');
			});
		}
	});
})();
