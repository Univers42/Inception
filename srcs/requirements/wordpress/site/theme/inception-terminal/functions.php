<?php
/**
 * Inception Terminal — theme setup.
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

define( 'INCEPTION_TERMINAL_VERSION', '1.0.0' );

function inception_terminal_setup() {
	add_theme_support( 'title-tag' );
	add_theme_support( 'automatic-feed-links' );
	add_theme_support( 'html5', array( 'search-form', 'gallery', 'caption', 'style', 'script', 'navigation-widgets' ) );
	register_nav_menus( array( 'primary' => 'Primary Menu' ) );
}
add_action( 'after_setup_theme', 'inception_terminal_setup' );

function inception_terminal_assets() {
	wp_enqueue_style(
		'inception-terminal',
		get_template_directory_uri() . '/assets/theme.css',
		array(),
		INCEPTION_TERMINAL_VERSION
	);
	wp_enqueue_script(
		'inception-terminal',
		get_template_directory_uri() . '/assets/theme.js',
		array(),
		INCEPTION_TERMINAL_VERSION,
		true
	);
}
add_action( 'wp_enqueue_scripts', 'inception_terminal_assets' );

/** Trim archive excerpts to terminal-card length. */
function inception_terminal_excerpt_length() {
	return 26;
}
add_filter( 'excerpt_length', 'inception_terminal_excerpt_length' );

function inception_terminal_excerpt_more() {
	return ' …';
}
add_filter( 'excerpt_more', 'inception_terminal_excerpt_more' );

/**
 * Post meta line: date + reading time (reading time comes from the
 * inception-kit plugin API when active — the theme reuses it).
 */
function inception_terminal_post_meta() {
	$meta = '<time datetime="' . esc_attr( get_the_date( 'c' ) ) . '">' . esc_html( get_the_date( 'Y-m-d' ) ) . '</time>';
	if ( function_exists( 'inception_kit_reading_time' ) ) {
		$icon  = function_exists( 'inception_kit_icon' ) ? inception_kit_icon( 'clock', 13 ) : '';
		$meta .= '<span class="meta-sep" aria-hidden="true">·</span><span>' . $icon . ' ' . (int) inception_kit_reading_time() . ' min read</span>';
	}
	echo '<p class="post-meta">' . $meta . '</p>'; // phpcs:ignore WordPress.Security.EscapeOutput
}

/** Fallback menu (before the seeded menu exists): list top-level pages. */
function inception_terminal_fallback_menu() {
	echo '<ul class="menu">';
	echo '<li><a href="' . esc_url( home_url( '/' ) ) . '">home</a></li>';
	$pages = get_pages( array( 'sort_column' => 'menu_order,post_title' ) );
	foreach ( $pages as $p ) {
		if ( (int) get_option( 'page_on_front' ) === $p->ID ) {
			continue;
		}
		echo '<li><a href="' . esc_url( get_permalink( $p ) ) . '">' . esc_html( strtolower( $p->post_title ) ) . '</a></li>';
	}
	echo '</ul>';
}
