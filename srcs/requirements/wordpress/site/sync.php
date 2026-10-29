<?php
/**
 * One rule for every page the repository seeds and keeps in step on each boot
 * (the wiki's pages, the blog's guide series): created when missing,
 * refreshed when the repository changed it, and left alone once someone has
 * edited it in wp-admin -- its content no longer matches the hash stored at
 * the last sync, and an edit made by a person wins.
 */

/**
 * @param array  $fields wp_insert_post() fields, post_content as written.
 * @param string $key    the page's stable name in the repository.
 * @param string $meta   meta key prefix: "{$meta}_slug" and "{$meta}_hash".
 * @return array        array( post ID or 0, created|refreshed|kept|unchanged|failed )
 */
function inception_sync_post( array $fields, $key, $meta ) {
	$hash  = sha1( $fields['post_content'] );
	$found = get_posts(
		array(
			'post_type'   => $fields['post_type'],
			'post_status' => 'any',
			'meta_key'    => "{$meta}_slug", // phpcs:ignore WordPress.DB.SlowDBQuery
			'meta_value'  => $key,           // phpcs:ignore WordPress.DB.SlowDBQuery
			'numberposts' => 1,
		)
	);
	// wp_insert_post() unslashes: without this a backslash in a shell example
	// would vanish, and the stored hash would never match again.
	$fields['post_content'] = wp_slash( $fields['post_content'] );

	if ( ! $found ) {
		$id = wp_insert_post( $fields, true );
		if ( is_wp_error( $id ) ) {
			WP_CLI::warning( "[sync] could not create $key: " . $id->get_error_message() );
			return array( 0, 'failed' );
		}
		update_post_meta( $id, "{$meta}_slug", $key );
		update_post_meta( $id, "{$meta}_hash", $hash );
		return array( $id, 'created' );
	}

	$id     = $found[0]->ID;
	$synced = get_post_meta( $id, "{$meta}_hash", true );
	if ( $synced === $hash ) {
		return array( $id, 'unchanged' );
	}
	if ( sha1( $found[0]->post_content ) !== $synced ) {
		return array( $id, 'kept' );
	}
	wp_update_post( array( 'ID' => $id ) + $fields );
	update_post_meta( $id, "{$meta}_hash", $hash );
	return array( $id, 'refreshed' );
}
