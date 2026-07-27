import 'package:flutter/foundation.dart';

import '../../../core/filters/filter_preset.dart';
import '../../../core/filters/filter_presets.dart';

/// A finished clip stored in the app's own library.
///
/// The look a clip was shot with is part of the clip's identity: the recorded
/// file holds the ungraded sensor image, so without [filterId] the gallery could
/// not play a clip back the way its author saw it. It is stored as the preset's
/// stable id rather than the matrix itself, so a tweak to a recipe reaches old
/// clips too.
@immutable
class Recording {
  const Recording({
    required this.path,
    required this.duration,
    required this.recordedAt,
    required this.filterId,
  });

  /// Rehydrates metadata written by [toJson], tolerating a missing or malformed
  /// sidecar by falling back to defaults rather than hiding the clip.
  factory Recording.fromJson(Map<String, dynamic> json, {required String path}) {
    return Recording(
      path: path,
      duration: Duration(milliseconds: (json['durationMs'] as num?)?.toInt() ?? 0),
      recordedAt:
          DateTime.tryParse(json['recordedAt'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      filterId: json['filterId'] as String? ?? FilterPresets.original.id,
    );
  }

  /// Absolute path of the `.mp4` in the app's documents directory.
  final String path;

  /// Wall-clock length of the clip.
  final Duration duration;

  /// When recording stopped.
  final DateTime recordedAt;

  /// [FilterPreset.id] of the look this clip was shot with.
  final String filterId;

  /// The look to play this clip back with.
  FilterPreset get filter => FilterPresets.byId(filterId);

  Map<String, dynamic> toJson() => <String, dynamic>{
    'durationMs': duration.inMilliseconds,
    'recordedAt': recordedAt.toIso8601String(),
    'filterId': filterId,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Recording &&
        other.path == path &&
        other.duration == duration &&
        other.recordedAt == recordedAt &&
        other.filterId == filterId;
  }

  @override
  int get hashCode => Object.hash(path, duration, recordedAt, filterId);

  @override
  String toString() => 'Recording($path, ${duration.inMilliseconds}ms, $filterId)';
}
