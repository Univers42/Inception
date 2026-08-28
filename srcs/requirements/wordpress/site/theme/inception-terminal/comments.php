<?php
/**
 * Comments list and comment form.
 *
 * The subject's evaluation asks the evaluator to "add a comment using the
 * available WordPress user", so a theme without this file makes that
 * impossible: WordPress renders no comment form unless a template calls
 * comments_template(), however open the discussion settings are.
 *
 * @package inception-terminal
 */

// A password-protected post must not leak its discussion.
if ( post_password_required() ) {
	return;
}
?>
<section id="comments" class="post-comments">

	<?php if ( have_comments() ) : ?>
		<h2 class="section-title">
			<span class="section-prompt">$</span> ls ./comments
			<span class="comment-count"><?php echo esc_html( number_format_i18n( get_comments_number() ) ); ?></span>
		</h2>

		<ol class="comment-list">
			<?php
			wp_list_comments(
				array(
					'style'       => 'ol',
					'short_ping'  => true,
					'avatar_size' => 0,
				)
			);
			?>
		</ol>

		<?php the_comments_pagination(); ?>
	<?php endif; ?>

	<?php if ( ! comments_open() && get_comments_number() > 0 ) : ?>
		<p class="no-comments">Comments are closed.</p>
	<?php endif; ?>

	<?php
	comment_form(
		array(
			'title_reply'         => 'Leave a comment',
			'title_reply_before'  => '<h2 class="section-title"><span class="section-prompt">$</span> ',
			'title_reply_after'   => '</h2>',
			'class_submit'        => 'comment-submit',
			'label_submit'        => 'Post comment',
			'comment_notes_before' => '',
		)
	);
	?>
</section>
