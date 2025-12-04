import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

/// App background widget with blur effect
///
/// Displays custom background image with configurable blur
/// Falls back to solid color when no background is set
class AppBackground extends StatelessWidget {
  final Widget child;

  const AppBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        final backgroundPath = themeProvider.backgroundPath;
        final blur = themeProvider.backgroundBlur;

        if (backgroundPath == null) {
          // No background, use default
          return child;
        }

        return Stack(
          children: [
            // Background image
            Positioned.fill(child: _buildBackground(backgroundPath, blur)),
            // Content
            child,
          ],
        );
      },
    );
  }

  /// Build background with blur effect
  Widget _buildBackground(String imagePath, double blur) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Image
        Image.file(
          File(imagePath),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            // If image fails to load, show nothing
            return const SizedBox.shrink();
          },
        ),
        // Blur effect
        if (blur > 0)
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: Container(color: Colors.transparent),
          ),
        // Overlay to ensure content readability
        Container(color: Colors.black.withValues(alpha: 0.1)),
      ],
    );
  }
}

/// Scaffold with app background
///
/// Wraps standard Scaffold with background support
class BackgroundScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget? body;
  final Widget? floatingActionButton;
  final Widget? drawer;
  final Widget? endDrawer;
  final Widget? bottomNavigationBar;
  final Color? backgroundColor;

  const BackgroundScaffold({
    super.key,
    this.appBar,
    this.body,
    this.floatingActionButton,
    this.drawer,
    this.endDrawer,
    this.bottomNavigationBar,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        final hasBackground = themeProvider.backgroundPath != null;

        return Scaffold(
          appBar: appBar,
          body: hasBackground
              ? AppBackground(
                  child: Container(color: Colors.transparent, child: body),
                )
              : body,
          floatingActionButton: floatingActionButton,
          drawer: drawer,
          endDrawer: endDrawer,
          bottomNavigationBar: bottomNavigationBar,
          backgroundColor: hasBackground ? Colors.transparent : backgroundColor,
        );
      },
    );
  }
}
