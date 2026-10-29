<?php
/**
 * wp-admin's dashboard for the maintainer: "Write" puts the blog and the wiki
 * one click away, and "The network" asks every service of the stack, from
 * inside the wordpress container, whether it answers on the Docker network
 * the pages themselves travel through.
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

function inception_kit_dashboard() {
	if ( current_user_can( 'edit_posts' ) ) {
		wp_add_dashboard_widget( 'inception_write', 'Write for Inception', 'inception_kit_dashboard_write', null, null, 'normal', 'high' );
	}
	if ( current_user_can( 'manage_options' ) ) {
		wp_add_dashboard_widget( 'inception_network', 'The network', 'inception_kit_dashboard_network', null, null, 'normal', 'high' );
	}
	// "WordPress Events and News" fetches wordpress.org on every dashboard load.
	remove_meta_box( 'dashboard_primary', 'dashboard', 'side' );
	remove_action( 'welcome_panel', 'wp_welcome_panel' );
}
add_action( 'wp_dashboard_setup', 'inception_kit_dashboard' );

// Vendor upsell banners. weDocs' is downloaded from its own server once a day
// (wp_remote_get, 15 s timeout) on the first admin page: answering its cache
// key with an empty list ends both the banner and the third-party request.
if ( ! defined( 'WP_REDIS_DISABLE_BANNERS' ) ) {
	define( 'WP_REDIS_DISABLE_BANNERS', true );
}
function inception_kit_no_promotions() {
	if ( defined( 'WEDOCS_PROMO_KEY' ) ) {
		add_filter( 'pre_transient_' . WEDOCS_PROMO_KEY, '__return_empty_array' );
	}
}
add_action( 'plugins_loaded', 'inception_kit_no_promotions' );

function inception_kit_dashboard_write() {
	$posts = (int) wp_count_posts( 'post' )->publish;
	$docs  = (int) wp_count_posts( 'docs' )->publish;
	$wiki  = get_page_by_path( 'wiki' );
	$links = array(
		'New post'          => admin_url( 'post-new.php' ),
		'New wiki page'     => admin_url( 'post-new.php?post_type=docs' ),
		'Arrange the wiki'  => admin_url( 'admin.php?page=wedocs' ),
		'Open the blog'     => get_permalink( (int) get_option( 'page_for_posts' ) ),
		'Open the wiki'     => $wiki ? get_permalink( $wiki ) : home_url( '/wiki/' ),
	);
	printf( '<p>%d posts on the blog, %d pages in the wiki.</p><p>', $posts, $docs );
	$first = true;
	foreach ( $links as $label => $url ) {
		printf( '<a class="button%s" href="%s" style="margin:0 6px 6px 0">%s</a>', $first ? ' button-primary' : '', esc_url( $url ), esc_html( $label ) );
		$first = false;
	}
	echo '</p><ul style="list-style:disc;padding-left:1.2em">';
	echo '<li>A wiki page goes under its area with <em>Page Attributes → Parent</em>; its place in the area is the <em>Order</em>.</li>';
	echo '<li>Pages cut from the repository\'s docs are refreshed by the next deploy, until you edit one here: from then on your version wins.</li>';
	echo '<li>Diagrams: insert the <em>Diagram (Mermaid)</em> pattern (Inception Kit) and write Mermaid; the page draws it.</li>';
	echo '</ul>';
}

/**
 * The stack's services by their Compose names. A TCP connect proves the name
 * resolves and something listens; the probes that can also ask a question
 * (MariaDB, Redis, FTP, HTTP) check that the right thing answered.
 */
function inception_kit_network_services() {
	return array(
		array( 'nginx', 'nginx', 443, 'tcp' ),
		array( 'MariaDB', 'mariadb', 3306, 'sql' ),
		array( 'Redis', 'redis', 6379, 'redis' ),
		array( 'Landing (staticsite)', 'staticsite', 8090, 'http' ),
		array( 'Adminer', 'adminer', 8080, 'http' ),
		array( 'FTP', 'ftp', 21, 'ftp' ),
		array( 'Lab web', 'web', 8080, 'http' ),
		array( 'Lab API', 'api', 3000, 'tcp' ),
	);
}

/**
 * array( answered, detail ) for one service.
 *
 * Caveat: half a second per probe. A service that is up but slower than that
 * reads as silent, and eight silent services hold the dashboard for 4 s.
 */
function inception_kit_probe( $host, $port, $kind ) {
	global $wpdb;
	if ( 'sql' === $kind ) {
		$version = $wpdb->get_var( 'SELECT VERSION()' );
		return array( (bool) $version, $version ? 'SELECT VERSION() → ' . $version : 'no answer to SELECT VERSION()' );
	}
	$errno  = 0;
	$errstr = '';
	$socket = @fsockopen( $host, $port, $errno, $errstr, 0.5 ); // phpcs:ignore WordPress.PHP.NoSilencedErrors -- a down service is an answer, not a warning
	if ( ! $socket ) {
		return array( false, $errstr ? $errstr : 'no answer' );
	}
	stream_set_timeout( $socket, 0, 500000 );
	$detail = 'accepts connections';
	if ( 'redis' === $kind ) {
		fwrite( $socket, "PING\r\n" );
		$detail = trim( (string) fgets( $socket ) );
	} elseif ( 'ftp' === $kind ) {
		$detail = trim( (string) fgets( $socket ) );
	} elseif ( 'http' === $kind ) {
		fwrite( $socket, "HEAD / HTTP/1.0\r\nHost: {$host}\r\n\r\n" );
		$detail = trim( (string) fgets( $socket ) );
	}
	fclose( $socket );
	return array( true, '' === $detail ? 'connected, no greeting' : $detail );
}

function inception_kit_dashboard_network() {
	echo '<table class="widefat striped"><thead><tr><th>Service</th><th>Address</th><th>Answer</th><th>ms</th></tr></thead><tbody>';
	foreach ( inception_kit_network_services() as $service ) {
		list( $label, $host, $port, $kind ) = $service;
		$start                     = microtime( true );
		list( $answered, $detail ) = inception_kit_probe( $host, $port, $kind );
		printf(
			'<tr><td>%s %s</td><td><code>%s:%d</code></td><td>%s</td><td>%s</td></tr>',
			$answered ? '<span style="color:#00a32a" aria-hidden="true">●</span>' : '<span style="color:#d63638" aria-hidden="true">●</span>',
			esc_html( $label ),
			esc_html( $host ),
			(int) $port,
			esc_html( ( $answered ? '' : 'down: ' ) . $detail ),
			$answered ? (int) round( ( microtime( true ) - $start ) * 1000 ) : '–'
		);
	}
	echo '</tbody></table><p class="description">Asked from inside the wordpress container, by Compose service name, on every load of this page.</p>';
}
