<?php
/**
 * The front page: what https://<login>.42.fr/ opens on.
 *
 * It is WordPress's own page on purpose. The evaluation opens the bare domain
 * expecting "the configured WordPress website", then edits a page in wp-admin
 * and looks for the change on the site, so the Home page's title and content
 * are the hero here, rendered as written. The landing (bonus staticsite) and
 * Deeper are links, never the page itself.
 */
get_header();
while ( have_posts() ) :
	the_post();
	?>
<section class="page-hero shell">
	<p class="eyebrow">Inception · <?php echo esc_html( wp_parse_url( home_url(), PHP_URL_HOST ) ); ?></p>
	<h1 class="display"><?php the_title(); ?></h1>
	<div class="front-content prose">
		<?php the_content(); ?>
	</div>
	<p class="front-actions">
		<a class="btn btn-primary" href="<?php echo esc_url( home_url( '/blog/' ) ); ?>">Read the blog</a>
		<a class="btn btn-ghost" href="<?php echo esc_url( home_url( '/wiki/' ) ); ?>">Open the wiki</a>
		<a class="btn btn-ghost" href="<?php echo esc_url( home_url( '/dream/' ) ); ?>">Dream levels</a>
		<a class="btn btn-ghost" href="<?php echo esc_url( home_url( '/deeper/' ) ); ?>">Go deeper</a>
	</p>
</section>
	<?php
endwhile;

$inception_latest = new WP_Query(
	array(
		'post_type'           => 'post',
		'posts_per_page'      => 3,
		'ignore_sticky_posts' => true,
		'no_found_rows'       => true,
	)
);
if ( $inception_latest->have_posts() ) :
	?>
<section class="shell front-latest" aria-labelledby="front-latest-title">
	<h2 id="front-latest-title" class="eyebrow">Latest from the blog</h2>
	<ol class="post-grid">
		<?php
		while ( $inception_latest->have_posts() ) :
			$inception_latest->the_post();
			?>
			<li class="post-card reveal">
				<?php inception_terminal_post_meta( null, false ); ?>
				<h3 class="post-card-title"><a class="card-link" href="<?php the_permalink(); ?>"><?php the_title(); ?></a></h3>
				<p class="post-card-excerpt"><?php echo esc_html( get_the_excerpt() ); ?></p>
				<span class="more" aria-hidden="true">Read the post →</span>
			</li>
		<?php endwhile; ?>
	</ol>
</section>
	<?php
	wp_reset_postdata();
endif;
get_footer();
