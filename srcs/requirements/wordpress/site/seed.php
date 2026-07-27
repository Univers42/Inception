<?php
/**
 * Inception site seeding — executed in ONE PHP process via
 * `wp eval-file seed.php` (WordPress fully bootstrapped by WP-CLI).
 * Every step is idempotent; a marker option short-circuits the
 * content phase on later boots.
 */

$src = '/usr/src/inception-site';

/* ── 1. Activate plugin + theme (cheap no-ops when already active) ── */
require_once ABSPATH . 'wp-admin/includes/plugin.php';
activate_plugin( 'inception-kit/inception-kit.php' );
if ( wp_get_theme()->get_stylesheet() !== 'inception-terminal' ) {
	switch_theme( 'inception-terminal' );
}

/* ── 2. Pretty permalinks ─────────────────────────────────────────── */
if ( get_option( 'permalink_structure' ) !== '/%postname%/' ) {
	global $wp_rewrite;
	$wp_rewrite->set_permalink_structure( '/%postname%/' );
	flush_rewrite_rules();
}

/* ── 3. Content (once) ────────────────────────────────────────────── */
if ( get_option( 'inception_site_seeded' ) === '1' ) {
	WP_CLI::log( '[site] content already seeded' );
	return;
}
WP_CLI::log( '[site] seeding documentation content ...' );

function ink_ensure( $slug, $title, $type, $file = null, $date = null ) {
	$existing = get_page_by_path( $slug, OBJECT, $type );
	if ( $existing ) {
		return (int) $existing->ID;
	}
	$args = array(
		'post_type'   => $type,
		'post_status' => 'publish',
		'post_name'   => $slug,
		'post_title'  => $title,
		'post_content'=> ( $file && file_exists( $file ) ) ? file_get_contents( $file ) : '',
	);
	if ( $date ) {
		$args['post_date'] = $date;
	}
	$id = wp_insert_post( $args, true );
	if ( is_wp_error( $id ) ) {
		WP_CLI::warning( "[site] failed to create $slug: " . $id->get_error_message() );
		return 0;
	}
	return (int) $id;
}

$pages = $src . '/content/pages';
$posts = $src . '/content/posts';

$home_id    = ink_ensure( 'home', 'Inception', 'page' );
$journal_id = ink_ensure( 'journal', 'Journal', 'page' );
$ug_id      = ink_ensure( 'user-guide', 'user-guide', 'page', "$pages/user-guide.html" );
$dg_id      = ink_ensure( 'developer-guide', 'developer-guide', 'page', "$pages/developer-guide.html" );
$ar_id      = ink_ensure( 'architecture', 'architecture', 'page', "$pages/architecture.html" );
$bm_id      = ink_ensure( 'benchmarks', 'benchmarks', 'page', "$pages/benchmarks.html" );
$qa_id      = ink_ensure( 'defense-qa', 'defense-qa', 'page', "$pages/defense-qa.html" );

/* journal category + posts */
$term    = wp_insert_term( 'Engineering Journal', 'category', array( 'slug' => 'engineering-journal' ) );
$term_id = is_wp_error( $term )
	? (int) ( get_term_by( 'slug', 'engineering-journal', 'category' )->term_id ?? 0 )
	: (int) $term['term_id'];

$journal_posts = array(
	array( 'the-blank-page-bug', 'the blank page bug', "$posts/the-blank-page-bug.html", '2026-07-24 10:00:00' ),
	array( '2x-faster-cold-builds', '2× faster cold builds', "$posts/two-x-faster-cold-builds.html", '2026-07-25 11:00:00' ),
	array( 'seven-second-boots', 'seven-second boots', "$posts/seven-second-boots.html", '2026-07-26 12:00:00' ),
	array( 'tls-with-a-local-ca', 'TLS with a local CA', "$posts/tls-local-ca.html", '2026-07-27 09:00:00' ),
);
foreach ( $journal_posts as $jp ) {
	$pid = ink_ensure( $jp[0], $jp[1], 'post', $jp[2], $jp[3] );
	if ( $pid && $term_id ) {
		wp_set_post_terms( $pid, array( $term_id ), 'category' );
	}
}

/* drop WordPress sample content */
foreach ( array( array( 'hello-world', 'post' ), array( 'sample-page', 'page' ) ) as $sample ) {
	$s = get_page_by_path( $sample[0], OBJECT, $sample[1] );
	if ( $s ) {
		wp_delete_post( $s->ID, true );
	}
}

/* navigation menu */
$menu    = wp_get_nav_menu_object( 'primary' );
$menu_id = $menu ? (int) $menu->term_id : (int) wp_create_nav_menu( 'primary' );
if ( empty( wp_get_nav_menu_items( $menu_id ) ) ) {
	wp_update_nav_menu_item( $menu_id, 0, array(
		'menu-item-title'  => 'home',
		'menu-item-url'    => home_url( '/' ),
		'menu-item-type'   => 'custom',
		'menu-item-status' => 'publish',
	) );
	$entries = array(
		array( $ug_id, 'user guide' ),
		array( $dg_id, 'dev guide' ),
		array( $ar_id, 'architecture' ),
		array( $bm_id, 'benchmarks' ),
		array( $qa_id, 'defense q&a' ),
		array( $journal_id, 'journal' ),
	);
	foreach ( $entries as $entry ) {
		if ( ! $entry[0] ) {
			continue;
		}
		wp_update_nav_menu_item( $menu_id, 0, array(
			'menu-item-title'     => $entry[1],
			'menu-item-object-id' => $entry[0],
			'menu-item-object'    => 'page',
			'menu-item-type'      => 'post_type',
			'menu-item-status'    => 'publish',
		) );
	}
}
$locations            = get_theme_mod( 'nav_menu_locations', array() );
$locations['primary'] = $menu_id;
set_theme_mod( 'nav_menu_locations', $locations );

/* static front page + posts page */
update_option( 'show_on_front', 'page' );
update_option( 'page_on_front', $home_id );
update_option( 'page_for_posts', $journal_id );
update_option( 'blogdescription', 'infra docs & engineering journal' );

update_option( 'inception_site_seeded', '1' );
WP_CLI::log( '[site] seeding complete — theme, plugin, 7 pages, 4 posts, menu.' );
