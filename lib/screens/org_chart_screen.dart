import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/department.dart';
import '../models/department_role.dart';
import '../models/profile.dart';
import '../providers/department_members_provider.dart';
import '../providers/departments_provider.dart';
import '../providers/roles_provider.dart';
import '../providers/settings_provider.dart';
import '../theme/nocturne_theme.dart';
import '../widgets/people_plates.dart';

/// The organization at a glance, for IT and the Operator: departments as big
/// dots, their managers and members as smaller ones, joined by lines. Hover
/// (or tap) a dot for the details; the search box dims everything that does
/// not match. Read-only: it only shows what [departmentMembersProvider] and
/// [departmentsProvider] already return to an admin.
///
/// Passwords are never shown: accounts store only a one-way hash, so there
/// is nothing to display (and nothing safe to).
class OrgChartScreen extends ConsumerStatefulWidget {
  const OrgChartScreen({super.key});

  @override
  ConsumerState<OrgChartScreen> createState() => _OrgChartScreenState();
}

class _OrgChartScreenState extends ConsumerState<OrgChartScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );
  final _viewer = TransformationController();
  final _search = TextEditingController();
  _Node? _hover;
  _Node? _pinned;
  Offset _pointer = Offset.zero;
  bool _fitted = false;

  @override
  void dispose() {
    _float.dispose();
    _viewer.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.nocturne;
    final reduceMotion = ref.watch(settingsProvider).reduceMotion;
    if (reduceMotion) {
      _float.stop();
    } else if (!_float.isAnimating) {
      _float.repeat();
    }

    final departments = ref.watch(departmentsProvider).valueOrNull ?? const [];
    final people = ref.watch(departmentMembersProvider).valueOrNull ?? const [];
    final roles = ref.watch(departmentRolesProvider).valueOrNull ?? const [];
    final layout = _layout(departments, people, roles);
    final query = _search.text.trim().toLowerCase();
    final shown = _pinned ?? _hover;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Organization'),
        actions: [
          SizedBox(
            width: 240,
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Find a person or department',
                prefixIcon: Icon(Icons.search, size: 18),
              ),
            ),
          ),
          const SizedBox(width: NocturneSpace.s4),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              NocturneSpace.s4, 0, NocturneSpace.s4, NocturneSpace.s2),
            child: Wrap(
              spacing: NocturneSpace.s4,
              runSpacing: NocturneSpace.s1,
              children: [
                _LegendDot(color: tokens.neutral300, size: 14, label: 'Department'),
                _LegendDot(color: tokens.neutral300, size: 10, label: 'Manager', ring: true),
                _LegendDot(color: tokens.neutral300, size: 8, label: 'Member'),
                Text(
                  'Hover or tap a dot for details · drag to pan · scroll to zoom',
                  style: TextStyle(fontSize: 12, color: tokens.neutral500),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                if (!_fitted && layout.size > 0) {
                  _fitted = true;
                  final s = math.min(1.0, math.min(box.maxWidth, box.maxHeight) / layout.size);
                  _viewer.value = Matrix4.translationValues(
                    (box.maxWidth - layout.size * s) / 2,
                    (box.maxHeight - layout.size * s) / 2,
                    0,
                  )..scaleByDouble(s, s, s, 1);
                }
                return Stack(
                  children: [
                    MouseRegion(
                      onHover: (e) => setState(() {
                        _pointer = e.localPosition;
                        final scene = _viewer.toScene(e.localPosition);
                        _hover = layout.hit(scene, _float.value);
                      }),
                      onExit: (_) => setState(() => _hover = null),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (d) => setState(() {
                          _pointer = d.localPosition;
                          final hit = layout.hit(_viewer.toScene(d.localPosition), _float.value);
                          _pinned = hit == _pinned ? null : hit;
                        }),
                        child: InteractiveViewer(
                          transformationController: _viewer,
                          constrained: false,
                          minScale: 0.15,
                          maxScale: 3,
                          boundaryMargin: const EdgeInsets.all(2000),
                          child: SizedBox(
                            width: layout.size,
                            height: layout.size,
                            child: CustomPaint(
                              painter: _ChartPainter(
                                layout: layout,
                                animation: _float,
                                query: query,
                                tokens: tokens,
                                accent: context.nocturneAccent,
                                highlight: shown,
                                departmentColor: context.departmentColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (shown != null)
                      Positioned(
                        left: (_pointer.dx + 16).clamp(8, math.max(8, box.maxWidth - 280)),
                        top: (_pointer.dy + 16).clamp(8, math.max(8, box.maxHeight - 220)),
                        child: IgnorePointer(child: _DetailCard(node: shown)),
                      ),
                    if (departments.isEmpty && people.isEmpty)
                      const Center(child: PanelNotice('Nothing to show yet.')),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ layout

enum _Kind { department, manager, member }

class _Node {
  _Node({
    required this.kind,
    required this.label,
    required this.base,
    required this.radius,
    required this.phase,
    required this.department,
    this.profile,
    this.title,
    this.counts,
    this.parent,
  });

  final _Kind kind;
  final String label;
  final Offset base;
  final double radius;
  final double phase;
  final Department department;
  final Profile? profile;
  final String? title;
  final String? counts;
  final _Node? parent;

  Offset at(double t) => base + Offset(
    math.sin(t * 2 * math.pi + phase) * 3,
    math.cos(t * 2 * math.pi * 1.3 + phase) * 3,
  );
}

class _Layout {
  _Layout(this.nodes, this.size);
  final List<_Node> nodes;
  final double size;

  _Node? hit(Offset scene, double t) {
    _Node? best;
    var bestD = double.infinity;
    for (final n in nodes) {
      final d = (n.at(t) - scene).distance;
      if (d <= n.radius + 6 && d < bestD) {
        best = n;
        bestD = d;
      }
    }
    return best;
  }
}

_Layout _layout(
  List<Department> departments,
  List<Profile> people,
  List<DepartmentRole> roles,
) {
  if (departments.isEmpty) return _Layout(const [], 0);
  const gap = 28.0;
  // Each department's people sit on rings around its dot.
  double ringRadiusFor(int count, {int skip = 0}) {
    var r = 46.0 + skip * gap;
    var left = count;
    while (left > 0) {
      left -= math.max(6, (2 * math.pi * r / gap).floor());
      if (left > 0) r += gap;
    }
    return r;
  }

  final byDept = {for (final d in departments) d.id: <Profile>[]};
  for (final p in people) {
    byDept[p.departmentId]?.add(p);
  }
  double outer(Department d) {
    final n = byDept[d.id]!.length;
    return n == 0 ? 40 : ringRadiusFor(n) + 24;
  }

  final op = departments.where((d) => d.isOperator).firstOrNull;
  final rest = departments.where((d) => !d.isOperator).toList()
    ..sort((a, b) => a.isIt == b.isIt ? a.name.compareTo(b.name) : (a.isIt ? -1 : 1));
  final maxOuter = [for (final d in departments) outer(d)].fold<double>(40, math.max);
  final ring = math.max(
    op == null ? 0.0 : outer(op) + maxOuter + 60,
    rest.length * (2 * maxOuter + 36) / (2 * math.pi),
  );
  final size = 2 * (ring + maxOuter + 40);
  final center = Offset(size / 2, size / 2);
  final nodes = <_Node>[];
  final rng = math.Random(7);

  void addDepartment(Department d, Offset at) {
    final members = byDept[d.id]!;
    final managers = members.where((p) => p.isManager).toList();
    final plain = members.where((p) => !p.isManager).toList();
    final node = _Node(
      kind: _Kind.department,
      label: d.name,
      base: at,
      radius: 17,
      phase: rng.nextDouble() * 6.28,
      department: d,
      counts: '${managers.length} manager${managers.length == 1 ? '' : 's'} · '
          '${plain.length} member${plain.length == 1 ? '' : 's'}',
    );
    nodes.add(node);

    void place(List<Profile> list, double startRadius, _Kind kind, double dotRadius) {
      var i = 0;
      var r = startRadius;
      while (i < list.length) {
        final cap = math.max(6, (2 * math.pi * r / gap).floor());
        final take = math.min(cap, list.length - i);
        for (var k = 0; k < take; k++) {
          final a = 2 * math.pi * k / take + r * 0.05;
          final p = list[i + k];
          nodes.add(_Node(
            kind: kind,
            label: p.displayName,
            base: at + Offset(math.cos(a), math.sin(a)) * r,
            radius: dotRadius,
            phase: rng.nextDouble() * 6.28,
            department: d,
            profile: p,
            title: roles.where((x) => x.id == p.customRoleId).firstOrNull?.name,
            parent: node,
          ));
        }
        i += take;
        r += gap;
      }
    }

    place(managers, 46, _Kind.manager, 8);
    final used = managers.isEmpty ? 0 : ringRadiusFor(managers.length) - 46;
    place(plain, 46 + (managers.isEmpty ? 0 : used + gap), _Kind.member, 6);
  }

  if (op != null) addDepartment(op, center);
  for (var i = 0; i < rest.length; i++) {
    final a = 2 * math.pi * i / rest.length - math.pi / 2;
    addDepartment(rest[i], center + Offset(math.cos(a), math.sin(a)) * ring);
  }
  return _Layout(nodes, size);
}

// ---------------------------------------------------------------- painting

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.layout,
    required this.animation,
    required this.query,
    required this.tokens,
    required this.accent,
    required this.highlight,
    required this.departmentColor,
  }) : super(repaint: animation);

  final _Layout layout;
  final Animation<double> animation;
  final String query;
  final NocturneColors tokens;
  final Color accent;
  final _Node? highlight;
  final Color Function(String) departmentColor;

  bool _matches(_Node n) {
    if (query.isEmpty) return true;
    return n.label.toLowerCase().contains(query) ||
        (n.profile?.username.toLowerCase().contains(query) ?? false) ||
        n.department.name.toLowerCase().contains(query) && n.kind == _Kind.department;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final line = Paint()..strokeWidth = 1;
    // lines first, so dots sit on top
    for (final n in layout.nodes) {
      final parent = n.parent;
      if (parent == null) continue;
      final dim = !(_matches(n) || _matches(parent));
      line.color = (n.kind == _Kind.manager ? tokens.neutral600 : tokens.neutral700)
          .withValues(alpha: dim ? 0.15 : 0.7);
      canvas.drawLine(parent.at(t), n.at(t), line);
    }
    for (final n in layout.nodes) {
      final p = n.at(t);
      final hue = departmentColor(n.department.name);
      final dim = !_matches(n);
      final alpha = dim ? 0.2 : 1.0;
      final isHot = identical(n, highlight);
      switch (n.kind) {
        case _Kind.department:
          canvas.drawCircle(p, n.radius + (isHot ? 3 : 0), Paint()..color = hue.withValues(alpha: alpha));
          if (n.department.isOperator || n.department.isIt) {
            canvas.drawCircle(
              p,
              n.radius + 5,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2
                ..color = accent.withValues(alpha: alpha),
            );
          }
          final tp = TextPainter(
            text: TextSpan(
              text: n.label,
              style: TextStyle(
                fontFamily: 'IBMPlexSans',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: tokens.text.withValues(alpha: alpha),
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, p + Offset(-tp.width / 2, -n.radius - 24));
        case _Kind.manager:
          canvas.drawCircle(p, n.radius + (isHot ? 3 : 0), Paint()..color = hue.withValues(alpha: alpha));
          canvas.drawCircle(
            p,
            n.radius + 3,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = hue.withValues(alpha: alpha),
          );
        case _Kind.member:
          canvas.drawCircle(p, n.radius + (isHot ? 3 : 0), Paint()..color = hue.withValues(alpha: alpha * 0.8));
      }
      if (isHot) {
        canvas.drawCircle(
          p,
          n.radius + 7,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = tokens.text,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) =>
      old.query != query || old.highlight != highlight || old.layout != layout || old.tokens != tokens;
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.size, required this.label, this.ring = false});

  final Color color;
  final double size;
  final String label;
  final bool ring;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: ring ? Border.all(color: color, width: 2) : null,
        ),
      ),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(fontSize: 12, color: context.nocturne.neutral400)),
    ],
  );
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.node});

  final _Node node;

  @override
  Widget build(BuildContext context) {
    final tokens = context.nocturne;
    final p = node.profile;
    final rows = <(String, String)>[];
    if (p == null) {
      rows.add(('Type', node.department.isOperator
          ? 'Operator department'
          : node.department.isIt
          ? 'IT department'
          : 'Department'));
      rows.add(('People', node.counts ?? ''));
    } else {
      rows.add(('Role', p.isManager ? 'Manager' : (node.title ?? 'Member')));
      rows.add(('Username', p.username));
      rows.add(('Department', node.department.name));
      if (p.createdAt != null) {
        final d = p.createdAt!.toLocal();
        rows.add(('Account created',
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}'));
      }
      rows.add(('Password', 'Stored encrypted; cannot be shown'));
    }
    return Material(
      color: tokens.surface,
      elevation: 8,
      borderRadius: BorderRadius.circular(NocturneRadius.lg),
      child: Container(
        width: 264,
        padding: const EdgeInsets.all(NocturneSpace.s3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(NocturneRadius.lg),
          border: Border.all(color: tokens.edge),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(node.label, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: NocturneSpace.s2),
            for (final (k, v) in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 104,
                      child: Text(k, style: TextStyle(fontSize: 12, color: tokens.neutral500)),
                    ),
                    Expanded(child: Text(v, style: const TextStyle(fontSize: 12))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
