<?php
get_header();
while ( have_posts() ) :
	the_post();
	?>
<article <?php post_class( 'entry shell' ); ?>>
	<header class="entry-head">
		<h1 class="display entry-title"><?php the_title(); ?></h1>
	</header>
	<div class="prose">
		<?php the_content(); ?>
	</div>
	<?php
	if ( comments_open() || get_comments_number() ) {
		comments_template();
	}
	?>
</article>
	<?php
endwhile;
get_footer();
