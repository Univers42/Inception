<?php
/**
 * Site header — terminal titlebar with traffic lights, prompt brand and nav.
 */
?>
<!doctype html>
<html <?php language_attributes(); ?>>
<head>
	<meta charset="<?php bloginfo( 'charset' ); ?>">
	<meta name="viewport" content="width=device-width, initial-scale=1">
	<meta name="color-scheme" content="dark">
	<?php wp_head(); ?>
</head>
<body <?php body_class(); ?>>
<?php wp_body_open(); ?>
<a class="skip-link" href="#main">Skip to content</a>

<header class="site-header" role="banner">
	<div class="shell">
		<div class="header-inner">
			<span class="ik-dots header-dots" aria-hidden="true"><i class="ik-dot ik-dot-r"></i><i class="ik-dot ik-dot-y"></i><i class="ik-dot ik-dot-g"></i></span>
			<a class="site-brand" href="<?php echo esc_url( home_url( '/' ) ); ?>" aria-label="<?php bloginfo( 'name' ); ?> — home">
				<span class="brand-user">dlesieur@inception</span><span class="brand-sep">:</span><span class="brand-path">~</span><span class="brand-sign">$</span><span class="brand-cursor" aria-hidden="true"></span>
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
		</div>
	</div>
</header>

<main id="main" class="site-main">
