<?php
/**
 * The wiki: weDocs' hierarchical `docs` post type, served under /wiki/ and
 * drawn by the theme (single-docs.php for a page, page-wiki.php for the home).
 * The pages are cut from the project's own docs by tools/wiki and seeded by
 * site/wiki.php; this file only routes and navigates them.
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

/** /wiki/<area>/<page>/ instead of weDocs' /docs/. */
function inception_kit_wiki_post_type( $args ) {
	$args['rewrite'] = array(
		'slug'       => 'wiki',
		'with_front' => false,
	);
	return $args;
}
add_filter( 'wedocs_post_type', 'inception_kit_wiki_post_type' );

/**
 * weDocs' block and Elementor renderers would bypass the theme; "legacy" makes
 * it load single-docs.php from the theme, which is where the wiki's design is.
 */
function inception_kit_wiki_renderer() {
	return 'legacy';
}
add_filter( 'wedocs_single_doc_renderer', 'inception_kit_wiki_renderer' );

/**
 * weDocs' own front-end CSS, its jQuery anchor script and its block styles
 * would fight the theme's tokens; the theme draws everything they would.
 */
function inception_kit_wiki_dequeue() {
	if ( ! is_singular( 'docs' ) && ! is_page( 'wiki' ) ) {
		return;
	}
	foreach ( array( 'wedocs-styles', 'wedocs-block-style', 'wedocs-app-style' ) as $style ) {
		wp_dequeue_style( $style );
	}
	foreach ( array( 'wedocs-scripts', 'wedocs-anchorjs' ) as $script ) {
		wp_dequeue_script( $script );
	}
}
add_action( 'wp_enqueue_scripts', 'inception_kit_wiki_dequeue', 100 );

/** The wiki page seeded under a tools/wiki slug, or null. */
function inception_kit_wiki_doc( $slug ) {
	static $cache = array();
	if ( ! array_key_exists( $slug, $cache ) ) {
		$found          = get_posts(
			array(
				'post_type'   => 'docs',
				'post_status' => 'publish',
				'meta_key'    => '_inception_wiki_slug', // phpcs:ignore WordPress.DB.SlowDBQuery -- 52 rows, indexed meta_key
				'meta_value'  => $slug,                  // phpcs:ignore WordPress.DB.SlowDBQuery
				'numberposts' => 1,
			)
		);
		$cache[ $slug ] = $found ? $found[0] : null;
	}
	return $cache[ $slug ];
}

/** Top-level areas (Start here, Architecture, …) in their seeded order. */
/**
 * The wiki home's introduction: seeded once, then the page's own content.
 * page-wiki.php falls back to it when that content is (nearly) empty: an
 * edit once left a lone dash under the headline.
 */
function inception_kit_wiki_intro() {
	return '<p>Everything about this stack, cut from the project\'s own documentation: what each container does, why it is built that way, how to run it, and how to defend it.</p>';
}

function inception_kit_wiki_areas() {
	return get_pages(
		array(
			'post_type'   => 'docs',
			'parent'      => 0,
			'sort_column' => 'menu_order,post_title',
		)
	);
}

/** The area a wiki page belongs to (itself for an area). */
function inception_kit_wiki_area( $post ) {
	$post      = get_post( $post );
	$ancestors = get_post_ancestors( $post );
	return $ancestors ? get_post( end( $ancestors ) ) : $post;
}

/**
 * Every wiki page in reading order: each area, then its pages depth-first.
 * get_pages() with child_of returns a subtree already in that order.
 */
function inception_kit_wiki_sequence() {
	static $sequence = null;
	if ( null === $sequence ) {
		$sequence = array();
		foreach ( inception_kit_wiki_areas() as $area ) {
			$sequence[] = $area;
			$children   = get_pages(
				array(
					'post_type'   => 'docs',
					'child_of'    => $area->ID,
					'sort_column' => 'menu_order,post_title',
				)
			);
			foreach ( $children as $child ) {
				$sequence[] = $child;
			}
		}
	}
	return $sequence;
}

/** array( previous, next ) around a wiki page, across area boundaries. */
function inception_kit_wiki_neighbours( $post ) {
	$post = get_post( $post );
	$ids  = wp_list_pluck( inception_kit_wiki_sequence(), 'ID' );
	$at   = array_search( $post->ID, $ids, true );
	if ( false === $at ) {
		return array( null, null );
	}
	$sequence = inception_kit_wiki_sequence();
	return array( $sequence[ $at - 1 ] ?? null, $sequence[ $at + 1 ] ?? null );
}

/** Which dream-level tint (1..3) an area wears: they cycle in seeded order. */
function inception_kit_wiki_tint( $area ) {
	$ids = wp_list_pluck( inception_kit_wiki_areas(), 'ID' );
	$at  = array_search( get_post( $area )->ID, $ids, true );
	return false === $at ? 1 : ( $at % 3 ) + 1;
}

/**
 * Pages the wiki replaced, the journal renamed to blog and weDocs' own /docs/
 * keep answering at their old address with a 301: "page:" names a page, the
 * rest a wiki page. Priority 1: before redirect_canonical(), whose slug
 * guessing would send /architecture/ to the area rather than the page.
 */
function inception_kit_moved_redirect() {
	if ( ! is_404() ) {
		return;
	}
	$path  = trim( (string) wp_parse_url( wp_unslash( $_SERVER['REQUEST_URI'] ?? '' ), PHP_URL_PATH ), '/' ); // phpcs:ignore WordPress.Security.ValidatedSanitizedInput -- compared to a fixed list only
	$moved = array(
		'journal'         => 'page:blog',
		'docs'            => 'page:wiki',
		'user-guide'      => 'user-guide',
		'developer-guide' => 'developer-guide',
		'architecture'    => 'architecture-overview',
		'benchmarks'      => 'benchmarks',
		'defense-qa'      => 'defense-qa',
	);
	if ( ! array_key_exists( $path, $moved ) ) {
		return;
	}
	if ( 0 === strpos( $moved[ $path ], 'page:' ) ) {
		$page   = get_page_by_path( substr( $moved[ $path ], 5 ) );
		$target = $page && 'publish' === $page->post_status ? get_permalink( $page ) : '';
	} else {
		$doc    = inception_kit_wiki_doc( $moved[ $path ] );
		$target = $doc ? get_permalink( $doc ) : '';
	}
	if ( $target ) {
		wp_safe_redirect( $target, 301 );
		exit;
	}
}
add_action( 'template_redirect', 'inception_kit_moved_redirect', 1 );
