import 'package:flutter/material.dart';
import 'package:twmt/widgets/layouts/fluent_scaffold.dart';
import '../widgets/welcome_card.dart';
import '../widgets/stats_cards.dart';
import '../widgets/recent_projects_card.dart';

/// Home/Dashboard screen
/// Shows overview of recent activity and statistics
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FluentScaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome Card
            const WelcomeCard(),
            const SizedBox(height: 24),

            // Statistics Cards
            const StatsCards(),
            const SizedBox(height: 24),

            // Recent Projects
            const RecentProjectsCard(),
          ],
        ),
      ),
    );
  }
}
