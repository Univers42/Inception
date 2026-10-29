</main>

<footer class="site-footer">
	<div class="shell site-footer-inner">
		<p class="footer-brand"><?php inception_terminal_totem( 18 ); ?> Inception · dlesieur · 42</p>
		<ul class="footer-links">
			<li><a href="<?php echo esc_url( home_url( '/dream/' ) ); ?>">Landing</a></li>
			<li><a href="<?php echo esc_url( home_url( '/blog/' ) ); ?>">Blog</a></li>
			<li><a href="<?php echo esc_url( home_url( '/wiki/' ) ); ?>">Wiki</a></li>
			<li><a href="<?php echo esc_url( home_url( '/lab/' ) ); ?>">Lab</a></li>
			<li><a href="<?php echo esc_url( admin_url() ); ?>"><?php echo is_user_logged_in() ? 'Dashboard' : 'Sign in'; ?></a></li>
		</ul>
		<p class="footer-note">TLS 1.2/1.3 · port 443 only</p>
	</div>
</footer>

<?php wp_footer(); ?>
</body>
</html>
