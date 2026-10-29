<?php
/*
 * $args['aria_label'] names the search landmark: a page can carry two (the
 * header's and its own), and two unnamed ones read the same to a screen reader.
 */
$inception_search_id    = wp_unique_id( 'search-' );
$inception_search_label = isset( $args['aria_label'] ) ? $args['aria_label'] : 'Site search';
?>
<form role="search" method="get" class="search-form" action="<?php echo esc_url( home_url( '/' ) ); ?>" aria-label="<?php echo esc_attr( $inception_search_label ); ?>">
	<label class="sr-only" for="<?php echo esc_attr( $inception_search_id ); ?>">Search the wiki and the blog</label>
	<svg class="search-icon" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true" focusable="false"><circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/></svg>
	<input type="search" id="<?php echo esc_attr( $inception_search_id ); ?>" class="search-field" placeholder="Search…" value="<?php echo esc_attr( get_search_query() ); ?>" name="s">
	<button type="submit" class="search-submit sr-only">Search</button>
</form>
