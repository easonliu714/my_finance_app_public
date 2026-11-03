// C500-G0l: isolated bounded XRef-stream object-access experiment.
// Reads only the pinned PDF's startxref stream; never opens a whole-document
// object graph or promotes any invoice/winning/NOT_WIN authority.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'c500_g0_content_glyph_probe.dart';

import 'package:my_finance_app/features/invoice/invoice_award_cloud_pdf_bounded_stream_decoder.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_pdf_structure_probe.dart';

class C500G0BoundedXrefException implements Exception {
  const C500G0BoundedXrefException(this.code);
  final String code;
  @override
  String toString() => code;
}

// G0o.4: lab-only source selector for independent per-period wall-clock
// budgets. The default remains BOTH pinned sources. A one-period run is
// permitted ONLY for the all-root-subtrees diagnostic, never award authority.
class C500G0OfficialPeriodSelector {
  const C500G0OfficialPeriodSelector();

  static const periods = <String>['115-05-06', '115-07-08'];

  List<String> select({
    required String? requestedPeriod,
    required bool allowSinglePeriod,
  }) {
    if (requestedPeriod == null) return periods;
    if (!allowSinglePeriod || !periods.contains(requestedPeriod)) {
      throw const C500G0BoundedXrefException(
          'C500_G0O4_PERIOD_SELECTION_INVALID');
    }
    return <String>[requestedPeriod];
  }
}

// G0j: bounded, exact /Kids reference selection. Never scan arbitrary siblings
// or infer complete page-tree / sorted-award coverage from one branch.
class C500G0RootKidSelector {
  const C500G0RootKidSelector();

  (int, int) select(String pagesBody, int ordinal) {
    if (ordinal != 0 && ordinal != 1 && ordinal != 2 &&
        ordinal != -1 && ordinal != -2) {
      throw const C500G0BoundedXrefException('C500_G0J_ORDINAL_INVALID');
    }
    // G0o.7: duplicate /Kids dictionaries are ambiguous; fail closed.
    final kidsGroups = RegExp(r'/Kids\s*\[([^\]]{0,65536})\]')
        .allMatches(pagesBody).toList();
    if (kidsGroups.length != 1) {
      throw const C500G0BoundedXrefException('C500_G0T_KIDS_FORM_UNSUPPORTED');
    }
    final kids = kidsGroups.single.group(1)!;
    final reference = RegExp(r'(\d+)\s+(\d+)\s+R\b');
    final matches = reference.allMatches(kids).toList();
    if (matches.isEmpty || matches.length > 2048 ||
        kids.replaceAll(reference, '').trim().isNotEmpty) {
      throw const C500G0BoundedXrefException('C500_G0J_KIDS_GRAMMAR_INVALID');
    }
    // G0o.10: one PDF object number cannot be counted as distinct /Kids
    // merely by changing its generation or zero-padding its spelling.
    final seen = <int>{};
    for (final match in matches) {
      if (!seen.add(int.parse(match.group(1)!))) {
        throw const C500G0BoundedXrefException('C500_G0J_DUPLICATE_KID');
      }
    }
    // G0m: select a genuinely new far-tail subtree without enumerating
    // page descendants. A two-child root cannot count as new coverage.
    if (ordinal == -1 && matches.length < 3) {
      throw const C500G0BoundedXrefException('C500_G0M_LAST_ROOT_CHILD_NOT_DISTINCT');
    }
    // G0n: an interior subtree must differ from first, second and tail.
    if (ordinal == -2 && matches.length < 5) {
      throw const C500G0BoundedXrefException('C500_G0N_MIDDLE_ROOT_CHILD_NOT_DISTINCT');
    }
    final selectedIndex = ordinal == -2 ? matches.length ~/ 2
        : ordinal == -1 ? matches.length - 1 : ordinal;
    if (matches.length <= selectedIndex) {
      throw const C500G0BoundedXrefException('C500_G0J_SECOND_ROOT_CHILD_MISSING');
    }
    final selected = matches[selectedIndex];
    return (int.parse(selected.group(1)!), int.parse(selected.group(2)!));
  }
}

// G0o: bounded root-level /Kids Count crosscheck. This validates only
// immediate children, never their descendants, ordering or NOT_WIN.
class C500G0RootChildCountAuditor {
  const C500G0RootChildCountAuditor();

  Future<Map<String, Object?>> inspect({
    required String pagesBody,
    required int rootId,
    required int rootGeneration,
    required int declaredPages,
    required C500G0ReadObject readObject,
  }) async {
    if (declaredPages <= 0 || declaredPages > 1000000) {
      throw const C500G0BoundedXrefException('C500_G0O_ROOT_COUNT_INVALID');
    }
    final groups = RegExp(r'/Kids\s*\[([^\]]{0,65536})\]')
        .allMatches(pagesBody).toList();
    if (groups.length != 1) {
      throw const C500G0BoundedXrefException('C500_G0O_ROOT_KIDS_INVALID');
    }
    final raw = groups.single.group(1)!;
    final reference = RegExp(r'(\d+)\s+(\d+)\s+R\b');
    final kids = reference.allMatches(raw).toList();
    if (kids.isEmpty || kids.length > 64 ||
        raw.replaceAll(reference, '').trim().isNotEmpty) {
      throw const C500G0BoundedXrefException('C500_G0O_ROOT_KIDS_BUDGET_OR_GRAMMAR');
    }
    final seen = <int>{rootId};
    var sum = 0;
    for (final kid in kids) {
      final id = int.parse(kid.group(1)!);
      final generation = int.parse(kid.group(2)!);
      if (!seen.add(id)) {
        throw const C500G0BoundedXrefException('C500_G0O_ROOT_KID_DUPLICATE_OR_CYCLE');
      }
      final body = await readObject(id, generation);
      final pages = RegExp(r'/Type\s*/Pages\b').hasMatch(body);
      final page = RegExp(r'/Type\s*/Page\b').hasMatch(body);
      if (pages == page) {
        throw const C500G0BoundedXrefException('C500_G0O_ROOT_KID_TYPE_INVALID');
      }
      final parents = RegExp(r'/Parent\s+(\d+)\s+(\d+)\s+R\b')
          .allMatches(body).toList();
      if (parents.length != 1 ||
          int.parse(parents.single.group(1)!) != rootId ||
          int.parse(parents.single.group(2)!) != rootGeneration) {
        throw const C500G0BoundedXrefException('C500_G0O_ROOT_KID_PARENT_MISMATCH');
      }
      final counts = RegExp(r'/Count\s+(\d+)\b').allMatches(body).toList();
      if ((pages && counts.length != 1) || (page && counts.isNotEmpty)) {
        throw const C500G0BoundedXrefException('C500_G0O_ROOT_KID_COUNT_INVALID');
      }
      final count = pages ? int.parse(counts.single.group(1)!) : 1;
      if (count <= 0 || count > declaredPages || sum > declaredPages - count) {
        throw const C500G0BoundedXrefException('C500_G0O_ROOT_KID_COUNT_OVERFLOW');
      }
      sum += count;
    }
    if (sum != declaredPages) {
      throw const C500G0BoundedXrefException('C500_G0O_ROOT_COUNT_SUM_MISMATCH');
    }
    return <String, Object?>{
      'root_child_count': kids.length,
      'root_child_declared_count_sum': sum,
      'root_level_count_consistency':
          'VERIFIED_IMMEDIATE_CHILDREN_ONLY_DESCENDANTS_UNKNOWN',
    };
  }
}

// G0o.1/G0o.2: verify root plus one selected subtree /Kids and /Count.
// Each level is bounded to 64 pinned references; deeper pages stay UNKNOWN.
class C500G0FirstRootSubtreeCountAuditor {
  const C500G0FirstRootSubtreeCountAuditor();

  Future<Map<String, Object?>> inspect({
    required String pagesBody,
    required int rootId,
    required int rootGeneration,
    required int declaredPages,
    required C500G0ReadObject readObject,
    int rootChildOrdinal = 0,
  }) async {
    if (rootChildOrdinal != 0 && rootChildOrdinal != 1 &&
        rootChildOrdinal != 2) {
      throw const C500G0BoundedXrefException('C500_G0O2_ORDINAL_INVALID');
    }
    final root = await const C500G0RootChildCountAuditor().inspect(
      pagesBody: pagesBody,
      rootId: rootId,
      rootGeneration: rootGeneration,
      declaredPages: declaredPages,
      readObject: readObject,
    );
    final selected = const C500G0RootKidSelector()
        .select(pagesBody, rootChildOrdinal);
    final label = rootChildOrdinal == 0 ? 'first'
        : rootChildOrdinal == 1 ? 'second' : 'third';
    final body = await readObject(selected.$1, selected.$2);
    if (!RegExp(r'/Type\s*/Pages\b').hasMatch(body) ||
        RegExp(r'/Type\s*/Page\b').hasMatch(body)) {
      throw const C500G0BoundedXrefException(
          'C500_G0O1_FIRST_SUBTREE_NOT_PAGES');
    }
    final counts = RegExp(r'/Count\s+(\d+)\b').allMatches(body).toList();
    if (counts.length != 1) {
      throw const C500G0BoundedXrefException(
          'C500_G0O1_FIRST_SUBTREE_COUNT_INVALID');
    }
    final declared = int.parse(counts.single.group(1)!);
    if (declared <= 0 || declared > declaredPages) {
      throw const C500G0BoundedXrefException(
          'C500_G0O1_FIRST_SUBTREE_COUNT_BOUNDS');
    }
    final subtree = await const C500G0RootChildCountAuditor().inspect(
      pagesBody: body,
      rootId: selected.$1,
      rootGeneration: selected.$2,
      declaredPages: declared,
      readObject: readObject,
    );
    return <String, Object?>{
      ...root,
      '${label}_root_subtree_id': selected.$1,
      '${label}_root_subtree_declared_count': declared,
      '${label}_root_subtree_child_count': subtree['root_child_count'],
      '${label}_root_subtree_child_count_sum':
          subtree['root_child_declared_count_sum'],
      '${label}_root_subtree_consistency':
          'VERIFIED_TWO_LEVELS_ONLY_DEEPER_DESCENDANTS_UNKNOWN',
    };
  }
}

// G0o.4: all root subtrees' second-level /Kids custody, not leaf coverage.
// Fixed 16-root and 192-grandchild budget; pinned XRef reader only.
class C500G0AllRootSubtreesCountAuditor {
  const C500G0AllRootSubtreesCountAuditor();

  Future<Map<String, Object?>> inspect({
    required String pagesBody,
    required int rootId,
    required int rootGeneration,
    required int declaredPages,
    required C500G0ReadObject readObject,
  }) async {
    final root = await const C500G0RootChildCountAuditor().inspect(
      pagesBody: pagesBody, rootId: rootId,
      rootGeneration: rootGeneration, declaredPages: declaredPages,
      readObject: readObject,
    );
    final raw = RegExp(r'/Kids\s*\[([^\]]{0,65536})\]')
        .firstMatch(pagesBody)?.group(1);
    if (raw == null) {
      throw const C500G0BoundedXrefException('C500_G0O4_ROOT_KIDS_MISSING');
    }
    final reference = RegExp(r'(\d+)\s+(\d+)\s+R\b');
    final children = reference.allMatches(raw).toList();
    if (children.isEmpty || children.length > 16 ||
        raw.replaceAll(reference, '').trim().isNotEmpty) {
      throw const C500G0BoundedXrefException('C500_G0O4_ROOT_BUDGET');
    }
    final seen = <int>{rootId};
    for (final child in children) {
      if (!seen.add(int.parse(child.group(1)!))) {
        throw const C500G0BoundedXrefException('C500_G0O4_CROSS_BRANCH_DUPLICATE');
      }
    }
    var grandchildren = 0;
    var sum = 0;
    for (final child in children) {
      final id = int.parse(child.group(1)!);
      final generation = int.parse(child.group(2)!);
      final body = await readObject(id, generation);
      if (!RegExp(r'/Type\s*/Pages\b').hasMatch(body) ||
          RegExp(r'/Type\s*/Page\b').hasMatch(body)) {
        throw const C500G0BoundedXrefException('C500_G0O4_ROOT_CHILD_NOT_PAGES');
      }
      final counts = RegExp(r'/Count\s+(\d+)\b').allMatches(body).toList();
      if (counts.length != 1) {
        throw const C500G0BoundedXrefException('C500_G0O4_COUNT_INVALID');
      }
      final declared = int.parse(counts.single.group(1)!);
      if (declared <= 0 || declared > declaredPages ||
          sum > declaredPages - declared) {
        throw const C500G0BoundedXrefException('C500_G0O4_COUNT_BOUNDS');
      }
      final nestedRaw = RegExp(r'/Kids\s*\[([^\]]{0,65536})\]')
          .firstMatch(body)?.group(1);
      if (nestedRaw == null) {
        throw const C500G0BoundedXrefException('C500_G0O4_NESTED_KIDS_MISSING');
      }
      final nested = reference.allMatches(nestedRaw).toList();
      if (nested.isEmpty || nested.length > 64 ||
          grandchildren + nested.length > 192 ||
          nestedRaw.replaceAll(reference, '').trim().isNotEmpty) {
        throw const C500G0BoundedXrefException('C500_G0O4_TOTAL_BUDGET');
      }
      for (final grandchild in nested) {
        if (!seen.add(int.parse(grandchild.group(1)!))) {
          throw const C500G0BoundedXrefException('C500_G0O4_CROSS_BRANCH_DUPLICATE');
        }
      }
      final audit = await const C500G0RootChildCountAuditor().inspect(
        pagesBody: body, rootId: id, rootGeneration: generation,
        declaredPages: declared, readObject: readObject,
      );
      if (audit['root_child_count'] != nested.length ||
          audit['root_child_declared_count_sum'] != declared) {
        throw const C500G0BoundedXrefException('C500_G0O4_SUBTREE_COUNT_MISMATCH');
      }
      grandchildren += nested.length;
      sum += declared;
    }
    if (sum != declaredPages) {
      throw const C500G0BoundedXrefException('C500_G0O4_TOTAL_COUNT_MISMATCH');
    }
    return <String, Object?>{
      ...root,
      'all_root_subtrees_audited': children.length,
      'all_root_subtrees_grandchild_refs_verified': grandchildren,
      'all_root_subtrees_declared_count_sum': sum,
      'all_root_subtrees_consistency':
          'VERIFIED_ALL_ROOT_SUBTREES_TWO_LEVELS_DEEPER_UNKNOWN',
    };
  }
}

// G0o.5: bounded third-level /Parent and /Count audit of ALL grandchildren
// under the first root branch. Other branches and every leaf remain UNKNOWN.
class C500G0FirstBranchAllGrandchildrenAuditor {
  const C500G0FirstBranchAllGrandchildrenAuditor();

  Future<Map<String, Object?>> inspect({
    required String pagesBody,
    required int rootId,
    required int rootGeneration,
    required int declaredPages,
    required C500G0ReadObject readObject,
    int rootChildOrdinal = 0,
  }) async {
    if (rootChildOrdinal != 0 && rootChildOrdinal != 1 &&
        rootChildOrdinal != 2) {
      throw const C500G0BoundedXrefException('C500_G0O6_ORDINAL_INVALID');
    }
    final two = await const C500G0FirstRootSubtreeCountAuditor().inspect(
      pagesBody: pagesBody, rootId: rootId,
      rootGeneration: rootGeneration, declaredPages: declaredPages,
      readObject: readObject,
      rootChildOrdinal: rootChildOrdinal,
    );
    final selected = const C500G0RootKidSelector().select(pagesBody, rootChildOrdinal);
    final branch = await readObject(selected.$1, selected.$2);
    final label = rootChildOrdinal == 0 ? 'first'
        : rootChildOrdinal == 1 ? 'second' : 'third';
    final expected = two['${label}_root_subtree_declared_count']! as int;
    final groups = RegExp(r'/Kids\s*\[([^\]]{0,65536})\]')
        .allMatches(branch).toList();
    if (groups.length != 1) {
      throw const C500G0BoundedXrefException('C500_G0O5_KIDS_INVALID');
    }
    final raw = groups.single.group(1)!;
    final reference = RegExp(r'(\d+)\s+(\d+)\s+R\b');
    final grandchildren = reference.allMatches(raw).toList();
    if (grandchildren.isEmpty || grandchildren.length > 16 ||
        raw.replaceAll(reference, '').trim().isNotEmpty) {
      throw const C500G0BoundedXrefException('C500_G0O5_BRANCH_BUDGET');
    }
    final rootRaw = RegExp(r'/Kids\s*\[([^\]]{0,65536})\]')
        .firstMatch(pagesBody)!.group(1)!;
    final seen = <int>{rootId};
    for (final kid in reference.allMatches(rootRaw)) {
      if (!seen.add(int.parse(kid.group(1)!))) {
        throw const C500G0BoundedXrefException('C500_G0O5_ALIAS_OR_CYCLE');
      }
    }
    for (final kid in grandchildren) {
      if (!seen.add(int.parse(kid.group(1)!))) {
        throw const C500G0BoundedXrefException('C500_G0O5_ALIAS_OR_CYCLE');
      }
    }
    var sum = 0;
    var descendants = 0;
    for (final kid in grandchildren) {
      final id = int.parse(kid.group(1)!);
      final generation = int.parse(kid.group(2)!);
      final body = await readObject(id, generation);
      if (!RegExp(r'/Type\s*/Pages\b').hasMatch(body) ||
          RegExp(r'/Type\s*/Page\b').hasMatch(body)) {
        throw const C500G0BoundedXrefException('C500_G0O5_NOT_PAGES');
      }
      final counts = RegExp(r'/Count\s+(\d+)\b').allMatches(body).toList();
      if (counts.length != 1) {
        throw const C500G0BoundedXrefException('C500_G0O5_COUNT_INVALID');
      }
      final count = int.parse(counts.single.group(1)!);
      if (count <= 0 || count > expected || sum > expected - count) {
        throw const C500G0BoundedXrefException('C500_G0O5_COUNT_BOUNDS');
      }
      final nestedGroups = RegExp(r'/Kids\s*\[([^\]]{0,65536})\]')
          .allMatches(body).toList();
      if (nestedGroups.length != 1) {
        throw const C500G0BoundedXrefException('C500_G0O5_NESTED_KIDS_INVALID');
      }
      final nestedRaw = nestedGroups.single.group(1)!;
      final nested = reference.allMatches(nestedRaw).toList();
      if (nested.isEmpty || nested.length > 64 ||
          descendants + nested.length > 256 ||
          nestedRaw.replaceAll(reference, '').trim().isNotEmpty) {
        throw const C500G0BoundedXrefException('C500_G0O5_TOTAL_BUDGET');
      }
      for (final child in nested) {
        if (!seen.add(int.parse(child.group(1)!))) {
          throw const C500G0BoundedXrefException('C500_G0O5_ALIAS_OR_CYCLE');
        }
      }
      final audit = await const C500G0RootChildCountAuditor().inspect(
        pagesBody: body, rootId: id, rootGeneration: generation,
        declaredPages: count, readObject: readObject,
      );
      if (audit['root_child_count'] != nested.length ||
          audit['root_child_declared_count_sum'] != count) {
        throw const C500G0BoundedXrefException('C500_G0O5_CHILD_SUM_MISMATCH');
      }
      sum += count;
      descendants += nested.length;
    }
    if (sum != expected) {
      throw const C500G0BoundedXrefException('C500_G0O5_BRANCH_SUM_MISMATCH');
    }
    return <String, Object?>{
      ...two,
      '${label}_branch_grandchildren_audited': grandchildren.length,
      '${label}_branch_great_grandchildren_refs_verified': descendants,
      '${label}_branch_third_level_count_sum': sum,
      '${label}_branch_third_level_consistency':
          'VERIFIED_SELECTED_BRANCH_THREE_LEVELS_OTHER_BRANCHES_AND_LEAVES_UNKNOWN',
    };
  }
}

// G0o.3: bounded third-level /Kids custody on one first branch only.
class C500G0ThreeLevelFirstBranchAuditor {
  const C500G0ThreeLevelFirstBranchAuditor();
  Future<Map<String, Object?>> inspect({
    required String pagesBody, required int rootId,
    required int rootGeneration, required int declaredPages,
    required C500G0ReadObject readObject,
  }) async {
    final two = await const C500G0FirstRootSubtreeCountAuditor().inspect(
      pagesBody: pagesBody, rootId: rootId,
      rootGeneration: rootGeneration, declaredPages: declaredPages,
      readObject: readObject,
    );
    final first = const C500G0RootKidSelector().select(pagesBody, 0);
    final firstBody = await readObject(first.$1, first.$2);
    final child = const C500G0RootKidSelector().select(firstBody, 0);
    if (child.$1 == rootId || child.$1 == first.$1) {
      throw const C500G0BoundedXrefException('C500_G0O3_BRANCH_CYCLE');
    }
    final body = await readObject(child.$1, child.$2);
    if (!RegExp(r'/Type\s*/Pages\b').hasMatch(body) ||
        RegExp(r'/Type\s*/Page\b').hasMatch(body)) {
      throw const C500G0BoundedXrefException('C500_G0O3_GRANDCHILD_NOT_PAGES');
    }
    final matches = RegExp(r'/Count\s+(\d+)\b').allMatches(body).toList();
    if (matches.length != 1) {
      throw const C500G0BoundedXrefException('C500_G0O3_COUNT_INVALID');
    }
    final count = int.parse(matches.single.group(1)!);
    if (count <= 0 ||
        count > (two['first_root_subtree_declared_count']! as int)) {
      throw const C500G0BoundedXrefException('C500_G0O3_COUNT_BOUNDS');
    }
    final third = await const C500G0RootChildCountAuditor().inspect(
      pagesBody: body, rootId: child.$1, rootGeneration: child.$2,
      declaredPages: count, readObject: readObject,
    );
    return <String, Object?>{
      ...two,
      'first_grandchild_subtree_id': child.$1,
      'first_grandchild_subtree_declared_count': count,
      'first_grandchild_subtree_child_count': third['root_child_count'],
      'first_grandchild_subtree_child_count_sum':
          third['root_child_declared_count_sum'],
      'first_grandchild_subtree_consistency':
          'VERIFIED_THREE_LEVELS_ONE_BRANCH_ONLY_REMAINDER_UNKNOWN',
    };
  }
}

// G0r: pinned-XRef midpoint ordinal-to-leaf path, not a global scan.
// Bounded to 8 levels and 512 object reads; all siblings at each visited
// level must agree on /Count, /Parent and unique object identities.
class C500G0MidpointPageAuditor {
  const C500G0MidpointPageAuditor();
  Future<Map<String, Object?>> inspect({
    required String pagesBody, required int rootId,
    required int rootGeneration, required int declaredPages,
    required C500G0ReadObject readObject,
  }) async {
    if (declaredPages <= 0 || declaredPages > 100000) {
      throw const C500G0BoundedXrefException('C500_G0R_COUNT_LIMIT');
    }
    final target = declaredPages ~/ 2;
    var ordinal = target;
    var nodeId = rootId, nodeGeneration = rootGeneration;
    var nodeBody = pagesBody, nodeCount = declaredPages, objectsRead = 0;
    final seen = <int>{rootId};
    final reference = RegExp(r'(\d+)\s+(\d+)\s+R\b');
    for (var depth = 1; depth <= 8; depth++) {
      if (!RegExp(r'/Type\s*/Pages\b').hasMatch(nodeBody) ||
          RegExp(r'/Type\s*/Page\b').hasMatch(nodeBody)) {
        throw const C500G0BoundedXrefException('C500_G0R_PARENT_NOT_PAGES');
      }
      final counts = RegExp(r'/Count\s+(\d+)\b').allMatches(nodeBody).toList();
      if (counts.length != 1 ||
          int.parse(counts.single.group(1)!) != nodeCount) {
        throw const C500G0BoundedXrefException('C500_G0R_PARENT_COUNT_MISMATCH');
      }
      final groups = RegExp(r'/Kids\s*\[([^\]]{0,65536})\]')
          .allMatches(nodeBody).toList();
      if (groups.length != 1) {
        throw const C500G0BoundedXrefException('C500_G0R_KIDS_AMBIGUOUS');
      }
      final raw = groups.single.group(1)!;
      final refs = reference.allMatches(raw).toList();
      if (refs.isEmpty || refs.length > 64 ||
          raw.replaceAll(reference, '').trim().isNotEmpty) {
        throw const C500G0BoundedXrefException('C500_G0R_KIDS_BUDGET_OR_GRAMMAR');
      }
      var sum = 0;
      int? selectedId, selectedGeneration, selectedStart, selectedCount;
      String? selectedBody;
      var selectedIsPage = false;
      for (final ref in refs) {
        final id = int.parse(ref.group(1)!);
        final generation = int.parse(ref.group(2)!);
        if (++objectsRead > 512 || !seen.add(id)) {
          throw const C500G0BoundedXrefException('C500_G0R_BUDGET_ALIAS_OR_CYCLE');
        }
        final body = await readObject(id, generation);
        final parents = RegExp(r'/Parent\s+(\d+)\s+(\d+)\s+R\b')
            .allMatches(body).toList();
        if (parents.length != 1 ||
            int.parse(parents.single.group(1)!) != nodeId ||
            int.parse(parents.single.group(2)!) != nodeGeneration) {
          throw const C500G0BoundedXrefException('C500_G0R_PARENT_MISMATCH');
        }
        final isPages = RegExp(r'/Type\s*/Pages\b').hasMatch(body);
        final isPage = RegExp(r'/Type\s*/Page\b').hasMatch(body);
        if (isPages == isPage) {
          throw const C500G0BoundedXrefException('C500_G0R_CHILD_TYPE_INVALID');
        }
        final childCounts = RegExp(r'/Count\s+(\d+)\b')
            .allMatches(body).toList();
        if ((isPages && childCounts.length != 1) ||
            (isPage && (childCounts.isNotEmpty ||
                RegExp(r'/Kids\s*\[').hasMatch(body)))) {
          throw const C500G0BoundedXrefException('C500_G0R_CHILD_COUNT_INVALID');
        }
        final count = isPages ? int.parse(childCounts.single.group(1)!) : 1;
        if (count <= 0 || count > nodeCount || sum > nodeCount - count) {
          throw const C500G0BoundedXrefException('C500_G0R_COUNT_OVERFLOW');
        }
        if (selectedId == null && ordinal >= sum && ordinal < sum + count) {
          selectedId = id; selectedGeneration = generation;
          selectedStart = sum; selectedCount = count;
          selectedBody = body; selectedIsPage = isPage;
        }
        sum += count;
      }
      if (sum != nodeCount || selectedId == null) {
        throw const C500G0BoundedXrefException('C500_G0R_SIBLING_SUM_MISMATCH');
      }
      if (selectedIsPage) {
        if (ordinal != selectedStart) {
          throw const C500G0BoundedXrefException('C500_G0R_LEAF_ORDINAL_MISMATCH');
        }
        return <String, Object?>{
          'midpoint_page_index': target,
          'midpoint_leaf_id': selectedId,
          'midpoint_leaf_generation': selectedGeneration,
          'midpoint_path_depth': depth,
          'midpoint_path_objects_read': objectsRead,
          'midpoint_path_status': 'ONE_XREF_BOUND_LEAF_AND_ANCESTRY_ONLY',
          'all_pages': 'NOT_VERIFIED', 'global_not_win': 'NOT_PROVEN',
        };
      }
      ordinal -= selectedStart!;
      nodeId = selectedId;
      nodeGeneration = selectedGeneration!;
      nodeBody = selectedBody!;
      nodeCount = selectedCount!;
    }
    throw const C500G0BoundedXrefException('C500_G0R_DEPTH_LIMIT');
  }
}

class C500G0BoundedXrefInspector {
  const C500G0BoundedXrefInspector({
    this.maxHeaderBytes = 1024 * 1024,
    this.maxCompressedBytes = 32 * 1024 * 1024,
    this.maxDecodedBytes = 64 * 1024 * 1024,
    this.maxRootDecodedBytes = 512 * 1024 * 1024,
  });

  final int maxHeaderBytes;
  final int maxCompressedBytes;
  final int maxDecodedBytes;
  // Lab-only total decompressed-byte budget; never a heap or product limit.
  final int maxRootDecodedBytes;

  Future<Map<String, Object?>> inspect({
    required File file,
    required int expectedBytes,
    required String expectedSha256,
    bool verifyObjectOffsets = false,
    bool verifyCompressedMembers = false,
    bool verifyCatalogRoot = false,
    bool verifyFirstPageChild = false,
    bool verifyFirstPagePath = false,
    bool verifyFirstPageContents = false,
    bool verifyFirstPageGlyphOperands = false,
    bool verifyFirstPageFontResources = false,
    bool verifyFirstPageCmapStreams = false,
    bool verifyFirstPageCmapSemantics = false,
    bool verifyFirstPageGlyphUnicode = false,
    bool verifyFirstPageOperandUnicodeRun = false,
    bool verifyFirstPageAllOperandsUnicode = false,
    // G0j: second root-child's leftmost leaf, NOT the document's second page.
    int rootChildOrdinal = 0,
    bool verifyRootChildCounts = false,
    bool verifyFirstRootSubtreeCounts = false,
    bool verifySecondRootSubtreeCounts = false,
    bool verifyFirstGrandchildCounts = false,
    bool verifyAllRootSubtreesCounts = false,
    bool verifyFirstBranchAllGrandchildrenCounts = false,
    bool verifyMidpointPagePath = false,
  }) async {
    if (rootChildOrdinal != 0 && rootChildOrdinal != 1 &&
        rootChildOrdinal != 2 && rootChildOrdinal != -1 &&
        rootChildOrdinal != -2) {
      throw const C500G0BoundedXrefException('C500_G0J_ORDINAL_INVALID');
    }
    if (verifyMidpointPagePath &&
        (verifyRootChildCounts || verifyFirstPageChild ||
         verifyFirstPagePath || verifyFirstBranchAllGrandchildrenCounts ||
         verifyAllRootSubtreesCounts || verifyFirstGrandchildCounts ||
         verifyFirstRootSubtreeCounts || verifySecondRootSubtreeCounts)) {
      throw const C500G0BoundedXrefException('C500_G0R_EXCLUSIVE_AUDIT');
    }
    if (verifyMidpointPagePath && !verifyCatalogRoot) {
      throw const C500G0BoundedXrefException('C500_G0R_REQUIRES_PINNED_ROOT');
    }
    if (verifyFirstBranchAllGrandchildrenCounts &&
        (verifyAllRootSubtreesCounts || verifyFirstGrandchildCounts ||
         verifyFirstRootSubtreeCounts || verifySecondRootSubtreeCounts)) {
      throw const C500G0BoundedXrefException('C500_G0O5_EXCLUSIVE_AUDIT');
    }
    if (verifyAllRootSubtreesCounts &&
        (verifyFirstGrandchildCounts || verifyFirstRootSubtreeCounts ||
         verifySecondRootSubtreeCounts)) {
      throw const C500G0BoundedXrefException('C500_G0O4_EXCLUSIVE_AUDIT');
    }
    if (verifyFirstGrandchildCounts &&
        (verifyFirstRootSubtreeCounts || verifySecondRootSubtreeCounts)) {
      throw const C500G0BoundedXrefException('C500_G0O3_EXCLUSIVE_AUDIT');
    }
    if (verifyFirstRootSubtreeCounts && verifySecondRootSubtreeCounts) {
      throw const C500G0BoundedXrefException('C500_G0O2_EXCLUSIVE_AUDIT');
    }
    if (verifySecondRootSubtreeCounts && rootChildOrdinal != 1) {
      throw const C500G0BoundedXrefException('C500_G0O2_REQUIRES_SECOND_CHILD');
    }
    if ((verifyFirstRootSubtreeCounts || verifySecondRootSubtreeCounts ||
        verifyFirstGrandchildCounts || verifyAllRootSubtreesCounts ||
        verifyFirstBranchAllGrandchildrenCounts) &&
        !verifyRootChildCounts) {
      throw const C500G0BoundedXrefException('C500_G0O1_REQUIRES_ROOT_AUDIT');
    }
    if (verifyRootChildCounts && !verifyCatalogRoot) {
      throw const C500G0BoundedXrefException('C500_G0O_REQUIRES_PINNED_ROOT');
    }
    if (verifyFirstGrandchildCounts && rootChildOrdinal != 0) {
      throw const C500G0BoundedXrefException('C500_G0O3_REQUIRES_FIRST_CHILD');
    }
    if (rootChildOrdinal != 0 && !verifySecondRootSubtreeCounts &&
        !verifyFirstBranchAllGrandchildrenCounts &&
        (!verifyCatalogRoot || !verifyFirstPageChild || !verifyFirstPagePath)) {
      throw const C500G0BoundedXrefException('C500_G0J_REQUIRES_PINNED_PATH');
    }
    if (maxHeaderBytes < 256 ||
        maxCompressedBytes <= 0 ||
        maxDecodedBytes <= 0 || maxRootDecodedBytes < 1024 * 1024) {
      throw const C500G0BoundedXrefException('C500_G0L_INVALID_LIMITS');
    }
    if (verifyCompressedMembers && !verifyObjectOffsets) {
      throw const C500G0BoundedXrefException('C500_G0O_REQUIRES_OFFSET_VERIFICATION');
    }
    // G0t: one first child only; never claim full page-tree coverage.
    if (verifyFirstPagePath && !verifyFirstPageChild) {
      throw const C500G0BoundedXrefException('C500_G0U_REQUIRES_FIRST_CHILD');
    }
    // G0ai: full first operand must retain the proven first-glyph custody.
    if (verifyFirstPageOperandUnicodeRun && !verifyFirstPageGlyphUnicode) {
      throw const C500G0BoundedXrefException('C500_G0AI_REQUIRES_FIRST_GLYPH');
    }
    // G0aj: first-leaf multi-operand coverage cannot skip first-operand proof.
    if (verifyFirstPageAllOperandsUnicode &&
        !verifyFirstPageOperandUnicodeRun) {
      throw const C500G0BoundedXrefException(
          'C500_G0AJ_REQUIRES_FIRST_OPERAND');
    }
    // G0ah: real glyph Unicode requires bounded CMap semantics first.
    if (verifyFirstPageGlyphUnicode && !verifyFirstPageCmapSemantics) {
      throw const C500G0BoundedXrefException('C500_G0AH_REQUIRES_SEMANTIC_CMAP');
    }
    // G0ad: semantic CMap inspection is strictly downstream of bounded streams.
    if (verifyFirstPageCmapSemantics && !verifyFirstPageCmapStreams) {
      throw const C500G0BoundedXrefException('C500_G0AD_REQUIRES_CMAP_STREAM');
    }
    // G0ab: CMap access requires verified font bindings.
    if (verifyFirstPageCmapStreams && !verifyFirstPageFontResources) {
      throw const C500G0BoundedXrefException('C500_G0AB_REQUIRES_FONT_BINDING');
    }
    // G0aa: resource-to-font XRef binding requires proven first-leaf glyph state.
    if (verifyFirstPageFontResources && !verifyFirstPageGlyphOperands) {
      throw const C500G0BoundedXrefException('C500_G0AA_REQUIRES_GLYPH_STATE');
    }
    if (verifyFirstPageGlyphOperands && !verifyFirstPageContents) {
      throw const C500G0BoundedXrefException('C500_G0W_REQUIRES_CONTENT');
    }
    if (verifyFirstPageContents && !verifyFirstPagePath) {
      throw const C500G0BoundedXrefException('C500_G0V_REQUIRES_LEAF_PATH');
    }
    if (verifyFirstPageChild && !verifyCatalogRoot) {
      throw const C500G0BoundedXrefException('C500_G0T_REQUIRES_ROOT');
    }
    // G0q: Catalog/Pages-root access validates its own direct or compressed
    // object identity. Unrelated global ObjStm samples are NOT a prerequisite:
    // a sampled oversized parent must not obscure the root's first failure.
    // Reuse the existing fixed-window SHA/topology probe, not PDFBox/qpdf.
    final source = await const CloudAwardPdfStructureProbe().inspect(file: file);
    if (source.byteLength != expectedBytes ||
        source.sha256 != expectedSha256) {
      throw const C500G0BoundedXrefException('C500_G0L_SOURCE_PIN_MISMATCH');
    }
    if (source.xrefTopology != CloudAwardPdfXrefTopology.xrefStream ||
        source.hasEncryptionMarker ||
        source.hasIncrementalPreviousRevision) {
      throw const C500G0BoundedXrefException('C500_G0L_UNSUPPORTED_TOPOLOGY');
    }

    final handle = await file.open(mode: FileMode.read);
    try {
      await handle.setPosition(source.startXrefOffset);
      final headerBytes = await handle.read(
        min(maxHeaderBytes, source.byteLength - source.startXrefOffset),
      );
      final header = latin1.decode(headerBytes, allowInvalid: true);
      if (!RegExp(r'^\s*\d+\s+\d+\s+obj\b').hasMatch(header)) {
        throw const C500G0BoundedXrefException('C500_G0L_XREF_OBJECT_MISSING');
      }
      // G0m: real pinned XRef streams did not match the old 64 KiB,
      // newline-before-stream assumption. Only accept a bounded dictionary
      // terminator and stream token, never scan arbitrary PDF content.
      final streamMarker = RegExp(
        r'>>[ \t]*(?:\r\n|\r|\n)?stream(?:\r\n|\r|\n)',
      ).firstMatch(header);
      if (streamMarker == null) {
        throw const C500G0BoundedXrefException('C500_G0L_STREAM_HEADER_MISSING');
      }
      final dictionary = header.substring(0, streamMarker.start + 2);
      if (!dictionary.endsWith('>>') ||
          !RegExp(r'/Type\s*/XRef\b').hasMatch(dictionary)) {
        throw const C500G0BoundedXrefException('C500_G0L_NOT_XREF_STREAM');
      }
      if (RegExp(r'/Length\s+\d+\s+\d+\s+R\b').hasMatch(dictionary)) {
        throw const C500G0BoundedXrefException('C500_G0L_INDIRECT_LENGTH');
      }
      if (!RegExp(r'/Filter\s*(?:/FlateDecode\b|\[\s*/FlateDecode\s*\])')
              .hasMatch(dictionary) ||
          dictionary.contains('/DecodeParms')) {
        throw const C500G0BoundedXrefException('C500_G0L_UNSUPPORTED_FILTER');
      }
      int requiredNumber(String key) {
        final match = RegExp('/$key' r'\s+(\d+)\b').firstMatch(dictionary);
        if (match == null) {
          throw const C500G0BoundedXrefException('C500_G0L_REQUIRED_NUMBER_MISSING');
        }
        return int.parse(match.group(1)!);
      }

      final size = requiredNumber('Size');
      final compressedLength = requiredNumber('Length');
      final widthsMatch =
          RegExp(r'/W\s*\[\s*(\d+)\s+(\d+)\s+(\d+)\s*\]').firstMatch(dictionary);
      if (widthsMatch == null) {
        throw const C500G0BoundedXrefException('C500_G0L_W_MISSING');
      }
      final widths = <int>[
        int.parse(widthsMatch.group(1)!),
        int.parse(widthsMatch.group(2)!),
        int.parse(widthsMatch.group(3)!),
      ];
      final entryWidth = widths.reduce((a, b) => a + b);
      if (size <= 0 ||
          size > 8000000 ||
          widths.any((value) => value < 0 || value > 8) ||
          entryWidth == 0) {
        throw const C500G0BoundedXrefException('C500_G0L_INVALID_ENTRY_WIDTH');
      }

      final indexMatch = RegExp(r'/Index\s*\[([0-9\s]+)\]').firstMatch(dictionary);
      final indexes = indexMatch == null
          ? <int>[0, size]
          : RegExp(r'\d+')
              .allMatches(indexMatch.group(1)!)
              .map((match) => int.parse(match.group(0)!))
              .toList(growable: false);
      if (indexes.isEmpty || indexes.length.isOdd) {
        throw const C500G0BoundedXrefException('C500_G0L_INVALID_INDEX');
      }
      var entries = 0;
      for (var i = 0; i < indexes.length; i += 2) {
        if (indexes[i] < 0 ||
            indexes[i + 1] <= 0 ||
            indexes[i] + indexes[i + 1] > size) {
          throw const C500G0BoundedXrefException('C500_G0L_INVALID_INDEX');
        }
        entries += indexes[i + 1];
      }
      if (entries > maxDecodedBytes ~/ entryWidth) {
        throw const C500G0BoundedXrefException('C500_G0L_DECODED_LIMIT');
      }
      if (compressedLength <= 0 || compressedLength > maxCompressedBytes) {
        throw const C500G0BoundedXrefException('C500_G0L_COMPRESSED_LIMIT');
      }
      final streamOffset = source.startXrefOffset + streamMarker.end;
      if (streamOffset + compressedLength > source.byteLength) {
        throw const C500G0BoundedXrefException('C500_G0L_STREAM_TRUNCATED');
      }
      await handle.setPosition(streamOffset);
      final compressed = await handle.read(compressedLength);
      if (compressed.length != compressedLength) {
        throw const C500G0BoundedXrefException('C500_G0L_STREAM_TRUNCATED');
      }
      final decoded = CloudAwardPdfBoundedStreamDecoder(
        maxCompressedBytes: maxCompressedBytes,
        maxDecodedBytes: maxDecodedBytes,
      ).decode(bytes: compressed, filters: const <String>['FlateDecode']);
      if (decoded.length != entries * entryWidth) {
        throw const C500G0BoundedXrefException('C500_G0L_DECODED_LENGTH_MISMATCH');
      }
      final types = <int, int>{0: 0, 1: 0, 2: 0};
      for (var offset = 0; offset < decoded.length; offset += entryWidth) {
        var type = widths[0] == 0 ? 1 : 0;
        for (var i = 0; i < widths[0]; i++) {
          type = (type << 8) | decoded[offset + i];
        }
        if (!types.containsKey(type)) {
          throw const C500G0BoundedXrefException('C500_G0L_UNKNOWN_ENTRY_TYPE');
        }
        types[type] = types[type]! + 1;
      }
      final navigation = verifyObjectOffsets
          ? await _sampleAddresses(handle, source.byteLength, decoded,
              widths, indexes, entryWidth, size, verifyCompressedMembers)
          : const <String, Object?>{};
      final catalog = verifyCatalogRoot
          ? await _verifyCatalogRoot(handle, source.byteLength, dictionary,
              decoded, widths, indexes, entryWidth,
              verifyFirstPageChild, verifyFirstPagePath,
              verifyFirstPageContents, verifyFirstPageGlyphOperands,
              verifyFirstPageFontResources, verifyFirstPageCmapStreams,
              verifyFirstPageCmapSemantics, verifyFirstPageGlyphUnicode,
              verifyFirstPageOperandUnicodeRun,
              verifyFirstPageAllOperandsUnicode, rootChildOrdinal,
              verifyRootChildCounts, verifyFirstRootSubtreeCounts,
              verifySecondRootSubtreeCounts, verifyFirstGrandchildCounts,
              verifyAllRootSubtreesCounts,
              verifyFirstBranchAllGrandchildrenCounts,
              verifyMidpointPagePath)
          : const <String, Object?>{};
      return <String, Object?>{
        'gate': 'C500_G0L_BOUNDED_XREF_ONLY',
        'root_child_ordinal': rootChildOrdinal,
        'sample_scope': verifyMidpointPagePath
            ? 'MIDPOINT_ONE_XREF_BOUND_LEAF_ANCESTRY_NOT_GLOBAL_PROOF'
            : verifyFirstBranchAllGrandchildrenCounts
            ? rootChildOrdinal == 0
                ? 'FIRST_BRANCH_ALL_GRANDCHILDREN_THREE_LEVELS_NOT_GLOBAL_PROOF'
                : rootChildOrdinal == 1
                    ? 'SECOND_BRANCH_ALL_GRANDCHILDREN_THREE_LEVELS_NOT_GLOBAL_PROOF'
                    : 'THIRD_BRANCH_ALL_GRANDCHILDREN_THREE_LEVELS_NOT_GLOBAL_PROOF'
            : verifyAllRootSubtreesCounts
            ? 'ALL_ROOT_SUBTREES_TWO_LEVEL_COUNT_ONLY_NOT_GLOBAL_PROOF'
            : verifyFirstGrandchildCounts
            ? 'FIRST_BRANCH_THREE_LEVEL_COUNT_ONLY_NOT_GLOBAL_PROOF'
            : verifySecondRootSubtreeCounts
            ? 'SECOND_ROOT_SUBTREE_TWO_LEVEL_COUNT_ONLY_NOT_GLOBAL_PROOF'
            : verifyFirstRootSubtreeCounts
            ? 'FIRST_ROOT_SUBTREE_TWO_LEVEL_COUNT_ONLY_NOT_GLOBAL_PROOF'
            : verifyRootChildCounts
            ? 'ROOT_CHILD_COUNT_ONLY_NOT_DESCENDANT_OR_GLOBAL_PROOF'
            : rootChildOrdinal == 0
            ? 'DOCUMENT_LEFTMOST_LEAF_ONLY'
            : rootChildOrdinal == 1
                ? 'SECOND_ROOT_CHILD_LEFTMOST_LEAF_ONLY_NOT_SECOND_DOCUMENT_PAGE'
                : rootChildOrdinal == -1
                    ? 'LAST_ROOT_CHILD_LEFTMOST_LEAF_ONLY_NOT_LAST_DOCUMENT_PAGE'
                    : 'MIDDLE_ROOT_CHILD_LEFTMOST_LEAF_ONLY_NOT_MIDDLE_DOCUMENT_PAGE',
        ...navigation,
        ...catalog,
        'sha256': source.sha256,
        'bytes': source.byteLength,
        'startxref': source.startXrefOffset,
        'declared_size': size,
        'xref_entries': entries,
        'entry_width': entryWidth,
        'compressed_bytes': compressedLength,
        'decoded_bytes': decoded.length,
        'free_entries': types[0],
        'uncompressed_entries': types[1],
        'object_stream_entries': types[2],
        'all_pages': 'NOT_VERIFIED',
        'global_not_win': 'NOT_PROVEN',
        'award_authority': 'HOLD',
      };
    } finally {
      await handle.close();
    }
  }


  // G0p: reuse the pinned, bounded XRef for exactly two references.
  // Catalog and Pages-root validation is not page traversal or NOT_WIN.
  Map<String, int>? _lookupXrefEntry(
    List<int> bytes, List<int> widths, List<int> indexes, int stride, int id,
  ) {
    int field(int offset, int count) {
      var value = 0;
      for (var i = 0; i < count; i++) {
        value = (value << 8) | bytes[offset + i];
      }
      return value;
    }
    var base = 0;
    for (var i = 0; i < indexes.length; i += 2) {
      final start = indexes[i], count = indexes[i + 1];
      if (id >= start && id < start + count) {
        final offset = (base + id - start) * stride;
        return <String, int>{
          'type': widths[0] == 0 ? 1 : field(offset, widths[0]),
          'second': field(offset + widths[0], widths[1]),
          'third': field(offset + widths[0] + widths[1], widths[2]),
        };
      }
      base += count;
    }
    return null;
  }

  Future<Map<String, Object?>> _verifyCatalogRoot(
    RandomAccessFile file, int sourceLength, String xrefDictionary,
    List<int> bytes, List<int> widths, List<int> indexes, int stride,
    bool verifyFirstPageChild, bool verifyFirstPagePath,
    bool verifyFirstPageContents, bool verifyFirstPageGlyphOperands,
    bool verifyFirstPageFontResources, bool verifyFirstPageCmapStreams,
    bool verifyFirstPageCmapSemantics, bool verifyFirstPageGlyphUnicode,
    bool verifyFirstPageOperandUnicodeRun,
    bool verifyFirstPageAllOperandsUnicode,
    int rootChildOrdinal,
    bool verifyRootChildCounts,
    bool verifyFirstRootSubtreeCounts,
    bool verifySecondRootSubtreeCounts,
    bool verifyFirstGrandchildCounts,
    bool verifyAllRootSubtreesCounts,
    bool verifyFirstBranchAllGrandchildrenCounts,
    bool verifyMidpointPagePath,
  ) async {
    final root = RegExp(r'/Root\s+(\d+)\s+(\d+)\s+R\b')
        .firstMatch(xrefDictionary);
    if (root == null) {
      throw const C500G0BoundedXrefException('C500_G0P_ROOT_REFERENCE_MISSING');
    }
    final rootId = int.parse(root.group(1)!);
    final rootGeneration = int.parse(root.group(2)!);

    Future<String> readObject(int id, int generation) async {
      final entry = _lookupXrefEntry(bytes, widths, indexes, stride, id);
      if (entry == null || entry['type'] == 0) {
        throw const C500G0BoundedXrefException('C500_G0P_ROOT_XREF_MISSING');
      }
      if (entry['type'] == 1) {
        if (entry['third'] != generation) {
          throw const C500G0BoundedXrefException('C500_G0P_GENERATION_MISMATCH');
        }
        final offset = entry['second']!;
        if (offset <= 0 || offset >= sourceLength) {
          throw const C500G0BoundedXrefException('C500_G0P_OBJECT_OFFSET_INVALID');
        }
        await file.setPosition(offset);
        final content = latin1.decode(
          await file.read(min(64 * 1024, sourceLength - offset)),
          allowInvalid: true,
        );
        if (!RegExp('^$id\\s+$generation\\s+obj\\b').hasMatch(content)) {
          throw const C500G0BoundedXrefException('C500_G0P_OBJECT_HEADER_MISMATCH');
        }
        final end = RegExp(r'\bendobj\b').firstMatch(content);
        if (end == null) {
          throw const C500G0BoundedXrefException('C500_G0P_OBJECT_BUDGET_EXCEEDED');
        }
        return content.substring(0, end.start);
      }
      if (entry['type'] == 2) {
        if (generation != 0) {
          throw const C500G0BoundedXrefException('C500_G0P_GENERATION_MISMATCH');
        }
        final parentId = entry['second']!;
        final parent = _lookupXrefEntry(bytes, widths, indexes, stride, parentId);
        if (parent == null || parent['type'] != 1) {
          throw const C500G0BoundedXrefException('C500_G0P_PARENT_NOT_DIRECT');
        }
        final offset = parent['second']!;
        final parentGeneration = parent['third']!;
        if (offset <= 0 || offset >= sourceLength) {
          throw const C500G0BoundedXrefException('C500_G0P_OBJECT_OFFSET_INVALID');
        }
        await file.setPosition(offset);
        final header = latin1.decode(
          await file.read(min(4096, sourceLength - offset)),
          allowInvalid: true,
        );
        if (!RegExp('^$parentId\\s+$parentGeneration\\s+obj\\b')
                .hasMatch(header) ||
            !RegExp(r'/Type\s*/ObjStm\b').hasMatch(header)) {
          throw const C500G0BoundedXrefException('C500_G0P_PARENT_HEADER_MISMATCH');
        }
        return _verifyCompressedMember(file, sourceLength, offset, header,
            <String, int>{'id': id, 'index': entry['third']!},
            allowLargeRootSpool: true);
      }
      throw const C500G0BoundedXrefException('C500_G0P_UNSUPPORTED_ENTRY_TYPE');
    }

    final catalog = await readObject(rootId, rootGeneration);
    if (!RegExp(r'/Type\s*/Catalog\b').hasMatch(catalog)) {
      throw const C500G0BoundedXrefException('C500_G0P_CATALOG_TYPE_INVALID');
    }
    final pages = RegExp(r'/Pages\s+(\d+)\s+(\d+)\s+R\b')
        .firstMatch(catalog);
    if (pages == null) {
      throw const C500G0BoundedXrefException('C500_G0P_PAGES_REFERENCE_MISSING');
    }
    final pagesId = int.parse(pages.group(1)!);
    final pagesBody = await readObject(pagesId, int.parse(pages.group(2)!));
    if (!RegExp(r'/Type\s*/Pages\b').hasMatch(pagesBody) ||
        !RegExp(r'/Kids\s*\[').hasMatch(pagesBody)) {
      throw const C500G0BoundedXrefException('C500_G0P_PAGES_TYPE_INVALID');
    }
    // G0o.8: a duplicate root /Count is ambiguous even when its first
    // value matches the sampled tree. Never infer page coverage from it.
    final rootCounts = RegExp(r'/Count\s+(\d+)\b')
        .allMatches(pagesBody).toList();
    final declared = rootCounts.length == 1
        ? int.tryParse(rootCounts.single.group(1)!) : null;
    if (declared == null || declared <= 0 || declared > 1000000) {
      throw const C500G0BoundedXrefException('C500_G0P_PAGE_COUNT_INVALID');
    }
    final rootCountEvidence =
        verifyMidpointPagePath
        ? await const C500G0MidpointPageAuditor().inspect(
            pagesBody: pagesBody, rootId: pagesId,
            rootGeneration: int.parse(pages.group(2)!),
            declaredPages: declared, readObject: readObject,
          )
        : verifyFirstBranchAllGrandchildrenCounts
        ? await const C500G0FirstBranchAllGrandchildrenAuditor().inspect(
            pagesBody: pagesBody, rootId: pagesId,
            rootGeneration: int.parse(pages.group(2)!),
            declaredPages: declared, readObject: readObject,
            rootChildOrdinal: rootChildOrdinal,
          )
        : verifyAllRootSubtreesCounts
        ? await const C500G0AllRootSubtreesCountAuditor().inspect(
            pagesBody: pagesBody, rootId: pagesId,
            rootGeneration: int.parse(pages.group(2)!),
            declaredPages: declared, readObject: readObject,
          )
        : verifyFirstGrandchildCounts
        ? await const C500G0ThreeLevelFirstBranchAuditor().inspect(
            pagesBody: pagesBody, rootId: pagesId,
            rootGeneration: int.parse(pages.group(2)!),
            declaredPages: declared, readObject: readObject,
          )
        : (verifyFirstRootSubtreeCounts || verifySecondRootSubtreeCounts)
        ? await const C500G0FirstRootSubtreeCountAuditor().inspect(
            pagesBody: pagesBody,
            rootId: pagesId,
            rootGeneration: int.parse(pages.group(2)!),
            declaredPages: declared,
            readObject: readObject,
            rootChildOrdinal: verifySecondRootSubtreeCounts ? 1 : 0,
          )
        : verifyRootChildCounts
        ? await const C500G0RootChildCountAuditor().inspect(
            pagesBody: pagesBody,
            rootId: pagesId,
            rootGeneration: int.parse(pages.group(2)!),
            declaredPages: declared,
            readObject: readObject,
          )
        : const <String, Object?>{};
    // G0t: inspect exactly one /Kids child through the pinned XRef.
    // Require the child's /Parent to point back to this Pages root.
    // This is not recursive traversal, award proof, or global NOT_WIN.
    final firstChildEvidence = <String, Object?>{};
    if (verifyFirstPageChild) {
      // G0j: one XRef-bound root child per invocation. Ordinal one follows
      // the leftmost leaf of the second root subtree, not the next page.
      final selectedKid = const C500G0RootKidSelector()
          .select(pagesBody, rootChildOrdinal);
      final childId = selectedKid.$1;
      final childGeneration = selectedKid.$2;
      if (childId == rootId || childId == pagesId) {
        throw const C500G0BoundedXrefException('C500_G0T_CHILD_CYCLE');
      }
      final entry = _lookupXrefEntry(bytes, widths, indexes, stride, childId);
      if (entry == null || entry['type'] == 0) {
        throw const C500G0BoundedXrefException('C500_G0T_CHILD_XREF_MISSING');
      }
      final childBody = await readObject(childId, childGeneration);
      if (!RegExp(r'/Type\s*/(?:Pages|Page)\b').hasMatch(childBody)) {
        throw const C500G0BoundedXrefException('C500_G0T_CHILD_TYPE_INVALID');
      }
      // G0o.9: an additional /Parent can contradict the first matching
      // reference. Fail closed before granting even one sampled leaf path.
      final parents = RegExp(r'/Parent\s+(\d+)\s+(\d+)\s+R\b')
          .allMatches(childBody).toList();
      if (parents.length != 1 ||
          int.parse(parents.single.group(1)!) != pagesId ||
          int.parse(parents.single.group(2)!) != int.parse(pages.group(2)!)) {
        throw const C500G0BoundedXrefException('C500_G0T_PARENT_MISMATCH');
      }
      // G0u: only the leftmost bounded path to one Page leaf.
      // Each object uses the pinned XRef and capped direct/ObjStm reader.
      // Siblings, whole tree, sorted awards and NOT_WIN remain unverified.
      if (verifyFirstPagePath) {
        const maxDepth = 8;
        final seen = <int>{pagesId, childId};
        var nodeId = childId;
        var nodeGeneration = childGeneration;
        var nodeBody = childBody;
        // Resources are inheritable: retain only this bounded leftmost path.
        final resourcePath = <String>[pagesBody, childBody];
        var parentCount = declared;
        var depth = 1;
        while (RegExp(r'/Type\s*/Pages\b').hasMatch(nodeBody)) {
          if (depth >= maxDepth) {
            throw const C500G0BoundedXrefException('C500_G0U_PATH_DEPTH_LIMIT');
          }
          // G0o.8: reject ambiguous intermediate page counts before
          // following any child reference in this bounded path.
          final nodeCounts = RegExp(r'/Count\s+(\d+)\b')
              .allMatches(nodeBody).toList();
          final childCount = nodeCounts.length == 1
              ? int.tryParse(nodeCounts.single.group(1)!) : null;
          if (childCount == null || childCount <= 0 ||
              childCount > parentCount) {
            throw const C500G0BoundedXrefException('C500_G0U_SUBTREE_COUNT_INVALID');
          }
          final next = RegExp(r'/Kids\s*\[\s*(\d+)\s+(\d+)\s+R\b')
              .firstMatch(nodeBody);
          if (next == null) {
            throw const C500G0BoundedXrefException('C500_G0U_KIDS_FORM_UNSUPPORTED');
          }
          final nextId = int.parse(next.group(1)!);
          final nextGeneration = int.parse(next.group(2)!);
          if (nextId == rootId || !seen.add(nextId)) {
            throw const C500G0BoundedXrefException('C500_G0U_CHILD_CYCLE');
          }
          final nextBody = await readObject(nextId, nextGeneration);
          resourcePath.add(nextBody);
          if (!RegExp(r'/Type\s*/(?:Pages|Page)\b').hasMatch(nextBody)) {
            throw const C500G0BoundedXrefException('C500_G0U_CHILD_TYPE_INVALID');
          }
          // G0o.9: reject duplicate /Parent on each bounded descendant;
          // a valid first entry cannot hide a forged second entry.
          final parentRefs = RegExp(r'/Parent\s+(\d+)\s+(\d+)\s+R\b')
              .allMatches(nextBody).toList();
          if (parentRefs.length != 1 ||
              int.parse(parentRefs.single.group(1)!) != nodeId ||
              int.parse(parentRefs.single.group(2)!) != nodeGeneration) {
            throw const C500G0BoundedXrefException('C500_G0U_PARENT_MISMATCH');
          }
          parentCount = childCount;
          nodeId = nextId;
          nodeGeneration = nextGeneration;
          nodeBody = nextBody;
          depth++;
        }
        if (!RegExp(r'/Type\s*/Page\b').hasMatch(nodeBody)) {
          throw const C500G0BoundedXrefException('C500_G0U_LEAF_TYPE_INVALID');
        }
        firstChildEvidence['leftmost_page_id'] = nodeId;
        firstChildEvidence['leftmost_path_depth'] = depth;
        firstChildEvidence['leftmost_path_verified'] = true;
        if (verifyFirstPageContents) {
          firstChildEvidence.addAll(await _verifyFirstPageContents(
            file, sourceLength, bytes, widths, indexes, stride, nodeBody,
            verifyFirstPageGlyphOperands, verifyFirstPageAllOperandsUnicode,
          ));
          // G0ag: the raw candidate is internal and must never reach JSON.
          final firstOperands =
              firstChildEvidence.remove('__g0ag_first_font_operands');
          final allOperands =
              firstChildEvidence.remove('__g0aj_all_font_operands');
          try {
            if (verifyFirstPageFontResources) {
            if (firstOperands is! Map<String, List<int>>) {
              throw const C500G0BoundedXrefException(
                  'C500_G0AG_FIRST_OPERAND_MISSING');
            }
            final names =
                firstChildEvidence['first_page_text_font_names_unverified'];
            if (names is! List<String>) {
              throw const C500G0BoundedXrefException(
                  'C500_G0AA_FONT_STATE_MISSING');
            }
            firstChildEvidence.addAll(
              await const C500G0FontResourceInspector().inspect(
                pageTreeObjects: resourcePath,
                selectedFontNames: names,
                selectedFirstOperands: firstOperands,
                selectedAllOperands: verifyFirstPageAllOperandsUnicode
                    ? allOperands as Map<String, List<List<int>>>?
                    : null,
                readObject: readObject,
                verifyCmapStreams: verifyFirstPageCmapStreams,
                verifyCmapSemantics: verifyFirstPageCmapSemantics,
                verifyFirstGlyphUnicode: verifyFirstPageGlyphUnicode,
                verifyFirstOperandUnicodeRun: verifyFirstPageOperandUnicodeRun,
                verifyAllFirstPageOperandsUnicode: verifyFirstPageAllOperandsUnicode,
                firstLeafOperandCaptureTruncated:
                    firstChildEvidence['first_page_first_leaf_operand_capture_truncated'] == true,
                firstLeafUncapturedOperandsUnknown:
                    firstChildEvidence['first_page_first_leaf_uncaptured_operands_unknown'] as int? ?? 0,
                firstLeafZeroGlyphOperands:
                    firstChildEvidence['first_page_first_leaf_zero_glyph_operands_structural_only'] as int? ?? 0,
              ),
            );
          }
          } finally {
            // G0ai: never retain privately captured glyph operands after
            // bounded font/CMap inspection, including fail-closed exceptions.
            if (firstOperands is Map<String, List<int>>) {
              for (final bytes in firstOperands.values) {
                bytes.fillRange(0, bytes.length, 0);
              }
              firstOperands.clear();
            }
            if (allOperands is Map<String, List<List<int>>>) {
              for (final operands in allOperands.values) {
                for (final bytes in operands) {
                  bytes.fillRange(0, bytes.length, 0);
                }
                operands.clear();
              }
              allOperands.clear();
            }
          }
        }
      }
      // Retain the legacy key for existing tests, but identify the actual
      // selected subtree explicitly in new bounded evidence.
      firstChildEvidence['selected_root_child_id'] = childId;
      firstChildEvidence['first_root_child_id'] = childId;
      firstChildEvidence['first_root_child_verified'] = true;
    }
    return <String, Object?>{
      'catalog_root_id': rootId,
      'catalog_root_verified': true,
      'pages_root_id': pagesId,
      'pages_root_verified': true,
      'declared_page_count_unverified': declared,
      ...rootCountEvidence,
      ...firstChildEvidence,
      'page_tree': verifyFirstPagePath
          ? 'LEFTMOST_PATH_ONLY_NOT_TRAVERSED'
          : verifyFirstPageChild
          ? 'FIRST_CHILD_ONLY_NOT_TRAVERSED'
          : 'ROOT_ONLY_NOT_TRAVERSED',
    };
  }


  // G0v: bounded access to ONE first-page /Contents stream; lexical evidence
  // only. Not PDF text/award parsing, all-page proof or NOT_WIN authority.
  Future<Map<String, Object?>> _verifyFirstPageContents(
    RandomAccessFile file, int sourceLength, List<int> xref,
    List<int> widths, List<int> indexes, int stride, String leaf,
    bool verifyFirstPageGlyphOperands,
    bool verifyFirstPageAllOperandsUnicode,
  ) async {
    if (RegExp(r'/Contents\s*\[').hasMatch(leaf)) {
      throw const C500G0BoundedXrefException('C500_G0V_CONTENT_ARRAY_UNSUPPORTED');
    }
    final refs = RegExp(r'/Contents\s+(\d+)\s+(\d+)\s+R\b').allMatches(leaf).toList();
    if (refs.length != 1) {
      throw const C500G0BoundedXrefException('C500_G0V_CONTENT_REFERENCE_MISSING');
    }
    final id = int.parse(refs.single.group(1)!);
    final generation = int.parse(refs.single.group(2)!);
    final entry = _lookupXrefEntry(xref, widths, indexes, stride, id);
    if (entry == null || entry['type'] != 1 || entry['third'] != generation) {
      throw const C500G0BoundedXrefException('C500_G0V_CONTENT_XREF_INVALID');
    }
    final objectOffset = entry['second']!;
    if (objectOffset <= 0 || objectOffset >= sourceLength) {
      throw const C500G0BoundedXrefException('C500_G0V_CONTENT_OFFSET_INVALID');
    }
    await file.setPosition(objectOffset);
    final header = latin1.decode(
      await file.read(min(4096, sourceLength - objectOffset)),
      allowInvalid: true,
    );
    if (!RegExp('^$id\\s+$generation\\s+obj\\b').hasMatch(header)) {
      throw const C500G0BoundedXrefException('C500_G0V_CONTENT_HEADER_MISMATCH');
    }
    final marker = RegExp(
      r'>>[ \t]*(?:\r\n|\r|\n)?stream(?:\r\n|\r|\n)',
    ).firstMatch(header);
    if (marker == null) {
      throw const C500G0BoundedXrefException('C500_G0V_CONTENT_STREAM_MISSING');
    }
    final dictionary = header.substring(0, marker.start + 2);
    if (dictionary.contains('/DecodeParms') ||
        RegExp(r'/Length\s+\d+\s+\d+\s+R\b').hasMatch(dictionary)) {
      throw const C500G0BoundedXrefException('C500_G0V_CONTENT_UNSUPPORTED');
    }
    final lengthMatch = RegExp(r'/Length\s+(\d+)\b').firstMatch(dictionary);
    if (lengthMatch == null) {
      throw const C500G0BoundedXrefException('C500_G0V_CONTENT_LENGTH_MISSING');
    }
    final length = int.parse(lengthMatch.group(1)!);
    const maxCompressed = 2 * 1024 * 1024;
    if (length <= 0 || length > maxCompressed) {
      throw const C500G0BoundedXrefException('C500_G0V_CONTENT_LENGTH_LIMIT');
    }
    final hasFilter = dictionary.contains('/Filter');
    if (hasFilter &&
        !RegExp(r'/Filter\s*(?:/FlateDecode\b|\[\s*/FlateDecode\s*\])')
            .hasMatch(dictionary)) {
      throw const C500G0BoundedXrefException('C500_G0V_CONTENT_FILTER_UNSUPPORTED');
    }
    final streamOffset = objectOffset + marker.end;
    if (streamOffset > sourceLength || length > sourceLength - streamOffset) {
      throw const C500G0BoundedXrefException('C500_G0V_CONTENT_TRUNCATED');
    }
    await file.setPosition(streamOffset);
    final compressed = await file.read(length);
    if (compressed.length != length) {
      throw const C500G0BoundedXrefException('C500_G0V_CONTENT_TRUNCATED');
    }
    final suffix = await file.read(min(32, sourceLength - streamOffset - length));
    if (!RegExp(r'^(?:\r\n|\r|\n)?endstream\b')
        .hasMatch(latin1.decode(suffix, allowInvalid: true))) {
      throw const C500G0BoundedXrefException('C500_G0V_CONTENT_ENDSTREAM_MISMATCH');
    }
    List<int> decoded;
    try {
      decoded = hasFilter
          ? const CloudAwardPdfBoundedStreamDecoder(
              maxCompressedBytes: maxCompressed,
              maxDecodedBytes: 8 * 1024 * 1024,
            ).decode(bytes: compressed, filters: const <String>['FlateDecode'])
          : compressed;
    } catch (_) {
      throw const C500G0BoundedXrefException('C500_G0V_CONTENT_DECODE_FAILED');
    }
    final body = latin1.decode(decoded, allowInvalid: true);
    if (!RegExp(r'(?:^|\s)BT(?:\s|$)').hasMatch(body) ||
        !RegExp(r'(?:^|\s)ET(?:\s|$)').hasMatch(body)) {
      throw const C500G0BoundedXrefException('C500_G0V_CONTENT_TEXT_MARKERS_MISSING');
    }
    final firstOperands = <String, List<int>>{};
    final allOperands = <String, List<List<int>>>{};
    Map<String, Object?> glyphEvidence;
    try {
      glyphEvidence = verifyFirstPageGlyphOperands
          ? const C500G0GlyphProbe().inspect(decoded,
              onFirstFontOperand: (font, bytes) {
                firstOperands[font] = bytes;
              },
              onEveryFontOperand: verifyFirstPageAllOperandsUnicode
                  ? (font, bytes) {
                      (allOperands[font] ??= <List<int>>[]).add(bytes);
                    }
                  : null,
              // G0an: lab only. A proven empty glyph string is a no-glyph
              // structural operator, never a Unicode or award assertion.
              emptyOperandIsNoGlyphForLab: verifyFirstPageAllOperandsUnicode)
          : const <String, Object?>{};
    } catch (_) {
      // G0aj: fail-closed lexer exceptions must also wipe private operands.
      for (final bytes in firstOperands.values) {
        bytes.fillRange(0, bytes.length, 0);
      }
      for (final operands in allOperands.values) {
        for (final bytes in operands) {
          bytes.fillRange(0, bytes.length, 0);
        }
      }
      rethrow;
    }
    return <String, Object?>{
      'leftmost_content_object_id': id,
      'leftmost_content_compressed_bytes': length,
      'leftmost_content_decoded_bytes': decoded.length,
      'leftmost_content_stream_verified': true,
      ...glyphEvidence,
      '__g0ag_first_font_operands': firstOperands,
      '__g0aj_all_font_operands': allOperands,
      'content_semantics': verifyFirstPageGlyphOperands
          ? 'GLYPH_OPERANDS_ONE_PAGE_ONLY'
          : 'UNPARSED_ONE_PAGE_ONLY',
    };
  }

  // G0n: at most five direct and five compressed-parent address samples.
  // Header samples are not a page-tree traversal or a NOT_WIN proof.
  Future<Map<String, Object?>> _sampleAddresses(
    RandomAccessFile file, int length, List<int> bytes,
    List<int> widths, List<int> indexes, int stride, int size,
    bool verifyCompressedMembers,
  ) async {
    int field(int offset, int count) {
      var result = 0;
      for (var i = 0; i < count; i++) {
        result = (result << 8) | bytes[offset + i];
      }
      return result;
    }
    Map<String, int>? lookup(int id) =>
        _lookupXrefEntry(bytes, widths, indexes, stride, id);
    final targets = <int>[0, size ~/ 4, size ~/ 2, size * 3 ~/ 4, size - 1];
    final direct = <Map<String, int>>[], compressed = <Map<String, int>>[];
    var d = 0, c = 0, base = 0;
    for (var i = 0; i < indexes.length; i += 2) {
      for (var j = 0; j < indexes[i + 1]; j++) {
        final id = indexes[i] + j, offset = (base + j) * stride;
        final type = widths[0] == 0 ? 1 : field(offset, widths[0]);
        if (type == 1 && d < targets.length && id >= targets[d]) {
          direct.add(<String, int>{
            'id': id,
            'offset': field(offset + widths[0], widths[1]),
            'generation': field(offset + widths[0] + widths[1], widths[2]),
          });
          d++;
        } else if (type == 2 && c < targets.length && id >= targets[c]) {
          compressed.add(<String, int>{
            'id': id,
            'parent': field(offset + widths[0], widths[1]),
            'index': field(offset + widths[0] + widths[1], widths[2]),
          });
          c++;
        }
      }
      base += indexes[i + 1];
    }
    Future<String> header(int id, int generation, int offset) async {
      if (offset < 0 || offset >= length) {
        throw const C500G0BoundedXrefException('C500_G0N_OBJECT_OFFSET_INVALID');
      }
      await file.setPosition(offset);
      final content = latin1.decode(
        await file.read(min(4096, length - offset)), allowInvalid: true,
      );
      if (!RegExp('^$id\\s+$generation\\s+obj\\b').hasMatch(content)) {
        throw const C500G0BoundedXrefException('C500_G0N_OBJECT_HEADER_MISMATCH');
      }
      return content;
    }
    for (final sample in direct) {
      await header(sample['id']!, sample['generation']!, sample['offset']!);
    }
    var verifiedMembers = 0;
    for (final sample in compressed) {
      final id = sample['parent']!, parent = lookup(sample['parent']!);
      if (parent == null || parent['type'] != 1) {
        throw const C500G0BoundedXrefException('C500_G0N_PARENT_NOT_DIRECT');
      }
      final content = await header(id, parent['third']!, parent['second']!);
      if (!RegExp(r'/Type\s*/ObjStm\b').hasMatch(content)) {
        throw const C500G0BoundedXrefException('C500_G0N_PARENT_NOT_OBJSTM');
      }
      final match = RegExp(r'/N\s+(\d+)\b').firstMatch(content);
      final count = int.tryParse(match?.group(1) ?? '');
      if (count == null || count <= 0 || sample['index']! >= count) {
        throw const C500G0BoundedXrefException('C500_G0N_COMPRESSED_INDEX_INVALID');
      }
      if (verifyCompressedMembers) {
        await _verifyCompressedMember(file, length, parent['second']!, content, sample);
        verifiedMembers++;
      }
    }
    return <String, Object?>{
      'object_navigation': verifyCompressedMembers
          ? 'BOUNDED_OBJSTM_MEMBER_SAMPLES_ONLY'
          : 'BOUNDED_HEADER_SAMPLES_ONLY',
      'compressed_members_verified': verifiedMembers,
      'direct_headers_verified': direct.length,
      'objstm_parent_headers_verified': compressed.length,
      'page_tree': 'NOT_TRAVERSED',
    };
  }

  // G0o: decode only a selected size-capped ObjStm and prove that its
  // XRef compressed member id/index pair matches. Not full-page evidence.
  Future<String> _verifyCompressedMember(
    RandomAccessFile file, int sourceLength, int parentOffset,
    String header, Map<String, int> sample, {
    bool allowLargeRootSpool = false,
  }) async {
    final marker = RegExp(
      r'>>[ \t]*(?:\r\n|\r|\n)?stream(?:\r\n|\r|\n)',
    ).firstMatch(header);
    if (marker == null) {
      throw const C500G0BoundedXrefException('C500_G0O_STREAM_HEADER_MISSING');
    }
    final dictionary = header.substring(0, marker.start + 2);
    if (!RegExp(r'/Type\s*/ObjStm\b').hasMatch(dictionary) ||
        !RegExp(r'/Filter\s*(?:/FlateDecode\b|\[\s*/FlateDecode\s*\])')
            .hasMatch(dictionary) ||
        dictionary.contains('/DecodeParms') ||
        RegExp(r'/Length\s+\d+\s+\d+\s+R\b').hasMatch(dictionary)) {
      throw const C500G0BoundedXrefException('C500_G0O_UNSUPPORTED_STREAM');
    }
    int number(String key) {
      final match = RegExp('/$key' r'\s+(\d+)\b').firstMatch(dictionary);
      if (match == null) {
        throw const C500G0BoundedXrefException('C500_G0O_REQUIRED_NUMBER_MISSING');
      }
      return int.parse(match.group(1)!);
    }
    final count = number('N'), first = number('First');
    final compressedLength = number('Length');
    // G0q: preserve each independent resource ceiling and attribute the
    // first rejected field; never silently increase a cap for official PDFs.
    if (count <= 0 || count > 100000) {
      throw const C500G0BoundedXrefException('C500_G0O_COUNT_LIMIT');
    }
    if (first <= 0 || first > 1024 * 1024) {
      throw const C500G0BoundedXrefException('C500_G0O_FIRST_LIMIT');
    }
    if (compressedLength <= 0 ||
        (!allowLargeRootSpool && compressedLength > 2 * 1024 * 1024)) {
      throw const C500G0BoundedXrefException('C500_G0O_COMPRESSED_LIMIT');
    }
    // G0r: root-only disk-spool experiment, not an in-memory cap increase.
    if (allowLargeRootSpool && compressedLength > 32 * 1024 * 1024) {
      throw const C500G0BoundedXrefException('C500_G0R_COMPRESSED_LIMIT');
    }
    final offset = parentOffset + marker.end;
    if (offset < 0 || offset > sourceLength ||
        compressedLength > sourceLength - offset) {
      throw const C500G0BoundedXrefException('C500_G0O_STREAM_TRUNCATED');
    }
    if (allowLargeRootSpool && compressedLength > 2 * 1024 * 1024) {
      return _readRootMemberViaBoundedStream(
        file, offset, compressedLength, count, first, sample,
      );
    }
    await file.setPosition(offset);
    final compressed = await file.read(compressedLength);
    if (compressed.length != compressedLength) {
      throw const C500G0BoundedXrefException('C500_G0O_STREAM_TRUNCATED');
    }
    final decoded = const CloudAwardPdfBoundedStreamDecoder(
      maxCompressedBytes: 2 * 1024 * 1024,
      maxDecodedBytes: 8 * 1024 * 1024,
    ).decode(bytes: compressed, filters: const <String>['FlateDecode']);
    if (first >= decoded.length) {
      throw const C500G0BoundedXrefException('C500_G0O_FIRST_INVALID');
    }
    final words = latin1.decode(decoded.sublist(0, first))
        .trim().split(RegExp(r'\s+'));
    if (words.length != 2 * count ||
        words.any((word) => !RegExp(r'^\d+$').hasMatch(word))) {
      throw const C500G0BoundedXrefException('C500_G0O_INDEX_HEADER_INVALID');
    }
    final index = sample['index']!;
    if (index < 0 || index >= count ||
        int.parse(words[2 * index]) != sample['id']) {
      throw const C500G0BoundedXrefException('C500_G0O_MEMBER_ID_MISMATCH');
    }
    var previous = -1;
    for (var i = 0; i < count; i++) {
      final start = int.parse(words[2 * i + 1]);
      if (start < 0 || start <= previous ||
          start >= decoded.length - first) {
        throw const C500G0BoundedXrefException('C500_G0O_MEMBER_OFFSET_INVALID');
      }
      previous = start;
    }
    final start = first + int.parse(words[2 * index + 1]);
    final end = index + 1 == count
        ? decoded.length
        : first + int.parse(words[2 * (index + 1) + 1]);
    if (end <= start || decoded.sublist(start, end).every((b) => b <= 32)) {
      throw const C500G0BoundedXrefException('C500_G0O_EMPTY_MEMBER');
    }
    return latin1.decode(decoded.sublist(start, end), allowInvalid: true);
  }

  // G0s: root-only, bounded-memory selective stream extraction. The prior
  // 64 MiB disposable spool failed for BOTH pinned genuine MOF PDFs. Do not
  // increase heap/disk allocation to match an untrusted ObjStm: retain only
  // <=1 MiB index + <=64 KiB selected member, while validating the ENTIRE
  // Flate stream and Adler32 under a 512 MiB total-output/32 MiB input cap.
  // This is NOT page-tree traversal, a PDFBox fix, or global NOT_WIN proof.
  Future<String> _readRootMemberViaBoundedStream(
    RandomAccessFile source, int offset, int compressedLength,
    int count, int first, Map<String, int> sample,
  ) async {
    const maxMember = 64 * 1024, maxChunk = 1024 * 1024;
    final indexBytes = <int>[];
    final memberBytes = <int>[];
    List<int>? starts;
    int? begin, end;
    var decodedBytes = 0, adlerA = 1, adlerB = 0;
    try {
      await for (final chunk in ZLibDecoder().bind(
        File(source.path).openRead(offset, offset + compressedLength),
      )) {
        if (chunk.length > maxChunk) {
          throw const C500G0BoundedXrefException('C500_G0S_CHUNK_LIMIT');
        }
        if (chunk.length > maxRootDecodedBytes - decodedBytes) {
          throw const C500G0BoundedXrefException('C500_G0S_TOTAL_DECODED_LIMIT');
        }
        final chunkStart = decodedBytes;
        final chunkEnd = chunkStart + chunk.length;
        if (indexBytes.length < first) {
          final take = min(first - indexBytes.length, chunk.length);
          indexBytes.addAll(chunk.take(take));
          if (indexBytes.length == first) {
            final words = latin1.decode(indexBytes).trim().split(RegExp(r'\s+'));
            if (words.length != count * 2 ||
                words.any((word) => !RegExp(r'^\d+$').hasMatch(word))) {
              throw const C500G0BoundedXrefException('C500_G0O_INDEX_HEADER_INVALID');
            }
            final index = sample['index']!;
            if (index < 0 || index >= count ||
                int.parse(words[index * 2]) != sample['id']) {
              throw const C500G0BoundedXrefException('C500_G0O_MEMBER_ID_MISMATCH');
            }
            starts = <int>[];
            var previous = -1;
            for (var i = 0; i < count; i++) {
              final start = int.parse(words[i * 2 + 1]);
              if (start <= previous) {
                throw const C500G0BoundedXrefException('C500_G0O_MEMBER_OFFSET_INVALID');
              }
              starts.add(start);
              previous = start;
            }
            begin = first + starts[index];
            if (index + 1 < count) {
              end = first + starts[index + 1];
              if (end <= begin || end - begin > maxMember) {
                throw const C500G0BoundedXrefException('C500_G0R_SELECTED_MEMBER_LIMIT');
              }
            }
          }
        }
        if (begin != null) {
          final overlapStart = max(chunkStart, begin);
          final overlapEnd = min(chunkEnd, end ?? chunkEnd);
          if (overlapEnd > overlapStart) {
            if (overlapEnd - overlapStart > maxMember - memberBytes.length) {
              throw const C500G0BoundedXrefException('C500_G0R_SELECTED_MEMBER_LIMIT');
            }
            memberBytes.addAll(chunk.sublist(
              overlapStart - chunkStart, overlapEnd - chunkStart,
            ));
          }
        }
        for (final value in chunk) {
          adlerA = (adlerA + value) % 65521;
          adlerB = (adlerB + adlerA) % 65521;
        }
        decodedBytes = chunkEnd;
      }
    } on C500G0BoundedXrefException {
      rethrow;
    } catch (_) {
      throw const C500G0BoundedXrefException('C500_G0R_STREAM_DECODE_FAILED');
    }
    // Independently compare the RFC1950 trailer even when zlib accepts it.
    await source.setPosition(offset + compressedLength - 4);
    final trailer = await source.read(4);
    if (trailer.length != 4) {
      throw const C500G0BoundedXrefException('C500_G0R_STREAM_TRUNCATED');
    }
    final expected = (trailer[0] << 24) | (trailer[1] << 16) |
        (trailer[2] << 8) | trailer[3];
    if (((adlerB << 16) | adlerA) != expected) {
      throw const C500G0BoundedXrefException('C500_G0R_ADLER_MISMATCH');
    }
    if (starts == null || first >= decodedBytes || begin == null) {
      throw const C500G0BoundedXrefException('C500_G0O_FIRST_INVALID');
    }
    for (final start in starts) {
      if (start >= decodedBytes - first) {
        throw const C500G0BoundedXrefException('C500_G0O_MEMBER_OFFSET_INVALID');
      }
    }
    final selectedEnd = end ?? decodedBytes;
    if (selectedEnd <= begin || selectedEnd - begin > maxMember) {
      throw const C500G0BoundedXrefException('C500_G0R_SELECTED_MEMBER_LIMIT');
    }
    if (memberBytes.length != selectedEnd - begin ||
        memberBytes.every((b) => b <= 32)) {
      throw const C500G0BoundedXrefException('C500_G0O_EMPTY_MEMBER');
    }
    return latin1.decode(memberBytes, allowInvalid: true);
  }

}

Future<void> main(List<String> args) async {
  final auditFirstSubtree = args.length == 1 &&
      args.single == '--audit-first-root-subtree';
  final auditSecondSubtree = args.length == 1 &&
      args.single == '--audit-second-root-subtree';
  final auditFirstGrandchild = args.length == 1 &&
      args.single == '--audit-first-grandchild';
  final auditAllRootSubtrees = args.length == 1 &&
      args.single == '--audit-all-root-subtrees';
  final auditFirstBranchAllGrandchildren = args.length == 1 &&
      args.single == '--audit-first-branch-all-grandchildren';
  // G0o.6: separate second branch, not full-document proof.
  final auditSecondBranchAllGrandchildren = args.length == 1 &&
      args.single == '--audit-second-branch-all-grandchildren';
  // G0o.11: third distinct root subtree, identical 16/256 reference budgets.
  final auditThirdBranchAllGrandchildren = args.length == 1 &&
      args.single == '--audit-third-branch-all-grandchildren';
  final auditMidpointPage = args.length == 1 &&
      args.single == '--audit-midpoint-page';
  final auditSelectedBranchAllGrandchildren =
      auditFirstBranchAllGrandchildren || auditSecondBranchAllGrandchildren ||
      auditThirdBranchAllGrandchildren;
  final auditRootChildren = auditFirstSubtree || auditSecondSubtree ||
      auditFirstGrandchild || auditAllRootSubtrees ||
      auditSelectedBranchAllGrandchildren ||
      (args.length == 1 && args.single == '--audit-root-children');
  final rootChildOrdinal = auditThirdBranchAllGrandchildren ? 2
      : (auditSecondSubtree || auditSecondBranchAllGrandchildren) ? 1
      : auditRootChildren || auditMidpointPage || args.isEmpty ? 0
      : args.length == 1 && args.single == '--second-root-child' ? 1
      : args.length == 1 && args.single == '--last-root-child' ? -1
      : args.length == 1 && args.single == '--middle-root-child' ? -2 : -3;
  if (rootChildOrdinal == -3) {
    stderr.writeln('C500_G0N_USAGE_OPTIONAL_SECOND_LAST_OR_MIDDLE_ROOT_CHILD');
    exitCode = 64;
    return;
  }
  const sources = <Map<String, Object>>[
    <String, Object>{
      'period': '115-05-06',
      'env': 'G0_OLD_PDF',
      'bytes': 119769589,
      'sha': '1efe4dcc5af410c9b5cfaf3ca605c2b8aea1e9259a4f16ebd8f8b9ea7110d0fe',
    },
    <String, Object>{
      'period': '115-07-08',
      'env': 'G0_NEW_PDF',
      'bytes': 135200798,
      'sha': 'f50d0dcebc7497c51ce2eea9da9525232e638fdc4103decc6a8e0a1c1dac5571',
    },
  ];
  // G0o.4: each pinned PDF receives the same existing 300-second bound.
  // This avoids charging the second official period for the first's work.
  // Invalid/empty period overrides fail closed; other modes always run both.
  late final List<String> selectedPeriods;
  try {
    selectedPeriods = const C500G0OfficialPeriodSelector().select(
      requestedPeriod: Platform.environment['G0_SOURCE_PERIOD'],
      allowSinglePeriod: auditAllRootSubtrees,
    );
  } on C500G0BoundedXrefException catch (error) {
    stderr.writeln(error.code);
    exitCode = 64;
    return;
  }
  var failures = 0;
  for (final source in sources) {
    if (!selectedPeriods.contains(source['period'])) continue;
    final period = source['period']! as String;
    final path = Platform.environment[source['env']! as String];
    try {
      if (path == null || path.isEmpty) {
        throw const C500G0BoundedXrefException('C500_G0L_SOURCE_UNAVAILABLE');
      }
      final result = await const C500G0BoundedXrefInspector().inspect(
        file: File(path),
        expectedBytes: source['bytes']! as int,
        expectedSha256: source['sha']! as String,
        // G0q official experiment: isolate exactly the pinned Catalog and
        // Pages root; never run unrelated sampled ObjStm scans in this mode.
        verifyObjectOffsets: false,
        verifyCompressedMembers: false,
        verifyCatalogRoot: true,
        verifyFirstPageChild: !auditRootChildren && !auditMidpointPage,
        verifyFirstPagePath: !auditRootChildren && !auditMidpointPage,
        verifyFirstPageContents: !auditRootChildren && !auditMidpointPage,
        verifyFirstPageGlyphOperands: !auditRootChildren && !auditMidpointPage,
        verifyFirstPageFontResources: !auditRootChildren && !auditMidpointPage,
        verifyFirstPageCmapStreams: !auditRootChildren && !auditMidpointPage,
        verifyFirstPageCmapSemantics: !auditRootChildren && !auditMidpointPage,
        verifyFirstPageGlyphUnicode: !auditRootChildren && !auditMidpointPage,
        verifyFirstPageOperandUnicodeRun: !auditRootChildren && !auditMidpointPage,
        verifyFirstPageAllOperandsUnicode: !auditRootChildren && !auditMidpointPage,
        verifyRootChildCounts: auditRootChildren,
        verifyMidpointPagePath: auditMidpointPage,
        verifyFirstRootSubtreeCounts: auditFirstSubtree,
        verifySecondRootSubtreeCounts: auditSecondSubtree,
        verifyFirstGrandchildCounts: auditFirstGrandchild,
        verifyAllRootSubtreesCounts: auditAllRootSubtrees,
        verifyFirstBranchAllGrandchildrenCounts:
            auditSelectedBranchAllGrandchildren,
        rootChildOrdinal: rootChildOrdinal,
      );
      stdout.writeln(jsonEncode(<String, Object?>{'period': period, ...result}));
    } catch (error) {
      failures++;
      stdout.writeln(jsonEncode(<String, Object?>{
        'period': period,
        'gate': 'C500_G0L_HOLD_BOUNDED_XREF',
        'failure': error.toString(),
        'global_not_win': 'NOT_PROVEN',
        'award_authority': 'HOLD',
      }));
    }
  }
  if (failures != 0) exitCode = 1;
}


// G0ap: lab-only exact Standard-14 Type1 / WinAnsi printable-ASCII fallback.
// A font without ToUnicode is UNKNOWN unless every font/encoding constraint
// and every glyph byte is proven. Never return or log decoded invoice text.
class C500G0SimpleWinAnsiProbe {
  const C500G0SimpleWinAnsiProbe();

  static const _standard14Latin = <String>{
    'Helvetica', 'Helvetica-Bold', 'Helvetica-Oblique',
    'Helvetica-BoldOblique', 'Courier', 'Courier-Bold',
    'Courier-Oblique', 'Courier-BoldOblique', 'Times-Roman',
    'Times-Bold', 'Times-Italic', 'Times-BoldItalic',
  };

  String classify(String font) {
    if (RegExp(r'/ToUnicode\b').hasMatch(font)) return 'HAS_TOUNICODE';
    if (RegExp(r'/Subtype\s*/Type1\b').allMatches(font).length != 1) {
      return 'NOT_EXACT_TYPE1';
    }
    final base = RegExp(r'/BaseFont\s*/([A-Za-z-]+)\b')
        .allMatches(font).toList();
    if (base.length != 1 ||
        !_standard14Latin.contains(base.single.group(1))) {
      return 'NOT_STANDARD14_LATIN';
    }
    final encoding = RegExp(r'/Encoding\s*/([A-Za-z0-9]+)\b')
        .allMatches(font).toList();
    if (encoding.length != 1 ||
        encoding.single.group(1) != 'WinAnsiEncoding') {
      return 'NOT_EXPLICIT_WINANSI';
    }
    if (RegExp(r'/Differences\b|/FontDescriptor\b|/FontFile\b|'
        r'/CharProcs\b|/DescendantFonts\b').hasMatch(font)) {
      return 'CUSTOM_OR_EMBEDDED_FONT';
    }
    return 'STANDARD14_WINANSI_ASCII_SUBSET';
  }

  int? countDecodedAsciiGlyphs(String font, List<int> operand) {
    if (classify(font) != 'STANDARD14_WINANSI_ASCII_SUBSET' ||
        operand.isEmpty || operand.length > 256 ||
        operand.any((byte) => byte < 0x20 || byte > 0x7e)) {
      return null;
    }
    // WinAnsi codes 0x20..0x7E map to the same Unicode code points.
    final decoded = String.fromCharCodes(operand);
    return decoded.runes.length;
  }
}

// G0aa: bounded FIRST-LEAF inherited /Resources -> /Font XRef binding.
// Resolves only selected font objects. No CMap decoding, award numbers,
// sibling pages, full page-tree traversal, or global NOT_WIN authority.
typedef C500G0ReadObject = Future<String> Function(int id, int generation);

class C500G0FontResourceInspector {
  const C500G0FontResourceInspector();

  Future<Map<String, Object?>> inspect({
    required List<String> pageTreeObjects,
    required List<String> selectedFontNames,
    required C500G0ReadObject readObject,
    Map<String, List<int>>? selectedFirstOperands,
    Map<String, List<List<int>>>? selectedAllOperands,
    bool verifyCmapStreams = false,
    bool verifyCmapSemantics = false,
    bool verifyFirstGlyphUnicode = false,
    bool verifyFirstOperandUnicodeRun = false,
    bool verifyAllFirstPageOperandsUnicode = false,
    // G0ak: a captured prefix is never whole-leaf Unicode authority.
    bool firstLeafOperandCaptureTruncated = false,
    int firstLeafUncapturedOperandsUnknown = 0,
    int firstLeafZeroGlyphOperands = 0,
  }) async {
    if (firstLeafZeroGlyphOperands < 0 ||
        firstLeafUncapturedOperandsUnknown < 0 ||
        firstLeafOperandCaptureTruncated !=
            (firstLeafUncapturedOperandsUnknown > 0)) {
      throw const C500G0BoundedXrefException(
          'C500_G0AK_PREFIX_EVIDENCE_INCONSISTENT');
    }
    if (pageTreeObjects.isEmpty || pageTreeObjects.length > 9 ||
        selectedFontNames.isEmpty || selectedFontNames.length > 16 ||
        selectedFontNames.toSet().length != selectedFontNames.length) {
      throw const C500G0BoundedXrefException('C500_G0AA_RESOURCE_BUDGET');
    }
    String? resources;
    for (final object in pageTreeObjects) {
      final keys = RegExp(r'/Resources\b').allMatches(object).toList();
      if (keys.length > 1) {
        throw const C500G0BoundedXrefException('C500_G0AA_DUPLICATE_RESOURCES');
      }
      if (keys.isNotEmpty) {
        // The nearest page/ancestor definition replaces an inherited one.
        resources = await _resolveDictionary(
          object.substring(keys.single.end), readObject);
      }
    }
    if (resources == null) {
      throw const C500G0BoundedXrefException('C500_G0AA_RESOURCES_MISSING');
    }
    final fontKeys = RegExp(r'/Font\b').allMatches(resources).toList();
    if (fontKeys.length != 1) {
      throw const C500G0BoundedXrefException('C500_G0AA_FONT_DICTIONARY_MISSING');
    }
    final fontDictionary = await _resolveDictionary(
      resources.substring(fontKeys.single.end), readObject);
    final refs = RegExp(r'/([A-Za-z0-9_.-]{1,64})\s+(\d+)\s+(\d+)\s+R\b')
        .allMatches(fontDictionary);
    final bindings = <String, List<int>>{};
    for (final ref in refs) {
      final name = ref.group(1)!;
      if (bindings.containsKey(name) || bindings.length >= 64) {
        throw const C500G0BoundedXrefException('C500_G0AA_FONT_BINDING_DUPLICATE_OR_LIMIT');
      }
      bindings[name] = <int>[
        int.parse(ref.group(2)!), int.parse(ref.group(3)!),
      ];
    }
    if (verifyAllFirstPageOperandsUnicode &&
        !verifyFirstOperandUnicodeRun) {
      throw const C500G0BoundedXrefException(
          'C500_G0AJ_REQUIRES_FIRST_OPERAND');
    }
    if (verifyFirstOperandUnicodeRun && !verifyFirstGlyphUnicode) {
      throw const C500G0BoundedXrefException('C500_G0AI_REQUIRES_FIRST_GLYPH');
    }
    if (verifyFirstGlyphUnicode && !verifyCmapSemantics) {
      throw const C500G0BoundedXrefException('C500_G0AH_REQUIRES_SEMANTIC_CMAP');
    }
    if (verifyCmapSemantics && !verifyCmapStreams) {
      throw const C500G0BoundedXrefException('C500_G0AD_REQUIRES_CMAP_STREAM');
    }
    var cmapReferences = 0, cmapStreams = 0, cmapMappedCodes = 0;
    var cmapBoundOperands = 0, unicodeFirstGlyphs = 0;
    var unicodeFullOperands = 0, unicodeFullOperandGlyphs = 0;
    var allVerifiedOperands = 0, allVerifiedGlyphs = 0;
    var allUnmappedFontOperands = 0, allCapturedOperands = 0;
    var simpleAsciiVerifiedOperands = 0, simpleAsciiVerifiedGlyphs = 0;
    final fontFallbackClasses = <String, String>{};
    for (final name in selectedFontNames) {
      final ref = bindings[name];
      if (ref == null) {
        throw const C500G0BoundedXrefException('C500_G0AA_SELECTED_FONT_UNBOUND');
      }
      final candidate = selectedFirstOperands?[name];
      final allForFont = selectedAllOperands?[name];
      if (verifyAllFirstPageOperandsUnicode) {
        // Fonts first encountered beyond the prefix remain UNKNOWN.
        if (allForFont != null && allForFont.length > 128) {
          throw const C500G0BoundedXrefException(
              'C500_G0AJ_CAPTURE_BUDGET');
        }
        allCapturedOperands += allForFont?.length ?? 0;
        if (allCapturedOperands > 128) {
          throw const C500G0BoundedXrefException(
              'C500_G0AJ_CAPTURE_BUDGET');
        }
      }
      if (selectedFirstOperands != null &&
          (candidate == null || candidate.isEmpty || candidate.length > 64 * 1024)) {
        throw const C500G0BoundedXrefException(
            'C500_G0AG_FIRST_OPERAND_MISSING');
      }
      final font = await readObject(ref[0], ref[1]);
      if (!RegExp(r'/Type\s*/Font\b').hasMatch(font)) {
        throw const C500G0BoundedXrefException('C500_G0AA_FONT_OBJECT_INVALID');
      }
      final cmapKeys = RegExp(r'/ToUnicode\b').allMatches(font).toList();
      fontFallbackClasses[name] = const C500G0SimpleWinAnsiProbe().classify(font);
      if (cmapKeys.length > 1) {
        throw const C500G0BoundedXrefException('C500_G0AA_CMAP_REFERENCE_INVALID');
      }
      if (cmapKeys.isNotEmpty) {
        final tail = font.substring(cmapKeys.single.end).trimLeft();
        if (!RegExp(r'^\d+\s+\d+\s+R\b').hasMatch(tail)) {
          throw const C500G0BoundedXrefException('C500_G0AA_CMAP_REFERENCE_INVALID');
        }
        // G0ab: only selected font CMap objects via pinned XRef.
        final reference = RegExp(r'^(\d+)\s+(\d+)\s+R\b').firstMatch(tail);
        if (reference == null) {
          throw const C500G0BoundedXrefException('C500_G0AA_CMAP_REFERENCE_INVALID');
        }
        cmapReferences++;
        if (verifyCmapStreams) {
          final id = int.parse(reference.group(1)!);
          final generation = int.parse(reference.group(2)!);
          // G0ah: same SHA-pinned selected font/CMap object.
          // Unicode stays private; only a count enters diagnostics.
          final cmapObject = await readObject(id, generation);
          cmapMappedCodes += const C500G0CmapStreamProbe().verify(
            object: cmapObject,
            id: id,
            generation: generation,
            verifyMappings: verifyCmapSemantics,
            firstOperand: verifyFirstGlyphUnicode ? candidate : null,
            verifyFullOperand: verifyFirstOperandUnicodeRun,
            allOperands: verifyAllFirstPageOperandsUnicode &&
                    allForFont != null && allForFont.isNotEmpty
                ? allForFont
                : null,
            onAllOperandsDecoded: (operandCount, glyphCount) {
              allVerifiedOperands += operandCount;
              allVerifiedGlyphs += glyphCount;
            },
            onFullOperandDecoded: (count) {
              unicodeFullOperands++;
              unicodeFullOperandGlyphs += count;
            },
          );
          cmapStreams++;
          if (verifyCmapSemantics && candidate != null) {
            cmapBoundOperands++;
            if (verifyFirstGlyphUnicode) unicodeFirstGlyphs++;
          }
        }
      } else if (verifyAllFirstPageOperandsUnicode) {
        // G0ap: no guessed mapping for a missing ToUnicode. A narrowly
        // proven built-in WinAnsi ASCII subset is private Unicode evidence;
        // every other captured operand remains UNKNOWN.
        for (final operand in allForFont ?? <List<int>>[]) {
          final glyphs = const C500G0SimpleWinAnsiProbe()
              .countDecodedAsciiGlyphs(font, operand);
          if (glyphs == null) {
            allUnmappedFontOperands++;
          } else {
            simpleAsciiVerifiedOperands++;
            simpleAsciiVerifiedGlyphs += glyphs;
          }
        }
      }
    }
    if (verifyCmapStreams && cmapStreams == 0) {
      throw const C500G0BoundedXrefException('C500_G0AB_CMAP_REFERENCE_MISSING');
    }
    if (verifyFirstGlyphUnicode && unicodeFirstGlyphs == 0) {
      throw const C500G0BoundedXrefException('C500_G0AH_NO_FIRST_GLYPH');
    }
    return <String, Object?>{
      'first_page_font_resource_binding': 'SELECTED_FONT_XREF_OBJECTS_ONLY',
      'first_page_font_objects_verified': selectedFontNames.length,
      'first_page_tounicode_references_unverified': cmapReferences - cmapStreams,
      'first_page_tounicode_streams_structure_verified': cmapStreams,
      'first_page_tounicode_mapping_codes_syntax_verified': cmapMappedCodes,
      // Only the real first-page operand's font-to-CMap object relationship.
      // No code-space segmentation or glyph-to-Unicode decoding is claimed.
      'first_page_font_operand_cmap_candidates_bound': cmapBoundOperands,
      'first_page_font_operand_cmap_unicode_single_glyph_verified': unicodeFirstGlyphs,
      'first_page_font_operand_unicode_full_runs_verified': unicodeFullOperands,
      'first_page_first_leaf_text_operands_captured_untrusted': allCapturedOperands,
      'first_page_first_leaf_tounicode_operands_verified': allVerifiedOperands,
      'first_page_first_leaf_tounicode_glyphs_verified': allVerifiedGlyphs,
      'first_page_first_leaf_no_tounicode_operands_unknown':
          allUnmappedFontOperands,
      'first_page_first_leaf_font_fallback_classes': fontFallbackClasses,
      'first_page_first_leaf_standard14_winansi_ascii_operands_verified':
          simpleAsciiVerifiedOperands,
      'first_page_first_leaf_standard14_winansi_ascii_glyphs_verified':
          simpleAsciiVerifiedGlyphs,
      'first_page_first_leaf_unicode_operands_verified':
          allVerifiedOperands + simpleAsciiVerifiedOperands,
      'first_page_first_leaf_uncaptured_operands_unknown':
          firstLeafUncapturedOperandsUnknown,
      'first_page_first_leaf_unicode_coverage_status':
          !verifyAllFirstPageOperandsUnicode ? 'NOT_RUN'
          : !firstLeafOperandCaptureTruncated &&
              firstLeafUncapturedOperandsUnknown == 0 &&
              allCapturedOperands ==
                  allVerifiedOperands + simpleAsciiVerifiedOperands &&
              allUnmappedFontOperands == 0
              ? 'FIRST_LEAF_ONLY_DECODED_NOT_AWARD_OR_GLOBAL_PROOF'
              : 'PARTIAL_FIRST_LEAF_COVERAGE_UNKNOWN_NOT_AWARD_PROOF',
      'first_page_font_operand_unicode_full_run_glyphs_verified': unicodeFullOperandGlyphs,
      'first_page_font_operand_unicode_full_run_status': unicodeFullOperands > 0
          ? 'ONE_BOUNDED_OPERAND_PER_FONT_PRIVATELY_DECODED_NOT_AWARD_PROOF'
          : 'NOT_VERIFIED',
      'first_page_font_operand_cmap_unicode_status': unicodeFirstGlyphs > 0
          ? 'ONE_GLYPH_DECODED_PRIVATELY_NOT_AWARD_NUMBER'
          : 'NOT_VERIFIED',
      'first_page_font_operand_cmap_status': cmapBoundOperands > 0
          ? 'OPERAND_FONT_CMAP_OBJECT_ONLY_NOT_DECODED'
          : 'NOT_VERIFIED',
      'first_page_font_cmap': verifyCmapSemantics && cmapMappedCodes > 0
          ? 'BOUNDED_CMAP_SYNTAX_ONLY_NOT_GLYPH_TEXT'
          : cmapStreams > 0
              ? 'BOUNDED_STREAM_LEXICAL_STRUCTURE_ONLY_NOT_MAPPING'
              : 'NOT_VERIFIED',
      'first_page_text_authority': 'FONT_OBJECTS_ONLY_NOT_AWARD_NUMBERS',
    };
  }

  Future<String> _resolveDictionary(
    String value, C500G0ReadObject readObject,
  ) async {
    final tail = value.trimLeft();
    if (tail.startsWith('<<')) return _boundedDictionary(tail);
    final reference = RegExp(r'^(\d+)\s+(\d+)\s+R\b').firstMatch(tail);
    if (reference == null) {
      throw const C500G0BoundedXrefException('C500_G0AA_DICTIONARY_FORM_UNSUPPORTED');
    }
    final object = await readObject(
      int.parse(reference.group(1)!), int.parse(reference.group(2)!));
    final start = object.indexOf('<<');
    if (start < 0) {
      throw const C500G0BoundedXrefException('C500_G0AA_DICTIONARY_FORM_UNSUPPORTED');
    }
    return _boundedDictionary(object.substring(start));
  }

  String _boundedDictionary(String text) {
    if (!text.startsWith('<<') || text.length > 64 * 1024) {
      throw const C500G0BoundedXrefException('C500_G0AA_DICTIONARY_BUDGET');
    }
    var depth = 0;
    for (var i = 0; i < text.length - 1; i++) {
      final a = text.codeUnitAt(i), b = text.codeUnitAt(i + 1);
      if (a == 60 && b == 60) {
        depth++;
        if (depth > 16) {
          throw const C500G0BoundedXrefException('C500_G0AA_DICTIONARY_DEPTH');
        }
        i++;
      } else if (a == 62 && b == 62) {
        depth--;
        i++;
        if (depth == 0) return text.substring(2, i - 1);
        if (depth < 0) {
          throw const C500G0BoundedXrefException('C500_G0AA_DICTIONARY_UNBALANCED');
        }
      }
    }
    throw const C500G0BoundedXrefException('C500_G0AA_DICTIONARY_UNBALANCED');
  }
}


// G0ab: one SHA-pinned XRef-resolved /ToUnicode stream at a time.
// This validates only bounded CMap lexical structure, never Unicode mapping,
// invoice numbers, all pages, or global NOT_WIN.
class C500G0CmapStreamProbe {
  const C500G0CmapStreamProbe();

  int verify({
    required String object,
    required int id,
    required int generation,
    bool verifyMappings = false,
    List<int>? firstOperand,
    List<List<int>>? allOperands,
    bool verifyFullOperand = false,
    void Function(int glyphCount)? onFullOperandDecoded,
    void Function(int operandCount, int glyphCount)? onAllOperandsDecoded,
  }) {
    if (object.length > 64 * 1024 ||
        !RegExp('^$id\\s+$generation\\s+obj\\b').hasMatch(object)) {
      throw const C500G0BoundedXrefException('C500_G0AB_OBJECT_IDENTITY_OR_BUDGET');
    }
    final marker = RegExp(
      r'>>[ \t]*(?:\r\n|\r|\n)?stream(?:\r\n|\r|\n)',
    ).firstMatch(object);
    if (marker == null) {
      throw const C500G0BoundedXrefException('C500_G0AB_STREAM_HEADER_MISSING');
    }
    final dictionary = object.substring(0, marker.start + 2);
    final lengths = RegExp(r'/Length\s+(\d+)\b').allMatches(dictionary).toList();
    if (lengths.length != 1 ||
        RegExp(r'/Length\s+\d+\s+\d+\s+R\b').hasMatch(dictionary) ||
        dictionary.contains('/DecodeParms')) {
      throw const C500G0BoundedXrefException('C500_G0AB_UNSUPPORTED_DICTIONARY');
    }
    final length = int.parse(lengths.single.group(1)!);
    if (length <= 0 || length > 32 * 1024) {
      throw const C500G0BoundedXrefException('C500_G0AB_COMPRESSED_LENGTH_LIMIT');
    }
    final filters = RegExp(r'/Filter\b').allMatches(dictionary).length;
    if (filters > 1 ||
        (filters == 1 &&
            !RegExp(r'/Filter\s*(?:/FlateDecode\b|\[\s*/FlateDecode\s*\])')
                .hasMatch(dictionary))) {
      throw const C500G0BoundedXrefException('C500_G0AB_FILTER_UNSUPPORTED');
    }
    if (length > object.length - marker.end) {
      throw const C500G0BoundedXrefException('C500_G0AB_STREAM_TRUNCATED');
    }
    final suffix = object.substring(marker.end + length);
    if (!RegExp(r'^(?:\r\n|\r|\n)?endstream\b').hasMatch(suffix)) {
      throw const C500G0BoundedXrefException('C500_G0AB_ENDSTREAM_MISMATCH');
    }
    final bytes = latin1.encode(object.substring(marker.end, marker.end + length));
    List<int> decoded;
    try {
      decoded = filters == 1
          ? const CloudAwardPdfBoundedStreamDecoder(
              maxCompressedBytes: 32 * 1024,
              maxDecodedBytes: 256 * 1024,
            ).decode(bytes: bytes, filters: const <String>['FlateDecode'])
          : bytes;
    } catch (_) {
      throw const C500G0BoundedXrefException('C500_G0AB_STREAM_DECODE_FAILED');
    }
    final body = latin1.decode(decoded, allowInvalid: true);
    if (RegExp(r'\bbegincmap\b').allMatches(body).length != 1 ||
        RegExp(r'\bendcmap\b').allMatches(body).length != 1 ||
        !RegExp(r'\bbegincodespacerange\b').hasMatch(body) ||
        !RegExp(r'\bendcodespacerange\b').hasMatch(body) ||
        !(RegExp(r'\bbeginbfchar\b').hasMatch(body) ||
            RegExp(r'\bbeginbfrange\b').hasMatch(body))) {
      throw const C500G0BoundedXrefException('C500_G0AB_CMAP_LEXICAL_MARKERS_MISSING');
    }
    if (firstOperand != null && !verifyMappings) {
      throw const C500G0BoundedXrefException('C500_G0AH_REQUIRES_SEMANTIC_CMAP');
    }
    final mapped = verifyMappings ? const C500G0CmapSemanticProbe().verify(body) : 0;
    if (firstOperand != null) {
      // Never serialize Unicode or raw operand; no invoice-number authority.
      const C500G0CmapSemanticProbe().decodeFirstOperandGlyph(
        body: body, operand: firstOperand,
      );
    }
    if (verifyFullOperand) {
      if (firstOperand == null || !verifyMappings) {
        throw const C500G0BoundedXrefException('C500_G0AI_REQUIRES_FIRST_GLYPH');
      }
      final count = const C500G0CmapSemanticProbe()
          .countFullyDecodedOperandGlyphs(body: body, operand: firstOperand);
      onFullOperandDecoded?.call(count);
    }
    if (allOperands != null) {
      if (!verifyMappings || allOperands.isEmpty || allOperands.length > 128) {
        throw const C500G0BoundedXrefException(
            'C500_G0AJ_OPERANDS_OR_CMAP_INVALID');
      }
      var totalBytes = 0, totalGlyphs = 0;
      for (final operand in allOperands) {
        totalBytes += operand.length;
        if (totalBytes > 16384) {
          throw const C500G0BoundedXrefException(
              'C500_G0AJ_CAPTURE_BUDGET');
        }
        totalGlyphs += const C500G0CmapSemanticProbe()
            .countFullyDecodedOperandGlyphs(body: body, operand: operand);
      }
      onAllOperandsDecoded?.call(allOperands.length, totalGlyphs);
    }
    return mapped;
  }
}


// G0ad: bounded syntax and UTF-16 consistency for one already verified CMap.
// This never promotes glyph bytes to invoice numbers, and never proves the
// remaining pages, global ordering, or NOT_WIN. Unsupported syntax fails closed.
class C500G0CmapSemanticProbe {
  const C500G0CmapSemanticProbe();

  // G0ai: decode every code in ONE bounded first text-show operand only.
  // Full CMap validation precedes segmentation; Unicode never leaves memory.
  // This is neither a page-level nor an invoice-level authority decision.
  int countFullyDecodedOperandGlyphs({
    required String body,
    required List<int> operand,
  }) {
    if (operand.isEmpty || operand.length > 256 ||
        operand.any((byte) => byte < 0 || byte > 255)) {
      throw const C500G0BoundedXrefException('C500_G0AI_OPERAND_BUDGET');
    }
    final codespaces = <List<int>>[];
    // Retain only mapping membership, never private Unicode code units.
    final mappings = <int>{};
    verify(body,
      onCodespace: (width, low, high) {
        codespaces.add(<int>[width, low, high]);
      },
      onMapping: (width, source, units) {
        mappings.add((width << 32) | source);
      },
    );
    var position = 0;
    var glyphCount = 0;
    while (position < operand.length) {
      if (glyphCount >= 64) {
        throw const C500G0BoundedXrefException('C500_G0AI_GLYPH_BUDGET');
      }
      final matches = <int>[];
      var prefix = 0;
      for (var width = 1; width <= 4 &&
          position + width <= operand.length; width++) {
        prefix = (prefix << 8) | operand[position + width - 1];
        for (final range in codespaces) {
          if (range[0] == width && range[1] <= prefix &&
              prefix <= range[2]) {
            matches.add(width);
          }
        }
      }
      if (matches.length != 1) {
        throw const C500G0BoundedXrefException(
            'C500_G0AI_CODESPACE_AMBIGUOUS_OR_TRUNCATED');
      }
      final width = matches.single;
      var source = 0;
      for (var i = 0; i < width; i++) {
        source = (source << 8) | operand[position + i];
      }
      if (!mappings.contains((width << 32) | source)) {
        throw const C500G0BoundedXrefException(
            'C500_G0AI_OPERAND_GLYPH_UNMAPPED');
      }
      position += width;
      glyphCount++;
    }
    return glyphCount;
  }

  // G0ah: first code-space-delimited glyph in a verified text-show operand.
  // Entire CMap is validated before decoding; ambiguous/missing fails closed.
  String decodeFirstOperandGlyph({
    required String body,
    required List<int> operand,
  }) {
    if (operand.isEmpty || operand.length > 64 * 1024) {
      throw const C500G0BoundedXrefException('C500_G0AH_OPERAND_BUDGET');
    }
    final prefixes = <int, int>{};
    var code = 0;
    for (var i = 0; i < min(4, operand.length); i++) {
      final byte = operand[i];
      if (byte < 0 || byte > 255) {
        throw const C500G0BoundedXrefException('C500_G0AH_OPERAND_BUDGET');
      }
      code = (code << 8) | byte;
      prefixes[i + 1] = code;
    }
    final matches = <int>[];
    List<int>? decodedUnits;
    verify(body,
      onCodespace: (width, low, high) {
        final prefix = prefixes[width];
        if (prefix != null && low <= prefix && prefix <= high) {
          matches.add(width);
        }
      },
      onMapping: (width, source, units) {
        if (prefixes[width] == source) decodedUnits = List<int>.of(units);
      },
    );
    if (matches.length != 1) {
      throw const C500G0BoundedXrefException('C500_G0AH_CODESPACE_AMBIGUOUS_OR_MISSING');
    }
    if (decodedUnits == null) {
      throw const C500G0BoundedXrefException('C500_G0AH_FIRST_GLYPH_UNMAPPED');
    }
    return String.fromCharCodes(decodedUnits!);
  }

  // G0af: bounded one-glyph ToUnicode lookup after validating the ENTIRE
  // selected CMap. This is a lab-only code-unit experiment, not a PDF invoice,
  // complete-page, sorting, or NOT_WIN decision.
  String decodeOneGlyph({
    required String body,
    required List<int> codeBytes,
  }) {
    if (codeBytes.isEmpty || codeBytes.length > 4 ||
        codeBytes.any((byte) => byte < 0 || byte > 255)) {
      throw const C500G0BoundedXrefException('C500_G0AF_GLYPH_CODE_INVALID');
    }
    var sourceCode = 0;
    for (final byte in codeBytes) {
      sourceCode = (sourceCode << 8) | byte;
    }
    List<int>? matchedUnits;
    verify(body, onMapping: (width, code, utf16Units) {
      if (width == codeBytes.length && code == sourceCode) {
        matchedUnits = List<int>.of(utf16Units);
      }
    });
    if (matchedUnits == null) {
      throw const C500G0BoundedXrefException('C500_G0AF_GLYPH_UNMAPPED');
    }
    return String.fromCharCodes(matchedUnits!);
  }

  int verify(String body, {
    void Function(int width, int code, List<int> utf16Units)? onMapping,
    void Function(int width, int low, int high)? onCodespace,
  }) {
    if (body.length > 256 * 1024 ||
        RegExp(r'\busecmap\b|\b(?:begin|end)(?:cidchar|cidrange|notdefchar|notdefrange)\b')
            .hasMatch(body)) {
      throw const C500G0BoundedXrefException('C500_G0AD_UNSUPPORTED_SEMANTICS');
    }
    final codespaces = <List<int>>[];
    final seen = <int>{};
    var mapped = 0;
    String? kind;
    var expected = 0;
    final entries = <String>[];
    final begin = RegExp(r'^(\d+)[ \t]+begin(codespacerange|bfchar|bfrange)$');
    final control = RegExp(r'\b(?:begin|end)(?:codespacerange|bfchar|bfrange)\b');
    final tokens = RegExp(r'<[0-9A-Fa-f]+>|\[|\]|[^\s]+');

    for (final rawLine in body.split(RegExp(r'\r\n|\r|\n'))) {
      final line = rawLine.split('%').first.trim();
      if (line.isEmpty) continue;
      if (kind == null) {
        final match = begin.firstMatch(line);
        if (match != null) {
          expected = int.parse(match.group(1)!);
          if (expected < 1 || expected > 256) {
            throw const C500G0BoundedXrefException('C500_G0AD_BLOCK_BUDGET');
          }
          kind = match.group(2)!;
          entries.clear();
        } else if (control.hasMatch(line)) {
          throw const C500G0BoundedXrefException('C500_G0AD_BLOCK_GRAMMAR');
        }
        continue;
      }
      if (line == 'end$kind') {
        var index = 0;
        for (var row = 0; row < expected; row++) {
          if (index + 1 >= entries.length) {
            throw const C500G0BoundedXrefException('C500_G0AD_BLOCK_GRAMMAR');
          }
          final low = _source(entries[index++]);
          final highOrTarget = entries[index++];
          if (kind == 'codespacerange') {
            final high = _source(highOrTarget);
            if (low.$1 != high.$1 || low.$2 > high.$2 ||
                codespaces.length >= 16) {
              throw const C500G0BoundedXrefException('C500_G0AD_CODESPACE_INVALID');
            }
            codespaces.add(<int>[low.$1, low.$2, high.$2]);
            onCodespace?.call(low.$1, low.$2, high.$2);
            continue;
          }
          _requireCodespace(low, codespaces);
          if (kind == 'bfchar') {
            final units = _utf16(highOrTarget);
            _record(low.$1, low.$2, seen);
            onMapping?.call(low.$1, low.$2, units);
            mapped++;
            continue;
          }
          final high = _source(highOrTarget);
          if (high.$1 != low.$1 || high.$2 < low.$2 ||
              high.$2 - low.$2 >= 8192) {
            throw const C500G0BoundedXrefException('C500_G0AD_RANGE_INVALID');
          }
          final span = high.$2 - low.$2 + 1;
          if (index >= entries.length) {
            throw const C500G0BoundedXrefException('C500_G0AD_BLOCK_GRAMMAR');
          }
          final destination = entries[index++];
          final mappedUnits = <List<int>>[];
          if (destination == '[') {
            for (var offset = 0; offset < span; offset++) {
              if (index >= entries.length) {
                throw const C500G0BoundedXrefException('C500_G0AD_BLOCK_GRAMMAR');
              }
              mappedUnits.add(_utf16(entries[index++]));
            }
            if (index >= entries.length || entries[index++] != ']') {
              throw const C500G0BoundedXrefException('C500_G0AD_BLOCK_GRAMMAR');
            }
          } else {
            final units = _utf16(destination);
            if (units.length != 1) {
              throw const C500G0BoundedXrefException('C500_G0AD_RANGE_INVALID');
            }
            for (var offset = 0; offset < span; offset++) {
              final unit = units.single + offset;
              if (unit > 0xffff || (unit >= 0xd800 && unit <= 0xdfff)) {
                throw const C500G0BoundedXrefException('C500_G0AD_UTF16_INVALID');
              }
              mappedUnits.add(<int>[unit]);
            }
          }
          for (var offset = 0; offset < span; offset++) {
            _requireCodespace((low.$1, low.$2 + offset), codespaces);
            _record(low.$1, low.$2 + offset, seen);
            onMapping?.call(low.$1, low.$2 + offset, mappedUnits[offset]);
          }
          mapped += span;
          if (mapped > 8192) {
            throw const C500G0BoundedXrefException('C500_G0AD_MAPPING_BUDGET');
          }
        }
        if (index != entries.length) {
          throw const C500G0BoundedXrefException('C500_G0AD_BLOCK_GRAMMAR');
        }
        kind = null;
        entries.clear();
        continue;
      }
      if (control.hasMatch(line)) {
        throw const C500G0BoundedXrefException('C500_G0AD_BLOCK_GRAMMAR');
      }
      entries.addAll(tokens.allMatches(line).map((match) => match.group(0)!));
      if (entries.length > 32768) {
        throw const C500G0BoundedXrefException('C500_G0AD_BLOCK_BUDGET');
      }
    }
    if (kind != null || codespaces.isEmpty || mapped == 0) {
      throw const C500G0BoundedXrefException('C500_G0AD_BLOCK_GRAMMAR');
    }
    return mapped;
  }

  (int, int) _source(String token) {
    final match = RegExp(r'^<([0-9A-Fa-f]{2,8})>$').firstMatch(token);
    final hex = match?.group(1);
    if (hex == null || hex.length.isOdd) {
      throw const C500G0BoundedXrefException('C500_G0AD_SOURCE_INVALID');
    }
    return (hex.length ~/ 2, int.parse(hex, radix: 16));
  }

  List<int> _utf16(String token) {
    final match = RegExp(r'^<([0-9A-Fa-f]{4,64})>$').firstMatch(token);
    final hex = match?.group(1);
    if (hex == null || hex.length % 4 != 0) {
      throw const C500G0BoundedXrefException('C500_G0AD_UTF16_INVALID');
    }
    final units = <int>[];
    for (var i = 0; i < hex.length; i += 4) {
      units.add(int.parse(hex.substring(i, i + 4), radix: 16));
    }
    for (var i = 0; i < units.length; i++) {
      final unit = units[i];
      if (unit >= 0xd800 && unit <= 0xdbff) {
        if (++i >= units.length ||
            units[i] < 0xdc00 || units[i] > 0xdfff) {
          throw const C500G0BoundedXrefException('C500_G0AD_UTF16_INVALID');
        }
      } else if (unit >= 0xdc00 && unit <= 0xdfff) {
        throw const C500G0BoundedXrefException('C500_G0AD_UTF16_INVALID');
      }
    }
    return units;
  }

  void _requireCodespace((int, int) code, List<List<int>> ranges) {
    if (!ranges.any((range) => range[0] == code.$1 &&
        range[1] <= code.$2 && code.$2 <= range[2])) {
      throw const C500G0BoundedXrefException('C500_G0AD_CODESPACE_INVALID');
    }
  }

  void _record(int width, int value, Set<int> seen) {
    if (!seen.add((width << 32) | value) || seen.length > 8192) {
      throw const C500G0BoundedXrefException('C500_G0AD_DUPLICATE_OR_BUDGET');
    }
  }
}
