/* Inception Terminal — hero boot-sequence reveal.
   Lines appear one by one like a real `make up`; instantly visible
   when prefers-reduced-motion is set (handled in CSS + here). */
(function () {
	'use strict';
	document.addEventListener('DOMContentLoaded', function () {
		var boot = document.querySelector('.boot[data-boot]');
		if (!boot) return;

		var lines = boot.querySelectorAll('.boot-line');
		var reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

		if (reduced) {
			lines.forEach(function (l) { l.classList.add('is-shown'); });
			return;
		}
		lines.forEach(function (line, i) {
			window.setTimeout(function () {
				line.classList.add('is-shown');
			}, 350 + i * 320);
		});
	});
})();
