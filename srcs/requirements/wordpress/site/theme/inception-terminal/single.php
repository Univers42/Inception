<?php
get_header();
while ( have_posts() ) :
	the_post();
	$inception_cats = get_the_category();
	?>
<article <?php post_class( 'entry shell' ); ?>>
	<header class="entry-head">
		<nav class="crumbs" aria-label="Breadcrumb">
			<a href="<?php echo esc_url( get_permalink( (int) get_option( 'page_for_posts' ) ) ); ?>">Blog</a>
			<?php if ( $inception_cats ) : ?>
				<span aria-hidden="true">/</span><a href="<?php echo esc_url( get_category_link( $inception_cats[0] ) ); ?>"><?php echo esc_html( $inception_cats[0]->name ); ?></a>
			<?php endif; ?>
		</nav>
		<h1 class="display entry-title"><?php the_title(); ?></h1>
		<?php inception_terminal_post_meta(); ?>
		<?php edit_post_link( 'Edit this post', '<p class="edit-link">', '</p>' ); ?>
	</header>

	<div class="entry-body">
		<div class="prose ik-doc-content">
			<?php the_content(); ?>
		</div>
		<?php // kit.js fills this rail from the headings and marks the one in view. ?>
		<nav class="ik-toc entry-rail" aria-label="On this page">
			<p class="ik-toc-title" aria-hidden="true">On this page</p>
		</nav>
	</div>

	<?php the_tags( '<p class="tags"><span class="sr-only">Tags: </span>', '', '</p>' ); ?>

	<nav class="pager-cards" aria-label="More posts">
		<?php
		$inception_prev = get_previous_post();
		$inception_next = get_next_post();
		if ( $inception_prev ) {
			printf( '<a class="pager-card" rel="prev" href="%s"><span class="eyebrow">Older</span><span class="pager-title">%s</span></a>', esc_url( get_permalink( $inception_prev ) ), esc_html( get_the_title( $inception_prev ) ) );
		}
		if ( $inception_next ) {
			printf( '<a class="pager-card pager-next" rel="next" href="%s"><span class="eyebrow">Newer</span><span class="pager-title">%s</span></a>', esc_url( get_permalink( $inception_next ) ), esc_html( get_the_title( $inception_next ) ) );
		}
		?>
	</nav>

	<?php
	if ( comments_open() || get_comments_number() ) {
		comments_template();
	}
	?>
</article>
	<?php
endwhile;
get_footer();
