import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/filters/filter_preset.dart';
import '../../../../core/filters/filter_presets.dart';
import '../../../gallery/presentation/pages/gallery_page.dart';
import '../../../video_preview/presentation/pages/video_preview_page.dart';
import '../../domain/recording.dart';
import '../cubit/camera_cubit.dart';
import '../cubit/camera_state.dart';
import '../widgets/camera_preview_surface.dart';
import '../widgets/capture_gate_view.dart';
import '../widgets/filter_tray.dart';
import '../widgets/glass_icon_button.dart';
import '../widgets/record_button.dart';
import '../widgets/recording_timer_badge.dart';
import '../widgets/zoom_control.dart';

/// The capture screen.
class CameraPage extends StatelessWidget {
  const CameraPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<CameraCubit>(
      create: (_) => CameraCubit()..start(),
      child: const _CameraView(),
    );
  }
}

class _CameraView extends StatefulWidget {
  const _CameraView();

  @override
  State<_CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends State<_CameraView> with WidgetsBindingObserver {
  /// Whether the filter strip is expanded. This is presentation-only — the cubit
  /// tracks which look is *selected*, not whether the drawer showing them is open.
  bool _isTrayOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraCubit cubit = context.read<CameraCubit>();
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        unawaited(cubit.releaseCamera());
      case AppLifecycleState.resumed:
        // Only reopen if this screen is the one the user is looking at. Coming
        // back to the app while playback is on top must not start the sensor
        // behind it; that route restores the camera itself when it is popped.
        if (ModalRoute.of(context)?.isCurrent ?? true) {
          unawaited(cubit.restoreCamera());
        }
      case AppLifecycleState.inactive:
        // Deliberately ignored. `inactive` also fires for transient interruptions
        // such as the permission sheet sliding up, and tearing the camera down for
        // those would fight the very request that triggered them.
        break;
    }
  }

  /// Pushes [page] over the capture screen, releasing the camera for as long as it
  /// is covered.
  ///
  /// The sensor is a shared resource and playback runs a decoder of its own, so
  /// keeping the preview alive behind another full-screen route wastes power for a
  /// picture nobody can see.
  Future<void> _openOverCamera(BuildContext context, Widget page) async {
    final CameraCubit cubit = context.read<CameraCubit>();
    final NavigatorState navigator = Navigator.of(context);

    // Push first, release second. Releasing the camera puts this screen back into
    // its loading state, and doing that before the route is on top would flash a
    // spinner over the preview on the way out.
    final Future<void> untilPopped = navigator.push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
    await cubit.releaseCamera();
    await untilPopped;

    if (!mounted) return;
    await cubit.restoreCamera();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: BlocConsumer<CameraCubit, CameraState>(
        listenWhen: (CameraState previous, CameraState current) =>
            previous.notice != current.notice ||
            previous.lastRecording != current.lastRecording,
        listener: _handleStateSideEffects,
        builder: (BuildContext context, CameraState state) => _buildBody(context, state),
      ),
    );
  }

  /// Turns one-off state into the things that are not rebuilds: a snackbar, and a
  /// push onto the navigator.
  void _handleStateSideEffects(BuildContext context, CameraState state) {
    final CameraCubit cubit = context.read<CameraCubit>();

    final String? notice = state.notice;
    if (notice != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(notice)));
      cubit.clearNotice();
    }

    final Recording? recording = state.lastRecording;
    if (recording != null) {
      // Cleared before navigating, so returning to this screen cannot push the
      // same clip a second time.
      cubit.clearLastRecording();
      unawaited(_openOverCamera(context, VideoPreviewPage(recording: recording)));
    }
  }

  Widget _buildBody(BuildContext context, CameraState state) {
    switch (state.status) {
      case CameraStatus.initial:
      case CameraStatus.requestingPermission:
      case CameraStatus.initializing:
        return const Center(
          child: CircularProgressIndicator(color: AppColors.onDarkMuted),
        );

      case CameraStatus.permissionDenied:
        return CaptureGateView(
          icon: Icons.videocam_off_outlined,
          title: 'Camera access needed',
          message:
              'This app records video, so it needs the camera and the microphone. '
              'Nothing is uploaded — clips stay on this device.',
          primaryLabel: 'Allow access',
          onPrimary: context.read<CameraCubit>().start,
        );

      case CameraStatus.permissionPermanentlyDenied:
        return CaptureGateView(
          icon: Icons.lock_outline,
          title: 'Access is blocked',
          message:
              'Camera and microphone access has been turned off for this app. '
              'You can switch it back on in system settings.',
          primaryLabel: 'Open settings',
          onPrimary: context.read<CameraCubit>().openSystemSettings,
          secondaryLabel: 'Check again',
          onSecondary: context.read<CameraCubit>().start,
        );

      case CameraStatus.failure:
        return CaptureGateView(
          icon: Icons.error_outline,
          title: 'The camera could not start',
          message: state.errorMessage ?? 'Something went wrong opening the camera.',
          primaryLabel: 'Try again',
          onPrimary: context.read<CameraCubit>().start,
        );

      case CameraStatus.ready:
        return _buildCamera(context, state);
    }
  }

  Widget _buildCamera(BuildContext context, CameraState state) {
    final CameraCubit cubit = context.read<CameraCubit>();
    final controller = state.controller!;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        CameraPreviewSurface(
          controller: controller,
          filter: state.filter,
          zoom: state.zoom,
          zoomRange: state.zoomRange,
          onFocusRequested: cubit.focusAt,
          onZoomChanged: cubit.setZoom,
        ),

        // Scrims: white controls over an arbitrary scene need a gradient behind
        // them, and a gradient reads as less intrusive than opaque bars.
        const _EdgeScrim(alignment: Alignment.topCenter),
        const _EdgeScrim(alignment: Alignment.bottomCenter),

        SafeArea(
          child: Column(
            children: <Widget>[
              _buildTopBar(context, state, cubit),
              Expanded(child: _buildSideRail(state, cubit)),
              _buildBottomCluster(state, cubit),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar(BuildContext context, CameraState state, CameraCubit cubit) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SizedBox(
        height: 48,
        child: Stack(
          children: <Widget>[
            Align(
              alignment: Alignment.centerLeft,
              child: GlassIconButton(
                icon: Icons.photo_library_outlined,
                semanticLabel: 'Saved clips',
                onPressed: state.isRecording
                    ? null
                    : () => _openOverCamera(context, const GalleryPage()),
              ),
            ),
            if (state.isRecording)
              Align(
                alignment: Alignment.center,
                child: RecordingTimerBadge(elapsed: state.elapsed),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: GlassIconButton(
                icon: state.flash.isOn ? Icons.flash_on : Icons.flash_off,
                semanticLabel: state.flash.toggled.label,
                isActive: state.flash.isOn,
                onPressed: cubit.toggleFlash,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSideRail(CameraState state, CameraCubit cubit) {
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (state.canSwitchLens)
              GlassIconButton(
                icon: Icons.flip_camera_ios_outlined,
                semanticLabel: 'Switch camera',
                label: 'Flip',
                // Switching lenses restarts the sensor, which would cut the clip
                // in two.
                onPressed: state.isRecording ? null : cubit.switchLens,
              ),
            const SizedBox(height: 18),
            GlassIconButton(
              icon: Icons.auto_awesome_outlined,
              semanticLabel: _isTrayOpen ? 'Hide filters' : 'Show filters',
              label: 'Filters',
              isActive: _isTrayOpen || state.filter != FilterPresets.original,
              onPressed: () => setState(() => _isTrayOpen = !_isTrayOpen),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomCluster(CameraState state, CameraCubit cubit) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (state.canZoom)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: ZoomControl(
              range: state.zoomRange,
              value: state.zoom,
              onChanged: cubit.setZoom,
            ),
          ),

        // The tray and the selected-look caption occupy the same slot: the caption
        // is what tells the user a filter is active once the tray is put away.
        AnimatedSize(
          duration: AppTheme.quickTransition,
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomCenter,
          child: _isTrayOpen
              ? FilterTray(
                  presets: FilterPresets.all,
                  selected: state.filter,
                  onSelected: cubit.selectFilter,
                )
              : _SelectedFilterCaption(filter: state.filter),
        ),

        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 24),
          child: RecordButton(
            isRecording: state.isRecording,
            isBusy: state.isBusy,
            progress: state.recordingProgress,
            onPressed: cubit.toggleRecording,
          ),
        ),
      ],
    );
  }
}

/// Caption naming the active look, hidden when that look is the neutral one.
class _SelectedFilterCaption extends StatelessWidget {
  const _SelectedFilterCaption({required this.filter});

  final FilterPreset filter;

  @override
  Widget build(BuildContext context) {
    if (filter == FilterPresets.original) return const SizedBox(height: 8);

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: Text(
        filter.label,
        style: const TextStyle(
          color: AppColors.onDark,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
          shadows: <Shadow>[Shadow(color: Colors.black54, blurRadius: 6)],
        ),
      ),
    );
  }
}

/// A soft vertical gradient at the top or bottom edge, so white controls stay
/// legible over a bright preview.
class _EdgeScrim extends StatelessWidget {
  const _EdgeScrim({required this.alignment});

  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final bool isTop = alignment == Alignment.topCenter;
    return IgnorePointer(
      child: Align(
        alignment: alignment,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return Container(
              // Proportional rather than fixed, so the scrim covers the control
              // clusters on a short phone and a tall tablet alike.
              height: constraints.maxHeight * (isTop ? 0.18 : 0.3),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: isTop ? Alignment.topCenter : Alignment.bottomCenter,
                  end: isTop ? Alignment.bottomCenter : Alignment.topCenter,
                  colors: <Color>[
                    Colors.black.withValues(alpha: 0.45),
                    Colors.transparent,
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
