# TikTok-Inspired Camera Module

A Flutter camera module built around video capture with real-time looks: front/back
switching, torch, zoom, tap-to-focus, a recording clock with a one-minute ceiling,
local storage, and playback that shows a clip under the same filter it was shot
with.

Android is the target platform for this build.

---

## Requirement coverage

| Requirement | Where it lives |
| --- | --- |
| Front and back camera switching | [`CameraService.switchLens`](lib/features/camera/data/camera_service.dart) — rebuilds the controller so zoom range and flash are re-read for the new sensor |
| Video recording | [`CameraCubit`](lib/features/camera/presentation/cubit/camera_cubit.dart) start/stop, with a 60 s ceiling and a minimum-length guard |
| Flash control | [`FlashSetting`](lib/features/camera/domain/flash_setting.dart) — torch on/off (see *Design decisions*) |
| Zoom support | Pinch on the preview plus a slider; range read per sensor via [`ZoomRange`](lib/features/camera/domain/zoom_range.dart) |
| Tap to focus | [`CameraPreviewSurface`](lib/features/camera/presentation/widgets/camera_preview_surface.dart) — maps the tap back through the cover-crop, locks focus, animates a reticle |
| Camera permission handling | [`CapturePermissionService`](lib/features/camera/data/capture_permission_service.dart) — camera + microphone as one unit, with a distinct permanently-denied path |
| Recording timer | [`RecordingTimerBadge`](lib/features/camera/presentation/widgets/recording_timer_badge.dart) plus the progress ring on the shutter |
| Video preview after recording | [`VideoPreviewPage`](lib/features/video_preview/presentation/pages/video_preview_page.dart) — loops, scrubs, graded to match capture |
| Save recorded video locally | [`RecordingRepository`](lib/features/camera/data/recording_repository.dart) — clips move into app documents with a JSON sidecar |
| Real-time filters | 8 looks in [`FilterPresets`](lib/core/filters/filter_presets.dart), composed from [`ColorMatrix`](lib/core/filters/color_matrix.dart) primitives |
| Clean camera UI | Capture, playback and library screens under `lib/features/*/presentation` |
| Gallery button (optional) | [`GalleryPage`](lib/features/gallery/presentation/pages/gallery_page.dart) |
| State management | `flutter_bloc` cubits, one per screen |
| Responsive layout | Constraint-driven sizing throughout; the library grid gains columns by extent rather than a fixed count |

The looks are **Original, Beauty, B&W, Vintage, Warm, Cool, Vivid, Fade** — the five
named in the brief plus two extras.

---

## Getting started

**Prerequisites**

- Flutter **3.44.4** or newer, stable channel (Dart 3.12+)
- Android SDK, device or emulator on **API 24+**
- A physical device is recommended — see *Platform notes*

```bash
flutter pub get
flutter run              # attach a device first
```

Other useful commands:

```bash
flutter analyze          # expected: "No issues found!"
flutter test             # 61 unit and widget tests
flutter build apk --release
```

**Permissions.** The app requests camera and microphone on first launch; both are
declared in [`AndroidManifest.xml`](android/app/src/main/AndroidManifest.xml).
`WRITE_EXTERNAL_STORAGE` is declared with `maxSdkVersion="32"` only because the
optional "copy to system gallery" action needs the legacy permission up to Android
12L. Nothing is required for the app's own library, which lives in private storage.

---

## How the filters work

### Composition, not magic numbers

`ColorFilter.matrix` takes twenty coefficients. Hand-writing those for eight looks
would be unreadable, so [`ColorMatrix`](lib/core/filters/color_matrix.dart) provides
one factory per photographic adjustment — `saturation`, `contrast`, `brightness`,
`exposure`, `temperature`, `tint`, `sepia`, `grayscale` — and a `then` operator that
composes them properly, carrying the translation column through the multiplication:

```dart
static final FilterPreset vintage = FilterPreset(
  id: 'vintage',
  label: 'Vintage',
  matrix: ColorMatrix.sepia(0.7)
      .then(ColorMatrix.saturation(0.9))
      .then(ColorMatrix.contrast(0.88))
      .then(ColorMatrix.brightness(12)),
);
```

A four-step recipe collapses into a single matrix at construction, so a long recipe
renders no slower than a short one. `then` is the piece most likely to be got wrong
— composing affine transforms by multiplying only the linear parts silently drops
offsets — so it is tested against sequential application of the same steps.

### One code path for every surface

[`FilteredView`](lib/core/filters/filtered_view.dart) is the only place a preset
becomes render layers. The live preview, playback, and the tray swatches all go
through it, which guarantees a clip looks the same while shooting and while watching
it back, and means a tweaked recipe cannot leave its thumbnail behind.

Both layers are applied by the compositor. No frame data crosses into the Dart
isolate, and the per-frame cost is independent of preview resolution.

`AnimatedFilteredView` cross-fades between looks by interpolating the matrices, so
switching filters glides rather than snaps.

Tray swatches are the preset applied to one shared reference gradient — no extra
camera textures, no snapshots, and a swatch is by construction an honest preview of
what the filter does.

### Beauty

Skin smoothing is not expressible as a colour matrix, so `Beauty` is the one preset
that also carries a `blurSigma`. `FilteredView` softens first and grades second —
grading a blurred image rather than blurring a graded one, which would drag the
grade's contrast back down.

### What the saved file contains

**The recorded `.mp4` holds the ungraded sensor image.** Filters are a render-time
layer; the `camera` plugin encodes what the sensor produces, and nothing in the
Flutter render tree reaches the encoder.

So that a clip still plays back the way its author saw it, the chosen preset's id is
stored in the clip's JSON sidecar and playback re-applies it through the same
`FilteredView`:

```json
{"durationMs":36546,"recordedAt":"2026-07-26T19:51:28.151541","filterId":"mono"}
```

Inside the app the experience is consistent end to end. A clip exported to the
system gallery will look ungraded in other apps — the playback screen says so.

Baking the grade into the file would need either a post-processing pass (FFmpeg
`colorchannelmixer`/`eq` built from the same coefficients) or a native
CameraX + OpenGL pipeline recording from a filtered surface. Each preset carries its
own coefficients, so the first route reads them straight off `ColorMatrix` rather
than duplicating the recipes.

---

## Architecture

```
lib/
├── app/                      MaterialApp, theme
├── core/
│   ├── filters/              ColorMatrix, FilterPreset, FilterPresets, FilteredView
│   └── utils/                clock formatting
└── features/
    ├── camera/
    │   ├── data/             CameraService, CapturePermissionService, RecordingRepository
    │   ├── domain/           Recording, FlashSetting, ZoomRange, limits, failures
    │   └── presentation/     CameraCubit + CameraState, CameraPage, widgets
    ├── video_preview/        VideoPreviewCubit + page
    └── gallery/              GalleryCubit + page
```

**Layering.** `domain` is plain Dart values with no plugin imports. `data` owns every
platform call and translates plugin errors into
[`CameraFailure`](lib/features/camera/domain/camera_failure.dart) or
[`StorageFailure`](lib/features/camera/domain/storage_failure.dart) with user-ready
messages, so no widget ever interprets a platform error code. `presentation` holds
cubits and widgets.

**State management: `flutter_bloc` cubits**, one per screen. Widgets report intent
and read state; they never call the camera plugin. What deliberately stays *out* of
cubit state:

- **Video playback position** — it changes many times a second and already lives on
  `VideoPlayerController`; the scrub bar listens to it directly instead of rebuilding
  the screen once per frame.
- **The focus reticle** and **whether the filter tray is open** — pure view feedback
  that nothing outside the screen needs.

The one exception to "no plugin types in state" is `CameraController`, which
`CameraPreview` needs in order to find its texture.

**Hardware faults.** A camera can die after it has started — a HAL crash, or the OS
handing the sensor to something else. `CameraService` watches the controller for
that and reports it, and the cubit drops the dead controller and shows the reason
with a retry, rather than leaving a preview frozen on its last frame and a shutter
that does nothing. Finalising a clip is also given a deadline: if the encoder never
returns because its session died, the stop fails with a message and the camera is
rebuilt, instead of the UI sitting in "saving" forever. This was not a theoretical
concern — the development emulator's camera HAL segfaulted mid-take and produced
exactly that dead end.

**Lifecycle.** Android hands the sensor to the foreground app, so `CameraPage`
observes lifecycle and the cubit releases the camera on pause and reopens it on
resume, re-checking permission in case it was granted in system settings meanwhile.
A take in progress is **stopped and saved**, not discarded. `inactive` is ignored on
purpose: it also fires when the permission sheet slides up, and tearing down there
would fight the request that triggered it.

---

## Design decisions

**Flash is a torch toggle, not a four-way mode.** `FlashMode.always` and `.auto`
drive the pre-capture flash for *photos*; during video recording they fire nothing.
Offering them would give the user two controls that visibly do nothing, so the toggle
maps to `FlashMode.torch` — continuous light, which is what actually lights a video
and what the reference app exposes.

**Capture orientation is locked to portrait.** Without it, `CameraPreview` takes its
rotation and aspect ratio from the *device* orientation, which the plugin keeps
reporting from the sensors even when the app is portrait-locked; the preview would
rotate its contents inside a box that did not rotate with it. Locking makes the
preview geometry and the recorded orientation deterministic, which is also what lets
the preview surface compute its own cover-crop and map taps back to sensor
coordinates.

**The preview is centre-cropped to fill, not letterboxed.** Sensor aspect almost
never matches screen aspect, and filling is what makes the screen read as a camera
rather than a video player. Playback crops the same way, so a clip is reviewed with
the framing it was shot with.

**Clips are saved automatically, deleted only on request.** Recording stops → the clip
is already in the library. "Retake" deletes it behind a confirmation. Keeping footage
by default is the safer way round.

**A sidecar per clip rather than one index file.** A crash mid-write can at worst cost
the metadata of the clip being written, and there is no index to reconcile against the
directory afterwards. Missing or corrupt metadata degrades to defaults, so a playable
file is never hidden from the library.

---

## Performance notes

- Filters are compositor-level (`ColorFiltered` / `ImageFiltered`). Frame data never
  enters Dart, and cost does not scale with preview resolution.
- Only `Beauty` pays for a blur pass; the other seven are a single colour matrix. A
  test asserts that.
- `FilteredView` returns its child untouched for a pass-through preset, so `Original`
  allocates no save-layer at all — and `ColorMatrix.lerp` returns its endpoints
  exactly, so a finished cross-fade drops back to that cheap path instead of settling
  a hair off the identity.
- The recording clock ticks at 10 Hz and is measured against a wall-clock start time
  rather than by counting ticks, so it cannot drift behind the actual recording.
- `ResolutionPreset.high` (720p) is the capture target: a deliberate balance between
  clip quality and encoder load on mid-range hardware.

---

## Testing

```bash
flutter test
```

61 tests, no mocking framework — collaborators are injected and subclassed directly:

- **`ColorMatrix`** — every factory checked by transforming reference pixels rather
  than by restating coefficients; `then` verified against sequential application,
  including the offset-carrying case a naive implementation gets wrong.
- **`FilterPresets`** — ids unique and stable (they are persisted), only `Beauty`
  blurs, unknown ids fall back to `Original` so clips from an older build still play.
- **`FilteredView`** — asserts the layer stack: nothing for pass-through, colour only
  for a grade, blur *nested inside* colour for `Beauty`; plus that
  `AnimatedFilteredView` genuinely interpolates.
- **`Recording`** — sidecar round-trip and tolerant parsing of empty or malformed
  metadata.
- **`CameraCubit`** — permission outcomes including the permanently-denied branch,
  camera-open failure surfacing as a message, controls inert before the camera is
  live, progress clamping, that backgrounding during the permission prompt does not
  abandon the request, and that a mid-session hardware fault drops the preview and
  resets the shutter instead of freezing.

Paths that need a live sensor are verified on device rather than faked.

### Verified on device

Checked on an Android 14 emulator: permission handshake, camera open, filter
selection and swatch rendering, recording with a live timer and progress ring,
automatic save with correct sidecar metadata, playback under the recorded look, the
library grid, lens switching (`CameraId-0` closed → `CameraId-1` opened), and
lifecycle teardown/restore on background and foreground with every camera surface
released and the active lens preserved. No unhandled exceptions in `logcat`
throughout.

---

## Platform notes

### Emulator graphics

The emulator used during development (LDPlayer, Android 14 x86-64) could not render
the camera preview at all under Impeller's Vulkan backend:

```
Could not create image for external buffer: ErrorValidationFailed
```

Its driver cannot import the camera's `AHardwareBuffer` into Vulkan. Debug builds
therefore request the OpenGL ES backend via
[`src/debug/AndroidManifest.xml`](android/app/src/debug/AndroidManifest.xml), which
that driver does support. Release builds keep Impeller's default Vulkan backend for
performance. If the preview is black on some other emulator, that flag is the first
thing to try.

### Colour grading of the preview needs real hardware to confirm

On that same emulator, with the preview working under OpenGL ES, a second limitation
showed up. Isolated with a single `CameraPreview` and one effect at a time:

| Layer over the camera texture | Result |
| --- | --- |
| none | preview renders |
| `ImageFiltered` (blur) | renders, blurred |
| `ColorFiltered` (matrix) | texture renders **black** |
| `ImageFiltered(ColorFilter)` | texture renders **black** |
| `ImageFilter.compose(colour, blur)` | texture renders **black** |

Non-texture widgets inside the same filtered subtree graded correctly while the
texture went black, so the filter was being applied — the emulator's GL driver simply
contributes nothing for the external camera texture once a colour matrix is in the
chain. Grading of *video playback* and of the tray swatches works on this emulator;
only the live camera texture is affected.

This build uses the standard `ColorFiltered`-over-`CameraPreview` approach, which is
what the Flutter camera ecosystem relies on and which works on physical Android
devices. **Colour grading of the live preview has not been visually confirmed on
physical hardware in this environment** and should be checked on a real device.
Everything filter-related is isolated in `FilteredView`, so an alternative path would
be a change to one file.

### Other limitations

- **Portrait only**, by design (see *Design decisions*).
- **Library thumbnails are stand-ins**, not decoded frames: a real thumbnail needs a
  frame-grabbing dependency and a video decoder per tile. Each tile shows its clip's
  own look over a neutral field, which distinguishes clips at a glance for free.
- **iOS is not configured.** Android was the agreed scope; the Dart code is
  platform-neutral, but `Info.plist` usage descriptions and an iOS run are not
  included.
- Clips exported to the system gallery are ungraded, as explained above.
