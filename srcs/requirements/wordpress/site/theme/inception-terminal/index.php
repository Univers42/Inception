<?php
get_header();
$inception_title = is_home() ? 'Notes from the build.' : get_the_archive_title();
$inception_sub   = is_home() ? 'The bugs, the measurements and the fixes behind the stack, one post at a time.' : get_the_archive_description();
?>
<section class="page-hero shell">
	<p class="eyebrow"><?php echo is_home() ? 'The journal' : 'Archive'; ?></p>
	<h1 class="display"><?php echo wp_kses_post( $inception_title ); ?></h1>
	<?php if ( $inception_sub ) : ?>
		<p class="lede"><?php echo wp_kses_post( wp_strip_all_tags( $inception_sub ) ); ?></p>
	<?php endif; ?>
</section>

<section class="shell">
	<?php if ( have_posts() ) : ?>
		<ol class="post-grid">
			<?php
			$inception_i = 0;
			while ( have_posts() ) :
				the_post();
				$inception_lead = 0 === $inception_i++ && ! is_paged();
				?>
				<li class="post-card reveal<?php echo $inception_lead ? ' post-card-lead' : ''; ?>">
					<?php inception_terminal_post_meta( null, false ); ?>
					<h2 class="post-card-title"><a class="card-link" href="<?php the_permalink(); ?>"><?php the_title(); ?></a></h2>
					<p class="post-card-excerpt"><?php echo esc_html( get_the_excerpt() ); ?></p>
					<span class="more" aria-hidden="true">Read the post →</span>
				</li>
			<?php endwhile; ?>
		</ol>
		<?php
		the_posts_pagination(
			array(
				'prev_text' => '← Newer',
				'next_text' => 'Older →',
			)
		);
		?>
	<?php else : ?>
		<p class="empty">Nothing here yet. <a href="<?php echo esc_url( home_url( '/wiki/' ) ); ?>">The wiki</a> has the long version.</p>
	<?php endif; ?>
</section>
<?php
get_footer();
