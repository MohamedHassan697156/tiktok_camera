import 'package:equatable/equatable.dart';

import '../../../camera/domain/recording.dart';

/// Where loading the library has got to.
enum GalleryStatus { loading, ready, failure }

/// State for the list of clips stored on this device.
class GalleryState extends Equatable {
  const GalleryState({
    this.status = GalleryStatus.loading,
    this.recordings = const <Recording>[],
    this.errorMessage,
    this.notice,
  });

  final GalleryStatus status;

  /// Stored clips, newest first.
  final List<Recording> recordings;

  /// Why the library could not be read, when [status] is [GalleryStatus.failure].
  final String? errorMessage;

  /// One-off message for the user, cleared once shown.
  final String? notice;

  /// Whether the library loaded but holds nothing.
  bool get isEmpty => status == GalleryStatus.ready && recordings.isEmpty;

  GalleryState copyWith({
    GalleryStatus? status,
    List<Recording>? recordings,
    String? errorMessage,
    bool clearErrorMessage = false,
    String? notice,
    bool clearNotice = false,
  }) {
    return GalleryState(
      status: status ?? this.status,
      recordings: recordings ?? this.recordings,
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      notice: clearNotice ? null : (notice ?? this.notice),
    );
  }

  @override
  List<Object?> get props => <Object?>[status, recordings, errorMessage, notice];
}
