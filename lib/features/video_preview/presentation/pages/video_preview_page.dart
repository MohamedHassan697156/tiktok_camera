import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_player/video_player.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/filters/filtered_view.dart';
import '../../../../core/utils/duration_format.dart';
import '../../../camera/domain/recording.dart';
import '../cubit/video_preview_cubit.dart';
import '../cubit/video_preview_state.dart';

/// Review screen for a clip: plays it back under the look it was shot with, and
/// offers the two decisions that follow — keep it, or bin it and shoot again.
class VideoPreviewPage extends StatelessWidget {
  const VideoPreviewPage({super.key, required this.recording});

  final Recording recording;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<VideoPreviewCubit>(
      create: (_) => VideoPreviewCubit(recording: recording)..initialise(),
      child: const _VideoPreviewView(),
    );
  }
}

class _VideoPreviewView extends StatelessWidget {
  const _VideoPreviewView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: BlocConsumer<VideoPreviewCubit, VideoPreviewState>(
        listenWhen: (VideoPreviewState previous, VideoPreviewState current) =>
            previous.notice != current.notice && current.notice != null,
        listener: (BuildContext context, VideoPreviewState state) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(state.notice!)));
          context.read<VideoPreviewCubit>().clearNotice();
        },
        builder: (BuildContext context, VideoPreviewState state) {
          switch (state.status) {
            case VideoPreviewStatus.loading:
              return const Center(
                child: CircularProgressIndicator(color: AppColors.onDarkMuted),
              );
            case VideoPreviewStatus.failure:
              return _PlaybackFailure(message: state.errorMessage);
            case VideoPreviewStatus.ready:
              return _buildPlayer(context, state);
          }
        },
      ),
    );
  }

  Widget _buildPlayer(BuildContext context, VideoPreviewState state) {
    final VideoPreviewCubit cubit = context.read<VideoPreviewCubit>();
    final VideoPlayerController controller = state.controller!;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        GestureDetector(
          onTap: cubit.togglePlayback,
          behavior: HitTestBehavior.opaque,
          child: _FilteredVideoSurface(controller: controller, state: state),
        ),

        // Play glyph while paused, so a tapped-to-pause clip does not look frozen.
        Center(
          child: ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: controller,
            builder: (BuildContext context, VideoPlayerValue value, _) {
              return AnimatedOpacity(
                opacity: value.isPlaying ? 0 : 1,
                duration: AppTheme.quickTransition,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.controlScrim,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: AppColors.onDark,
                      size: 44,
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        SafeArea(
          child: Column(
            children: <Widget>[
              _buildTopBar(context, state),
              const Spacer(),
              _buildBottomBar(context, state, controller, cubit),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar(BuildContext context, VideoPreviewState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
          ),
          const Spacer(),
          _MetaChip(
            text: '${state.recording.filter.label} · '
                '${state.recording.duration.asShortClock}',
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildBottomBar(
    BuildContext context,
    VideoPreviewState state,
    VideoPlayerController controller,
    VideoPreviewCubit cubit,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: <Color>[Colors.black.withValues(alpha: 0.6), Colors.transparent],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Scrub bar listens to the controller itself, so dragging it does not
          // rebuild the rest of the screen.
          VideoProgressIndicator(
            controller,
            allowScrubbing: true,
            padding: const EdgeInsets.symmetric(vertical: 10),
            colors: VideoProgressColors(
              playedColor: AppColors.accent,
              bufferedColor: AppColors.onDark.withValues(alpha: 0.25),
              backgroundColor: AppColors.onDark.withValues(alpha: 0.15),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _confirmRetake(context, cubit),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Retake'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.onDark,
                    side: BorderSide(color: AppColors.onDark.withValues(alpha: 0.4)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.cornerRadius),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: state.isExporting ? null : cubit.exportToGallery,
                  icon: state.isExporting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.onDark,
                          ),
                        )
                      : const Icon(Icons.download_rounded, size: 18),
                  label: Text(state.isExporting ? 'Saving' : 'Gallery'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.onDark,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.cornerRadius),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Already saved on this device. "Gallery" also copies it to your camera roll.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.onDarkMuted.withValues(alpha: 0.75),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  /// Deleting footage is not undoable, so it is confirmed first.
  Future<void> _confirmRetake(BuildContext context, VideoPreviewCubit cubit) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Discard this clip?'),
        content: const Text('It will be deleted from this device.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.accent),
            child: const Text('Discard'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final NavigatorState navigator = Navigator.of(context);
    if (await cubit.discard() && navigator.mounted) {
      navigator.pop();
    }
  }
}

/// The video, cover-cropped and graded with the clip's look.
///
/// `BoxFit.cover` mirrors how the frame was composed while shooting: the capture
/// preview was cropped to fill the screen, so reviewing the clip letterboxed would
/// show a wider field of view than the user framed.
class _FilteredVideoSurface extends StatelessWidget {
  const _FilteredVideoSurface({required this.controller, required this.state});

  final VideoPlayerController controller;
  final VideoPreviewState state;

  @override
  Widget build(BuildContext context) {
    // A decoder that has not reported dimensions yet would collapse the fitted box
    // to nothing; a portrait stand-in keeps the layout stable until it does.
    final Size frame = controller.value.size.isEmpty
        ? const Size(720, 1280)
        : controller.value.size;

    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: frame.width,
          height: frame.height,
          // The same widget grades the live preview, so a clip looks on playback
          // the way it looked while it was being shot.
          child: FilteredView(
            preset: state.recording.filter,
            child: VideoPlayer(controller),
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.controlScrim,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.onDark,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _PlaybackFailure extends StatelessWidget {
  const _PlaybackFailure({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(Icons.error_outline, size: 48, color: AppColors.onDarkMuted),
              const SizedBox(height: 16),
              Text(
                message ?? 'This clip could not be played back.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.onDarkMuted, fontSize: 14),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).maybePop(),
                style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
                child: const Text('Back to camera'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
