<?php
/**
 * Journal archive (posts page) + generic fallback listing.
 */
get_header();
?>

<section class="archive">
	<div class="shell shell-narrow">
		<header class="archive-head">
			<h1 class="section-title"><span class="section-prompt">$</span> ls -lt ./journal</h1>
			<p class="archive-sub">Engineering journal — the build, the bugs, the numbers.</p>
		</header>

		<?php if ( have_posts() ) : ?>
			<div class="journal-list journal-list-full">
				<?php
				while ( have_posts() ) :
					the_post();
					?>
				<article <?php post_class( 'journal-card' ); ?>>
					<h2 class="journal-card-title">
						<a href="<?php the_permalink(); ?>"><span class="journal-card-prefix">$ cat</span> <?php the_title(); ?></a>
					</h2>
					<?php inception_terminal_post_meta(); ?>
					<p class="journal-card-excerpt"><?php echo esc_html( get_the_excerpt() ); ?></p>
				</article>
				<?php endwhile; ?>
			</div>
			<nav class="pager" aria-label="Posts navigation">
				<?php the_posts_pagination( array( 'prev_text' => '← prev', 'next_text' => 'next →' ) ); ?>
			</nav>
		<?php else : ?>
			<p class="archive-empty">journal.log is empty — nothing here yet.</p>
		<?php endif; ?>
	</div>
</section>

<?php get_footer(); ?>
