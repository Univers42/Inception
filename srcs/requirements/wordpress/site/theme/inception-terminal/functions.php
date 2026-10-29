<?php
/**
 * inception-terminal: the blog and the wiki behind the Inception landing.
 *
 * One design system with the landing (bonus/staticsite): both load the same
 * srcs/design/tokens.css and fonts, which the image copies to assets/design/.
 * The slug keeps its old name so no install has to switch themes.
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

define( 'INCEPTION_TERMINAL_VERSION', '3.0.0' );

function inception_terminal_setup() {
	add_theme_support( 'title-tag' );
	add_theme_support( 'automatic-feed-links' );
	add_theme_support( 'responsive-embeds' );
	add_theme_support( 'html5', array( 'search-form', 'comment-form', 'comment-list', 'gallery', 'caption', 'style', 'script', 'navigation-widgets' ) );
	register_nav_menus( array( 'primary' => 'Primary Menu' ) );

	add_theme_support( 'editor-styles' );
	add_editor_style( array( 'assets/design/tokens.css', 'assets/editor.css' ) );
	add_theme_support(
		'editor-color-palette',
		array(
			array( 'name' => 'Ink',         'slug' => 'ink',     'color' => '#06080c' ),
			array( 'name' => 'Fog',         'slug' => 'fog',     'color' => '#e9eef5' ),
			array( 'name' => 'Steel',       'slug' => 'steel',   'color' => '#8db4d8' ),
			array( 'name' => 'Teal',        'slug' => 'teal',    'color' => '#5cc2b4' ),
			array( 'name' => 'Limbo sand',  'slug' => 'sand',    'color' => '#cdb48e' ),
			array( 'name' => 'Totem amber', 'slug' => 'amber',   'color' => '#f0b45a' ),
			array( 'name' => 'Rust',        'slug' => 'rust',    'color' => '#f07a6a' ),
		)
	);
}
add_action( 'after_setup_theme', 'inception_terminal_setup' );

/**
 * ?ver= is the file's content hash. nginx serves these files as immutable for
 * 30 days, so with a fixed version number a visitor who had them kept the old
 * CSS and JS after every deploy, reload or not (audit, 2026-10-28).
 */
function inception_terminal_version( $relative ) {
	$path = get_template_directory() . '/' . $relative;
	return is_readable( $path ) ? substr( md5_file( $path ), 0, 12 ) : INCEPTION_TERMINAL_VERSION;
}

function inception_terminal_assets() {
	$uri = get_template_directory_uri();
	wp_enqueue_style( 'inception-tokens', $uri . '/assets/design/tokens.css', array(), inception_terminal_version( 'assets/design/tokens.css' ) );
	wp_enqueue_style( 'inception-terminal', $uri . '/assets/theme.css', array( 'inception-tokens' ), inception_terminal_version( 'assets/theme.css' ) );
	wp_enqueue_script(
		'inception-terminal',
		$uri . '/assets/theme.js',
		array(),
		inception_terminal_version( 'assets/theme.js' ),
		array(
			'in_footer' => true,
			'strategy'  => 'defer',
		)
	);
}
add_action( 'wp_enqueue_scripts', 'inception_terminal_assets' );

/** The two display faces render the first screen: fetch them with the HTML. */
function inception_terminal_preload_fonts() {
	$fonts = get_template_directory_uri() . '/assets/design/fonts/';
	foreach ( array( 'instrument-serif-400.woff2', 'geist-variable.woff2' ) as $font ) {
		printf( '<link rel="preload" href="%s" as="font" type="font/woff2" crossorigin>' . "\n", esc_url( $fonts . $font ) );
	}
}
add_action( 'wp_head', 'inception_terminal_preload_fonts', 1 );

function inception_terminal_excerpt_length() {
	return 30;
}
add_filter( 'excerpt_length', 'inception_terminal_excerpt_length' );

function inception_terminal_excerpt_more() {
	return '…';
}
add_filter( 'excerpt_more', 'inception_terminal_excerpt_more' );

function inception_terminal_reading_minutes( $post = null ) {
	return function_exists( 'inception_kit_reading_time' ) ? (int) inception_kit_reading_time( $post ) : 0;
}

/**
 * Date · reading time · first category, as one muted line. Inside a card that
 * is itself a link, the category must not be one: a nested <a> makes the
 * parser close the card's link early, leaving it empty and its text outside.
 */
function inception_terminal_post_meta( $post = null, $link_category = true ) {
	$post  = get_post( $post );
	$parts = array( '<time datetime="' . esc_attr( get_the_date( 'c', $post ) ) . '">' . esc_html( get_the_date( 'j M Y', $post ) ) . '</time>' );
	$min   = inception_terminal_reading_minutes( $post );
	if ( $min ) {
		$parts[] = '<span>' . $min . ' min read</span>';
	}
	$cats = get_the_category( $post->ID );
	if ( $cats ) {
		$parts[] = $link_category
			? '<a href="' . esc_url( get_category_link( $cats[0] ) ) . '">' . esc_html( $cats[0]->name ) . '</a>'
			: '<span>' . esc_html( $cats[0]->name ) . '</span>';
	}
	// Each part after the first carries its separator, so a wrapped line
	// starts with "· category" instead of ending on a lone dot.
	$first = array_shift( $parts );
	$rest  = '';
	foreach ( $parts as $part ) {
		$rest .= '<span class="meta-item"><span class="meta-sep" aria-hidden="true">·</span>' . $part . '</span>';
	}
	echo '<p class="meta">' . $first . $rest . '</p>'; // phpcs:ignore WordPress.Security.EscapeOutput -- parts escaped above
}

/** The totem: the brand mark the landing spins. */
function inception_terminal_totem( $size = 22 ) {
	printf(
		'<svg class="totem" width="%1$d" height="%1$d" viewBox="0 0 32 32" fill="none" aria-hidden="true" focusable="false"><path d="M16 2.5v6" stroke="#f0b45a" stroke-width="2.2" stroke-linecap="round"/><path d="M4.5 11.5C9 7.8 23 7.8 27.5 11.5L16.4 29.2a.5.5 0 0 1-.8 0z" fill="#e9a63f"/><path d="M6.5 12.6c5.6 2.3 13.4 2.3 19 0" stroke="#1a1206" stroke-opacity=".35" stroke-width="1.2"/></svg>',
		(int) $size
	);
}

function inception_terminal_fallback_menu() {
	echo '<ul class="menu">';
	foreach ( array( 'Blog' => '/blog/', 'Wiki' => '/wiki/', 'Lab' => '/lab/' ) as $label => $path ) {
		echo '<li><a href="' . esc_url( home_url( $path ) ) . '">' . esc_html( $label ) . '</a></li>';
	}
	echo '</ul>';
}

/**
 * WordPress marks the posts page current_page_parent on every view that is
 * not a page, so a wiki page, a search and the 404 all lit up "Blog". The
 * menu says where the reader is: Blog for posts and their archives, Wiki for
 * the wiki's pages.
 */
function inception_terminal_nav_current( $classes, $item ) {
	if ( 'post_type' !== $item->type ) {
		return $classes;
	}
	$id = (int) $item->object_id;
	if ( (int) get_option( 'page_for_posts' ) === $id && ! ( is_home() || is_singular( 'post' ) || is_archive() ) ) {
		$classes = array_diff( $classes, array( 'current_page_parent' ) );
	}
	$wiki = get_page_by_path( 'wiki' );
	if ( $wiki && $wiki->ID === $id && is_singular( 'docs' ) ) {
		$classes[] = 'current_page_parent';
	}
	return $classes;
}
add_filter( 'nav_menu_css_class', 'inception_terminal_nav_current', 10, 2 );

/**
 * WordPress gives aria-current only to the exact page, so on a post "Blog"
 * looked current but said nothing to a screen reader. Runs after the class
 * filter above, so it follows the same Blog/Wiki decision.
 */
function inception_terminal_nav_aria_current( $atts, $item ) {
	if ( empty( $atts['aria-current'] ) && in_array( 'current_page_parent', (array) $item->classes, true ) ) {
		$atts['aria-current'] = 'true';
	}
	return $atts;
}
add_filter( 'nav_menu_link_attributes', 'inception_terminal_nav_aria_current', 10, 2 );

/**
 * wp-login.php is the maintainers' door: it wears the site's tokens and the
 * totem, says that there is no public sign-up, and links home.
 */
function inception_terminal_login_assets() {
	$uri = get_template_directory_uri();
	wp_enqueue_style( 'inception-tokens', $uri . '/assets/design/tokens.css', array(), inception_terminal_version( 'assets/design/tokens.css' ) );
	wp_enqueue_style( 'inception-login', $uri . '/assets/login.css', array( 'login', 'inception-tokens' ), inception_terminal_version( 'assets/login.css' ) );
}
add_action( 'login_enqueue_scripts', 'inception_terminal_login_assets' );

/** Core's sign-in markup has no landmark at all: wrap the form in <main>. */
function inception_terminal_login_main_open() {
	echo '<main id="login-main">';
}
add_action( 'login_header', 'inception_terminal_login_main_open' );

function inception_terminal_login_main_close() {
	echo '</main>';
}
add_action( 'login_footer', 'inception_terminal_login_main_close', 99 );

function inception_terminal_login_url() {
	return home_url( '/' );
}
add_filter( 'login_headerurl', 'inception_terminal_login_url' );

function inception_terminal_login_title() {
	return 'Inception';
}
add_filter( 'login_headertext', 'inception_terminal_login_title' );

function inception_terminal_login_note( $message ) {
	return $message . '<p class="inception-login-note">Maintainers sign in here to write the blog and the wiki. There is no public sign-up.</p>';
}
add_filter( 'login_message', 'inception_terminal_login_note' );
add_filter( 'login_display_language_dropdown', '__return_false' );

/**
 * Relevanssi cuts excerpts from the page's text, where list items ran into
 * each other ("nginx waits for wordpress wordpress waits for mariadb").
 */
function inception_terminal_excerpt_items( $content ) {
	return preg_replace( '#(?<![.!?:;])\s*</li>#', '. </li>', $content );
}
add_filter( 'relevanssi_pre_excerpt_content', 'inception_terminal_excerpt_items' );

/** Search results say where they come from: the wiki, the blog or a page. */
function inception_terminal_kind( $post = null ) {
	$type = get_post_type( $post );
	return 'docs' === $type ? 'Wiki' : ( 'post' === $type ? 'Blog' : 'Page' );
}
