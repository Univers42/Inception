<?php
if ( post_password_required() ) {
	return;
}
?>
<section id="comments" class="comments">
	<?php if ( have_comments() ) : ?>
		<h2 class="comments-title">
			<?php echo esc_html( sprintf( _n( '%s comment', '%s comments', get_comments_number(), 'inception-terminal' ), number_format_i18n( get_comments_number() ) ) ); ?>
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
		<p class="empty">Comments are closed.</p>
	<?php endif; ?>
	<?php
	comment_form(
		array(
			'title_reply'          => 'Leave a comment',
			'title_reply_before'   => '<h2 class="comments-title">',
			'title_reply_after'    => '</h2>',
			'class_submit'         => 'btn btn-primary',
			'label_submit'         => 'Post comment',
			'comment_notes_before' => '',
		)
	);
	?>
</section>
