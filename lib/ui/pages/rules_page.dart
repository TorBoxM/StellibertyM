import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stelliberty/clash/providers/rules_provider.dart';
import 'package:stelliberty/clash/providers/clash_provider.dart';
import 'package:stelliberty/i18n/i18n.dart';
import 'package:stelliberty/ui/constants/spacing.dart';
import 'package:stelliberty/ui/widgets/modern_tooltip.dart';
import 'package:stelliberty/ui/widgets/rules/rule_card.dart';
import 'package:stelliberty/ui/widgets/subscription/provider_viewer_dialog.dart';

class _RulesListSpacing {
  _RulesListSpacing._();

  static const gridLeftEdge = 16.0;
  static const gridTopEdge = 16.0;
  static const gridRightEdge =
      16.0 - SpacingConstants.scrollbarRightCompensation;
  static const gridBottomEdge = 10.0;
  static const cardColumnSpacing = 16.0;
  static const cardRowSpacing = 16.0;

  static const gridPadding = EdgeInsets.fromLTRB(
    gridLeftEdge,
    gridTopEdge,
    gridRightEdge,
    gridBottomEdge,
  );
}

class RulesPage extends StatefulWidget {
  const RulesPage({super.key});

  @override
  State<RulesPage> createState() => _RulesPageState();
}

class _RulesPageState extends State<RulesPage> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  bool _isSyncingSearchController = false;

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RulesProvider>(
      builder: (context, provider, child) {
        _syncSearchController(provider.searchKeyword);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildControlBar(context, provider),
            const Divider(height: 1, thickness: 1),
            Expanded(
              child: Padding(
                padding: SpacingConstants.scrollbarPadding,
                child: _buildRulesList(context, provider),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildControlBar(BuildContext context, RulesProvider provider) {
    final trans = context.translate;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.rule_rounded,
                  size: 16,
                  color: colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 6),
                Text(
                  trans.rules.total_rules.replaceAll(
                    '{count}',
                    provider.rules.length.toString(),
                  ),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: () => ProviderViewerDialog.show(context),
            icon: const Icon(Icons.storage_rounded, size: 18),
            label: Text(trans.rules.providers),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 38,
              child: TextField(
                controller: _searchController,
                onChanged: (value) {
                  if (_isSyncingSearchController) return;
                  provider.setSearchKeyword(value);
                },
                decoration: InputDecoration(
                  hintText: trans.rules.search_placeholder,
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 0,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest,
                ),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ModernIconTooltip(
                message: trans.common.refresh,
                icon: provider.isRefreshing
                    ? Icons.hourglass_top_rounded
                    : Icons.refresh_rounded,
                onPressed: provider.isRefreshing
                    ? null
                    : () => provider.refreshRules(showLoading: false),
                iconSize: 20,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRulesList(BuildContext context, RulesProvider provider) {
    final trans = context.translate;
    final isCoreRunning = context.select<ClashProvider, bool>(
      (p) => p.isCoreRunning,
    );

    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.errorMessage != null) {
      return Center(
        child: Text(
          provider.errorMessage!,
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      );
    }

    if (!isCoreRunning) {
      return Center(child: Text(trans.rules.core_not_running));
    }

    final rules = provider.rules;
    if (rules.isEmpty) {
      return Center(child: Text(trans.rules.empty));
    }

    return Scrollbar(
      controller: _scrollController,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final crossAxisCount = constraints.maxWidth >= 800 ? 2 : 1;
          final mainAxisExtent = crossAxisCount >= 2 ? 96.0 : 88.0;

          return GridView.builder(
            controller: _scrollController,
            padding: _RulesListSpacing.gridPadding,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: _RulesListSpacing.cardColumnSpacing,
              mainAxisSpacing: _RulesListSpacing.cardRowSpacing,
              mainAxisExtent: mainAxisExtent,
            ),
            itemCount: rules.length,
            itemBuilder: (context, index) {
              return RuleCard(index: index + 1, rule: rules[index]);
            },
          );
        },
      ),
    );
  }

  void _syncSearchController(String searchKeyword) {
    if (_searchController.text == searchKeyword) return;

    _isSyncingSearchController = true;
    _searchController.value = TextEditingValue(
      text: searchKeyword,
      selection: TextSelection.collapsed(offset: searchKeyword.length),
    );
    _isSyncingSearchController = false;
  }
}
