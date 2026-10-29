<?php
/**
 * The sign-in surface of a site with one door, maintainers only and no mail
 * server. nginx carries the other half (wp-login.php POSTs rate-limited,
 * xmlrpc.php refused, security headers): srcs/requirements/nginx/conf/nginx.conf.
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

/**
 * One message for every failed sign-in. WordPress says "unknown username" or
 * "incorrect password", which tells a guesser which accounts exist.
 */
function inception_kit_login_error() {
	return '<strong>Sign-in failed.</strong> Check the email or username and the password.';
}
add_filter( 'login_errors', 'inception_kit_login_error' );

/**
 * No reset by mail: the stack has no mail server, so the form could only
 * fail. The administrator's password is line 1 of secrets/credentials.txt
 * (born2root writes it from its own secrets file) and the entrypoint applies
 * it again on every boot: that file is the reset.
 */
add_filter( 'allow_password_reset', '__return_false' );
add_filter( 'lost_password_html_link', '__return_empty_string' );

/**
 * Anonymous visitors cannot list the accounts. The theme names no author, so
 * /wp-json/wp/v2/users, ?author=N and /author/<login>/ served nothing but the
 * login names a password guesser needs.
 */
function inception_kit_hide_users( $endpoints ) {
	if ( is_user_logged_in() ) {
		return $endpoints;
	}
	foreach ( array_keys( $endpoints ) as $route ) {
		if ( 0 === strpos( $route, '/wp/v2/users' ) ) {
			unset( $endpoints[ $route ] );
		}
	}
	return $endpoints;
}
add_filter( 'rest_endpoints', 'inception_kit_hide_users' );

/** Priority 0: before redirect_canonical() turns ?author=1 into /author/<login>/. */
function inception_kit_no_author_pages() {
	if ( ! is_user_logged_in() && is_author() ) {
		global $wp_query;
		$wp_query->set_404();
		status_header( 404 );
		nocache_headers();
	}
}
add_action( 'template_redirect', 'inception_kit_no_author_pages', 0 );

/**
 * The administrator's address comes from the secrets (WP_ADMIN_EMAIL, synced
 * by the entrypoint), so the six-monthly "is this still your email?" screen
 * between sign-in and the dashboard would only ask about a file.
 */
add_filter( 'admin_email_check_interval', '__return_zero' );

function inception_kit_no_user_sitemap( $provider, $name ) {
	return 'users' === $name ? false : $provider;
}
add_filter( 'wp_sitemaps_add_provider', 'inception_kit_no_user_sitemap', 10, 2 );

/**
 * Core's emoji loader names s.w.org as its image source and swaps in images
 * from there when a browser fails its rendering test: a request to another
 * origin, which this site never makes (tests/site.sh S03). The RSD link only
 * advertises XML-RPC, which nginx refuses.
 */
function inception_kit_no_third_party_head() {
	remove_action( 'wp_head', 'print_emoji_detection_script', 7 );
	remove_action( 'embed_head', 'print_emoji_detection_script' );
	remove_action( 'admin_print_scripts', 'print_emoji_detection_script' );
	remove_action( 'wp_enqueue_scripts', 'wp_enqueue_emoji_styles' );
	remove_action( 'enqueue_embed_scripts', 'wp_enqueue_emoji_styles' );
	remove_action( 'wp_print_styles', 'print_emoji_styles' );
	remove_action( 'admin_print_styles', 'print_emoji_styles' );
	remove_filter( 'the_content_feed', 'wp_staticize_emoji' );
	remove_filter( 'comment_text_rss', 'wp_staticize_emoji' );
	remove_filter( 'wp_mail', 'wp_staticize_emoji_for_email' );
	remove_action( 'wp_head', 'rsd_link' );
}
add_action( 'init', 'inception_kit_no_third_party_head' );
add_filter( 'emoji_svg_url', '__return_false' );
