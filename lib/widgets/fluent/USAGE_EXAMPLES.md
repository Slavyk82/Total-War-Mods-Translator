# Fluent Widgets - Usage Examples

This document provides complete, copy-paste ready examples for using Fluent Design components in the TWMT application.

## 📋 Table of Contents

1. [Basic Dialog with Buttons](#basic-dialog-with-buttons)
2. [Form with Action Buttons](#form-with-action-buttons)
3. [Toolbar with Icon Buttons](#toolbar-with-icon-buttons)
4. [List Item Actions](#list-item-actions)
5. [Toast Notifications](#toast-notifications)
6. [Complete Screen Example](#complete-screen-example)

---

## Basic Dialog with Buttons

### Before (Material)

```dart
// ❌ Material Design
showDialog(
  context: context,
  builder: (context) => AlertDialog(
    title: Text('Confirm Delete'),
    content: Text('Are you sure you want to delete this item?'),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text('Cancel'),
      ),
      ElevatedButton(
        onPressed: () {
          _performDelete();
          Navigator.pop(context);
        },
        child: Text('Delete'),
      ),
    ],
  ),
);
```

### After (Fluent)

```dart
// ✅ Fluent Design
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

showDialog(
  context: context,
  builder: (context) => AlertDialog(
    title: Text('Confirm Delete'),
    content: Text('Are you sure you want to delete this item?'),
    actions: [
      FluentTextButton(
        onPressed: () => Navigator.pop(context),
        child: Text('Cancel'),
      ),
      FluentButton(
        onPressed: () {
          _performDelete();
          Navigator.pop(context);
        },
        icon: Icon(FluentIcons.delete_24_regular),
        child: Text('Delete'),
      ),
    ],
  ),
);
```

---

## Form with Action Buttons

### Before (Material)

```dart
// ❌ Material Design
Row(
  mainAxisAlignment: MainAxisAlignment.end,
  children: [
    OutlinedButton(
      onPressed: _resetForm,
      child: Text('Reset'),
    ),
    SizedBox(width: 8),
    TextButton(
      onPressed: () => Navigator.pop(context),
      child: Text('Cancel'),
    ),
    SizedBox(width: 8),
    ElevatedButton(
      onPressed: _saveForm,
      child: Text('Save'),
    ),
  ],
)
```

### After (Fluent)

```dart
// ✅ Fluent Design
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

Row(
  mainAxisAlignment: MainAxisAlignment.end,
  children: [
    FluentOutlinedButton(
      onPressed: _resetForm,
      icon: Icon(FluentIcons.arrow_reset_24_regular),
      child: Text('Reset'),
    ),
    SizedBox(width: 8),
    FluentTextButton(
      onPressed: () => Navigator.pop(context),
      child: Text('Cancel'),
    ),
    SizedBox(width: 8),
    FluentButton(
      onPressed: _saveForm,
      icon: Icon(FluentIcons.save_24_regular),
      child: Text('Save'),
    ),
  ],
)
```

---

## Toolbar with Icon Buttons

### Before (Material)

```dart
// ❌ Material Design
Row(
  children: [
    IconButton(
      icon: Icon(Icons.add),
      onPressed: _addItem,
      tooltip: 'Add',
    ),
    IconButton(
      icon: Icon(Icons.edit),
      onPressed: _editItem,
      tooltip: 'Edit',
    ),
    IconButton(
      icon: Icon(Icons.delete),
      onPressed: _deleteItem,
      tooltip: 'Delete',
    ),
    IconButton(
      icon: Icon(Icons.refresh),
      onPressed: _refreshList,
      tooltip: 'Refresh',
    ),
  ],
)
```

### After (Fluent)

```dart
// ✅ Fluent Design
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

Row(
  children: [
    FluentIconButton(
      icon: Icon(FluentIcons.add_24_regular),
      onPressed: _addItem,
      tooltip: 'Add',
    ),
    SizedBox(width: 4),
    FluentIconButton(
      icon: Icon(FluentIcons.edit_24_regular),
      onPressed: _editItem,
      tooltip: 'Edit',
    ),
    SizedBox(width: 4),
    FluentIconButton(
      icon: Icon(FluentIcons.delete_24_regular),
      onPressed: _deleteItem,
      tooltip: 'Delete',
    ),
    SizedBox(width: 4),
    FluentIconButton(
      icon: Icon(FluentIcons.arrow_clockwise_24_regular),
      onPressed: _refreshList,
      tooltip: 'Refresh',
    ),
  ],
)
```

---

## List Item Actions

### Before (Material)

```dart
// ❌ Material Design
ListTile(
  title: Text(item.name),
  subtitle: Text(item.description),
  trailing: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        icon: Icon(Icons.edit),
        onPressed: () => _editItem(item),
      ),
      IconButton(
        icon: Icon(Icons.delete),
        onPressed: () => _deleteItem(item),
      ),
    ],
  ),
)
```

### After (Fluent)

```dart
// ✅ Fluent Design
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

ListTile(
  title: Text(item.name),
  subtitle: Text(item.description),
  trailing: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      FluentIconButton(
        icon: Icon(FluentIcons.edit_24_regular),
        onPressed: () => _editItem(item),
        tooltip: 'Edit',
        size: 28,
        iconSize: 18,
      ),
      SizedBox(width: 4),
      FluentIconButton(
        icon: Icon(FluentIcons.delete_24_regular),
        onPressed: () => _deleteItem(item),
        tooltip: 'Delete',
        size: 28,
        iconSize: 18,
      ),
    ],
  ),
)
```

---

## Toast Notifications

### Before (Material)

```dart
// ❌ Material Design
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Text('Item saved successfully'),
    action: SnackBarAction(
      label: 'Undo',
      onPressed: _undoSave,
    ),
  ),
);

ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Text('Error: Failed to save item'),
    backgroundColor: Colors.red,
  ),
);
```

### After (Fluent)

```dart
// ✅ Fluent Design
import 'package:twmt/widgets/fluent/fluent_widgets.dart';

// Success notification
FluentToast.success(context, 'Item saved successfully');

// Error notification
FluentToast.error(context, 'Failed to save item');

// Warning notification
FluentToast.warning(context, 'Please review your input');

// Info notification
FluentToast.info(context, 'Processing in background');

// With action button
FluentToast.show(
  context: context,
  message: 'Item deleted',
  type: FluentToastType.success,
  actionLabel: 'Undo',
  onActionPressed: _undoDelete,
);

// Custom duration
FluentToast.show(
  context: context,
  message: 'Upload complete',
  type: FluentToastType.success,
  duration: Duration(seconds: 2),
);
```

---

## Complete Screen Example

Here's a complete screen implementation showing all Fluent components working together:

```dart
import 'package:flutter/material.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

class ItemManagementScreen extends StatefulWidget {
  const ItemManagementScreen({super.key});

  @override
  State<ItemManagementScreen> createState() => _ItemManagementScreenState();
}

class _ItemManagementScreenState extends State<ItemManagementScreen> {
  final List<Item> _items = [];
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Item Management'),
        actions: [
          // Toolbar with icon buttons
          FluentIconButton(
            icon: Icon(FluentIcons.add_24_regular),
            onPressed: _showAddDialog,
            tooltip: 'Add Item',
          ),
          SizedBox(width: 4),
          FluentIconButton(
            icon: Icon(FluentIcons.arrow_clockwise_24_regular),
            onPressed: _refreshItems,
            tooltip: 'Refresh',
          ),
          SizedBox(width: 4),
          FluentIconButton(
            icon: Icon(FluentIcons.filter_24_regular),
            onPressed: _showFilterDialog,
            tooltip: 'Filter',
          ),
          SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          // Action bar
          Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                FluentOutlinedButton(
                  onPressed: _applyFilters,
                  icon: Icon(FluentIcons.filter_24_regular),
                  child: Text('Apply Filters'),
                ),
                SizedBox(width: 8),
                FluentTextButton(
                  onPressed: _clearFilters,
                  child: Text('Clear All'),
                ),
                Spacer(),
                FluentButton(
                  onPressed: _exportItems,
                  icon: Icon(FluentIcons.arrow_download_24_regular),
                  child: Text('Export'),
                ),
              ],
            ),
          ),

          // List of items
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      return ListTile(
                        title: Text(item.name),
                        subtitle: Text(item.description),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FluentIconButton(
                              icon: Icon(FluentIcons.edit_24_regular),
                              onPressed: () => _editItem(item),
                              tooltip: 'Edit',
                              size: 28,
                              iconSize: 18,
                            ),
                            SizedBox(width: 4),
                            FluentIconButton(
                              icon: Icon(FluentIcons.delete_24_regular),
                              onPressed: () => _confirmDelete(item),
                              tooltip: 'Delete',
                              size: 28,
                              iconSize: 18,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _showAddDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add Item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: InputDecoration(labelText: 'Name'),
            ),
            SizedBox(height: 16),
            TextField(
              decoration: InputDecoration(labelText: 'Description'),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          FluentTextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          FluentButton(
            onPressed: () {
              _saveNewItem();
              Navigator.pop(context);
            },
            icon: Icon(FluentIcons.save_24_regular),
            child: Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(Item item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirm Delete'),
        content: Text('Are you sure you want to delete "${item.name}"?'),
        actions: [
          FluentTextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          FluentButton(
            onPressed: () {
              _deleteItem(item);
              Navigator.pop(context);
            },
            icon: Icon(FluentIcons.delete_24_regular),
            child: Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshItems() async {
    setState(() => _isLoading = true);
    try {
      // Simulate API call
      await Future.delayed(Duration(seconds: 1));
      FluentToast.success(context, 'Items refreshed');
    } catch (e) {
      FluentToast.error(context, 'Failed to refresh items');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _saveNewItem() {
    try {
      // Save logic here
      FluentToast.success(context, 'Item saved successfully');
    } catch (e) {
      FluentToast.error(context, 'Failed to save item');
    }
  }

  void _deleteItem(Item item) {
    try {
      setState(() => _items.remove(item));
      FluentToast.show(
        context: context,
        message: 'Item deleted',
        type: FluentToastType.success,
        actionLabel: 'Undo',
        onActionPressed: () {
          setState(() => _items.add(item));
        },
      );
    } catch (e) {
      FluentToast.error(context, 'Failed to delete item');
    }
  }

  void _editItem(Item item) {
    // Edit logic here
  }

  void _showFilterDialog() {
    // Filter dialog here
  }

  void _applyFilters() {
    FluentToast.info(context, 'Filters applied');
  }

  void _clearFilters() {
    FluentToast.info(context, 'Filters cleared');
  }

  void _exportItems() async {
    try {
      FluentToast.info(context, 'Exporting items...');
      await Future.delayed(Duration(seconds: 2));
      FluentToast.success(context, 'Export complete');
    } catch (e) {
      FluentToast.error(context, 'Export failed');
    }
  }
}

class Item {
  final String name;
  final String description;

  Item({required this.name, required this.description});
}
```

---

## 🎨 Styling Tips

### Custom Colors

```dart
// Primary button with custom colors
FluentButton(
  onPressed: _save,
  backgroundColor: Color(0xFF0078D4), // Windows blue
  foregroundColor: Colors.white,
  child: Text('Save'),
)

// Danger button (red)
FluentButton(
  onPressed: _delete,
  backgroundColor: Color(0xFFD13438), // Error red
  foregroundColor: Colors.white,
  icon: Icon(FluentIcons.delete_24_regular),
  child: Text('Delete'),
)

// Success button (green)
FluentButton(
  onPressed: _confirm,
  backgroundColor: Color(0xFF107C10), // Success green
  foregroundColor: Colors.white,
  child: Text('Confirm'),
)
```

### Custom Sizes

```dart
// Large button
FluentButton(
  onPressed: _action,
  minWidth: 120,
  minHeight: 40,
  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
  child: Text('Large Button'),
)

// Compact button
FluentButton(
  onPressed: _action,
  minWidth: 60,
  minHeight: 24,
  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
  borderRadius: 3,
  child: Text('Small', style: TextStyle(fontSize: 12)),
)

// Icon button sizes
FluentIconButton(
  icon: Icon(FluentIcons.settings_24_regular),
  onPressed: _settings,
  size: 40, // Larger touch target
  iconSize: 24, // Larger icon
)
```

---

## 🔄 Common Patterns

### Loading State

```dart
FluentButton(
  onPressed: _isLoading ? null : _performAction, // Disabled when loading
  child: _isLoading
      ? SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      : Text('Submit'),
)
```

### Conditional Buttons

```dart
if (_canSave)
  FluentButton(
    onPressed: _save,
    icon: Icon(FluentIcons.save_24_regular),
    child: Text('Save'),
  )
else
  FluentTextButton(
    onPressed: null, // Disabled
    child: Text('Save'),
  ),
```

### Button Groups

```dart
Row(
  mainAxisAlignment: MainAxisAlignment.spaceBetween,
  children: [
    // Left group
    Row(
      children: [
        FluentTextButton(
          onPressed: _action1,
          child: Text('Action 1'),
        ),
        SizedBox(width: 8),
        FluentTextButton(
          onPressed: _action2,
          child: Text('Action 2'),
        ),
      ],
    ),
    // Right group
    Row(
      children: [
        FluentTextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel'),
        ),
        SizedBox(width: 8),
        FluentButton(
          onPressed: _confirm,
          child: Text('Confirm'),
        ),
      ],
    ),
  ],
)
```

---

## 📱 Accessibility

All Fluent components support:

- **Keyboard Navigation**: Tab, Enter, Space, Esc
- **Screen Readers**: Windows Narrator compatible
- **High Contrast**: Respects system theme
- **Tooltips**: Automatic on icon buttons
- **Focus Indicators**: 2px border on focus

```dart
// Ensure tooltips for icon buttons
FluentIconButton(
  icon: Icon(FluentIcons.delete_24_regular),
  onPressed: _delete,
  tooltip: 'Delete item', // Required for accessibility
)
```

---

## 🎯 Best Practices

1. **Use appropriate button types:**
   - `FluentButton` for primary actions
   - `FluentTextButton` for secondary/dialog actions
   - `FluentIconButton` for toolbar/compact actions
   - `FluentOutlinedButton` for alternative primary actions

2. **Always provide tooltips on icon buttons:**
   ```dart
   FluentIconButton(
     icon: Icon(FluentIcons.save_24_regular),
     onPressed: _save,
     tooltip: 'Save changes', // Always include
   )
   ```

3. **Use icons from `fluentui_system_icons`:**
   ```dart
   import 'package:fluentui_system_icons/fluentui_system_icons.dart';
   Icon(FluentIcons.document_24_regular) // ✅ Correct
   Icon(Icons.document) // ❌ Wrong (Material icon)
   ```

4. **Maintain consistent spacing:**
   ```dart
   SizedBox(width: 8) // Between buttons
   SizedBox(width: 4) // Between icon buttons
   ```

5. **Show appropriate toast types:**
   ```dart
   FluentToast.success(context, msg) // For successful operations
   FluentToast.error(context, msg)   // For failures
   FluentToast.warning(context, msg) // For warnings
   FluentToast.info(context, msg)    // For information
   ```

---

**Last Updated:** 2025-11-16
**Maintained by:** TWMT Development Team
