import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class CameraFeedView extends StatelessWidget {
  final CameraController controller;
  final List<Widget> overlays;

  const CameraFeedView({
    super.key,
    required this.controller,
    this.overlays = const [],
  });

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final previewSize = controller.value.previewSize!;
        // previewSize is in landscape orientation (width > height),
        // so we flip it for portrait display.
        final previewAspectRatio = previewSize.height / previewSize.width;

        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.center,
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxWidth / previewAspectRatio,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    controller.buildPreview(),
                    ...overlays,
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
