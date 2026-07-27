<?php
/**
 * Site footer — tmux-style status bar.
 */
?>
</main>

<footer class="site-footer" role="contentinfo">
	<div class="shell">
		<div class="statusbar">
			<span class="status-seg status-seg-green">[inception]</span>
			<span class="status-seg">0:nginx</span>
			<span class="status-seg">1:wordpress<span class="status-active">*</span></span>
			<span class="status-seg">2:mariadb</span>
			<span class="status-spacer" aria-hidden="true"></span>
			<span class="status-seg status-dim">TLS 1.2/1.3 · port 443 only</span>
			<span class="status-seg status-dim"><?php echo esc_html( gmdate( 'Y' ) ); ?> · dlesieur · 42</span>
		</div>
	</div>
</footer>

<?php wp_footer(); ?>
</body>
</html>
