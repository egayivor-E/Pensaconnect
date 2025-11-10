import 'package:flutter/material.dart';
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
      builder: (_) => _NewRequestForm(repo: repo),
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
                  final isOwner = req.userId == repo.currentUserId;

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
                    showMarkAnswered: _tabController.index == 1 && isOwner,
                    onToggleAnswered: _tabController.index == 1 && isOwner
                        ? () async {
                            await repo.toggleAnswered(
                              req.id,
                              removeIfUnanswered: _tabController.index == 2,
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
            Text(
              "New Prayer Request",
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
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
                const Text("Pray anonymously"),
                const Spacer(),
                Switch(
                  value: isAnonymous,
                  onChanged: (v) => setState(() => isAnonymous = v),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
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

  @override
  void initState() {
    super.initState();
    hasPrayed = widget.request.hasPrayed;
    status = widget.request.status;
  }

  Future<void> _togglePrayer() async {
    if (widget.onTogglePrayer == null) return;

    setState(() => hasPrayed = !hasPrayed);

    try {
      await widget.onTogglePrayer!(widget.request.id);
    } catch (_) {
      setState(() => hasPrayed = !hasPrayed);
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
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundImage: widget.request.userProfilePic != null
                      ? NetworkImage(widget.request.userProfilePic!)
                      : null,
                  child: widget.request.userProfilePic == null
                      ? const Icon(Icons.person)
                      : null,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.request.isAnonymous
                      ? "Anonymous"
                      : (widget.request.username ??
                            "User ${widget.request.userId}"),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: widget.onDelete,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              widget.request.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            if (widget.request.category != null &&
                widget.request.category!.isNotEmpty)
              Text(
                "Category: ${widget.request.category}",
                style: theme.textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: Colors.grey[600],
                ),
              ),
            const SizedBox(height: 8),
            Text(widget.request.content),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  "${widget.request.prayersCount + (hasPrayed && !widget.request.hasPrayed ? 1 : 0)} prayers",
                ),
                const Spacer(),
                if (widget.showIPrayed && widget.onTogglePrayer != null)
                  Row(
                    children: [
                      IconButton(
                        onPressed: _togglePrayer,
                        icon: Icon(
                          hasPrayed ? Icons.favorite : Icons.favorite_border,
                          color: hasPrayed ? Colors.red : Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text("I prayed"),
                    ],
                  ),
                if (widget.showMarkAnswered && widget.onToggleAnswered != null)
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          status == "answered" ? Icons.undo : Icons.check,
                          color: status == "answered"
                              ? Colors.orange
                              : Colors.green,
                        ),
                        onPressed: _toggleAnswered,
                        tooltip: status == "answered"
                            ? "Mark as Pending"
                            : "Mark as Answered",
                      ),
                      Text(status == "answered" ? "Answered" : "Pending"),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
