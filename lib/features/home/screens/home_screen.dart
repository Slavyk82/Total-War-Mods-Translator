import 'package:flutter/material.dart';
import 'package:twmt/widgets/layouts/fluent_scaffold.dart';
import '../widgets/welcome_card.dart';
import '../widgets/stats_cards.dart';
import '../widgets/recent_projects_card.dart';
import '../widgets/quick_actions_card.dart';

/// Home/Dashboard screen
/// Shows overview of recent activity, quick actions, statistics
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

            // Two-column layout for Recent Projects and Quick Actions
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Recent Projects (takes 2/3 of width)
                const Expanded(
                  flex: 2,
                  child: RecentProjectsCard(),
                ),
                const SizedBox(width: 24),

                // Quick Actions (takes 1/3 of width)
                const Expanded(
                  flex: 1,
                  child: QuickActionsCard(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
