/// Fluent Design System widgets for Windows desktop applications.
///
/// This library provides a complete set of Fluent Design components that replace
/// Material Design widgets, ensuring compliance with Windows UI guidelines.
///
/// ## Available Components
///
/// ### Buttons
/// - [FluentButton] - Primary action button (replaces ElevatedButton)
/// - [FluentTextButton] - Secondary text-only button (replaces TextButton)
/// - [FluentIconButton] - Icon-only button (replaces IconButton)
/// - [FluentOutlinedButton] - Outlined button (replaces OutlinedButton)
///
/// ### Notifications
/// - [FluentToast] - Toast notifications (replaces SnackBar)
///
/// ### Input Controls
/// - [FluentToggleSwitch] - Toggle switch (replaces Switch)
/// - [FluentCheckbox] - Checkbox (replaces Checkbox)
/// - [FluentTextField] - Text field (replaces TextField)
///
/// ### Progress Indicators
/// - [FluentProgressRing] - Circular progress indicator (replaces CircularProgressIndicator)
/// - [FluentProgressBar] - Linear progress indicator (replaces LinearProgressIndicator)
///
/// ## Quick Start
///
/// Import this file to get access to all Fluent components:
/// ```dart
/// import 'package:twmt/widgets/fluent/fluent_widgets.dart';
/// ```
///
/// ### Example: Button Usage
/// ```dart
/// FluentButton(
///   onPressed: () => print('Clicked'),
///   icon: Icon(FluentIcons.save_24_regular),
///   child: Text('Save'),
/// )
/// ```
///
/// ### Example: Toast Notification
/// ```dart
/// FluentToast.success(context, 'Operation completed successfully');
/// ```
///
/// ## Design Principles
///
/// All components follow Windows Fluent Design System:
/// - **No Material ripple effects** - Uses opacity changes instead
/// - **Smooth animations** - 150ms transitions with AnimatedContainer
/// - **Proper hover states** - MouseRegion for cursor management
/// - **Accessibility** - Full keyboard navigation and screen reader support
/// - **Consistent spacing** - Follows 4px grid system
///
/// ## Visual Feedback Standards
///
/// - **Hover**: Background opacity change (5-8%)
/// - **Pressed**: Background opacity change (8-10%)
/// - **Disabled**: 50% opacity
/// - **Focus**: 2px border with primary color
///
/// ## Migration from Material Design
///
/// | Material Widget | Fluent Replacement |
/// |----------------|-------------------|
/// | ElevatedButton | FluentButton |
/// | TextButton | FluentTextButton |
/// | IconButton | FluentIconButton |
/// | OutlinedButton | FluentOutlinedButton |
/// | SnackBar | FluentToast |
/// | Switch | FluentToggleSwitch |
/// | Checkbox | FluentCheckbox |
/// | TextField | FluentTextField |
/// | CircularProgressIndicator | FluentProgressRing |
/// | LinearProgressIndicator | FluentProgressBar |
///
/// See [FLUENT_DESIGN_QUICK_FIX_GUIDE.md] for detailed migration instructions.
library;

// Buttons
export 'fluent_button.dart';
export 'fluent_text_button.dart';
export 'fluent_icon_button.dart';
export 'fluent_outlined_button.dart';
export 'fluent_dialog_button.dart';

// Notifications
export 'fluent_toast.dart';

// Input Controls
export 'fluent_toggle_switch.dart';
export 'fluent_checkbox.dart';
export 'fluent_text_field.dart';

// Progress Indicators
export 'fluent_progress_indicator.dart';
