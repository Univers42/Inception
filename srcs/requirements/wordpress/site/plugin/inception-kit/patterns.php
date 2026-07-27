<?php
/**
 * Inception Kit — block-editor integration.
 *
 * Makes the terminal components discoverable inside wp-admin: every
 * shortcode is available as an insertable Block Pattern (inserter →
 * Patterns → "Inception Kit"), so pages can be written entirely from
 * the WordPress interface without memorising any syntax.
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

/** "Inception Kit" category at the top of the pattern browser. */
function inception_kit_pattern_category() {
	if ( function_exists( 'register_block_pattern_category' ) ) {
		register_block_pattern_category( 'inception', array( 'label' => 'Inception Kit' ) );
	}
}
add_action( 'init', 'inception_kit_pattern_category', 9 );

/** One insertable pattern per component, pre-filled with an example. */
function inception_kit_register_patterns() {
	if ( ! function_exists( 'register_block_pattern' ) ) {
		return;
	}

	$patterns = array(
		'command'         => array(
			'title'       => 'Command (copyable)',
			'description' => 'A prompt line with a copy-to-clipboard button.',
			'content'     => "<!-- wp:shortcode -->\n[cmd]make up[/cmd]\n<!-- /wp:shortcode -->",
		),
		'command-output'  => array(
			'title'       => 'Command with output',
			'description' => 'A copyable command followed by its terminal output.',
			'content'     => "<!-- wp:shortcode -->\n[cmd]make status[/cmd]\n[out]NAME        STATUS\nnginx       Up (healthy)\nwordpress   Up (healthy)\nmariadb     Up (healthy)[/out]\n<!-- /wp:shortcode -->",
		),
		'terminal-window' => array(
			'title'       => 'Terminal window',
			'description' => 'A framed terminal window (traffic lights + title bar).',
			'content'     => "<!-- wp:shortcode -->\n[term_window title=\"dlesieur@inception:~\"]\n[cmd]echo hello world[/cmd]\n[out]hello world[/out]\n[/term_window]\n<!-- /wp:shortcode -->",
		),
		'callout-info'    => array(
			'title'       => 'Callout — info',
			'description' => 'Cyan information box.',
			'content'     => "<!-- wp:shortcode -->\n[callout type=\"info\" title=\"note\"]Something worth knowing.[/callout]\n<!-- /wp:shortcode -->",
		),
		'callout-ok'      => array(
			'title'       => 'Callout — success',
			'description' => 'Green success/lesson box.',
			'content'     => "<!-- wp:shortcode -->\n[callout type=\"ok\" title=\"lesson\"]It works — and here is why.[/callout]\n<!-- /wp:shortcode -->",
		),
		'callout-warn'    => array(
			'title'       => 'Callout — warning',
			'description' => 'Amber warning box.',
			'content'     => "<!-- wp:shortcode -->\n[callout type=\"warn\" title=\"careful\"]This has sharp edges.[/callout]\n<!-- /wp:shortcode -->",
		),
		'stat-tiles'      => array(
			'title'       => 'Stat tiles',
			'description' => 'A grid of big numbers with labels (value|label;…).',
			'content'     => "<!-- wp:shortcode -->\n[stats]~13s|cold build;~7s|fresh boot;40/41|checks green[/stats]\n<!-- /wp:shortcode -->",
		),
		'architecture'    => array(
			'title'       => 'Architecture diagram',
			'description' => 'The three-container request-flow diagram.',
			'content'     => "<!-- wp:shortcode -->\n[arch]\n<!-- /wp:shortcode -->",
		),
		'inline-extras'   => array(
			'title'       => 'Inline: kbd + badge',
			'description' => 'Keyboard keys and coloured badges inside a paragraph.',
			'content'     => "<!-- wp:paragraph -->\n<p>Press [kbd]Ctrl+C[/kbd] to stop — status: [badge color=\"green\"]healthy[/badge]</p>\n<!-- /wp:paragraph -->",
		),
	);

	foreach ( $patterns as $slug => $p ) {
		register_block_pattern(
			'inception/' . $slug,
			array(
				'title'       => $p['title'],
				'description' => $p['description'],
				'content'     => $p['content'],
				'categories'  => array( 'inception' ),
				'keywords'    => array( 'terminal', 'inception', 'shell' ),
			)
		);
	}
}
add_action( 'init', 'inception_kit_register_patterns' );
