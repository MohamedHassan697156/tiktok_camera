import 'package:equatable/equatable.dart';
import 'package:video_player/video_player.dart';

import '../../../camera/domain/recording.dart';

/// Where playback setup has got to.
enum VideoPreviewStatus { loading, ready, failure }

/// State for reviewing a clip that has just been recorded, or picked from the
/// library.
///
/// Playback *position* is deliberately absent: it changes many times a second and
/// lives on the player's own [VideoPlayerController] value, which the scrub bar
/// listens to directly. Mirroring it here would rebuild the whole screen for every
/// frame of video.
class VideoPreviewState extends Equatable {
  const VideoPreviewState({
    required this.recording,
    this.status = VideoPreviewStatus.loading,
    this.controller,
    this.isExporting = false,
    this.errorMessage,
    this.notice,
  });

  /// The clip under review.
  final Recording recording;

  final VideoPreviewStatus status;

  /// The player, once initialised.
  final VideoPlayerController? controller;

  /// Whether a copy to the system gallery is in flight.
  final bool isExporting;

  /// Why playback could not start, when [status] is [VideoPreviewStatus.failure].
  final String? errorMessage;

  /// One-off message for the user, cleared once shown.
  final String? notice;

  /// Whether the player is ready to render frames.
  bool get isReady => status == VideoPreviewStatus.ready && controller != null;

  VideoPreviewState copyWith({
    VideoPreviewStatus? status,
    VideoPlayerController? controller,
    bool? isExporting,
    String? errorMessage,
    bool clearErrorMessage = false,
    String? notice,
    bool clearNotice = false,
  }) {
    return VideoPreviewState(
      recording: recording,
      status: status ?? this.status,
      controller: controller ?? this.controller,
      isExporting: isExporting ?? this.isExporting,
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      notice: clearNotice ? null : (notice ?? this.notice),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    recording,
    status,
    controller,
    isExporting,
    errorMessage,
    notice,
  ];
}
