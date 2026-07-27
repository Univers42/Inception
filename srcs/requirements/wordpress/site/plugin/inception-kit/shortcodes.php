<?php
/**
 * Inception Kit — reusable shortcodes.
 *
 * [term_window title="~/x"] … [/term_window]   terminal window frame
 * [cmd]make up[/cmd]                           prompt line with copy button
 * [out]✔ mariadb healthy[/out]                 command output line(s)
 * [callout type="info|ok|warn|err" title=""]   TUI callout box
 * [stats]13s|cold build;7s|fresh boot[/stats]  stat tile grid
 * [arch]                                       architecture diagram
 * [kbd]Ctrl+C[/kbd]                            key cap
 * [badge color="green"]v1.0[/badge]            inline badge
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

/**
 * Keep WordPress texturize away from terminal content: it would turn
 * `--allow-root` into `–allow-root` (and smart-quote everything),
 * corrupting both the display and the copy-to-clipboard text.
 */
function inception_kit_no_texturize( $shortcodes ) {
	return array_merge( $shortcodes, array( 'cmd', 'out', 'term_window', 'arch' ) );
}
add_filter( 'no_texturize_shortcodes', 'inception_kit_no_texturize' );

/**
 * Strip the artifacts wpautop injects into shortcode bodies before the
 * shortcode runs (<br />, stray <p> wrappers).
 */
function inception_kit_clean_body( $content ) {
	return trim( preg_replace( '#<br\s*/?>|</?p>#i', '', (string) $content ) );
}

/** [term_window title="dlesieur@inception:~"] */
function inception_kit_sc_term_window( $atts, $content = '' ) {
	$atts = shortcode_atts( array( 'title' => 'dlesieur@inception:~' ), $atts, 'term_window' );
	return inception_kit_window( $atts['title'], do_shortcode( $content ) );
}
add_shortcode( 'term_window', 'inception_kit_sc_term_window' );

/** [cmd path="~"]make up[/cmd] — copyable command line */
function inception_kit_sc_cmd( $atts, $content = '' ) {
	$atts    = shortcode_atts( array( 'path' => '~' ), $atts, 'cmd' );
	$command = trim( wp_strip_all_tags( inception_kit_clean_body( $content ) ) );
	$command = str_replace( array( '&#8211;', '&#8212;', '–', '—' ), '--', $command );
	return sprintf(
		'<div class="ik-cmd">%1$s<code class="ik-cmd-text">%2$s</code><button type="button" class="ik-copy" data-copy="%3$s" aria-label="Copy command">%4$s%5$s</button></div>',
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

/** [stats]13s|true cold build;7s|fresh boot;40/41|checks green[/stats] */
function inception_kit_sc_stats( $atts, $content = '' ) {
	$items = array_filter( array_map( 'trim', explode( ';', wp_strip_all_tags( $content ) ) ) );
	$html  = '';
	foreach ( $items as $item ) {
		$parts = array_map( 'trim', explode( '|', $item, 2 ) );
		$value = isset( $parts[0] ) ? $parts[0] : '';
		$label = isset( $parts[1] ) ? $parts[1] : '';
		$html .= sprintf(
			'<div class="ik-stat"><span class="ik-stat-value">%s</span><span class="ik-stat-label">%s</span></div>',
			esc_html( $value ),
			esc_html( $label )
		);
	}
	return '<div class="ik-stats" role="list">' . $html . '</div>';
}
add_shortcode( 'stats', 'inception_kit_sc_stats' );

/** [arch] — the request-flow diagram, styled */
function inception_kit_sc_arch( $atts = array() ) {
	$diagram = <<<'ASCII'
            ┌─────────────────┐
   client ──►  nginx  :443    │   TLS 1.2/1.3 · the only door
            └────────┬────────┘
                     │ fastcgi :9000
            ┌────────▼────────┐
            │ wordpress       │   php-fpm 8.4 · no web server
            └────────┬────────┘
                     │ tcp :3306
            ┌────────▼────────┐
            │ mariadb  11.4   │   named volume · /home/dlesieur/data
            └─────────────────┘
ASCII;
	return inception_kit_window(
		'inception — bridge network',
		'<pre class="ik-arch" aria-label="Architecture diagram: client to nginx on port 443, FastCGI to WordPress on port 9000, TCP to MariaDB on port 3306">' . esc_html( $diagram ) . '</pre>',
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
