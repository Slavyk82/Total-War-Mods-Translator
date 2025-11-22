import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Fluent Design page transitions for Windows Desktop
///
/// Following CLAUDE.md principles:
/// - Subtle, direct, quick (150-200ms)
/// - NO Material ripple effects
/// - Rectangular fades (not circular)
class FluentPageTransitions {
  /// Fade transition for Fluent Design (150ms)
  static CustomTransitionPage<T> fadeTransition<T>({
    required Widget child,
    required GoRouterState state,
    Duration duration = const Duration(milliseconds: 150),
  }) {
    return CustomTransitionPage<T>(
      key: state.pageKey,
      child: child,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurveTween(curve: Curves.easeOut).animate(animation),
          child: child,
        );
      },
      transitionDuration: duration,
    );
  }

  /// Slide from right transition (for detail views)
  static CustomTransitionPage<T> slideFromRightTransition<T>({
    required Widget child,
    required GoRouterState state,
    Duration duration = const Duration(milliseconds: 200),
  }) {
    return CustomTransitionPage<T>(
      key: state.pageKey,
      child: child,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(0.3, 0.0); // Subtle slide (30% from right)
        const end = Offset.zero;
        final tween = Tween(begin: begin, end: end);
        final offsetAnimation = animation.drive(tween.chain(
          CurveTween(curve: Curves.easeOut),
        ));

        // Combine slide with fade for smooth effect
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: offsetAnimation,
            child: child,
          ),
        );
      },
      transitionDuration: duration,
    );
  }

  /// No transition (instant)
  static CustomTransitionPage<T> noTransition<T>({
    required Widget child,
    required GoRouterState state,
  }) {
    return CustomTransitionPage<T>(
      key: state.pageKey,
      child: child,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return child;
      },
      transitionDuration: Duration.zero,
    );
  }

  /// Default transition based on navigation type
  static Page<T> defaultTransition<T>({
    required Widget child,
    required GoRouterState state,
    bool isDetailView = false,
  }) {
    if (isDetailView) {
      return slideFromRightTransition<T>(child: child, state: state);
    }
    return fadeTransition<T>(child: child, state: state);
  }
}
