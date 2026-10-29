<?php
/**
 * The blog's guide series, "Building Inception": content/posts/series.json
 * names each post and its HTML file, and sync.php keeps them in step on every
 * boot by the wiki's rule (an edit made in wp-admin wins over the repository).
 * The four journal posts seed.php wrote on the first boot are not touched,
 * except to put two early titles in sentence case (below). The Home page, the
 * front page's hero, is filled once from content/pages/home.html.
 */

$src = '/usr/src/inception-site';
require_once $src . '/sync.php';

// Trusted repository content: kses would strip the diagrams' class and the
// shortcodes' attributes when no user is logged in (WP-CLI).
kses_remove_filters();

// The front page renders the Home page's content, and seed.php created that
// page empty. Fill it once -- the meta records that it happened -- so an edit
// in wp-admin (the evaluation's "edit a page, see it on the site", then the
// reboot that checks it persisted) is never written over, even if it empties
// the page.
$home = get_post( (int) get_option( 'page_on_front' ) );
if ( $home && 'page' === $home->post_type && ! get_post_meta( $home->ID, '_inception_home_filled', true ) ) {
	if ( '' === trim( $home->post_content ) ) {
		wp_update_post(
			array(
				'ID'           => $home->ID,
				'post_content' => (string) file_get_contents( "$src/content/pages/home.html" ),
			)
		);
		WP_CLI::log( '[posts] home: the front page content was filled' );
	}
	update_post_meta( $home->ID, '_inception_home_filled', '1' );
}

$series = json_decode( (string) file_get_contents( "$src/content/posts/series.json" ), true );
if ( ! is_array( $series ) ) {
	WP_CLI::warning( '[posts] content/posts/series.json is missing or not JSON — series not synced' );
	return;
}

$category = get_term_by( 'slug', 'building-inception', 'category' );
if ( ! $category ) {
	$made     = wp_insert_term( 'Building Inception', 'category', array( 'slug' => 'building-inception' ) );
	$category = is_wp_error( $made ) ? null : get_term( $made['term_id'], 'category' );
}

// Bylines and feeds print the display name, which WordPress sets to the login
// name: the one half of a credential the site would otherwise publish. An
// account whose display name is still its login gets a role name instead.
foreach ( get_users() as $user ) {
	if ( $user->display_name === $user->user_login ) {
		wp_update_user(
			array(
				'ID'           => $user->ID,
				'display_name' => in_array( 'administrator', (array) $user->roles, true ) ? 'Inception maintainer' : 'Inception editor',
			)
		);
	}
}
// Two journal posts were first seeded in lower case ("the blank page bug")
// while every other title is in sentence case. Rename them while the title is
// still the one seeded: a title someone chose in wp-admin stays.
$renamed = array(
	'the-blank-page-bug' => array( 'the blank page bug', 'The blank page bug' ),
	'seven-second-boots' => array( 'seven-second boots', 'Seven-second boots' ),
);
foreach ( $renamed as $slug => list( $seeded, $title ) ) {
	$journal = get_page_by_path( $slug, OBJECT, 'post' );
	if ( $journal && $journal->post_title === $seeded ) {
		wp_update_post(
			array(
				'ID'         => $journal->ID,
				'post_title' => $title,
			)
		);
		WP_CLI::log( "[posts] $slug: title put in sentence case" );
	}
}

$admins = get_users(
	array(
		'role'   => 'administrator',
		'number' => 1,
		'fields' => 'ID',
	)
);

$changed = 0;
foreach ( $series as $post ) {
	list( $id, $state ) = inception_sync_post(
		array(
			'post_type'     => 'post',
			'post_status'   => 'publish',
			'post_name'     => $post['slug'],
			'post_title'    => $post['title'],
			'post_excerpt'  => $post['excerpt'],
			'post_date'     => $post['date'],
			'post_author'   => $admins ? (int) $admins[0] : 0,
			'post_category' => $category ? array( (int) $category->term_id ) : array(),
			'tags_input'    => $post['tags'],
			'post_content'  => (string) file_get_contents( "$src/content/posts/{$post['file']}" ),
		),
		$post['slug'],
		'_inception_post'
	);
	if ( 'kept' === $state ) {
		WP_CLI::log( "[posts] {$post['slug']} was edited in wp-admin: kept, not overwritten" );
	}
	if ( 'created' === $state || 'refreshed' === $state ) {
		++$changed;
	}
}

WP_CLI::log( sprintf( '[posts] %d posts in the series, %d created or refreshed', count( $series ), $changed ) );
