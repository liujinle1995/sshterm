import 'package:flutter/material.dart';

import '../services/catalog.dart';
import 'adaptive.dart';

/// 更新记录：按时间倒序列出版本，**点标题就地展开**，不再跳二级页。
///
/// 之前是「更新记录列表 → 版本详情」两层，想看一行日志要点两次；现在最新一版
/// 进来就是展开的，等于零点击可见；想翻旧版，点一下标题原地展开即可。
class ChangelogPage extends StatelessWidget {
  const ChangelogPage({super.key, this.debugExpandIndex});

  /// 预览图 / 测试用：指定默认展开第几条（0 = 最新）。null 时展开最新那条。
  @visibleForTesting
  final int? debugExpandIndex;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('更新记录')),
      body: ReadableWidth(
        maxWidth: Adaptive.readableWidth,
        child: FutureBuilder<List<ReleaseNote>>(
          future: CatalogService().changelog(),
          builder:
              (BuildContext context, AsyncSnapshot<List<ReleaseNote>> snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final releases = snap.data ?? const <ReleaseNote>[];
                if (releases.isEmpty) {
                  return const Center(child: Text('还没有更新记录'));
                }

                final openIndex = debugExpandIndex ?? 0;
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
                  itemCount: releases.length,
                  itemBuilder: (BuildContext context, int index) => _ReleaseCard(
                    key: ValueKey<String>('release-${releases[index].version}'),
                    release: releases[index],
                    latest: index == 0,
                    initiallyOpen: index == openIndex,
                  ),
                );
              },
        ),
      ),
    );
  }
}

/// 一个版本。标题行常显，正文（摘要 + 改动条目）点了才展开。
class _ReleaseCard extends StatefulWidget {
  const _ReleaseCard({
    super.key,
    required this.release,
    required this.latest,
    required this.initiallyOpen,
  });

  final ReleaseNote release;
  final bool latest;
  final bool initiallyOpen;

  @override
  State<_ReleaseCard> createState() => _ReleaseCardState();
}

class _ReleaseCardState extends State<_ReleaseCard> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final release = widget.release;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 11, 10, 11),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Text(
                              'v${release.version}',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 14,
                                fontWeight: widget.latest
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              release.date,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            if (widget.latest) ...<Widget>[
                              const SizedBox(width: 8),
                              const _NewBadge(),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          release.tagline.isEmpty
                              ? release.summary
                              : release.tagline,
                          maxLines: _open ? null : 1,
                          overflow: _open ? null : TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _open ? 0.25 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 收起时高度收到 0（Column 的 stretch 会把宽度顶满，所以只有高度在动）
          AnimatedSize(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _open ? _body(context, release) : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, ReleaseNote release) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Divider(height: 1, thickness: 0.5, color: scheme.outlineVariant),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // 没有 tagline 时，摘要已经顶在标题里当副标题了，别再写一遍
              if (release.tagline.isNotEmpty) ...<Widget>[
                Text(
                  release.summary,
                  style: const TextStyle(fontSize: 13.5, height: 1.5),
                ),
                const SizedBox(height: 14),
              ],
              ...release.items.map(
                (ChangeItem item) => _ChangeRow(item: item),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChangeRow extends StatelessWidget {
  const _ChangeRow({required this.item});

  final ChangeItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: _ChangeBadge(type: item.type),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item.text,
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChangeBadge extends StatelessWidget {
  const _ChangeBadge({required this.type});

  final ChangeType type;

  @override
  Widget build(BuildContext context) {
    // 这几个 400 系颜色在白底上会发糊，浅色模式统一深一档
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (String label, Color color) = switch (type) {
      ChangeType.added => (
        '新增',
        dark ? Colors.teal.shade400 : Colors.teal.shade700,
      ),
      ChangeType.changed => ('调整', Colors.amber.shade700),
      ChangeType.fixed => (
        '修复',
        dark ? Colors.deepOrange.shade400 : Colors.deepOrange.shade700,
      ),
      ChangeType.removed => (
        '移除',
        dark ? Colors.red.shade400 : Colors.red.shade600,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        border: Border.all(color: color.withValues(alpha: 0.7), width: 0.8),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(label, style: TextStyle(fontSize: 10.5, color: color)),
    );
  }
}

class _NewBadge extends StatelessWidget {
  const _NewBadge();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text('最新', style: TextStyle(fontSize: 10.5, color: primary)),
    );
  }
}
