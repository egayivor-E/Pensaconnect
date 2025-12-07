import 'package:flutter/material.dart';

class CategoryFilter extends StatelessWidget {
  final int selectedCategory;
  final Function(int) onCategoryChanged;

  const CategoryFilter({
    super.key,
    required this.selectedCategory,
    required this.onCategoryChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SegmentedButton<int>(
        segments: const [
          ButtonSegment(
            value: 0,
            label: Text('English'),
            icon: Icon(Icons.language),
          ),
          ButtonSegment(
            value: 1,
            label: Text('African'),
            icon: Icon(Icons.public),
          ),
        ],
        selected: {selectedCategory},
        onSelectionChanged: (selection) {
          onCategoryChanged(selection.first);
        },
      ),
    );
  }
}
