import 'package:fc_api/fc_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ветвь для обхода: имя, каталог ли и дети; null — не прочитана.
class _Node {
  _Node(this.name, {this.children, this.open = true}) : directory = true;

  _Node.file(this.name) : children = null, directory = false, open = false;

  final String name;
  final List<_Node>? children;
  final bool directory;
  final bool open;
}

/// Общий обход дерева: глубина и склейка цепочек
/// (`docs/spec/trash-unavailable.md`, §4а).
void main() {
  List<String> labels(List<_Node> roots, {bool compact = true}) => [
    for (final row in treeRows<_Node>(
      roots,
      childrenOf: (node, _) => node.children,
      isOpen: (node) => node.open,
      isDirectory: (node) => node.directory,
      compact: compact,
    ))
      '${'  ' * row.level}${[...row.absorbed.map((it) => it.name), row.branch.name].join('/')}',
  ];

  final tree = [
    _Node(
      'music',
      children: [
        _Node(
          'a',
          children: [
            _Node('b', children: [_Node.file('x.mp3')]),
          ],
        ),
        _Node.file('y.mp3'),
      ],
    ),
  ];

  test('цепочка из единственных каталогов — одной строкой', () {
    expect(labels(tree), ['music', '  a/b', '    x.mp3', '  y.mp3']);
  });

  test('без склейки — лестница', () {
    expect(labels(tree, compact: false), ['music', '  a', '    b', '      x.mp3', '  y.mp3']);
  });

  test('корень не склеивается, даже если в нём один каталог', () {
    final single = [
      _Node(
        'root',
        children: [
          _Node('only', children: [_Node.file('f')]),
        ],
      ),
    ];
    expect(labels(single), ['root', '  only', '    f']);
  });

  test('закрытый и непрочитанный каталоги цепочку обрывают', () {
    final closed = [
      _Node(
        'root',
        children: [
          _Node('a', children: [_Node('shut', open: false, children: const [])]),
          _Node('unread', children: null),
        ],
      ),
    ];
    expect(labels(closed), ['root', '  a/shut', '  unread']);
  });
}
