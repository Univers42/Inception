<?php
/**
 * Front page — boot-sequence hero, stat tiles, documentation grid,
 * latest journal entries. Structural sections are coded here; the
 * reusable pieces come from the inception-kit plugin API.
 */
get_header();

$has_kit = function_exists( 'inception_kit_icon' );
?>

<section class="hero">
	<div class="shell">
		<div class="hero-grid">
			<div class="hero-copy">
				<p class="hero-kicker">// system administration · docker · 42</p>
				<h1 class="hero-title">Inception<span class="hero-cursor" aria-hidden="true">▊</span></h1>
				<p class="hero-tagline">A production-style WordPress infrastructure built from scratch —
three containers, one door, TLS only. Documented, benchmarked, and tested against every rule of the subject.</p>
				<div class="hero-actions">
					<a class="btn btn-primary" href="<?php echo esc_url( home_url( '/user-guide/' ) ); ?>">[ user guide ]</a>
					<a class="btn" href="<?php echo esc_url( home_url( '/developer-guide/' ) ); ?>">[ dev guide ]</a>
				</div>
			</div>
			<div class="hero-term">
				<?php if ( $has_kit ) : ?>
				<div class="ik-window hero-window">
					<div class="ik-window-bar">
						<span class="ik-dots" aria-hidden="true"><i class="ik-dot ik-dot-r"></i><i class="ik-dot ik-dot-y"></i><i class="ik-dot ik-dot-g"></i></span>
						<span class="ik-window-title">dlesieur@inception:~</span>
					</div>
					<div class="ik-window-body">
						<div class="boot" data-boot>
							<p class="boot-line"><?php echo inception_kit_prompt( '~' ); // phpcs:ignore ?><span class="boot-cmd">make up</span></p>
							<p class="boot-line boot-ok">✔ mariadb&nbsp;&nbsp;&nbsp;healthy&nbsp;&nbsp;<span class="boot-dim">3.9s</span></p>
							<p class="boot-line boot-ok">✔ wordpress&nbsp;healthy&nbsp;&nbsp;<span class="boot-dim">6.1s</span></p>
							<p class="boot-line boot-ok">✔ nginx&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;started&nbsp;&nbsp;<span class="boot-dim">6.3s</span></p>
							<p class="boot-line"><span class="boot-arrow">→</span> live at <a href="https://dlesieur.42.fr">https://dlesieur.42.fr</a> <span class="boot-dim">(tls 1.2/1.3)</span></p>
							<p class="boot-line"><?php echo inception_kit_prompt( '~' ); // phpcs:ignore ?><span class="boot-caret" aria-hidden="true"></span></p>
						</div>
					</div>
				</div>
				<?php endif; ?>
			</div>
		</div>

		<?php echo do_shortcode( '[stats]~13s|true cold build;~7s|fresh boot → live;40/41|compliance checks;420MB|three images[/stats]' ); // phpcs:ignore ?>
	</div>
</section>

<section class="home-docs">
	<div class="shell">
		<h2 class="section-title"><span class="section-prompt">$</span> ls ./docs</h2>
		<div class="doc-grid">
			<?php
			$docs = array(
				array( 'user-guide', 'book', 'user guide', 'Start, stop, log in, find your credentials — everything an operator needs.' ),
				array( 'developer-guide', 'wrench', 'developer guide', 'Setup from scratch, Makefile targets, entrypoint design, good practices.' ),
				array( 'architecture', 'layers', 'architecture', 'Three containers, one bridge network, named volumes, Docker secrets.' ),
				array( 'benchmarks', 'gauge', 'benchmarks', 'The performance engineering story with honest, reproducible numbers.' ),
				array( 'defense-qa', 'shield', 'defense q&a', 'Every question an evaluator asks — with runnable proof commands.' ),
			);
			foreach ( $docs as $doc ) :
				list( $slug, $icon, $title, $blurb ) = $doc;
				?>
			<a class="doc-card" href="<?php echo esc_url( home_url( '/' . $slug . '/' ) ); ?>">
				<span class="doc-card-icon"><?php echo $has_kit ? inception_kit_icon( $icon, 20 ) : ''; // phpcs:ignore ?></span>
				<span class="doc-card-name"><?php echo esc_html( $title ); ?>/</span>
				<span class="doc-card-blurb"><?php echo esc_html( $blurb ); ?></span>
				<span class="doc-card-go" aria-hidden="true"><?php echo $has_kit ? inception_kit_icon( 'arrow', 15 ) : '→'; // phpcs:ignore ?></span>
			</a>
			<?php endforeach; ?>
		</div>
	</div>
</section>

<section class="home-journal">
	<div class="shell">
		<h2 class="section-title"><span class="section-prompt">$</span> tail -n 3 journal.log</h2>
		<div class="journal-list">
			<?php
			$latest = new WP_Query(
				array(
					'posts_per_page'      => 3,
					'ignore_sticky_posts' => true,
				)
			);
			while ( $latest->have_posts() ) :
				$latest->the_post();
				?>
			<article class="journal-card">
				<h3 class="journal-card-title">
					<a href="<?php the_permalink(); ?>"><span class="journal-card-prefix">$ cat</span> <?php the_title(); ?></a>
				</h3>
				<?php inception_terminal_post_meta(); ?>
				<p class="journal-card-excerpt"><?php echo esc_html( get_the_excerpt() ); ?></p>
			</article>
			<?php endwhile; ?>
			<?php wp_reset_postdata(); ?>
		</div>
		<p class="journal-more">
			<a class="btn" href="<?php echo esc_url( home_url( '/journal/' ) ); ?>">[ all journal entries ]</a>
		</p>
	</div>
</section>

<?php get_footer(); ?>
