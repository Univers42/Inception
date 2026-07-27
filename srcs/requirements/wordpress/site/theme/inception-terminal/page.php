<?php
/**
 * Documentation page — man-page style header, content column,
 * auto-generated table of contents (kit.js) on wide screens.
 */
get_header();

while ( have_posts() ) :
	the_post();
	?>
<article <?php post_class( 'doc-page' ); ?>>
	<div class="shell">
		<header class="doc-head">
			<p class="doc-breadcrumb">
				<a href="<?php echo esc_url( home_url( '/' ) ); ?>">~</a><span aria-hidden="true">/</span><span><?php echo esc_html( get_post_field( 'post_name' ) ); ?></span>
			</p>
			<h1 class="doc-title"><span class="section-prompt">$</span> man <?php the_title(); ?></h1>
		</header>
		<div class="doc-layout">
			<div class="ik-doc-content doc-content">
				<?php the_content(); ?>
			</div>
			<aside class="ik-toc doc-toc" aria-label="On this page">
				<p class="doc-toc-title">// on this page</p>
			</aside>
		</div>
	</div>
</article>
	<?php
endwhile;

get_footer();
