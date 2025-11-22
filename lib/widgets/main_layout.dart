import 'package:flutter/material.dart';
import 'package:twmt/features/mods/screens/mods_screen.dart';
import 'package:twmt/features/projects/screens/projects_screen.dart';
import 'package:twmt/features/settings/screens/settings_screen.dart';
import 'package:twmt/widgets/navigation_sidebar.dart';
import 'package:twmt/widgets/layouts/fluent_scaffold.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _selectedIndex = 0;

  static const List<Widget> _screens = [
    ModsScreen(),
    ProjectsScreen(),
    SettingsScreen(),
  ];

  void _onItemSelected(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FluentScaffold(
      body: Row(
        children: [
          NavigationSidebar(
            selectedIndex: _selectedIndex,
            onItemSelected: _onItemSelected,
          ),
          Expanded(
            child: _screens[_selectedIndex],
          ),
        ],
      ),
    );
  }
}
