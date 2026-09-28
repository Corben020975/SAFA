import 'package:flutter/material.dart';

import '../../core/text_normalize.dart';

class TagsEditor extends StatefulWidget {
  const TagsEditor({super.key, required this.tags, required this.onChanged});
  final List<String> tags;
  final ValueChanged<List<String>> onChanged;

  @override
  State<TagsEditor> createState() => _TagsEditorState();
}

class _TagsEditorState extends State<TagsEditor> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add(String raw) {
    final additions = raw
        .split(RegExp(r'[,;]'))
        .map(normalizeTag)
        .whereType<String>()
        .where((t) => !widget.tags.contains(t));
    if (additions.isNotEmpty) {
      widget.onChanged([...widget.tags, ...additions.toSet()]);
    }
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in widget.tags)
                  InputChip(
                    label: Text('#$tag'),
                    onDeleted: () => widget.onChanged(
                      widget.tags.where((t) => t != tag).toList(),
                    ),
                    deleteButtonTooltipMessage: 'Retirer',
                  ),
              ],
            ),
          ),
        TextField(
          controller: _controller,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: 'Ajouter un tag (ex. cpas, famille)',
            prefixIcon: const Icon(Icons.tag),
            suffixIcon: IconButton(
              tooltip: 'Ajouter',
              icon: const Icon(Icons.add),
              onPressed: () => _add(_controller.text),
            ),
          ),
          onChanged: (text) {
            // Une virgule valide le tag, comme sur un clavier de messagerie.
            if (text.endsWith(',') || text.endsWith(';')) _add(text);
          },
          onSubmitted: _add,
        ),
      ],
    );
  }
}
