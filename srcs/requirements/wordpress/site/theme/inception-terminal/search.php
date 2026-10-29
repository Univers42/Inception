<?php
get_header();
global $wp_query;
?>
<section class="page-hero shell">
	<p class="eyebrow">Search</p>
	<?php
	$inception_query = get_search_query();
	$inception_found = (int) $wp_query->found_posts;
	if ( '' === trim( $inception_query ) ) {
		$inception_lede = 'Type a word: nginx, volume, secret.';
	} elseif ( 'docs' === get_query_var( 'post_type' ) ) {
		$inception_lede = sprintf( _n( '%d wiki page matches.', '%d wiki pages match.', $inception_found, 'inception-terminal' ), $inception_found );
	} else {
		$inception_lede = sprintf( _n( '%d result across the wiki and the blog.', '%d results across the wiki and the blog.', $inception_found, 'inception-terminal' ), $inception_found );
	}
	?>
	<h1 class="display"><?php echo '' === trim( $inception_query ) ? 'Search' : esc_html( sprintf( '“%s”', $inception_query ) ); ?></h1>
	<p class="lede"><?php echo esc_html( $inception_lede ); ?></p>
	<?php get_search_form( array( 'aria_label' => 'Refine the search' ) ); ?>
</section>

<section class="shell">
	<?php if ( '' === trim( get_search_query() ) ) : ?>
		<p class="empty">Or browse <a href="<?php echo esc_url( home_url( '/wiki/' ) ); ?>">the wiki</a> and <a href="<?php echo esc_url( home_url( '/blog/' ) ); ?>">the blog</a>.</p>
	<?php elseif ( have_posts() ) : ?>
		<ol class="result-list">
			<?php
			while ( have_posts() ) :
				the_post();
				$inception_kind = inception_terminal_kind();
				?>
				<li class="result reveal">
					<span class="kind kind-<?php echo esc_attr( strtolower( $inception_kind ) ); ?>"><?php echo esc_html( $inception_kind ); ?></span>
					<?php if ( 'Wiki' === $inception_kind && function_exists( 'inception_kit_wiki_area' ) ) : ?>
						<span class="meta"><?php echo esc_html( inception_kit_wiki_area( get_the_ID() )->post_title ); ?></span>
					<?php endif; ?>
					<h2 class="result-title"><a class="card-link" href="<?php the_permalink(); ?>"><?php the_title(); ?></a></h2>
					<p class="result-excerpt"><?php echo wp_kses_post( get_the_excerpt() ); ?></p>
				</li>
			<?php endwhile; ?>
		</ol>
		<?php the_posts_pagination(); ?>
	<?php else : ?>
		<p class="empty">Nothing matched. Try one word: <em>nginx</em>, <em>volume</em>, <em>secret</em>.</p>
	<?php endif; ?>
</section>
<?php
get_footer();
