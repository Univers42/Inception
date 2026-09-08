(function () {
	'use strict';
	document.addEventListener('DOMContentLoaded', function () {
		var reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

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
