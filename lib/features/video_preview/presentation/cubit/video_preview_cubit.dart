import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_player/video_player.dart';

import '../../../camera/data/recording_repository.dart';
import '../../../camera/domain/recording.dart';
import '../../../camera/domain/storage_failure.dart';
import 'video_preview_state.dart';

/// Owns playback of a single clip, plus the two things the user can do with it:
/// copy it to the system gallery, or throw it away.
class VideoPreviewCubit extends Cubit<VideoPreviewState> {
  VideoPreviewCubit({
    required Recording recording,
    RecordingRepository repository = const RecordingRepository(),
  }) : _repository = repository,
       super(VideoPreviewState(recording: recording));

  final RecordingRepository _repository;

  /// Prepares the player and starts playing.
  ///
  /// Clips loop, because a review screen for a few seconds of video that stops on
  /// a frozen frame reads as broken.
  Future<void> initialise() async {
    final File file = File(state.recording.path);
    if (!file.existsSync()) {
      emit(
        state.copyWith(
          status: VideoPreviewStatus.failure,
          errorMessage: 'This clip is no longer on the device.',
        ),
      );
      return;
    }

    final VideoPlayerController controller = VideoPlayerController.file(file);
    try {
      await controller.initialize();
      await controller.setLooping(true);
      if (isClosed) {
        await controller.dispose();
        return;
      }
      emit(state.copyWith(status: VideoPreviewStatus.ready, controller: controller));
      await controller.play();
    } catch (error) {
      await controller.dispose();
      if (isClosed) return;
      emit(
        state.copyWith(
          status: VideoPreviewStatus.failure,
          errorMessage: 'This clip could not be played back.',
        ),
      );
    }
  }

  /// Pauses or resumes.
  Future<void> togglePlayback() async {
    final VideoPlayerController? controller = state.controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
  }

  /// Copies the clip into the system gallery.
  Future<void> exportToGallery() async {
    if (state.isExporting) return;
    emit(state.copyWith(isExporting: true));

    try {
      await _repository.exportToGallery(state.recording);
      if (isClosed) return;
      emit(
        state.copyWith(
          isExporting: false,
          notice: 'Saved to your gallery in "${RecordingRepository.albumName}".',
        ),
      );
    } on StorageFailure catch (failure) {
      if (isClosed) return;
      emit(state.copyWith(isExporting: false, notice: failure.message));
    }
  }

  /// Deletes the clip. Returns whether it is gone, so the caller knows whether it
  /// is safe to leave the screen.
  ///
  /// The clip was already written to the library when recording stopped — keeping
  /// footage by default and deleting only on request is the safer way round.
  Future<bool> discard() async {
    // Playback holds the file open; releasing it first avoids deleting a file
    // that is still being read.
    await state.controller?.pause();
    try {
      await _repository.delete(state.recording);
      return true;
    } on StorageFailure catch (failure) {
      if (!isClosed) emit(state.copyWith(notice: failure.message));
      return false;
    }
  }

  /// Acknowledges the current notice so it is not shown twice.
  void clearNotice() {
    if (state.notice == null) return;
    emit(state.copyWith(clearNotice: true));
  }

  @override
  Future<void> close() async {
    await state.controller?.dispose();
    return super.close();
  }
}
