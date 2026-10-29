<?php
/**
 * /wiki/: the editable introduction (this page's content), a search scoped to
 * the wiki, then every area with its first-level pages.
 */
get_header();
the_post();
$inception_areas = function_exists( 'inception_kit_wiki_areas' ) ? inception_kit_wiki_areas() : array();
?>
<section class="page-hero shell">
	<p class="eyebrow">The wiki</p>
	<h1 class="display">Three levels deep, <em>written down.</em></h1>
	<div class="lede">
		<?php
		if ( strlen( trim( wp_strip_all_tags( get_the_content() ) ) ) < 20 && function_exists( 'inception_kit_wiki_intro' ) ) {
			echo wp_kses_post( inception_kit_wiki_intro() );
		} else {
			the_content();
		}
		?>
	</div>
	<form role="search" method="get" class="search-form search-form-lg" aria-label="Search the wiki" action="<?php echo esc_url( home_url( '/' ) ); ?>">
		<label class="sr-only" for="wiki-search">Search the wiki</label>
		<svg class="search-icon" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true" focusable="false"><circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/></svg>
		<input type="search" id="wiki-search" class="search-field" name="s" placeholder="nginx TLS, MariaDB bootstrap, PID 1…">
		<input type="hidden" name="post_type" value="docs">
		<button type="submit" class="btn btn-primary">Search</button>
	</form>
</section>

<section class="shell">
	<ol class="area-grid">
		<?php
		foreach ( $inception_areas as $inception_area ) :
			$inception_children = get_pages(
				array(
					'post_type'   => 'docs',
					'parent'      => $inception_area->ID,
					'sort_column' => 'menu_order,post_title',
				)
			);
			$inception_total    = count(
				get_pages(
					array(
						'post_type' => 'docs',
						'child_of'  => $inception_area->ID,
					)
				)
			);
			?>
			<li class="area-card reveal" style="--tint: var(--level-<?php echo (int) inception_kit_wiki_tint( $inception_area ); ?>)">
				<h2 class="area-title"><a href="<?php echo esc_url( get_permalink( $inception_area ) ); ?>"><?php echo esc_html( $inception_area->post_title ); ?></a></h2>
				<?php if ( $inception_area->post_excerpt ) : ?>
					<p class="area-summary"><?php echo esc_html( $inception_area->post_excerpt ); ?></p>
				<?php endif; ?>
				<ul class="area-pages">
					<?php foreach ( $inception_children as $inception_child ) : ?>
						<li><a href="<?php echo esc_url( get_permalink( $inception_child ) ); ?>"><?php echo esc_html( $inception_child->post_title ); ?></a></li>
					<?php endforeach; ?>
				</ul>
				<p class="area-count"><?php echo esc_html( sprintf( '%d pages', $inception_total + 1 ) ); ?></p>
			</li>
		<?php endforeach; ?>
	</ol>

	<?php
	$inception_recent = get_posts(
		array(
			'post_type'   => 'docs',
			'numberposts' => 6,
			'orderby'     => 'modified',
			'order'       => 'DESC',
		)
	);
	if ( $inception_recent ) :
		?>
		<h2 class="section-label">Recently updated</h2>
		<ul class="recent-list">
			<?php foreach ( $inception_recent as $inception_doc ) : ?>
				<li>
					<a href="<?php echo esc_url( get_permalink( $inception_doc ) ); ?>"><?php echo esc_html( $inception_doc->post_title ); ?></a>
					<span class="meta"><?php echo esc_html( inception_kit_wiki_area( $inception_doc )->post_title ); ?> · <?php echo esc_html( get_the_modified_date( 'j M Y', $inception_doc ) ); ?></span>
				</li>
			<?php endforeach; ?>
		</ul>
	<?php endif; ?>
</section>
<?php
get_footer();
