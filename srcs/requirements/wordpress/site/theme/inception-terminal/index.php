<?php
/**
 * Journal archive v2 — the full log stream.
 */
get_header();
?>

<section class="archive">
	<div class="shell shell-narrow">
		<header class="archive-head">
			<h1 class="section-title"><span class="section-prompt">$</span> tail -f journal.log</h1>
			<p class="archive-sub">Engineering journal — the build, the bugs, the numbers.</p>
		</header>

		<?php if ( have_posts() ) : ?>
			<div class="loglist loglist-full">
				<?php
				while ( have_posts() ) :
					the_post();
					?>
				<a class="logline logline-rich" href="<?php the_permalink(); ?>">
					<span class="log-ts"><?php echo esc_html( get_the_date( 'Y-m-d\TH:i' ) ); ?></span>
					<span class="log-level" aria-hidden="true">[post]</span>
					<span class="log-body">
						<span class="log-title"><?php the_title(); ?></span>
						<span class="log-excerpt"><?php echo esc_html( get_the_excerpt() ); ?></span>
					</span>
					<span class="log-meta"><?php echo function_exists( 'inception_kit_reading_time' ) ? (int) inception_kit_reading_time() . ' min' : ''; ?></span>
				</a>
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
