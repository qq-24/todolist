import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/todo.dart';
import '../providers/todo_provider.dart';

class DoneCollectionScreen extends StatelessWidget {
  const DoneCollectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TodoProvider>();
    final wishes = provider.completedWishes;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Group by year
    final byYear = <int, List<Todo>>{};
    for (final w in wishes) {
      (byYear[w.updatedAt.year] ??= []).add(w);
    }
    final years = byYear.keys.toList()..sort((a, b) => b.compareTo(a));

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1A1714) : const Color(0xFFFAF5EE),
      appBar: AppBar(
        title: const Text('做过的', style: TextStyle(fontFamily: 'Noto Serif SC')),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: wishes.isEmpty
          ? const Center(
              child: Text(
                '还没有做过的想做的事\n去想做的里记下第一个吧',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Noto Serif SC', fontSize: 16, height: 1.8),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              itemCount: years.length + 1, // +1 for hero
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
                    child: Text(
                      '这些年你悄悄做成了 ${wishes.length} 件自己想做的事',
                      style: const TextStyle(
                        fontFamily: 'Noto Serif SC',
                        fontSize: 20,
                        height: 1.6,
                      ),
                    ),
                  );
                }
                final year = years[index - 1];
                final items = byYear[year]!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 24, bottom: 8, left: 8),
                      child: Text(
                        '$year  ·  ${items.length} 件',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    ...items.map((w) => ListTile(
                          title: Text(w.title, style: const TextStyle(fontFamily: 'Noto Serif SC')),
                          subtitle: Text(
                            '${w.updatedAt.month}/${w.updatedAt.day}'
                            '${w.description.isNotEmpty ? '  ${w.description}' : ''}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              fontSize: 13,
                            ),
                          ),
                        )),
                  ],
                );
              },
            ),
    );
  }
}
