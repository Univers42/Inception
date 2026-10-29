<!doctype html>
<html <?php language_attributes(); ?>>
<head>
	<meta charset="<?php bloginfo( 'charset' ); ?>">
	<meta name="viewport" content="width=device-width, initial-scale=1">
	<meta name="color-scheme" content="light dark">
	<script>document.documentElement.classList.add('js')</script>
	<?php wp_head(); ?>
</head>
<body <?php body_class(); ?>>
<?php wp_body_open(); ?>
<a class="skip-link" href="#main">Skip to content</a>

<header class="site-header">
	<div class="site-header-bar glass">
		<a class="brand" href="<?php echo esc_url( home_url( '/' ) ); ?>">
			<?php inception_terminal_totem(); ?>
			<span>inception</span>
		</a>
		<nav class="site-nav" aria-label="Primary">
			<?php
			wp_nav_menu(
				array(
					'theme_location' => 'primary',
					'container'      => false,
					'menu_class'     => 'menu',
					'depth'          => 1,
					'fallback_cb'    => 'inception_terminal_fallback_menu',
				)
			);
			?>
		</nav>
		<div class="header-search"><?php get_search_form(); ?></div>
		<details class="nav-mobile">
			<summary aria-label="Menu"><span class="burger" aria-hidden="true"></span></summary>
			<div class="nav-mobile-panel glass">
				<?php
				wp_nav_menu(
					array(
						'theme_location' => 'primary',
						'container'      => false,
						'menu_class'     => 'menu',
						'depth'          => 1,
						'fallback_cb'    => 'inception_terminal_fallback_menu',
					)
				);
				get_search_form();
				?>
			</div>
		</details>
	</div>
	<div class="reading-progress" aria-hidden="true"><span></span></div>
</header>

<main id="main" class="site-main">
