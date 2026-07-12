import 'package:flutter/material.dart';
import 'package:pensaconnect/repositories/user_repository.dart';
import 'package:provider/provider.dart';
import '../models/prayer_request.dart';
import '../repositories/prayer_repository.dart';
import '../repositories/auth_repository.dart';

class PrayerWallScreen extends StatefulWidget {
  const PrayerWallScreen({super.key});

  @override
  State<PrayerWallScreen> createState() => _PrayerWallScreenState();
}

class _PrayerWallScreenState extends State<PrayerWallScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _initialized = false;
  final ScrollController _scrollController = ScrollController();
  int _currentPage = 1;
  final int _perPage = 20;
  bool _isFetchingMore = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        _currentPage = 1;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          await _fetchRequests(refresh: true);
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final repo = context.read<PrayerRepository>();
        final authRepo = context.read<AuthRepository>();

        final currentUserId = await authRepo.getCurrentUserId();
        repo.setCurrentUserId(currentUserId);

        await _fetchRequests(refresh: true);
      });

      _scrollController.addListener(() {
        final repo = context.read<PrayerRepository>();
        if (_scrollController.position.pixels >=
                _scrollController.position.maxScrollExtent - 200 &&
            !_isFetchingMore &&
            repo.hasMore) {
          _fetchRequests();
        }
      });
    }
  }

  Future<void> _fetchRequests({bool refresh = false}) async {
    final repo = context.read<PrayerRepository>();
    _isFetchingMore = true;

    final filter = _getFilterForTab(_tabController.index);

    await repo.fetchRequests(
      page: _currentPage,
      perPage: _perPage,
      filter: filter,
      refresh: refresh,
    );

    _isFetchingMore = false;
    if (!refresh) _currentPage++;
    setState(() {});
  }

  String _getFilterForTab(int index) {
    switch (index) {
      case 0:
        return "wall";
      case 1:
        return "my_prayers";
      case 2:
        return "answered";
      default:
        return "wall";
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _showNewRequestForm(BuildContext context, PrayerRepository repo) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _NewRequestForm(repo: repo),
    );
  }

  Widget _buildEmptyState(int tabIndex) {
    final content = switch (tabIndex) {
      0 => (
          Icons.volunteer_activism,
          "The wall is quiet right now",
          "Be the first to share something the community can pray over.",
        ),
      1 => (
          Icons.edit_note,
          "You haven't shared a prayer yet",
          "Tap the + button to ask your community to pray with you.",
        ),
      _ => (
          Icons.celebration,
          "No answered prayers yet",
          "When one of your requests is answered, mark it — it'll show up here as a reminder of what's been done.",
        ),
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(content.$1, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              content.$2,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              content.$3,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<PrayerRepository>();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Prayer Wall"),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: "Wall"),
            Tab(text: "My Prayers"),
            Tab(text: "Answered"),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _currentPage = 1;
          await _fetchRequests(refresh: true);
        },
        child: repo.isLoading && repo.requests.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : repo.requests.isEmpty
                ? ListView(
                    // ListView so RefreshIndicator's pull-to-refresh still
                    // works even when the empty state has nothing to scroll.
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.6,
                        child: _buildEmptyState(_tabController.index),
                      ),
                    ],
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: repo.requests.length + (repo.hasMore ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i >= repo.requests.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }

                      final req = repo.requests[i];
                      final isWallTab = _tabController.index == 0;

                      return _PrayerCard(
                        request: req,
                        showIPrayed: isWallTab,
                        onTogglePrayer: isWallTab
                            ? (prayerId) async {
                                await repo.togglePrayerById(prayerId);
                              }
                            : null,
                        onDelete: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text("Delete Prayer Request?"),
                              content: const Text(
                                "Are you sure you want to delete this prayer request?",
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text("Cancel"),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text("Delete"),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) {
                            await repo.deleteRequest(req.id);
                            setState(() {});
                          }
                        },
                        // ✅ Uses server-computed isOwner instead of
                        // comparing raw ids — works correctly even for the
                        // author's own anonymous requests, and never
                        // depends on a userId that may be null.
                        showMarkAnswered:
                            _tabController.index == 1 && req.isOwner,
                        onToggleAnswered:
                            _tabController.index == 1 && req.isOwner
                                ? () async {
                                    await repo.toggleAnswered(
                                      req.id,
                                      removeIfUnanswered:
                                          _tabController.index == 2,
                                    );
                                  }
                                : null,
                      );
                    },
                  ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showNewRequestForm(context, repo),
        child: const Icon(Icons.add),
      ),
    );
  }
}

// =================== NEW PRAYER FORM ===================
class _NewRequestForm extends StatefulWidget {
  final PrayerRepository repo;
  const _NewRequestForm({required this.repo});

  @override
  State<_NewRequestForm> createState() => _NewRequestFormState();
}

class _NewRequestFormState extends State<_NewRequestForm> {
  final TextEditingController titleCtrl = TextEditingController();
  final TextEditingController contentCtrl = TextEditingController();
  bool isAnonymous = false;
  String status = "pending";
  String category = "General";

  @override
  void dispose() {
    titleCtrl.dispose();
    contentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              "New Prayer Request",
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Your community is ready to stand with you",
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(
                labelText: "Title",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: contentCtrl,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: "Prayer Request",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: category,
              items: [
                "General",
                "Health",
                "Family",
                "Finances",
                "Spiritual",
                "Academics",
              ].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setState(() => category = v ?? "General"),
              decoration: const InputDecoration(
                labelText: "Category",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.visibility_off_outlined, size: 20),
                const SizedBox(width: 8),
                const Expanded(child: Text("Pray anonymously")),
                Switch(
                  value: isAnonymous,
                  onChanged: (v) => setState(() => isAnonymous = v),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () async {
                  if (!mounted) return;
                  final success = await widget.repo.createRequest(
                    title: titleCtrl.text,
                    content: contentCtrl.text,
                    isAnonymous: isAnonymous,
                    status: status,
                    category: category,
                  );
                  if (success && mounted) {
                    Navigator.pop(context);
                    await widget.repo.fetchRequests(refresh: true);
                    setState(() {});
                  }
                },
                child: const Text("Post Prayer Request"),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// =================== PRAYER CARD ===================
class _PrayerCard extends StatefulWidget {
  final PrayerRequest request;
  final bool showIPrayed;
  final Future<void> Function(int prayerId)? onTogglePrayer;
  final VoidCallback onDelete;
  final bool showMarkAnswered;
  final Future<void> Function()? onToggleAnswered;

  const _PrayerCard({
    required this.request,
    this.showIPrayed = false,
    this.onTogglePrayer,
    required this.onDelete,
    this.showMarkAnswered = false,
    this.onToggleAnswered,
  });

  @override
  State<_PrayerCard> createState() => _PrayerCardState();
}

class _PrayerCardState extends State<_PrayerCard> {
  late bool hasPrayed;
  late String status;
  bool _showPrayerBurst = false;

  // ✅ Same identity-color system used on forums/testimonies, so a given
  // person's name always maps to the same color across the whole app.
  static const List<Color> _avatarPalette = [
    Color(0xFF7C4DFF),
    Color(0xFF26A69A),
    Color(0xFFFF7043),
    Color(0xFF42A5F5),
    Color(0xFFEC407A),
    Color(0xFF66BB6A),
    Color(0xFF5C6BC0),
    Color(0xFFFFA726),
  ];

  Color _colorForName(String name) {
    if (name.isEmpty) return _avatarPalette.first;
    final hash = name.codeUnits.fold<int>(0, (a, b) => a + b);
    return _avatarPalette[hash % _avatarPalette.length];
  }

  String _initialsFor(String name) {
    if (name.isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  @override
  void initState() {
    super.initState();
    hasPrayed = widget.request.hasPrayed;
    status = widget.request.status;
  }

  Future<void> _togglePrayer() async {
    if (widget.onTogglePrayer == null) return;

    final wasPrayed = hasPrayed;
    setState(() => hasPrayed = !hasPrayed);

    // ✅ Satisfying, immediate feedback the moment you tap — this is the
    // "addictive" part: a quick heart burst + haptic-style scale, same
    // language as the testimony screen, so the gesture feels consistent
    // everywhere in the app.
    if (!wasPrayed) {
      setState(() => _showPrayerBurst = true);
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) setState(() => _showPrayerBurst = false);
      });
    }

    try {
      await widget.onTogglePrayer!(widget.request.id);
    } catch (_) {
      setState(() => hasPrayed = wasPrayed);
    }
  }

  Future<void> _toggleAnswered() async {
    if (widget.onToggleAnswered == null) return;

    final newStatus = status == "answered" ? "pending" : "answered";

    setState(() => status = newStatus);

    try {
      await widget.onToggleAnswered!();
    } catch (_) {
      setState(() => status = status == "answered" ? "pending" : "answered");
    }
  }

  @override
  void didUpdateWidget(covariant _PrayerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request.hasPrayed != widget.request.hasPrayed) {
      hasPrayed = widget.request.hasPrayed;
    }
    if (oldWidget.request.status != widget.request.status) {
      status = widget.request.status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final req = widget.request;
    final isAnswered = status == "answered";

    // ✅ Real display name, never a raw numeric id. Anonymous requests
    // show "Anonymous" (backend never sends the real name for those);
    // missing/blank names fall back to something human, not "User 4821".
    final displayName = req.isAnonymous
        ? "Anonymous"
        : ((req.username?.trim().isNotEmpty ?? false)
            ? req.username!.trim()
            : "A community member");
    final avatarColor = _colorForName(displayName);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        // ✅ Answered prayers get a warm celebratory border — a visible
        // "something good happened here" marker as you scroll the wall.
        border: isAnswered
            ? Border.all(color: Colors.amber.shade400, width: 1.5)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isAnswered)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.celebration, size: 16, color: Colors.amber.shade800),
                      const SizedBox(width: 6),
                      Text(
                        "Prayer Answered",
                        style: TextStyle(
                          color: Colors.amber.shade800,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  req.isAnonymous
                      ? CircleAvatar(
                          backgroundColor: Colors.grey[300],
                          child: const Icon(Icons.person_off_outlined,
                              size: 20, color: Colors.grey),
                        )
                      : CircleAvatar(
                          backgroundColor: avatarColor,
                          backgroundImage: req.userProfilePic != null
                              ? NetworkImage(
                                  UserRepository.getProfilePictureUrl(
                                    req.userProfilePic,
                                  ),
                                )
                              : null,
                          child: req.userProfilePic == null
                              ? Text(
                                  _initialsFor(displayName),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                )
                              : null,
                        ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      displayName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: req.isAnonymous ? null : avatarColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: widget.onDelete,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                req.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (req.category != null && req.category!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      req.category!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(req.content),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    "${req.prayersCount + (hasPrayed && !req.hasPrayed ? 1 : 0)} prayers",
                    style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6)),
                  ),
                  const Spacer(),
                  if (widget.showIPrayed && widget.onTogglePrayer != null)
                    InkWell(
                      onTap: _togglePrayer,
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Row(
                          children: [
                            Stack(
                              alignment: Alignment.center,
                              clipBehavior: Clip.none,
                              children: [
                                AnimatedScale(
                                  scale: hasPrayed ? 1.15 : 1.0,
                                  duration: const Duration(milliseconds: 200),
                                  curve: Curves.elasticOut,
                                  child: Icon(
                                    hasPrayed ? Icons.favorite : Icons.favorite_border,
                                    color: hasPrayed ? Colors.redAccent : Colors.grey,
                                  ),
                                ),
                                if (_showPrayerBurst)
                                  AnimatedOpacity(
                                    opacity: _showPrayerBurst ? 1 : 0,
                                    duration: const Duration(milliseconds: 150),
                                    child: AnimatedScale(
                                      scale: _showPrayerBurst ? 1.8 : 1.0,
                                      duration: const Duration(milliseconds: 500),
                                      curve: Curves.easeOut,
                                      child: Icon(
                                        Icons.favorite,
                                        color: Colors.redAccent.withOpacity(0.35),
                                        size: 26,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(width: 6),
                            const Text("I prayed"),
                          ],
                        ),
                      ),
                    ),
                  if (widget.showMarkAnswered && widget.onToggleAnswered != null)
                    InkWell(
                      onTap: _toggleAnswered,
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Row(
                          children: [
                            Icon(
                              isAnswered ? Icons.undo : Icons.check_circle_outline,
                              color: isAnswered ? Colors.orange : Colors.green,
                              size: 20,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isAnswered ? "Mark as Pending" : "Mark as Answered",
                              style: TextStyle(
                                color: isAnswered ? Colors.orange : Colors.green,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
