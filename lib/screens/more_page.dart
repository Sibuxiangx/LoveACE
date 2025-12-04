import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/more_provider.dart';
import '../providers/pinned_features_provider.dart';
import '../widgets/adaptive_sliver_app_bar.dart';
import '../widgets/glass_card.dart';
import '../widgets/empty_state.dart';

/// 更多功能页面
///
/// 显示所有可用的功能入口列表
/// 支持点击导航到对应功能页面
/// 满足需求: 1.4, 2.1, 2.2, 2.3, 2.4, 2.5, 10.1, 10.2, 10.5
class MorePage extends StatefulWidget {
  const MorePage({super.key});

  @override
  State<MorePage> createState() => _MorePageState();
}

class _MorePageState extends State<MorePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Consumer<MoreProvider>(
        builder: (context, provider, child) {
          // 功能列表为空时显示空状态
          if (provider.state == MoreState.loaded && provider.features.isEmpty) {
            return CustomScrollView(
              slivers: [
                AdaptiveSliverAppBar(title: '更多功能'),
                SliverFillRemaining(
                  child: EmptyState.noData(
                    title: '暂无功能',
                    description: '当前没有可用的功能',
                  ),
                ),
              ],
            );
          }

          // 显示功能列表
          return Consumer<PinnedFeaturesProvider>(
            builder: (context, pinnedProvider, child) {
              return CustomScrollView(
                slivers: [
                  AdaptiveSliverAppBar(title: '更多功能'),
                  SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final feature = provider.features[index];
                        final isPinned = pinnedProvider.isPinned(feature.id);

                        return GlassCard(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(0),
                          child: ListTile(
                            leading: Icon(
                              feature.icon,
                              size: 28,
                              color:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).primaryColor,
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    feature.title,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                if (isPinned)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? Theme.of(context)
                                                .colorScheme
                                                .primary
                                                .withValues(alpha: 0.25)
                                          : Theme.of(context).primaryColor
                                                .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.push_pin,
                                          size: 12,
                                          color:
                                              Theme.of(context).brightness ==
                                                  Brightness.dark
                                              ? Theme.of(
                                                  context,
                                                ).colorScheme.primary
                                              : Theme.of(context).primaryColor,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '已固定',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color:
                                                Theme.of(context).brightness ==
                                                    Brightness.dark
                                                ? Theme.of(
                                                    context,
                                                  ).colorScheme.primary
                                                : Theme.of(
                                                    context,
                                                  ).primaryColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Text(
                              feature.description,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            trailing: Icon(
                              Icons.chevron_right,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                            onTap: () {
                              provider.navigateToFeature(context, feature.id);
                            },
                          ),
                        );
                      }, childCount: provider.features.length),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
