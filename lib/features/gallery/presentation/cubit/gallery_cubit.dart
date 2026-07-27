import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../camera/data/recording_repository.dart';
import '../../../camera/domain/recording.dart';
import '../../../camera/domain/storage_failure.dart';
import 'gallery_state.dart';

/// Lists and prunes the clips stored on this device.
class GalleryCubit extends Cubit<GalleryState> {
  GalleryCubit({RecordingRepository repository = const RecordingRepository()})
    : _repository = repository,
      super(const GalleryState());

  final RecordingRepository _repository;

  /// Reads the library.
  ///
  /// Also used to refresh after returning from playback, where a clip may have
  /// been discarded.
  Future<void> load() async {
    try {
      final List<Recording> recordings = await _repository.list();
      if (isClosed) return;
      emit(
        state.copyWith(
          status: GalleryStatus.ready,
          recordings: recordings,
          clearErrorMessage: true,
        ),
      );
    } on StorageFailure catch (failure) {
      if (isClosed) return;
      emit(state.copyWith(status: GalleryStatus.failure, errorMessage: failure.message));
    }
  }

  /// Deletes a clip and updates the list in place, so the grid does not flash
  /// through a loading state for a single removal.
  Future<void> delete(Recording recording) async {
    try {
      await _repository.delete(recording);
      if (isClosed) return;
      emit(
        state.copyWith(
          recordings: state.recordings
              .where((Recording item) => item.path != recording.path)
              .toList(growable: false),
          notice: 'Clip deleted.',
        ),
      );
    } on StorageFailure catch (failure) {
      if (isClosed) return;
      emit(state.copyWith(notice: failure.message));
    }
  }

  /// Copies a clip into the system gallery.
  Future<void> exportToGallery(Recording recording) async {
    try {
      await _repository.exportToGallery(recording);
      if (isClosed) return;
      emit(
        state.copyWith(
          notice: 'Saved to your gallery in "${RecordingRepository.albumName}".',
        ),
      );
    } on StorageFailure catch (failure) {
      if (isClosed) return;
      emit(state.copyWith(notice: failure.message));
    }
  }

  /// Acknowledges the current notice so it is not shown twice.
  void clearNotice() {
    if (state.notice == null) return;
    emit(state.copyWith(clearNotice: true));
  }
}
