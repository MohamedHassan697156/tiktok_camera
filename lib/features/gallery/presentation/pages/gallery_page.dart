import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/filters/filtered_view.dart';
import '../../../../core/utils/duration_format.dart';
import '../../../camera/domain/recording.dart';
import '../../../video_preview/presentation/pages/video_preview_page.dart';
import '../cubit/gallery_cubit.dart';
import '../cubit/gallery_state.dart';

/// The clips saved on this device.
class GalleryPage extends StatelessWidget {
  const GalleryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<GalleryCubit>(
      create: (_) => GalleryCubit()..load(),
      child: const _GalleryView(),
    );
  }
}

class _GalleryView extends StatelessWidget {
  const _GalleryView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Saved clips'),
        backgroundColor: AppColors.background,
      ),
      body: BlocConsumer<GalleryCubit, GalleryState>(
        listenWhen: (GalleryState previous, GalleryState current) =>
            previous.notice != current.notice && current.notice != null,
        listener: (BuildContext context, GalleryState state) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(state.notice!)));
          context.read<GalleryCubit>().clearNotice();
        },
        builder: (BuildContext context, GalleryState state) {
          switch (state.status) {
            case GalleryStatus.loading:
              return const Center(
                child: CircularProgressIndicator(color: AppColors.onDarkMuted),
              );
            case GalleryStatus.failure:
              return _GalleryMessage(
                icon: Icons.folder_off_outlined,
                message: state.errorMessage ?? 'Could not read your clips.',
                actionLabel: 'Try again',
                onAction: context.read<GalleryCubit>().load,
              );
            case GalleryStatus.ready:
              if (state.isEmpty) {
                return const _GalleryMessage(
                  icon: Icons.videocam_outlined,
                  message: 'Nothing recorded yet.\nClips you record appear here.',
                );
              }
              return _RecordingGrid(recordings: state.recordings);
          }
        },
      ),
    );
  }
}

class _RecordingGrid extends StatelessWidget {
  const _RecordingGrid({required this.recordings});

  final List<Recording> recordings;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      // Sized by extent rather than a fixed column count, so the grid gains
      // columns on a wider screen instead of stretching tiles.
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190,
        childAspectRatio: 9 / 15,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: recordings.length,
      itemBuilder: (BuildContext context, int index) =>
          _RecordingTile(recording: recordings[index]),
    );
  }
}

class _RecordingTile extends StatelessWidget {
  const _RecordingTile({required this.recording});

  final Recording recording;

  @override
  Widget build(BuildContext context) {
    final GalleryCubit cubit = context.read<GalleryCubit>();

    return Semantics(
      button: true,
      label: 'Clip from ${_formatDate(recording.recordedAt)}, '
          '${recording.duration.asShortClock}, ${recording.filter.label} filter',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.cornerRadius),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // Stand-in artwork rather than a decoded frame.
            //
            // Extracting a real thumbnail needs a frame-grabbing dependency and a
            // decoder per tile; showing the clip's own look over a neutral field
            // keeps the grid free and still distinguishes the clips at a glance.
            FilteredView(
              preset: recording.filter,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[Color(0xFF3A3A44), Color(0xFF15151A)],
                  ),
                ),
                child: SizedBox.expand(),
              ),
            ),

            const Center(
              child: Icon(Icons.play_circle_outline, size: 40, color: AppColors.onDark),
            ),

            Positioned(
              left: 8,
              top: 8,
              child: _TileChip(text: recording.filter.label),
            ),

            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      _formatDate(recording.recordedAt),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.onDark,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        shadows: <Shadow>[Shadow(color: Colors.black87, blurRadius: 4)],
                      ),
                    ),
                  ),
                  _TileChip(text: recording.duration.asShortClock),
                ],
              ),
            ),

            // The tap target sits above the artwork so the whole tile is
            // interactive.
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => VideoPreviewPage(recording: recording),
                    ),
                  );
                  // The clip may have been discarded from the preview screen.
                  await cubit.load();
                },
                onLongPress: () => _confirmDelete(context, cubit),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, GalleryCubit cubit) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete this clip?'),
        content: const Text('It will be removed from this device.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.accent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) await cubit.delete(recording);
  }

  /// `dd MMM · HH:mm` without pulling in a localisation package for one label.
  String _formatDate(DateTime moment) {
    const List<String> months = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
    ];
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(moment.day)} ${months[moment.month - 1]} · '
        '${two(moment.hour)}:${two(moment.minute)}';
  }
}

class _TileChip extends StatelessWidget {
  const _TileChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.onDark,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _GalleryMessage extends StatelessWidget {
  const _GalleryMessage({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 48, color: AppColors.onDarkMuted),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.onDarkMuted,
                fontSize: 14,
                height: 1.45,
              ),
            ),
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: 24),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
