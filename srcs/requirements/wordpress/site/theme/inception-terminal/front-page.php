<?php
/**
 * Front page v2 — the page is one continuous shell session.
 * Banner → boot output → aliases → `ls -la ./docs` → `tail -f journal.log`.
 * Structural devices encode real metadata (reading time, modified dates).
 */
get_header();

$has_kit = function_exists( 'inception_kit_icon' );
?>

<section class="session" aria-labelledby="site-title">
	<div class="shell">
		<div class="session-rail" aria-hidden="true"><span>tty0 · inception</span></div>

		<div class="session-body" data-boot>
			<pre class="banner boot-line" aria-hidden="true">
██╗███╗   ██╗ ██████╗███████╗██████╗ ████████╗██╗ ██████╗ ███╗   ██╗
██║████╗  ██║██╔════╝██╔════╝██╔══██╗╚══██╔══╝██║██╔═══██╗████╗  ██║
██║██╔██╗ ██║██║     █████╗  ██████╔╝   ██║   ██║██║   ██║██╔██╗ ██║
██║██║╚██╗██║██║     ██╔══╝  ██╔═══╝    ██║   ██║██║   ██║██║╚██╗██║
██║██║ ╚████║╚██████╗███████╗██║        ██║   ██║╚██████╔╝██║ ╚████║
╚═╝╚═╝  ╚═══╝ ╚═════╝╚══════╝╚═╝        ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝</pre>

			<h1 id="site-title" class="session-echo boot-line">
				<span class="echo-dim">·</span> a production-style WordPress infrastructure, built from scratch —
				three containers, one door, TLS only<span class="echo-dim">.</span>
			</h1>

			<div class="session-run boot-line">
				<?php echo $has_kit ? inception_kit_prompt( '~' ) : '$'; // phpcs:ignore ?><span class="run-cmd">make up</span>
			</div>
			<pre class="session-out boot-line"><span class="out-ok">✔ mariadb    healthy</span>   <span class="out-t">3.9s</span>
<span class="out-ok">✔ wordpress  healthy</span>   <span class="out-t">6.1s</span>
<span class="out-ok">✔ nginx      started</span>   <span class="out-t">6.3s</span>
<span class="out-go">→ live at https://dlesieur.42.fr</span>  <span class="out-t">tls 1.2/1.3 · port 443 only</span></pre>

			<div class="session-run boot-line">
				<?php echo $has_kit ? inception_kit_prompt( '~' ) : '$'; // phpcs:ignore ?><span class="run-cmd">make bench</span>
			</div>
			<pre class="session-out boot-line">cold build <span class="out-num">13s</span>   fresh boot <span class="out-num">7s</span>   compliance <span class="out-num">40/41</span>   images <span class="out-num">420MB</span></pre>

			<div class="session-aliases boot-line">
				<a class="alias" href="<?php echo esc_url( home_url( '/user-guide/' ) ); ?>">[ user guide ]</a>
				<a class="alias" href="<?php echo esc_url( home_url( '/developer-guide/' ) ); ?>">[ dev guide ]</a>
				<a class="alias alias-dim" href="<?php echo esc_url( home_url( '/defense-qa/' ) ); ?>">[ defense q&amp;a ]</a>
			</div>

			<div class="session-run boot-line session-idle">
				<?php echo $has_kit ? inception_kit_prompt( '~' ) : '$'; // phpcs:ignore ?><span class="boot-caret" aria-hidden="true"></span>
			</div>
		</div>
	</div>
</section>

<section class="home-docs" aria-label="Documentation index">
	<div class="shell">
		<h2 class="section-title"><span class="section-prompt">$</span> ls -la ./docs</h2>
		<div class="lsla" role="list">
			<div class="lsla-head" aria-hidden="true">
				<span class="lsla-perm">mode</span><span class="lsla-size">read</span><span class="lsla-date">updated</span><span class="lsla-name">name</span>
			</div>
			<?php
			$docs = array(
				array( 'user-guide', 'user-guide/', 'start, stop, credentials, health — the operator manual' ),
				array( 'developer-guide', 'developer-guide/', 'setup, Makefile, entrypoints, good practices' ),
				array( 'architecture', 'architecture/', 'three containers, one bridge, named volumes, secrets' ),
				array( 'benchmarks', 'benchmarks/', 'the performance story, with honest numbers' ),
				array( 'defense-qa', 'defense-qa/', 'every evaluator question, with proof commands' ),
			);
			foreach ( $docs as $doc ) :
				list( $slug, $label, $blurb ) = $doc;
				$p    = get_page_by_path( $slug, OBJECT, 'page' );
				$mins = ( $p && function_exists( 'inception_kit_reading_time' ) ) ? inception_kit_reading_time( $p ) : 2;
				$date = $p ? get_post_modified_time( 'Y-m-d', false, $p ) : gmdate( 'Y-m-d' );
				?>
			<a class="lsla-row" role="listitem" href="<?php echo esc_url( home_url( '/' . $slug . '/' ) ); ?>">
				<span class="lsla-perm" aria-hidden="true">drwxr-xr-x</span>
				<span class="lsla-size"><?php echo (int) $mins; ?> min</span>
				<span class="lsla-date"><?php echo esc_html( $date ); ?></span>
				<span class="lsla-name"><?php echo esc_html( $label ); ?><span class="lsla-blurb"><?php echo esc_html( $blurb ); ?></span></span>
				<span class="lsla-go" aria-hidden="true">→</span>
			</a>
			<?php endforeach; ?>
		</div>
	</div>
</section>

<section class="home-journal" aria-label="Latest journal entries">
	<div class="shell">
		<h2 class="section-title"><span class="section-prompt">$</span> tail -n 3 journal.log</h2>
		<div class="loglist">
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
			<a class="logline" href="<?php the_permalink(); ?>">
				<span class="log-ts"><?php echo esc_html( get_the_date( 'Y-m-d\TH:i' ) ); ?></span>
				<span class="log-level" aria-hidden="true">[post]</span>
				<span class="log-title"><?php the_title(); ?></span>
				<span class="log-meta"><?php echo function_exists( 'inception_kit_reading_time' ) ? (int) inception_kit_reading_time() . ' min' : ''; ?></span>
			</a>
			<?php endwhile; ?>
			<?php wp_reset_postdata(); ?>
			<a class="logline logline-follow" href="<?php echo esc_url( home_url( '/journal/' ) ); ?>">
				<span class="log-ts" aria-hidden="true">·······</span>
				<span class="log-follow">follow the full log →</span>
			</a>
		</div>
	</div>
</section>

<?php get_footer(); ?>
