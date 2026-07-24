// lib/screens/bible_study_screen.dart
// ignore_for_file: curly_braces_in_flow_control_structures, unused_element

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pensaconnect/models/bible_models.dart';
import 'package:pensaconnect/repositories/bible_repository.dart';
import '../theme/app_style.dart';

// Add these enums to extend your models
enum DevotionCategory { daily, prayer, wisdom, encouragement, guidance }

enum StudyPlanDifficulty { beginner, intermediate, advanced }

// ---- Shared style helpers: keep category/difficulty look consistent everywhere ----
class _CategoryStyle {
  final String label;
  final IconData icon;
  final Color color;
  const _CategoryStyle(this.label, this.icon, this.color);
}

_CategoryStyle _categoryStyle(DevotionCategory category) {
  switch (category) {
    case DevotionCategory.prayer:
      return const _CategoryStyle(
        '🙏 Prayer',
        Icons.handshake,
        AppColors.roseQuartz,
      );
    case DevotionCategory.wisdom:
      return const _CategoryStyle('💡 Wisdom', Icons.lightbulb, Colors.amber);
    case DevotionCategory.encouragement:
      return const _CategoryStyle(
        '❤️ Encouragement',
        Icons.favorite,
        Colors.pink,
      );
    case DevotionCategory.guidance:
      return const _CategoryStyle('🧭 Guidance', Icons.explore, Colors.teal);
    case DevotionCategory.daily:
      return const _CategoryStyle(
        '📅 Daily',
        Icons.calendar_today,
        Colors.blue,
      );
  }
}

_CategoryStyle _difficultyStyle(StudyPlanDifficulty difficulty) {
  switch (difficulty) {
    case StudyPlanDifficulty.beginner:
      return const _CategoryStyle('🌱 Beginner', Icons.eco, Colors.green);
    case StudyPlanDifficulty.intermediate:
      return const _CategoryStyle(
        '🔥 Intermediate',
        Icons.local_fire_department,
        Colors.orange,
      );
    case StudyPlanDifficulty.advanced:
      return const _CategoryStyle('⚡ Advanced', Icons.bolt, Colors.red);
  }
}

// Colorful pill chip used across list items — light tinted background, bold colored text.
class _StyledChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StyledChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color.computeLuminance() > 0.9
              ? color
              : color.withRed((color.red * 0.7).round()),
        ),
      ),
    );
  }
}

class BibleStudyScreen extends StatefulWidget {
  const BibleStudyScreen({super.key});

  @override
  State<BibleStudyScreen> createState() => _BibleStudyScreenState();
}

class _BibleStudyScreenState extends State<BibleStudyScreen>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  late final TabController _tabController;

  final GlobalKey<_PlansListState> _plansListKey = GlobalKey();

  // Filter states
  DevotionCategory? _selectedCategory;
  StudyPlanDifficulty? _selectedDifficulty;
  DateTimeRange? _selectedDateRange;
  String _searchQuery = '';
  bool _hasCheckedForActivePlan = false;
  bool _isNavigating = false; // ✅ Prevent multiple pushes at once

  // ✅ TabBarView builds every child widget immediately (it's not lazy like
  // PageView.builder), so all three tabs used to fire their network loads
  // the instant this screen opened — Devotions, Study Plans, *and* Archive
  // all at once, even though only one tab is ever visible. Tracking which
  // tab indices have actually been viewed lets the other two stay as a
  // cheap empty placeholder (no widget, no fetch) until the user swipes or
  // taps their way to them, then they load lazily right when needed.
  final Set<int> _loadedTabs = {0};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabChange);

    // ✅ Delay logic until after first build
    //WidgetsBinding.instance.addPostFrameCallback((_) async {
    //if (!mounted || _hasCheckedForActivePlan) return;

    //await _checkAndNavigateToActivePlan();

    // _hasCheckedForActivePlan = true;
    // });
  }

  Future<void> _checkAndNavigateToActivePlan() async {
    try {
      final activePlan = await BibleRepository.getActivePlan();

      if (activePlan != null && !_isNavigating && mounted) {
        _isNavigating = true;

        // ✅ Safe navigation with guard against re-entrancy
        await context.push(
          '/bible/detail/plan/${activePlan.id}',
          extra: activePlan,
        );

        if (mounted) {
          // Reset navigation flag so user can open another plan later
          _isNavigating = false;
        }
      }
    } catch (e) {
      debugPrint('❌ Error checking active plan: $e');
    }
  }

  void _handleTabChange() {
    if (_tabController.index != _selectedIndex) {
      setState(() {
        _selectedIndex = _tabController.index;
        _loadedTabs.add(_selectedIndex);
      });
    }
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Filter Content',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                if (_selectedIndex == 0)
                  ..._buildDevotionFilters(setDialogState),
                if (_selectedIndex == 1)
                  ..._buildStudyPlanFilters(setDialogState),
                if (_selectedIndex == 2)
                  ..._buildArchiveFilters(setDialogState),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => _resetFilters(setDialogState),
              child: const Text('Reset'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              onPressed: () {
                Navigator.pop(context);
                setState(() {}); // Refresh the lists
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildDevotionFilters(StateSetter setDialogState) => [
    const Text('Category', style: TextStyle(fontWeight: FontWeight.bold)),
    const SizedBox(height: 8),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: DevotionCategory.values.map((category) {
        final style = _categoryStyle(category);
        final selected = _selectedCategory == category;
        return ChoiceChip(
          label: Text(style.label),
          selected: selected,
          selectedColor: style.color.withOpacity(0.2),
          onSelected: (_) => setDialogState(
            () => _selectedCategory = selected ? null : category,
          ),
        );
      }).toList(),
    ),
    const SizedBox(height: 16),
  ];

  List<Widget> _buildStudyPlanFilters(StateSetter setDialogState) => [
    const Text('Difficulty', style: TextStyle(fontWeight: FontWeight.bold)),
    const SizedBox(height: 8),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: StudyPlanDifficulty.values.map((difficulty) {
        final style = _difficultyStyle(difficulty);
        final selected = _selectedDifficulty == difficulty;
        return ChoiceChip(
          label: Text(style.label),
          selected: selected,
          selectedColor: style.color.withOpacity(0.2),
          onSelected: (_) => setDialogState(
            () => _selectedDifficulty = selected ? null : difficulty,
          ),
        );
      }).toList(),
    ),
  ];

  List<Widget> _buildArchiveFilters(StateSetter setDialogState) => [
    const Text('Date Range', style: TextStyle(fontWeight: FontWeight.bold)),
    const SizedBox(height: 8),
    FilledButton.icon(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      icon: const Icon(Icons.date_range),
      onPressed: () async {
        final range = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
        );
        if (range != null) {
          setDialogState(() => _selectedDateRange = range);
        }
      },
      label: Text(
        _selectedDateRange == null
            ? 'Select Date Range'
            : '${_formatDate(_selectedDateRange!.start)} - ${_formatDate(_selectedDateRange!.end)}',
      ),
    ),
  ];

  String _formatDate(DateTime date) =>
      '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';

  void _resetFilters(StateSetter setDialogState) {
    setDialogState(() {
      _selectedCategory = null;
      _selectedDifficulty = null;
      _selectedDateRange = null;
    });
  }

  bool _hasActiveFilters() {
    return _selectedCategory != null ||
        _selectedDifficulty != null ||
        _selectedDateRange != null ||
        _searchQuery.isNotEmpty;
  }

  DevotionCategory _determineCategory(Devotion devotion) {
    final content = devotion.content.toLowerCase();
    if (content.contains('pray') || content.contains('prayer'))
      return DevotionCategory.prayer;
    if (content.contains('wisdom') || content.contains('wise'))
      return DevotionCategory.wisdom;
    if (content.contains('encourage') || content.contains('hope'))
      return DevotionCategory.encouragement;
    if (content.contains('guide') || content.contains('direction'))
      return DevotionCategory.guidance;
    return DevotionCategory.daily;
  }

  StudyPlanDifficulty _determineDifficulty(StudyPlan plan) {
    final dayCount = plan.dayCount ?? 0;
    if (dayCount <= 7) return StudyPlanDifficulty.beginner;
    if (dayCount <= 21) return StudyPlanDifficulty.intermediate;
    return StudyPlanDifficulty.advanced;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight + 48),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [colorScheme.primary, colorScheme.secondary],
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: SafeArea(
            child: Column(
              children: [
                AppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  foregroundColor: Colors.white,
                  title: const Text(
                    '📖 Bible Study',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.replace('/home');
                      }
                    },
                  ),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: () => showSearch(
                        context: context,
                        delegate: _SimpleBibleSearchDelegate(),
                      ),
                    ),
                    IconButton(
                      icon: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Icon(Icons.filter_list),
                          if (_hasActiveFilters())
                            Positioned(
                              right: 0,
                              top: 0,
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: const BoxDecoration(
                                  color: Colors.pinkAccent,
                                  shape: BoxShape.circle,
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 10,
                                  minHeight: 10,
                                ),
                              ),
                            ),
                        ],
                      ),
                      onPressed: _showFilterDialog,
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
                TabBar(
                  controller: _tabController,
                  indicatorColor: Colors.white,
                  indicatorWeight: 3,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                  tabs: const [
                    Tab(text: '🙏 Devotions'),
                    Tab(text: '📚 Study Plans'),
                    Tab(text: '📦 Archive'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),

      body: TabBarView(
        controller: _tabController,
        children: [
          _loadedTabs.contains(0)
              ? _DevotionsList(
                  category: _selectedCategory,
                  searchQuery: _searchQuery,
                  determineCategory: _determineCategory,
                )
              : const SizedBox.shrink(),
          _loadedTabs.contains(1)
              ? _PlansList(
                  key: _plansListKey,
                  difficulty: _selectedDifficulty,
                  searchQuery: _searchQuery,
                  determineDifficulty: _determineDifficulty,
                )
              : const SizedBox.shrink(),
          _loadedTabs.contains(2)
              ? _ArchiveList(
                  dateRange: _selectedDateRange,
                  searchQuery: _searchQuery,
                )
              : const SizedBox.shrink(),
        ],
      ),
      floatingActionButton: _selectedIndex == 1
          ? Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                gradient: LinearGradient(
                  colors: [colorScheme.primary, colorScheme.secondary],
                ),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.primary.withOpacity(0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: FloatingActionButton.extended(
                backgroundColor: Colors.transparent,
                elevation: 0,
                onPressed: _createNewStudyPlan,
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text(
                  'New Plan',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            )
          : null,
    );
  }

  void _createNewStudyPlan() async {
    final result = await context.push<bool>('/bible/study-plan/create');

    if (result == true && mounted) {
      if (_plansListKey.currentState != null &&
          _plansListKey.currentState!.mounted) {
        await _plansListKey.currentState!._refreshPlans();
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            '🎉 Study plan created successfully!',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
    }
  }
}

// Enhanced search delegate with actual search functionality
class _SimpleBibleSearchDelegate extends SearchDelegate<String> {
  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, ''),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildSearchResults(context);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _buildSearchResults(context);
  }

  Widget _buildSearchResults(BuildContext context) {
    return FutureBuilder<Map<String, List<dynamic>>>(
      future: _performSearch(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return _ErrorState(
            message: 'Search failed: ${snapshot.error}',
            onRetry: () => _performSearch(),
          );
        }

        final results = snapshot.data ?? {'devotions': [], 'plans': []};
        final devotions = results['devotions']! as List<Devotion>;
        final plans = results['plans']! as List<StudyPlan>;
        final totalResults = devotions.length + plans.length;

        if (query.isEmpty) {
          return _buildEmptySearchState(context);
        }

        if (totalResults == 0) {
          return _EmptyState(message: 'No results found for "$query" 🔍');
        }

        return CustomScrollView(
          slivers: [
            if (devotions.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'Devotions (${devotions.length})',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                if (index < devotions.length) {
                  final devotion = devotions[index];
                  return _DevotionListItem(
                    devotion: devotion,
                    category: _determineCategory(devotion),
                  );
                }
                final planIndex = index - devotions.length;
                final plan = plans[planIndex];
                return _StudyPlanListItem(
                  plan: plan,
                  difficulty: _determineDifficulty(plan),
                );
              }, childCount: totalResults),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmptySearchState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search,
              size: 64,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              '🔎 Search Devotions & Study Plans',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Search by verse, content, title or description',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<Map<String, List<dynamic>>> _performSearch() async {
    if (query.length < 2) return {'devotions': [], 'plans': []};

    try {
      final devotions = await BibleRepository.fetchDevotions();
      final plans = await BibleRepository.fetchPlans();

      final lowerQuery = query.toLowerCase();

      final devotionResults = devotions.where(
        (devotion) =>
            devotion.verse.toLowerCase().contains(lowerQuery) ||
            devotion.content.toLowerCase().contains(lowerQuery),
      );

      final planResults = plans.where(
        (plan) =>
            plan.title.toLowerCase().contains(lowerQuery) ||
            plan.description.toLowerCase().contains(lowerQuery),
      );

      return {
        'devotions': devotionResults.toList(),
        'plans': planResults.toList(),
      };
    } catch (e) {
      throw Exception('Search failed: $e');
    }
  }

  DevotionCategory _determineCategory(Devotion devotion) {
    final content = devotion.content.toLowerCase();
    if (content.contains('pray') || content.contains('prayer'))
      return DevotionCategory.prayer;
    if (content.contains('wisdom') || content.contains('wise'))
      return DevotionCategory.wisdom;
    if (content.contains('encourage') || content.contains('hope'))
      return DevotionCategory.encouragement;
    if (content.contains('guide') || content.contains('direction'))
      return DevotionCategory.guidance;
    return DevotionCategory.daily;
  }

  StudyPlanDifficulty _determineDifficulty(StudyPlan plan) {
    final dayCount = plan.dayCount ?? 0;
    if (dayCount <= 7) return StudyPlanDifficulty.beginner;
    if (dayCount <= 21) return StudyPlanDifficulty.intermediate;
    return StudyPlanDifficulty.advanced;
  }

  @override
  String get searchFieldLabel => 'Search devotions and study plans...';
}

// Enhanced Devotions List with progress tracking
class _DevotionsList extends StatefulWidget {
  final DevotionCategory? category;
  final String searchQuery;
  final DevotionCategory Function(Devotion) determineCategory;

  const _DevotionsList({
    this.category,
    this.searchQuery = '',
    required this.determineCategory,
  });

  @override
  State<_DevotionsList> createState() => _DevotionsListState();
}

class _DevotionsListState extends State<_DevotionsList> {
  late Future<List<Devotion>> _devotionsFuture;
  final Map<int, ReadingProgress?> _progressCache = {};

  @override
  void initState() {
    super.initState();
    _devotionsFuture = _fetchDevotionsWithProgress();
  }

  Future<List<Devotion>> _fetchDevotionsWithProgress() async {
    final devotions = await BibleRepository.fetchDevotions();

    // ⚡ The backend's /bible/progress/devotion/<id> endpoint is currently
    // a stub — it doesn't query anything and always replies with the same
    // hardcoded {completed: false, progress: 0} regardless of which
    // devotion is asked about (see bible.py: get_devotion_progress). Firing
    // one HTTP round trip per devotion just to get back an identical,
    // known-in-advance answer was pure wasted network time on every load
    // of this tab. Building the equivalent ReadingProgress locally gives
    // the exact same result instantly, with zero requests.
    for (final devotion in devotions) {
      _progressCache[devotion.id] = ReadingProgress.initial(
        devotion.id,
        'devotion',
        1,
      );
    }

    return _filterDevotions(devotions);
  }

  List<Devotion> _filterDevotions(List<Devotion> devotions) {
    return devotions.where((devotion) {
      final matchesCategory =
          widget.category == null ||
          widget.determineCategory(devotion) == widget.category;
      final matchesSearch =
          widget.searchQuery.isEmpty ||
          devotion.verse.toLowerCase().contains(
            widget.searchQuery.toLowerCase(),
          ) ||
          devotion.content.toLowerCase().contains(
            widget.searchQuery.toLowerCase(),
          );
      return matchesCategory && matchesSearch;
    }).toList();
  }

  Future<void> _refresh() async {
    setState(() {
      _devotionsFuture = _fetchDevotionsWithProgress();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Devotion>>(
      future: _devotionsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return _ErrorState(
            message: 'Failed to load devotions',
            onRetry: _refresh,
          );
        }

        final items = snapshot.data ?? [];
        if (items.isEmpty) {
          return _EmptyState(
            message: widget.searchQuery.isNotEmpty || widget.category != null
                ? 'No devotions match your filters 🤔'
                : 'No devotions available yet ✨',
          );
        }

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 2),
            itemBuilder: (ctx, i) {
              final devotion = items[i];
              final progress = _progressCache[devotion.id];
              return _DevotionListItem(
                devotion: devotion,
                category: widget.determineCategory(devotion),
                progress: progress,
                onProgressUpdate: (newProgress) {
                  _progressCache[devotion.id] = newProgress;
                  setState(() {});
                },
                onArchive: _refresh, // Refresh list after archiving
              );
            },
          ),
        );
      },
    );
  }
}

// Enhanced Devotion List Item with progress tracking and archive functionality
class _DevotionListItem extends StatefulWidget {
  final Devotion devotion;
  final DevotionCategory category;
  final ReadingProgress? progress;
  final Function(ReadingProgress)? onProgressUpdate;
  final VoidCallback? onArchive;

  const _DevotionListItem({
    required this.devotion,
    required this.category,
    this.progress,
    this.onProgressUpdate,
    this.onArchive,
  });

  @override
  State<_DevotionListItem> createState() => _DevotionListItemState();
}

class _DevotionListItemState extends State<_DevotionListItem> {
  ReadingProgress? _currentProgress;
  bool _isArchiving = false;
  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();
    _currentProgress = widget.progress;
  }

  void _updateProgress(double newProgress) async {
    try {
      final progress = ReadingProgress(
        itemId: widget.devotion.id,
        itemType: 'devotion',
        progress: newProgress,
        currentPage: (newProgress * 10).toInt(),
        totalPages: 10,
        lastRead: DateTime.now(),
        isCompleted: newProgress >= 1.0,
      );

      await BibleRepository.saveProgress(progress);

      setState(() {
        _currentProgress = progress;
      });

      widget.onProgressUpdate?.call(progress);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update progress: ${e.toString()}')),
      );
    }
  }

  void _archiveDevotion() async {
    if (_isArchiving) return;

    setState(() {
      _isArchiving = true;
    });

    try {
      await BibleRepository.archiveDevotion(widget.devotion.id);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('📦 "${widget.devotion.verse}" added to archive'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          action: SnackBarAction(
            label: 'View',
            onPressed: () {
              // Switch to archive tab
              final state = context
                  .findAncestorStateOfType<_BibleStudyScreenState>();
              state?._tabController.animateTo(2);
            },
          ),
        ),
      );

      widget.onArchive?.call();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to archive: ${e.toString()}')),
      );
    } finally {
      setState(() {
        _isArchiving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = _currentProgress;
    final isCompleted = progress?.isCompleted ?? false;
    final progressPercentage = progress?.progress ?? 0.0;
    final style = _categoryStyle(widget.category);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: style.color.withOpacity(0.15)),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: style.color.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: Stack(
            children: [
              Center(child: Icon(style.icon, color: style.color, size: 20)),
              if (progressPercentage > 0)
                CircularProgressIndicator(
                  value: progressPercentage,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    style.color.withOpacity(0.5),
                  ),
                  strokeWidth: 3,
                ),
            ],
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                widget.devotion.verse,
                style: const TextStyle(fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isCompleted)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.check_circle, color: Colors.green, size: 16),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              widget.devotion.content,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _StyledChip(label: style.label, color: style.color),
                if (progress != null) ...[
                  const SizedBox(width: 6),
                  _StyledChip(
                    label: '${(progressPercentage * 100).toInt()}%',
                    color: _getProgressColor(progressPercentage),
                  ),
                ],
              ],
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: _isArchiving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.archive_outlined, size: 20),
              onPressed: _isArchiving ? null : _archiveDevotion,
              tooltip: 'Add to Archive',
            ),
            Icon(
              Icons.chevron_right,
              color: Theme.of(context).colorScheme.outline,
            ),
          ],
        ),
        onTap: () async {
          if (_isNavigating) return;
          _isNavigating = true;
          try {
            final result = await context.push<bool>(
              '/bible/detail/devotion/${widget.devotion.id}',
              extra: widget.devotion,
            );

            // Optionally refresh or act on result returned from detail
            if (result == true) {
              // e.g., widget.onArchive?.call() or any refresh
            }
          } catch (e) {
            if (mounted)
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Cannot open devotion: ${e.toString()}'),
                ),
              );
          } finally {
            if (mounted) _isNavigating = false;
          }
        },
        onLongPress: () {
          _showProgressDialog(context);
        },
      ),
    );
  }

  void _showProgressDialog(BuildContext context) {
    final currentProgress = _currentProgress?.progress ?? 0.0;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Update Reading Progress'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${(currentProgress * 100).toInt()}% complete'),
            const SizedBox(height: 16),
            Slider(
              value: currentProgress,
              onChanged: (value) {
                _updateProgress(value);
                Navigator.pop(context);
              },
              min: 0,
              max: 1,
              divisions: 10,
              label: '${(currentProgress * 100).toInt()}%',
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                FilledButton(
                  onPressed: () {
                    _updateProgress(0.0);
                    Navigator.pop(context);
                  },
                  child: const Text('Reset'),
                ),
                FilledButton(
                  onPressed: () {
                    _updateProgress(1.0);
                    Navigator.pop(context);
                  },
                  child: const Text('Complete'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getProgressColor(double progress) {
    if (progress >= 1.0) return Colors.green;
    if (progress >= 0.5) return Colors.blue;
    return Colors.grey;
  }
}

// Enhanced Study Plans List with progress tracking
class _PlansList extends StatefulWidget {
  final StudyPlanDifficulty? difficulty;
  final String searchQuery;
  final StudyPlanDifficulty Function(StudyPlan) determineDifficulty;

  // FIXED: `key` now forwards to super.key so the parent's GlobalKey actually
  // attaches to this widget. Previously it was a plain named field that never
  // reached the Widget base class, so `_plansListKey.currentState` was always
  // null and "create plan → refresh list" silently did nothing.
  const _PlansList({
    super.key,
    this.difficulty,
    this.searchQuery = '',
    required this.determineDifficulty,
  });

  @override
  State<_PlansList> createState() => _PlansListState();
}

class _PlansListState extends State<_PlansList> {
  late Future<List<StudyPlan>> _plansFuture;
  final Map<int, ReadingProgress?> _progressCache = {};

  @override
  void initState() {
    super.initState();
    _plansFuture = _fetchPlansWithProgress();
  }

  Future<List<StudyPlan>> _fetchPlansWithProgress() async {
    // Only the plans call itself should be able to fail the whole screen.
    // Progress is supplementary — if it errors for one plan (network hiccup,
    // a 500, a timeout, etc.) that must not take down the entire list.
    final plans = await BibleRepository.fetchPlans();

    // Fetch progress for all plans in parallel instead of one-by-one; a
    // sequential await-in-a-loop meant N round trips before the list could
    // ever render, and a slow/failing request anywhere in the chain stalled
    // or broke everything after it.
    await Future.wait(
      plans.map((plan) async {
        try {
          final progress = await BibleRepository.getProgress(
            plan.id,
            'study_plan',
          );
          _progressCache[plan.id] = progress;
        } catch (e) {
          // Missing/failed progress for a single plan shouldn't block the
          // rest of the list from loading — just leave it uncached.
          debugPrint('Failed to load progress for plan ${plan.id}: $e');
          _progressCache[plan.id] = null;
        }
      }),
    );

    return _filterPlans(plans);
  }

  List<StudyPlan> _filterPlans(List<StudyPlan> plans) {
    return plans.where((plan) {
      final matchesDifficulty =
          widget.difficulty == null ||
          widget.determineDifficulty(plan) == widget.difficulty;
      final matchesSearch =
          widget.searchQuery.isEmpty ||
          plan.title.toLowerCase().contains(widget.searchQuery.toLowerCase()) ||
          plan.description.toLowerCase().contains(
            widget.searchQuery.toLowerCase(),
          );
      return matchesDifficulty && matchesSearch;
    }).toList();
  }

  // Refresh after delete or create
  Future<void> _refreshPlans() async {
    setState(() {
      _plansFuture = _fetchPlansWithProgress();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<StudyPlan>>(
      future: _plansFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return _ErrorState(
            message: 'Failed to load study plans',
            onRetry: _refreshPlans,
          );
        }

        final items = snapshot.data ?? [];
        if (items.isEmpty) {
          return _EmptyState(
            message: widget.searchQuery.isNotEmpty || widget.difficulty != null
                ? 'No study plans match your filters 🤔'
                : 'No study plans yet — start one! 🚀',
          );
        }

        return RefreshIndicator(
          onRefresh: _refreshPlans,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 2),
            itemBuilder: (ctx, i) {
              final plan = items[i];
              final progress = _progressCache[plan.id];
              return _StudyPlanListItem(
                plan: plan,
                difficulty: widget.determineDifficulty(plan),
                progress: progress,
                onProgressUpdate: (newProgress) {
                  _progressCache[plan.id] = newProgress;
                  setState(() {});
                },
                onArchive: _refreshPlans, // Refresh list after archiving
                onDelete: _refreshPlans, // Refresh list after deleting
              );
            },
          ),
        );
      },
    );
  }
}

// Study Plan List Item with progress tracking, archive, and delete functionality
class _StudyPlanListItem extends StatefulWidget {
  final StudyPlan plan;
  final StudyPlanDifficulty difficulty;
  final ReadingProgress? progress;
  final Function(ReadingProgress)? onProgressUpdate;
  final VoidCallback? onArchive;
  final VoidCallback? onDelete;

  const _StudyPlanListItem({
    required this.plan,
    required this.difficulty,
    this.progress,
    this.onProgressUpdate,
    this.onArchive,
    this.onDelete,
  });

  @override
  State<_StudyPlanListItem> createState() => _StudyPlanListItemState();
}

class _StudyPlanListItemState extends State<_StudyPlanListItem> {
  ReadingProgress? _currentProgress;
  bool _isArchiving = false;
  bool _isDeleting = false;
  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();
    _currentProgress = widget.progress;
  }

  void _updateProgress(double newProgress) async {
    try {
      final progress = ReadingProgress(
        itemId: widget.plan.id,
        itemType: 'study_plan',
        progress: newProgress,
        currentPage: (newProgress * (widget.plan.dayCount ?? 30)).toInt(),
        totalPages: widget.plan.dayCount ?? 30,
        lastRead: DateTime.now(),
        isCompleted: newProgress >= 1.0,
      );

      await BibleRepository.saveProgress(progress);

      setState(() {
        _currentProgress = progress;
      });

      widget.onProgressUpdate?.call(progress);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update progress: ${e.toString()}')),
      );
    }
  }

  void _archiveStudyPlan() async {
    if (_isArchiving) return;

    setState(() {
      _isArchiving = true;
    });

    try {
      await BibleRepository.archiveStudyPlan(widget.plan.id);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('📦 "${widget.plan.title}" added to archive'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          action: SnackBarAction(
            label: 'View',
            onPressed: () {
              // Switch to archive tab
              final state = context
                  .findAncestorStateOfType<_BibleStudyScreenState>();
              state?._tabController.animateTo(2);
            },
          ),
        ),
      );

      widget.onArchive?.call();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to archive: ${e.toString()}')),
      );
    } finally {
      setState(() {
        _isArchiving = false;
      });
    }
  }

  void _deleteStudyPlan() async {
    if (_isDeleting) return;

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Study Plan'),
        content: Text(
          'Are you sure you want to delete "${widget.plan.title}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete != true) return;

    setState(() {
      _isDeleting = true;
    });

    try {
      await BibleRepository.deletePlan(widget.plan.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"${widget.plan.title}" deleted successfully'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        );

        // Notify parent to refresh the list
        widget.onDelete?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete study plan: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = _currentProgress;
    final isCompleted = progress?.isCompleted ?? false;
    final progressPercentage = progress?.progress ?? 0.0;
    final style = _difficultyStyle(widget.difficulty);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: style.color.withOpacity(0.15)),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: style.color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: style.color.withOpacity(0.35),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Stack(
            children: [
              const Center(
                child: Icon(Icons.assignment, color: Colors.white, size: 20),
              ),
              if (progressPercentage > 0)
                CircularProgressIndicator(
                  value: progressPercentage,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Colors.white.withOpacity(0.5),
                  ),
                  strokeWidth: 3,
                ),
            ],
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                widget.plan.title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (isCompleted)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.check_circle, color: Colors.green, size: 16),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              widget.plan.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _StyledChip(label: style.label, color: style.color),
                if (widget.plan.dayCount != null)
                  _StyledChip(
                    label: '${widget.plan.dayCount} days',
                    color: Colors.blueGrey,
                  ),
                if (progress != null)
                  _StyledChip(
                    label: '${(progressPercentage * 100).toInt()}%',
                    color: _getProgressColor(progressPercentage),
                  ),
              ],
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_isDeleting)
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: Theme.of(context).colorScheme.error,
                ),
                onPressed: _deleteStudyPlan,
                tooltip: 'Delete',
              )
            else
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),

            IconButton(
              icon: _isArchiving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.archive_outlined, size: 20),
              onPressed: _isArchiving ? null : _archiveStudyPlan,
              tooltip: 'Add to Archive',
            ),

            Icon(
              Icons.chevron_right,
              color: Theme.of(context).colorScheme.outline,
            ),
          ],
        ),
        onTap: () async {
          if (_isNavigating) return;
          _isNavigating = true;
          try {
            final result = await context.push<bool>(
              '/bible/detail/plan/${widget.plan.id}',
              extra: widget.plan,
            );

            if (result == true) {
              widget.onDelete?.call();
            }
          } catch (e) {
            if (mounted)
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Cannot open study plan: ${e.toString()}'),
                ),
              );
          } finally {
            if (mounted) _isNavigating = false;
          }
        },
        onLongPress: () {
          _showProgressDialog(context);
        },
      ),
    );
  }

  void _showProgressDialog(BuildContext context) {
    final currentProgress = _currentProgress?.progress ?? 0.0;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Update Study Progress'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${(currentProgress * 100).toInt()}% complete'),
            const SizedBox(height: 16),
            Slider(
              value: currentProgress,
              onChanged: (value) {
                _updateProgress(value);
                Navigator.pop(context);
              },
              min: 0,
              max: 1,
              divisions: 10,
              label: '${(currentProgress * 100).toInt()}%',
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                FilledButton(
                  onPressed: () {
                    _updateProgress(0.0);
                    Navigator.pop(context);
                  },
                  child: const Text('Reset'),
                ),
                FilledButton(
                  onPressed: () {
                    _updateProgress(1.0);
                    Navigator.pop(context);
                  },
                  child: const Text('Complete'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getProgressColor(double progress) {
    if (progress >= 1.0) return Colors.green;
    if (progress >= 0.5) return Colors.blue;
    return Colors.grey;
  }
}

// Enhanced Archive List with progress tracking
class _ArchiveList extends StatefulWidget {
  final DateTimeRange? dateRange;
  final String searchQuery;

  const _ArchiveList({this.dateRange, this.searchQuery = ''});

  @override
  State<_ArchiveList> createState() => _ArchiveListState();
}

class _ArchiveListState extends State<_ArchiveList> {
  late Future<List<ArchiveItem>> _archiveFuture;
  final Map<int, ReadingProgress?> _progressCache = {};

  @override
  void initState() {
    super.initState();
    _archiveFuture = _fetchArchiveWithProgress();
  }

  Future<List<ArchiveItem>> _fetchArchiveWithProgress() async {
    final archive = await BibleRepository.fetchArchive();

    // ⚡ There's no /bible/progress/archive/<id> route on the backend at
    // all — every call here would 404, and BibleRepository.getProgress
    // already just swallows that 404 and returns null. Skipping the call
    // gets to that exact same null result without N wasted round trips
    // (one per archived item, every single time this tab loads).
    for (final item in archive) {
      _progressCache[item.id] = null;
    }

    return _filterArchive(archive);
  }

  List<ArchiveItem> _filterArchive(List<ArchiveItem> archive) {
    return archive.where((item) {
      final matchesDate =
          widget.dateRange == null ||
          (item.date.isAfter(widget.dateRange!.start) &&
              item.date.isBefore(widget.dateRange!.end));
      final matchesSearch =
          widget.searchQuery.isEmpty ||
          item.title.toLowerCase().contains(widget.searchQuery.toLowerCase()) ||
          item.description.toLowerCase().contains(
            widget.searchQuery.toLowerCase(),
          );
      return matchesDate && matchesSearch;
    }).toList();
  }

  Future<void> _refresh() async {
    setState(() {
      _archiveFuture = _fetchArchiveWithProgress();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ArchiveItem>>(
      future: _archiveFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return _ErrorState(
            message: 'Failed to load archive',
            onRetry: _refresh,
          );
        }

        final items = snapshot.data ?? [];
        if (items.isEmpty) {
          return _EmptyState(
            message: widget.searchQuery.isNotEmpty || widget.dateRange != null
                ? 'No archive items match your filters 🤔'
                : 'Nothing archived yet 📦',
          );
        }

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 2),
            itemBuilder: (ctx, i) {
              final item = items[i];
              final progress = _progressCache[item.id];
              return _ArchiveListItem(
                item: item,
                progress: progress,
                onProgressUpdate: (newProgress) {
                  _progressCache[item.id] = newProgress;
                  setState(() {});
                },
                onUnarchive: _refresh, // Refresh list after unarchiving
              );
            },
          ),
        );
      },
    );
  }
}

// Archive List Item with progress tracking and unarchive functionality
class _ArchiveListItem extends StatefulWidget {
  final ArchiveItem item;
  final ReadingProgress? progress;
  final Function(ReadingProgress)? onProgressUpdate;
  final VoidCallback? onUnarchive;

  const _ArchiveListItem({
    required this.item,
    this.progress,
    this.onProgressUpdate,
    this.onUnarchive,
  });

  @override
  State<_ArchiveListItem> createState() => _ArchiveListItemState();
}

class _ArchiveListItemState extends State<_ArchiveListItem> {
  ReadingProgress? _currentProgress;
  bool _isUnarchiving = false;
  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();
    _currentProgress = widget.progress;
  }

  void _updateProgress(double newProgress) async {
    try {
      final progress = ReadingProgress(
        itemId: widget.item.id,
        itemType: 'archive',
        progress: newProgress,
        currentPage: (newProgress * 20).toInt(),
        totalPages: 20,
        lastRead: DateTime.now(),
        isCompleted: newProgress >= 1.0,
      );

      await BibleRepository.saveProgress(progress);

      setState(() {
        _currentProgress = progress;
      });

      widget.onProgressUpdate?.call(progress);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update progress: ${e.toString()}')),
      );
    }
  }

  void _unarchiveItem() async {
    if (_isUnarchiving) return;

    setState(() {
      _isUnarchiving = true;
    });

    try {
      await BibleRepository.unarchiveItem(widget.item.id);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${widget.item.title}" removed from archive'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );

      widget.onUnarchive?.call();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to unarchive: ${e.toString()}')),
      );
    } finally {
      setState(() {
        _isUnarchiving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = _currentProgress;
    final isCompleted = progress?.isCompleted ?? false;
    final progressPercentage = progress?.progress ?? 0.0;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: Theme.of(context).colorScheme.secondary.withOpacity(0.15),
        ),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondaryContainer,
            shape: BoxShape.circle,
          ),
          child: Stack(
            children: [
              Center(
                child: Icon(
                  Icons.archive,
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                  size: 20,
                ),
              ),
              if (progressPercentage > 0)
                CircularProgressIndicator(
                  value: progressPercentage,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.secondary.withOpacity(0.4),
                  ),
                  strokeWidth: 3,
                ),
            ],
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                widget.item.title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (isCompleted)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.check_circle, color: Colors.green, size: 16),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              widget.item.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [
                if (progress != null)
                  _StyledChip(
                    label: '${(progressPercentage * 100).toInt()}%',
                    color: _getProgressColor(progressPercentage),
                  ),
                _StyledChip(
                  label: _formatDate(widget.item.date),
                  color: Colors.blueGrey,
                ),
              ],
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: _isUnarchiving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.unarchive_outlined, size: 20),
              onPressed: _isUnarchiving ? null : _unarchiveItem,
              tooltip: 'Remove from Archive',
            ),
          ],
        ),
        onTap: () async {
          if (_isNavigating) return;
          _isNavigating = true;
          try {
            final result = await context.push<bool>(
              '/bible/detail/archive/${widget.item.id}',
              extra: widget.item,
            );

            if (result == true) {
              widget.onUnarchive?.call();
            }
          } catch (e) {
            if (mounted)
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Cannot open archive item: ${e.toString()}'),
                ),
              );
          } finally {
            if (mounted) _isNavigating = false;
          }
        },
        onLongPress: () {
          _showProgressDialog(context);
        },
      ),
    );
  }

  void _showProgressDialog(BuildContext context) {
    final currentProgress = _currentProgress?.progress ?? 0.0;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Update Reading Progress'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${(currentProgress * 100).toInt()}% complete'),
            const SizedBox(height: 16),
            Slider(
              value: currentProgress,
              onChanged: (value) {
                _updateProgress(value);
                Navigator.pop(context);
              },
              min: 0,
              max: 1,
              divisions: 10,
              label: '${(currentProgress * 100).toInt()}%',
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                FilledButton(
                  onPressed: () {
                    _updateProgress(0.0);
                    Navigator.pop(context);
                  },
                  child: const Text('Reset'),
                ),
                FilledButton(
                  onPressed: () {
                    _updateProgress(1.0);
                    Navigator.pop(context);
                  },
                  child: const Text('Complete'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getProgressColor(double progress) {
    if (progress >= 1.0) return Colors.green;
    if (progress >= 0.5) return Colors.blue;
    return Colors.grey;
  }

  String _formatDate(DateTime date) {
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
  }
}

// Enhanced Error State with retry functionality
class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Oops, something went wrong',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}

// Enhanced Empty State
class _EmptyState extends StatelessWidget {
  final String message;

  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.25),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
