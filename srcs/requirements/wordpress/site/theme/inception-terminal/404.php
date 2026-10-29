<?php
get_header();
?>
<section class="limbo shell">
	<div class="limbo-top" aria-hidden="true"><?php inception_terminal_totem( 72 ); ?></div>
	<p class="eyebrow">404 · Limbo</p>
	<h1 class="display">This page <em>never woke up.</em></h1>
	<p class="lede">The address leads nowhere in this dream. Search for it, or take the kick back to a level that exists.</p>
	<?php get_search_form( array( 'aria_label' => 'Search the site' ) ); ?>
	<p class="limbo-links">
		<a class="btn btn-primary" href="<?php echo esc_url( home_url( '/' ) ); ?>">Back to the surface</a>
		<a class="btn btn-ghost" href="<?php echo esc_url( home_url( '/wiki/' ) ); ?>">Open the wiki</a>
	</p>
</section>
<?php
get_footer();
