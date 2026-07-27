import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/recording.dart';
import '../domain/storage_failure.dart';

/// The app's own clip library, stored inside application documents.
///
/// Clips live in the app's private directory rather than the shared media store.
/// That is what makes them survive without any storage permission, and it keeps
/// half-finished experiments out of the user's camera roll — handing a clip to
/// the system gallery is a separate, explicit step ([exportToGallery]).
///
/// Each `.mp4` is paired with a `.json` sidecar holding its metadata. A sidecar
/// per clip rather than one shared index means a crash mid-write can at worst
/// cost the metadata of the clip being written, and there is no index to
/// reconcile against the directory afterwards.
class RecordingRepository {
  const RecordingRepository();

  static const String _folder = 'recordings';
  static const String _videoExtension = '.mp4';
  static const String _sidecarExtension = '.json';

  /// Album used when a clip is exported to the system gallery.
  static const String albumName = 'TikTok Camera';

  /// Moves a just-finished capture out of the plugin's cache into the library.
  ///
  /// The plugin writes to a cache directory it is free to clear, so this must
  /// happen before the clip is considered saved. [sourcePath] is taken as a plain
  /// path rather than the plugin's `XFile` so that storage has no opinion about
  /// where a clip came from.
  Future<Recording> persist({
    required String sourcePath,
    required Duration duration,
    required String filterId,
    DateTime? recordedAt,
  }) async {
    try {
      final Directory library = await _library();
      final DateTime timestamp = recordedAt ?? DateTime.now();
      final File target = File(
        '${library.path}${Platform.pathSeparator}VID_${_stamp(timestamp)}$_videoExtension',
      );

      await _move(File(sourcePath), target);

      final Recording recording = Recording(
        path: target.path,
        duration: duration,
        recordedAt: timestamp,
        filterId: filterId,
      );
      await _sidecarOf(target.path).writeAsString(jsonEncode(recording.toJson()));
      return recording;
    } on StorageFailure {
      rethrow;
    } catch (error) {
      throw StorageFailure('Could not save the recording.', cause: error);
    }
  }

  /// Every stored clip, newest first.
  Future<List<Recording>> list() async {
    try {
      final Directory library = await _library();
      final List<FileSystemEntity> entities = await library.list().toList();
      final List<Recording> recordings = <Recording>[];

      for (final FileSystemEntity entity in entities) {
        if (entity is! File || !entity.path.endsWith(_videoExtension)) continue;
        recordings.add(await _read(entity));
      }

      recordings.sort((Recording a, Recording b) => b.recordedAt.compareTo(a.recordedAt));
      return recordings;
    } catch (error) {
      throw StorageFailure('Could not read saved recordings.', cause: error);
    }
  }

  /// Removes a clip and its metadata.
  Future<void> delete(Recording recording) async {
    try {
      final File video = File(recording.path);
      if (video.existsSync()) await video.delete();
      final File sidecar = _sidecarOf(recording.path);
      if (sidecar.existsSync()) await sidecar.delete();
    } catch (error) {
      throw StorageFailure('Could not delete the recording.', cause: error);
    }
  }

  /// Copies a clip into the system gallery so it is visible to other apps.
  ///
  /// Note that the exported file carries the ungraded sensor image: the filter is
  /// a render-time layer, not something baked into the encoded video.
  Future<void> exportToGallery(Recording recording) async {
    try {
      if (!await Gal.hasAccess()) {
        final bool granted = await Gal.requestAccess();
        if (!granted) {
          throw const StorageFailure('Gallery access was denied.');
        }
      }
      await Gal.putVideo(recording.path, album: albumName);
    } on StorageFailure {
      rethrow;
    } on GalException catch (error) {
      throw StorageFailure(_describeGalError(error), cause: error);
    } catch (error) {
      throw StorageFailure('Could not add the clip to your gallery.', cause: error);
    }
  }

  /// The library directory, created on first use.
  Future<Directory> _library() async {
    final Directory documents = await getApplicationDocumentsDirectory();
    final Directory library = Directory('${documents.path}${Platform.pathSeparator}$_folder');
    if (!library.existsSync()) {
      await library.create(recursive: true);
    }
    return library;
  }

  /// Renames [source] to [target], falling back to copy-then-delete when the two
  /// paths sit on different filesystems (cache and documents are not guaranteed
  /// to share a mount).
  Future<void> _move(File source, File target) async {
    try {
      await source.rename(target.path);
    } on FileSystemException {
      await source.copy(target.path);
      try {
        await source.delete();
      } catch (error) {
        // The clip is safely at its destination; a leftover cache file is the
        // OS's problem, not the user's.
        debugPrint('RecordingRepository: could not remove cached capture: $error');
      }
    }
  }

  /// Reads a clip's metadata, reconstructing what it can when the sidecar is
  /// missing or unreadable so a playable file is never hidden from the gallery.
  Future<Recording> _read(File video) async {
    final File sidecar = _sidecarOf(video.path);
    if (sidecar.existsSync()) {
      try {
        final Object? decoded = jsonDecode(await sidecar.readAsString());
        if (decoded is Map<String, dynamic>) {
          return Recording.fromJson(decoded, path: video.path);
        }
      } catch (error) {
        debugPrint('RecordingRepository: unreadable sidecar for ${video.path}: $error');
      }
    }
    return Recording(
      path: video.path,
      duration: Duration.zero,
      recordedAt: (await video.stat()).modified,
      filterId: '',
    );
  }

  File _sidecarOf(String videoPath) {
    final int cut = videoPath.length - _videoExtension.length;
    return File('${videoPath.substring(0, cut)}$_sidecarExtension');
  }

  /// `yyyyMMdd_HHmmss`, sortable and filename-safe.
  String _stamp(DateTime moment) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${moment.year}${two(moment.month)}${two(moment.day)}'
        '_${two(moment.hour)}${two(moment.minute)}${two(moment.second)}';
  }

  String _describeGalError(GalException error) {
    switch (error.type) {
      case GalExceptionType.accessDenied:
        return 'Gallery access was denied.';
      case GalExceptionType.notEnoughSpace:
        return 'Not enough space to save the clip.';
      case GalExceptionType.notSupportedFormat:
        return 'The gallery rejected this video format.';
      case GalExceptionType.unexpected:
        return 'Could not add the clip to your gallery.';
    }
  }
}
