<?php
/**
 * One wiki page: the area's tree on the left, the page on the right, and the
 * wiki read in order through previous/next. weDocs loads this file because
 * inception-kit selects its "legacy" renderer.
 */
get_header();
while ( have_posts() ) :
	the_post();
	$inception_area      = inception_kit_wiki_area( get_the_ID() );
	$inception_tint      = inception_kit_wiki_tint( $inception_area );
	$inception_ancestors = array_reverse( get_post_ancestors( get_the_ID() ) );
	list( $inception_prev, $inception_next ) = inception_kit_wiki_neighbours( get_the_ID() );
	$inception_children  = get_pages(
		array(
			'post_type'   => 'docs',
			'parent'      => get_the_ID(),
			'sort_column' => 'menu_order,post_title',
		)
	);
	?>
<div class="wiki shell" style="--tint: var(--level-<?php echo (int) $inception_tint; ?>)">
	<aside class="wiki-side" aria-label="Wiki navigation">
		<details class="wiki-tree" open>
			<summary><?php echo esc_html( $inception_area->post_title ); ?></summary>
			<nav aria-label="Wiki pages">
				<ul class="wiki-areas">
					<?php foreach ( inception_kit_wiki_areas() as $inception_a ) : ?>
						<li<?php echo $inception_a->ID === $inception_area->ID ? ' class="is-current"' : ''; ?>>
							<a href="<?php echo esc_url( get_permalink( $inception_a ) ); ?>"<?php echo get_the_ID() === $inception_a->ID ? ' aria-current="page"' : ''; ?>><?php echo esc_html( $inception_a->post_title ); ?></a>
							<?php if ( $inception_a->ID === $inception_area->ID ) : ?>
								<ul class="wiki-pages">
									<?php
									wp_list_pages(
										array(
											'post_type'   => 'docs',
											'child_of'    => $inception_area->ID,
											'title_li'    => '',
											'sort_column' => 'menu_order,post_title',
										)
									);
									?>
								</ul>
							<?php endif; ?>
						</li>
					<?php endforeach; ?>
				</ul>
			</nav>
		</details>
	</aside>

	<article <?php post_class( 'entry wiki-entry' ); ?>>
		<header class="entry-head">
			<nav class="crumbs" aria-label="Breadcrumb">
				<a href="<?php echo esc_url( home_url( '/wiki/' ) ); ?>">Wiki</a>
				<?php foreach ( $inception_ancestors as $inception_up ) : ?>
					<span aria-hidden="true">/</span><a href="<?php echo esc_url( get_permalink( $inception_up ) ); ?>"><?php echo esc_html( get_the_title( $inception_up ) ); ?></a>
				<?php endforeach; ?>
			</nav>
			<h1 class="display entry-title"><?php the_title(); ?></h1>
			<p class="meta">
				<span>Updated <time datetime="<?php echo esc_attr( get_the_modified_date( 'c' ) ); ?>"><?php echo esc_html( get_the_modified_date( 'j M Y' ) ); ?></time></span>
				<span class="meta-sep" aria-hidden="true">·</span><span><?php echo (int) inception_terminal_reading_minutes(); ?> min read</span>
				<?php edit_post_link( 'Edit this page', '<span class="meta-sep" aria-hidden="true">·</span>' ); ?>
			</p>
		</header>

		<div class="prose">
			<?php the_content(); ?>
		</div>

		<?php if ( $inception_children ) : ?>
			<section class="wiki-children" aria-labelledby="wiki-children-title">
				<h2 id="wiki-children-title" class="section-label">In this section</h2>
				<ul>
					<?php foreach ( $inception_children as $inception_child ) : ?>
						<li><a class="child-card" href="<?php echo esc_url( get_permalink( $inception_child ) ); ?>"><?php echo esc_html( $inception_child->post_title ); ?><span aria-hidden="true">→</span></a></li>
					<?php endforeach; ?>
				</ul>
			</section>
		<?php endif; ?>

		<nav class="pager-cards" aria-label="Read the wiki in order">
			<?php
			if ( $inception_prev ) {
				printf( '<a class="pager-card" rel="prev" href="%s"><span class="eyebrow">Previous</span><span class="pager-title">%s</span></a>', esc_url( get_permalink( $inception_prev ) ), esc_html( get_the_title( $inception_prev ) ) );
			}
			if ( $inception_next ) {
				printf( '<a class="pager-card pager-next" rel="next" href="%s"><span class="eyebrow">Next</span><span class="pager-title">%s</span></a>', esc_url( get_permalink( $inception_next ) ), esc_html( get_the_title( $inception_next ) ) );
			}
			?>
		</nav>
	</article>
</div>
	<?php
endwhile;
get_footer();
