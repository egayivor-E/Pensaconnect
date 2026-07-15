import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pensaconnect/models/bible_models.dart';
import 'package:pensaconnect/repositories/bible_repository.dart';
import 'package:pensaconnect/screens/bible_study_screen.dart'
    hide StudyPlanDifficulty;

class CreateStudyPlanScreen extends StatefulWidget {
  const CreateStudyPlanScreen({super.key});

  @override
  State<CreateStudyPlanScreen> createState() => _CreateStudyPlanScreenState();
}

class _CreateStudyPlanScreenState extends State<CreateStudyPlanScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _versesController = TextEditingController();
  final _dayCountController = TextEditingController(text: '7');

  StudyPlanDifficulty _selectedDifficulty = StudyPlanDifficulty.beginner;
  bool _isSubmitting = false;
  bool _isImportingDocument = false;

  // For managing multiple verses
  final List<String> _versesList = [];

  // When the admin imports a document, the AI's real per-day write-ups
  // land here and are used instead of the placeholder generator below.
  // Cleared if the admin edits the title/description/verses afterward
  // would be nice, but for now: present once imported, reviewable in
  // the day cards, and always overridable by re-importing.
  List<StudyPlanDay>? _aiGeneratedDays;
  String? _importedFileName;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _versesController.dispose();
    _dayCountController.dispose();
    super.dispose();
  }

  void _addVerse() {
    final verse = _versesController.text.trim();
    if (verse.isNotEmpty) {
      setState(() {
        _versesList.add(verse);
        _versesController.clear();
      });
    }
  }

  void _removeVerse(int index) {
    setState(() {
      _versesList.removeAt(index);
    });
  }

  Future<void> _pickAndImportDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['docx', 'pdf', 'txt', 'md'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    setState(() => _isImportingDocument = true);

    try {
      final draft = await BibleRepository.extractStudyPlanFromDocument(file);

      final draftDays = (draft['days'] as List? ?? [])
          .map((d) => StudyPlanDay.fromJson(d as Map<String, dynamic>))
          .toList();
      final draftVerses = ((draft['verses'] as List?) ?? const [])
          .map((v) => v.toString())
          .toList();

      setState(() {
        _titleController.text = (draft['title'] ?? '').toString();
        _descriptionController.text = (draft['description'] ?? '').toString();
        _dayCountController.text =
            (draft['total_days'] ?? draftDays.length).toString();
        _versesList
          ..clear()
          ..addAll(draftVerses);
        _selectedDifficulty = switch (draft['level']) {
          'INTERMEDIATE' => StudyPlanDifficulty.intermediate,
          'ADVANCED' => StudyPlanDifficulty.advanced,
          _ => StudyPlanDifficulty.beginner,
        };
        _aiGeneratedDays = draftDays;
        _importedFileName = file.name;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Drafted ${draftDays.length} day(s) from "${file.name}" — review below before saving.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isImportingDocument = false);
    }
  }

  Future<void> _submitStudyPlan() async {
    if (!_formKey.currentState!.validate()) return;

    if (_versesList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one Bible verse')),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final studyPlan = StudyPlan(
        id: DateTime.now().millisecondsSinceEpoch,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        verses: List<String>.from(_versesList),
        dayCount: int.tryParse(_dayCountController.text) ?? 7,
        createdAt: DateTime.now(),
        totalLessons: int.tryParse(_dayCountController.text) ?? 7,
      );

      // Prefer the AI-drafted days from an imported document (real
      // per-day content); fall back to the placeholder generator only
      // when the admin built the plan by hand.
      final days = _aiGeneratedDays ?? _generateStudyPlanDays(studyPlan);

      final completeStudyPlan = studyPlan.copyWith(days: days);

      await BibleRepository.createStudyPlan(completeStudyPlan);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Study plan created successfully!')),
        );
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create study plan: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  List<StudyPlanDay> _generateStudyPlanDays(StudyPlan plan) {
    final days = <StudyPlanDay>[];
    final dayCount = plan.dayCount ?? 7;

    for (int i = 1; i <= dayCount; i++) {
      days.add(
        StudyPlanDay(
          dayNumber: i,
          title: 'Day $i: ${plan.title}',
          content: _generateDayContent(plan, i),
          verses: _getVersesForDay(plan.verses, i, dayCount),
          isCompleted: false,
        ),
      );
    }

    return days;
  }

  String _generateDayContent(StudyPlan plan, int dayNumber) {
    return '''
Welcome to Day $dayNumber of "${plan.title}".

Today we'll be focusing on building your spiritual foundation through scripture study and reflection.

**Key Focus Areas:**
- Scripture reading and meditation
- Personal reflection
- Practical application

**Today's Assignment:**
Read the assigned verses and reflect on how they apply to your daily life.
''';
  }

  List<String> _getVersesForDay(
    List<String> allVerses,
    int dayNumber,
    int totalDays,
  ) {
    if (allVerses.isEmpty) return [];

    // Distribute verses across days
    final versesPerDay = (allVerses.length / totalDays).ceil();
    final startIndex = (dayNumber - 1) * versesPerDay;
    final endIndex = startIndex + versesPerDay;

    if (startIndex >= allVerses.length) return [allVerses.last];

    return allVerses.sublist(
      startIndex,
      endIndex < allVerses.length ? endIndex : allVerses.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Study Plan'),
        actions: [
          if (_isSubmitting)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                // AI Document Import
                Card(
                  elevation: 2,
                  color: colorScheme.primaryContainer.withOpacity(0.35),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.auto_awesome, color: colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(
                              'Import from Document (AI)',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Upload a devotional guide (.docx, .pdf, .txt, .md) and '
                          'the AI will draft the title, verses, and full day-by-day '
                          'content below for you to review and edit.',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _isImportingDocument
                              ? null
                              : _pickAndImportDocument,
                          icon: _isImportingDocument
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.upload_file),
                          label: Text(
                            _isImportingDocument
                                ? 'Drafting from document…'
                                : 'Upload document',
                          ),
                        ),
                        if (_importedFileName != null && !_isImportingDocument) ...[
                          const SizedBox(height: 8),
                          Text(
                            '✓ Drafted from "$_importedFileName" — ${_aiGeneratedDays?.length ?? 0} day(s). '
                            'Edit any field below before saving.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Title Field
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Plan Title',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _titleController,
                          decoration: const InputDecoration(
                            hintText: 'e.g., 30 Days Through the Gospels',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.all(12),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter a title';
                            }
                            if (value.trim().length < 3) {
                              return 'Title must be at least 3 characters';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Description Field
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Description',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _descriptionController,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            hintText: 'Describe what this study plan covers...',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.all(12),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter a description';
                            }
                            if (value.trim().length < 10) {
                              return 'Description must be at least 10 characters';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Difficulty and Duration
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Plan Details',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Difficulty
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Difficulty Level',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<StudyPlanDifficulty>(
                              value: _selectedDifficulty,
                              items: StudyPlanDifficulty.values.map((
                                difficulty,
                              ) {
                                return DropdownMenuItem(
                                  value: difficulty,
                                  child: Text(_formatDifficulty(difficulty)),
                                );
                              }).toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() {
                                    _selectedDifficulty = value;
                                  });
                                }
                              },
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Duration
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Duration (days)',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _dayCountController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                hintText: 'e.g., 7, 21, 30',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.all(12),
                              ),
                              validator: (value) {
                                final days = int.tryParse(value ?? '');
                                if (days == null || days <= 0) {
                                  return 'Please enter a valid number of days';
                                }
                                if (days > 365) {
                                  return 'Duration cannot exceed 365 days';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Bible Verses Section
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Bible Verses',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (_versesList.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${_versesList.length}',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colorScheme.onPrimary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Add the Bible verses that will be studied in this plan',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Add Verse Input
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _versesController,
                                decoration: const InputDecoration(
                                  hintText: 'e.g., John 3:16',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.all(12),
                                ),
                                onFieldSubmitted: (_) => _addVerse(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: _addVerse,
                              child: const Icon(Icons.add),
                            ),
                          ],
                        ),

                        // Verses List
                        if (_versesList.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Added Verses:',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ..._versesList
                              .asMap()
                              .entries
                              .map(
                                (entry) => Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  color: colorScheme.surfaceVariant.withOpacity(
                                    0.3,
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    leading: Text(
                                      '${entry.key + 1}.',
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: colorScheme.primary,
                                          ),
                                    ),
                                    title: Text(
                                      entry.value,
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(
                                        Icons.remove_circle_outline,
                                        size: 20,
                                      ),
                                      onPressed: () => _removeVerse(entry.key),
                                      color: colorScheme.error,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ],
                      ],
                    ),
                  ),
                ),

                // Preview Section
                if (_versesList.isNotEmpty &&
                    _dayCountController.text.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.visibility,
                                size: 20,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Plan Preview',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildPlanPreview(),
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 32),

                // Submit Button
                FilledButton(
                  onPressed: _isSubmitting ? null : _submitStudyPlan,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'Create Study Plan',
                          style: TextStyle(fontSize: 16),
                        ),
                ),

                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlanPreview() {
    final dayCount = int.tryParse(_dayCountController.text) ?? 7;
    final versesPerDay = _versesList.isEmpty
        ? 0
        : (_versesList.length / dayCount).ceil();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '• $dayCount-day study plan',
          style: TextStyle(fontWeight: FontWeight.w500),
        ),
        Text(
          '• ${_versesList.length} Bible verses',
          style: TextStyle(fontWeight: FontWeight.w500),
        ),
        Text(
          '• ${versesPerDay == 0 ? 'No' : versesPerDay} verses per day',
          style: TextStyle(fontWeight: FontWeight.w500),
        ),
        Text(
          '• ${_formatDifficulty(_selectedDifficulty)} level',
          style: TextStyle(fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  String _formatDifficulty(StudyPlanDifficulty difficulty) {
    switch (difficulty) {
      case StudyPlanDifficulty.beginner:
        return 'Beginner';
      case StudyPlanDifficulty.intermediate:
        return 'Intermediate';
      case StudyPlanDifficulty.advanced:
        return 'Advanced';
    }
  }
}
