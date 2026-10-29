<?php
/**
 * Seeds and keeps the blog and the wiki in step with the repository, on every
 * boot (install.sh runs it after seed.php). Every step is idempotent.
 *
 *  1. plugin settings, once per INCEPTION_PLUGINS_CONFIG bump;
 *  2. the posts page is /blog/ (it was seeded as /journal/);
 *  3. the wiki: one weDocs page per entry of content/wiki/tree.json, cut
 *     from the docs by tools/wiki, kept in step by sync.php's rule (an edit
 *     made in wp-admin wins over the repository);
 *  4. the wiki's home page (/wiki/), the menu, and the search index.
 */

$src  = '/usr/src/inception-site';
$wiki = $src . '/content/wiki';
require_once $src . '/sync.php';

// Seeded HTML is trusted repository content: kses would strip the code-block
// classes and the shortcodes' attributes when no user is logged in (WP-CLI).
kses_remove_filters();

const INCEPTION_PLUGINS_CONFIG = 2;
const INCEPTION_MENU_VERSION   = 2;

// 1. plugin settings ---------------------------------------------------------
if ( (int) get_option( 'inception_plugins_configured' ) < INCEPTION_PLUGINS_CONFIG ) {
	// weDocs ships Appsero usage tracking, opt-in: record the answer "no".
	update_option( 'wedocs_allow_tracking', 'no' );
	update_option( 'wedocs_tracking_notice', 'hide' );

	$toc = get_option( 'ez-toc-settings', array() );
	$toc = array_merge(
		is_array( $toc ) ? $toc : array(),
		array(
			'enabled_post_types'         => array( 'post', 'docs' ),
			'auto_insert_post_types'     => array( 'post', 'docs' ),
			'position'                   => 'before',
			'start'                      => 3,
			'heading_levels'             => array( '2', '3' ),
			'show_heading_text'          => true,
			'heading_text'               => 'On this page',
			// 2: no show/hide toggle. Its label was not focusable, its icon was
			// black on the dark theme, and with the plugin CSS off it hid nothing.
			'visibility'                 => false,
			'visibility_hide_by_default' => false,
			'smooth_scroll'              => true,
			// the theme styles the table with the shared tokens
			'exclude_css'                => true,
		)
	);
	update_option( 'ez-toc-settings', $toc );

	update_option( 'relevanssi_index_post_types', array( 'post', 'page', 'docs' ) );
	update_option( 'inception_plugins_configured', INCEPTION_PLUGINS_CONFIG );
	WP_CLI::log( '[wiki] plugin settings applied' );
}

// Easy TOC sends the first wp-admin visit after its activation to a welcome
// screen. The settings above are that screen's job, and the detour turned a
// signed-in /wp-admin/ into a 302 (compliance E05).
delete_option( 'ez_toc_do_activation_redirect' );

// 2. the posts page is /blog/ ------------------------------------------------
$blog = get_page_by_path( 'blog', OBJECT, 'page' );
if ( ! $blog ) {
	$journal = get_page_by_path( 'journal', OBJECT, 'page' );
	if ( $journal ) {
		wp_update_post(
			array(
				'ID'         => $journal->ID,
				'post_name'  => 'blog',
				'post_title' => 'Blog',
			)
		);
		$blog_id = $journal->ID;
	} else {
		$blog_id = wp_insert_post(
			array(
				'post_type'   => 'page',
				'post_status' => 'publish',
				'post_name'   => 'blog',
				'post_title'  => 'Blog',
			)
		);
	}
} else {
	$blog_id = $blog->ID;
}
if ( (int) get_option( 'page_for_posts' ) !== (int) $blog_id ) {
	update_option( 'page_for_posts', (int) $blog_id );
}

// 3. the wiki ----------------------------------------------------------------
$tree = json_decode( (string) file_get_contents( "$wiki/tree.json" ), true );
if ( ! is_array( $tree ) ) {
	WP_CLI::warning( "[wiki] $wiki/tree.json is missing or not JSON — wiki not synced" );
	return;
}

$ids     = array();
$changed = 0;
foreach ( $tree as $node ) {
	list( $id, $state ) = inception_sync_post(
		array(
			'post_type'    => 'docs',
			'post_status'  => 'publish',
			'post_title'   => $node['title'],
			'post_name'    => $node['slug'],
			'post_parent'  => $node['parent'] ? ( $ids[ $node['parent'] ] ?? 0 ) : 0,
			'menu_order'   => (int) $node['order'],
			'post_excerpt' => $node['summary'],
			'post_content' => (string) file_get_contents( "$wiki/{$node['slug']}.html" ),
		),
		$node['slug'],
		'_inception_wiki'
	);
	if ( 'kept' === $state ) {
		WP_CLI::log( "[wiki] {$node['slug']} was edited in wp-admin: kept, not overwritten" );
	}
	if ( 'created' === $state || 'refreshed' === $state ) {
		++$changed;
	}
	if ( $id ) {
		$ids[ $node['slug'] ] = $id;
	}
}

// /wiki/ itself: a page the theme draws with page-wiki.php. Its content is
// the editable introduction above the areas.
$home = get_page_by_path( 'wiki', OBJECT, 'page' );
if ( ! $home ) {
	$home_id = wp_insert_post(
		array(
			'post_type'    => 'page',
			'post_status'  => 'publish',
			'post_name'    => 'wiki',
			'post_title'   => 'Wiki',
			'post_content' => inception_kit_wiki_intro(),
		)
	);
} else {
	$home_id = $home->ID;
}
$wedocs                                  = get_option( 'wedocs_settings', array() );
$wedocs                                  = is_array( $wedocs ) ? $wedocs : array();
$wedocs['general']                       = isset( $wedocs['general'] ) && is_array( $wedocs['general'] ) ? $wedocs['general'] : array();
if ( (int) ( $wedocs['general']['docs_home'] ?? 0 ) !== (int) $home_id ) {
	$wedocs['general']['docs_home'] = (int) $home_id;
	update_option( 'wedocs_settings', $wedocs );
}

// The pages the wiki replaced leave the site (kept as drafts, their content
// intact); inception-kit answers their old URLs with a 301 to the wiki. So
// does /docs/, the "[wedocs]" page weDocs creates when it is first activated.
foreach ( array( 'user-guide', 'developer-guide', 'architecture', 'benchmarks', 'defense-qa', 'docs' ) as $old ) {
	$page = get_page_by_path( $old, OBJECT, 'page' );
	if ( $page && 'publish' === $page->post_status ) {
		wp_update_post(
			array(
				'ID'          => $page->ID,
				'post_status' => 'draft',
			)
		);
	}
}

// /wiki/ rewrite rules: the slug comes from inception-kit's filter. Flushed
// when the stored rules do not route it, read from the rules themselves: an
// option saying "flushed for wiki" was once set by a boot whose rules were
// built under /docs/ (the kit inactive), and every page below /wiki/ 404ed.
$slug = get_post_type_object( 'docs' )->rewrite['slug'] ?? '';
if ( 'wiki' !== $slug ) {
	WP_CLI::warning( "[wiki] weDocs is served under /$slug/, not /wiki/: is inception-kit active?" );
}
if ( ! preg_grep( '#^' . preg_quote( $slug, '#' ) . '/#', array_keys( (array) get_option( 'rewrite_rules', array() ) ) ) ) {
	flush_rewrite_rules();
	WP_CLI::log( "[wiki] rewrite rules rebuilt for /$slug/" );
}

// 4. menu + search index -----------------------------------------------------
if ( (int) get_option( 'inception_menu_version' ) < INCEPTION_MENU_VERSION ) {
	$menu    = wp_get_nav_menu_object( 'primary' );
	$menu_id = $menu ? (int) $menu->term_id : (int) wp_create_nav_menu( 'primary' );
	foreach ( (array) wp_get_nav_menu_items( $menu_id ) as $item ) {
		wp_delete_post( $item->ID, true );
	}
	// Pages as page items, so WordPress builds their URL for the host the
	// visitor came in on (a NAT port included); the lab as a relative link.
	foreach ( array( array( 'Blog', $blog_id ), array( 'Wiki', $home_id ) ) as $entry ) {
		wp_update_nav_menu_item(
			$menu_id,
			0,
			array(
				'menu-item-title'     => $entry[0],
				'menu-item-object-id' => (int) $entry[1],
				'menu-item-object'    => 'page',
				'menu-item-type'      => 'post_type',
				'menu-item-status'    => 'publish',
			)
		);
	}
	wp_update_nav_menu_item(
		$menu_id,
		0,
		array(
			'menu-item-title'  => 'Lab',
			'menu-item-url'    => '/lab/',
			'menu-item-type'   => 'custom',
			'menu-item-status' => 'publish',
		)
	);
	$locations            = get_theme_mod( 'nav_menu_locations', array() );
	$locations['primary'] = $menu_id;
	set_theme_mod( 'nav_menu_locations', $locations );
	update_option( 'inception_menu_version', INCEPTION_MENU_VERSION );
}

if ( function_exists( 'relevanssi_build_index' ) && ( $changed > 0 || ! get_option( 'inception_search_indexed' ) ) ) {
	relevanssi_build_index( false, false );
	update_option( 'inception_search_indexed', '1' );
	WP_CLI::log( '[wiki] search index rebuilt' );
}

WP_CLI::log( sprintf( '[wiki] %d pages in the wiki, %d created or refreshed', count( $ids ), $changed ) );
