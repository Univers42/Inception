<?php
/**
 * Single journal entry.
 */
get_header();

while ( have_posts() ) :
	the_post();
	?>
<article <?php post_class( 'post-single' ); ?>>
	<div class="shell shell-narrow">
		<header class="post-head">
			<p class="doc-breadcrumb">
				<a href="<?php echo esc_url( home_url( '/' ) ); ?>">~</a><span aria-hidden="true">/</span><a href="<?php echo esc_url( home_url( '/journal/' ) ); ?>">journal</a><span aria-hidden="true">/</span><span><?php echo esc_html( get_post_field( 'post_name' ) ); ?></span>
			</p>
			<h1 class="post-title"><span class="section-prompt">$</span> cat <?php the_title(); ?></h1>
			<?php inception_terminal_post_meta(); ?>
		</header>
		<div class="doc-content post-content">
			<?php the_content(); ?>
		</div>
		<nav class="post-nav" aria-label="Post navigation">
			<div class="post-nav-prev"><?php previous_post_link( '%link', '← %title' ); ?></div>
			<div class="post-nav-next"><?php next_post_link( '%link', '%title →' ); ?></div>
		</nav>
	</div>
</article>
	<?php
endwhile;

get_footer();
