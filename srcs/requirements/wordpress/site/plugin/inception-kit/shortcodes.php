<?php

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

function inception_kit_no_texturize( $shortcodes ) {
	return array_merge( $shortcodes, array( 'cmd', 'out', 'term_window', 'arch' ) );
}
add_filter( 'no_texturize_shortcodes', 'inception_kit_no_texturize' );

function inception_kit_clean_body( $content ) {
	return trim( preg_replace( '#<br\s*/?>|</?p>#i', '', (string) $content ) );
}

/**
 * wpautop runs before shortcodes, so it leaves <p> and <br /> around the kit's
 * blocks: empty bands inside a terminal window and a <div> inside a <p>. A
 * window holds only [cmd] and [out], so its body loses them before rendering,
 * and the blocks lose the paragraph wrapped around them afterwards.
 */
function inception_kit_unwrap_blocks( $content ) {
	return preg_replace(
		array( '#<p>\s*(<(?:div|aside|pre|dl)\b[^>]*\bclass="ik-)#', '#(</(?:div|aside|pre|dl)>)\s*</p>#', '#<p>\s*</p>#' ),
		array( '$1', '$1', '' ),
		$content
	);
}
add_filter( 'the_content', 'inception_kit_unwrap_blocks', 12 );

/** [term_window title="dlesieur@inception:~"] */
function inception_kit_sc_term_window( $atts, $content = '' ) {
	$atts = shortcode_atts( array( 'title' => 'dlesieur@inception:~' ), $atts, 'term_window' );
	return inception_kit_window( $atts['title'], do_shortcode( inception_kit_clean_body( $content ) ) );
}
add_shortcode( 'term_window', 'inception_kit_sc_term_window' );

/**
 * [cmd path="~"]make up[/cmd] — copyable command line. The button sits beside
 * the scroller, not in it: inside, a long command ran under the button.
 */
function inception_kit_sc_cmd( $atts, $content = '' ) {
	$atts    = shortcode_atts( array( 'path' => '~' ), $atts, 'cmd' );
	$command = trim( wp_strip_all_tags( inception_kit_clean_body( $content ) ) );
	$command = str_replace( array( '&#8211;', '&#8212;', '–', '—' ), '--', $command );
	return sprintf(
		'<div class="ik-cmd"><div class="ik-cmd-scroll">%1$s<code class="ik-cmd-text">%2$s</code></div><button type="button" class="ik-copy" data-copy="%3$s" aria-label="Copy command">%4$s%5$s</button></div>',
		inception_kit_prompt( $atts['path'] ),
		esc_html( $command ),
		esc_attr( $command ),
		inception_kit_icon( 'copy', 14 ),
		inception_kit_icon( 'check', 14 )
	);
}
add_shortcode( 'cmd', 'inception_kit_sc_cmd' );

/** [out]✔ mariadb healthy[/out] — output block under a command */
function inception_kit_sc_out( $atts, $content = '' ) {
	return '<pre class="ik-out">' . esc_html( inception_kit_clean_body( $content ) ) . '</pre>';
}
add_shortcode( 'out', 'inception_kit_sc_out' );

/** [callout type="info" title="note"] … [/callout] */
function inception_kit_sc_callout( $atts, $content = '' ) {
	$atts  = shortcode_atts(
		array(
			'type'  => 'info',
			'title' => '',
		),
		$atts,
		'callout'
	);
	$type  = in_array( $atts['type'], array( 'info', 'ok', 'warn', 'err' ), true ) ? $atts['type'] : 'info';
	$icons = array(
		'info' => 'terminal',
		'ok'   => 'check',
		'warn' => 'shield',
		'err'  => 'shield',
	);
	$label = $atts['title'] ? $atts['title'] : strtoupper( $type );
	return sprintf(
		'<aside class="ik-callout ik-callout-%1$s"><div class="ik-callout-head">%2$s<span>%3$s</span></div><div class="ik-callout-body">%4$s</div></aside>',
		esc_attr( $type ),
		inception_kit_icon( $icons[ $type ], 15 ),
		esc_html( $label ),
		do_shortcode( wpautop( $content ) )
	);
}
add_shortcode( 'callout', 'inception_kit_sc_callout' );

/**
 * [stats]13 s|true cold build;7 s|fresh boot;40/41|checks green[/stats]
 * A <dl>: each figure is a term and its value (role="list" with no items was
 * an axe critical). The label comes first in the markup; CSS shows the value
 * on top.
 */
function inception_kit_sc_stats( $atts, $content = '' ) {
	$items = array_filter( array_map( 'trim', explode( ';', wp_strip_all_tags( $content ) ) ) );
	$html  = '';
	foreach ( $items as $item ) {
		$parts = array_map( 'trim', explode( '|', $item, 2 ) );
		$value = isset( $parts[0] ) ? $parts[0] : '';
		$label = isset( $parts[1] ) ? $parts[1] : '';
		$html .= sprintf(
			'<div class="ik-stat"><dt class="ik-stat-label">%s</dt><dd class="ik-stat-value">%s</dd></div>',
			esc_html( $label ),
			esc_html( $value )
		);
	}
	return '<dl class="ik-stats">' . $html . '</dl>';
}
add_shortcode( 'stats', 'inception_kit_sc_stats' );

/** [arch] — the request-flow diagram, drawn by Mermaid (the theme loads it) */
function inception_kit_sc_arch( $atts = array() ) {
	$diagram = <<<'MERMAID'
flowchart TB
    accTitle: The request path
    accDescr: A client reaches nginx over TLS 1.2 or 1.3 on port 443, the only door. nginx passes PHP to WordPress, php-fpm 8.4 with no web server, over FastCGI on port 9000. WordPress reaches MariaDB 11.4 over TCP on port 3306, its data on a named volume under /home/login/data.
    client([Client]) -->|"TLS 1.2 / 1.3 on :443, the only door"| nginx["nginx :443"]
    nginx -->|"FastCGI :9000"| wordpress["wordpress<br/>php-fpm 8.4, no web server"]
    wordpress -->|"TCP :3306"| mariadb[("mariadb 11.4<br/>named volume under /home/login/data")]
MERMAID;
	return inception_kit_window(
		'inception — bridge network',
		'<pre class="ik-arch mermaid">' . esc_html( $diagram ) . '</pre>',
		'ik-window-arch'
	);
}
add_shortcode( 'arch', 'inception_kit_sc_arch' );

/** [kbd]Ctrl+C[/kbd] */
function inception_kit_sc_kbd( $atts, $content = '' ) {
	return '<kbd class="ik-kbd">' . esc_html( $content ) . '</kbd>';
}
add_shortcode( 'kbd', 'inception_kit_sc_kbd' );

/** [badge color="green|amber|cyan|red"]text[/badge] */
function inception_kit_sc_badge( $atts, $content = '' ) {
	$atts  = shortcode_atts( array( 'color' => 'green' ), $atts, 'badge' );
	$color = in_array( $atts['color'], array( 'green', 'amber', 'cyan', 'red' ), true ) ? $atts['color'] : 'green';
	return sprintf( '<span class="ik-badge ik-badge-%s">%s</span>', esc_attr( $color ), esc_html( $content ) );
}
add_shortcode( 'badge', 'inception_kit_sc_badge' );
