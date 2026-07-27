<?php
/**
 * Plugin Name:       Inception Kit
 * Description:       Reusable terminal-styled components (shortcodes + helpers) powering the Inception documentation blog.
 * Version:           1.0.0
 * Author:            dlesieur
 * License:           MIT
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

define( 'INCEPTION_KIT_VERSION', '1.0.0' );
define( 'INCEPTION_KIT_URL', plugin_dir_url( __FILE__ ) );
define( 'INCEPTION_KIT_DIR', plugin_dir_path( __FILE__ ) );

require_once INCEPTION_KIT_DIR . 'shortcodes.php';

/**
 * Front-end assets for the kit components.
 */
function inception_kit_assets() {
	wp_enqueue_style(
		'inception-kit',
		INCEPTION_KIT_URL . 'assets/kit.css',
		array(),
		INCEPTION_KIT_VERSION
	);
	wp_enqueue_script(
		'inception-kit',
		INCEPTION_KIT_URL . 'assets/kit.js',
		array(),
		INCEPTION_KIT_VERSION,
		true
	);
}
add_action( 'wp_enqueue_scripts', 'inception_kit_assets' );

/* ──────────────────────────────────────────────────────────────────
 *  Public helper API — reused by the theme and the shortcodes.
 * ────────────────────────────────────────────────────────────────── */

/**
 * Estimated reading time of a post, in minutes (>= 1).
 */
function inception_kit_reading_time( $post = null ) {
	$post = get_post( $post );
	if ( ! $post ) {
		return 1;
	}
	$words = str_word_count( wp_strip_all_tags( $post->post_content ) );
	return max( 1, (int) ceil( $words / 220 ) );
}

/**
 * The shell-prompt fragment used across the site.
 * inception_kit_prompt( '~/docs' ) → dlesieur@inception:~/docs$
 */
function inception_kit_prompt( $path = '~' ) {
	return sprintf(
		'<span class="ik-prompt"><span class="ik-prompt-user">dlesieur@inception</span><span class="ik-prompt-sep">:</span><span class="ik-prompt-path">%s</span><span class="ik-prompt-sign">$</span></span>',
		esc_html( $path )
	);
}

/**
 * Small inline SVG icon set (single family, 1.5px stroke, currentColor).
 * Icons: book, wrench, layers, gauge, shield, terminal, copy, check,
 *        arrow-right, clock, tag.
 */
function inception_kit_icon( $name, $size = 16 ) {
	$paths = array(
		'book'     => '<path d="M3 4.5A1.5 1.5 0 0 1 4.5 3H8a2 2 0 0 1 2 2v14a2 2 0 0 0-2-2H3.5a.5.5 0 0 1-.5-.5v-12ZM21 4.5A1.5 1.5 0 0 0 19.5 3H16a2 2 0 0 0-2 2v14a2 2 0 0 1 2-2h4.5a.5.5 0 0 0 .5-.5v-12Z"/>',
		'wrench'   => '<path d="M14.7 6.3a4.5 4.5 0 0 0-6 5.6L3 17.6V21h3.4l5.7-5.7a4.5 4.5 0 0 0 5.6-6l-3 3-2.7-.3-.3-2.7 3-3Z"/>',
		'layers'   => '<path d="m12 3 9 5-9 5-9-5 9-5Z"/><path d="m3 13 9 5 9-5"/><path d="m3 17 9 5 9-5"/>',
		'gauge'    => '<path d="M12 15a2 2 0 1 0 0-4 2 2 0 0 0 0 4Z"/><path d="m13.4 11.6 3.6-3.6"/><path d="M20.5 15.5a9 9 0 1 0-17 0"/>',
		'shield'   => '<path d="M12 3 5 6v5c0 4.5 3 8.2 7 10 4-1.8 7-5.5 7-10V6l-7-3Z"/><path d="m9 12 2 2 4-4"/>',
		'terminal' => '<path d="m5 7 5 5-5 5"/><path d="M12 19h7"/>',
		'copy'     => '<rect x="9" y="9" width="11" height="11" rx="1.5"/><path d="M5 15H4.5A1.5 1.5 0 0 1 3 13.5v-9A1.5 1.5 0 0 1 4.5 3h9A1.5 1.5 0 0 1 15 4.5V5"/>',
		'check'    => '<path d="m4 12.5 5 5L20 6.5"/>',
		'arrow'    => '<path d="M4 12h16"/><path d="m13 5 7 7-7 7"/>',
		'clock'    => '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 3"/>',
		'tag'      => '<path d="m3 12 9-9h7.5a1.5 1.5 0 0 1 1.5 1.5V12l-9 9-9-9Z"/><circle cx="16" cy="8" r="1"/>',
	);
	if ( ! isset( $paths[ $name ] ) ) {
		return '';
	}
	return sprintf(
		'<svg class="ik-icon ik-icon-%1$s" width="%2$d" height="%2$d" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">%3$s</svg>',
		esc_attr( $name ),
		(int) $size,
		$paths[ $name ]
	);
}

/**
 * Terminal-window wrapper used by shortcodes and theme templates.
 */
function inception_kit_window( $title, $inner_html, $extra_class = '' ) {
	return sprintf(
		'<div class="ik-window %3$s"><div class="ik-window-bar"><span class="ik-dots" aria-hidden="true"><i class="ik-dot ik-dot-r"></i><i class="ik-dot ik-dot-y"></i><i class="ik-dot ik-dot-g"></i></span><span class="ik-window-title">%1$s</span></div><div class="ik-window-body">%2$s</div></div>',
		esc_html( $title ),
		$inner_html,
		esc_attr( $extra_class )
	);
}
