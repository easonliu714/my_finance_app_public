// C500-G0w: synthetic-only PDF text-show operand grammar, never award authority.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import '../../../tool/c500_g0_content_glyph_probe.dart';

void main() {
  const probe = C500G0GlyphProbe();


  // G0x: a PDF text-state font name is necessary, never sufficient for
  // semantic Unicode or invoice-award authority.
  test('G0x records bounded font selections but never asserts ToUnicode', () {
    final result = probe.inspect(latin1.encode(
      'BT /F1 10 Tf (12345678) Tj /F2 9 Tf [<3132> 0 (345678)] TJ ET',
    ));
    expect(result['first_page_text_font_selection_operators'], 2);
    expect(result['first_page_text_font_names_unverified'], ['F1', 'F2']);
    expect(result['first_page_text_font_binding'],
        'TEXT_STATE_ONLY_NO_RESOURCE_OR_CMAP');
    expect(result['first_page_font_cmap'], 'NOT_VERIFIED');
    expect(result['first_page_text_authority'],
        'GLYPH_OPERANDS_ONLY_NOT_AWARD_NUMBERS');
  });

  test('G0x text-show without selected font fails closed', () {
    expect(() => probe.inspect(latin1.encode('BT (12345678) Tj ET')),
        throwsA(isA<C500G0GlyphException>().having(
            (e) => e.code, 'code', 'C500_G0X_FONT_NOT_SELECTED')));
  });

  test('G0x malformed font selection fails closed', () {
    expect(() => probe.inspect(latin1.encode('BT /F1 (12) Tf (1) Tj ET')),
        throwsA(isA<C500G0GlyphException>().having(
            (e) => e.code, 'code', 'C500_G0X_FONT_SELECTION_INVALID')));
  });

  test('G0x text-state font persists across separate BT/ET blocks', () {
    final result = probe.inspect(latin1.encode(
      'BT /F1 12 Tf (12345678) Tj ET BT (87654321) Tj ET',
    ));
    expect(result['first_page_text_font_selection_operators'], 1);
    expect(result['first_page_tj_operators'], 2);
  });


  // G0y: these are real grammar/security contracts, not extra telemetry.
  // Invalid font size or empty TJ must never produce apparent glyph evidence.
  test('G0y rejects non-positive and over-budget font sizes', () {
    for (final size in <String>['0', '-1', '1000001']) {
      expect(() => probe.inspect(latin1.encode(
        'BT /F1 $size Tf (12345678) Tj ET',
      )), throwsA(isA<C500G0GlyphException>().having(
        (e) => e.code, 'code', 'C500_G0Y_FONT_SIZE_INVALID',
      )));
    }
  });

  test('G0y accepts finite fractional Tf but preserves untrusted authority', () {
    final result = probe.inspect(latin1.encode(
      'BT /F1 12.5 Tf (12345678) Tj ET',
    ));
    expect(result['first_page_text_font_selection_operators'], 1);
    expect(result['first_page_font_cmap'], 'NOT_VERIFIED');
    expect(result['first_page_text_authority'],
        'GLYPH_OPERANDS_ONLY_NOT_AWARD_NUMBERS');
  });

  test('G0y rejects positioning-only TJ array as text evidence', () {
    expect(() => probe.inspect(latin1.encode(
      'BT /F1 12 Tf [0 -12 4] TJ ET',
    )), throwsA(isA<C500G0GlyphException>().having(
      (e) => e.code, 'code', 'C500_G0Y_TJ_NO_GLYPHS',
    )));
  });

  // G0z: compile/runtime regression for nullable look-behind snapshots.
  // Valid operands remain count-only; invalid look-behind cannot be trusted.
  test('G0z valid Tf and TJ snapshots preserve untrusted glyph authority', () {
    final result = probe.inspect(latin1.encode(
      'BT /F1 12 Tf [(12345678) -4 <31323334>] TJ ET',
    ));
    expect(result['first_page_text_font_selection_operators'], 1);
    expect(result['first_page_tj_array_operators'], 1);
    expect(result['first_page_raw_ascii_eight_digit_runs_untrusted'], 1);
    expect(result['first_page_font_cmap'], 'NOT_VERIFIED');
    expect(result['first_page_text_authority'],
        'GLYPH_OPERANDS_ONLY_NOT_AWARD_NUMBERS');
  });

  test('G0z invalid Tf and TJ look-behind fail closed', () {
    expect(() => probe.inspect(latin1.encode(
      'BT 12 Tf (12345678) Tj ET',
    )), throwsA(isA<C500G0GlyphException>().having(
      (e) => e.code, 'code', 'C500_G0X_FONT_SELECTION_INVALID',
    )));
    expect(() => probe.inspect(latin1.encode(
      'BT /F1 12 Tf (12345678) TJ ET',
    )), throwsA(isA<C500G0GlyphException>().having(
      (e) => e.code, 'code', 'C500_G0W_TEXT_ARRAY_INVALID',
    )));
  });

  test('bounded Tj and TJ recognize raw glyph operands without award proof', () {
    final result = probe.inspect(latin1.encode(
      'BT /F1 10 Tf (12345678) Tj [(AB) -10 <3132333435363738>] TJ ET',
    ));
    expect(result['first_page_bt_et_pairs'], 1);
    expect(result['first_page_tj_operators'], 1);
    expect(result['first_page_tj_array_operators'], 1);
    expect(result['first_page_literal_glyph_operands'], 2);
    expect(result['first_page_hex_glyph_operands'], 1);
    expect(result['first_page_raw_ascii_eight_digit_runs_untrusted'], 2);
    expect(result['first_page_font_cmap'], 'NOT_VERIFIED');
    expect(result['first_page_text_authority'],
        'GLYPH_OPERANDS_ONLY_NOT_AWARD_NUMBERS');
  });

  test('escaped octal and PDF comment are parsed, not promoted to text', () {
    final result = probe.inspect(latin1.encode(
      '% BT (99999999) Tj ET\nBT /F1 10 Tf (\\0612345678) Tj ET',
    ));
    expect(result['first_page_bt_et_pairs'], 1);
    expect(result['first_page_raw_ascii_eight_digit_runs_untrusted'], 1);
  });

  test('unterminated literal fails closed', () {
    expect(() => probe.inspect(latin1.encode('BT (abc Tj ET')),
        throwsA(isA<C500G0GlyphException>().having(
            (e) => e.code, 'code', 'C500_G0W_LITERAL_UNTERMINATED')));
  });

  test('nested TJ array fails closed', () {
    expect(() => probe.inspect(latin1.encode('BT [[(12)]] TJ ET')),
        throwsA(isA<C500G0GlyphException>().having(
            (e) => e.code, 'code', 'C500_G0W_ARRAY_LIMIT')));
  });

  test('text-show outside BT fails closed', () {
    expect(() => probe.inspect(latin1.encode('(12345678) Tj')),
        throwsA(isA<C500G0GlyphException>().having(
            (e) => e.code, 'code', 'C500_G0W_TEXT_OPERAND_INVALID')));
  });

  test('unsupported quote text-show fails closed', () {
    expect(() => probe.inspect(latin1.encode("BT (12345678) ' ET")),
        throwsA(isA<C500G0GlyphException>().having(
            (e) => e.code, 'code', 'C500_G0W_TEXT_SHOW_UNSUPPORTED')));
  });

  test('inline-image content is never interpreted as text', () {
    expect(() => probe.inspect(latin1.encode('BT BI ID abc EI ET')),
        throwsA(isA<C500G0GlyphException>().having(
            (e) => e.code, 'code', 'C500_G0W_INLINE_IMAGE_UNSUPPORTED')));
  });

  test('truncated BT/ET structure fails closed', () {
    expect(() => probe.inspect(latin1.encode('BT /F1 10 Tf (12345678) Tj')),
        throwsA(isA<C500G0GlyphException>().having(
            (e) => e.code, 'code', 'C500_G0W_TEXT_STRUCTURE_UNVERIFIED')));
  });
  // G0aj: synthetic-only capture boundary; the callback never emits text.
  test('G0aj captures every first-leaf text-show operand by selected font', () {
    final observed = <String, int>{};
    final result = probe.inspect(
      latin1.encode('BT /F1 10 Tf (1) Tj (2) Tj /F2 9 Tf [(3) -5 (4)] TJ ET'),
      onEveryFontOperand: (font, bytes) {
        observed[font] = (observed[font] ?? 0) + 1;
        bytes.fillRange(0, bytes.length, 0);
      },
    );
    expect(observed, <String, int>{'F1': 2, 'F2': 2});
    expect(result.containsKey('first_page_first_leaf_unicode_coverage_status'),
        false);
    expect(result['first_page_text_authority'],
        'GLYPH_OPERANDS_ONLY_NOT_AWARD_NUMBERS');
  });

  test('G0al oversized operand is UNKNOWN, contiguous prefix stays verified', () {
    final oversized = List<String>.filled(257, 'A').join();
    var captured = 0;
    final result = probe.inspect(
      latin1.encode('BT /F1 10 Tf (B) Tj ($oversized) Tj (C) Tj ET'),
      onEveryFontOperand: (font, bytes) {
        captured++;
        bytes.fillRange(0, bytes.length, 0);
      },
    );
    expect(captured, 1);
    expect(result['first_page_first_leaf_uncaptured_operands_unknown'], 2);
    expect(result['first_page_first_leaf_operand_capture_truncated'], true);
    expect(result['first_page_text_authority'],
        'GLYPH_OPERANDS_ONLY_NOT_AWARD_NUMBERS');
  });

  test('G0al empty text-show still fails closed before capture', () {
    expect(() => probe.inspect(
      latin1.encode('BT /F1 10 Tf () Tj ET'),
      onEveryFontOperand: (font, bytes) {},
    ), throwsA(isA<C500G0GlyphException>().having(
      (e) => e.code, 'code', 'C500_G0AJ_CAPTURE_BUDGET')));
  });

  // G0am: strict default negative remains red. Only the isolated source
  // lab may retain a complete prefix preceding an empty text-show.
  test('G0am lab empty operand is UNKNOWN and stops the contiguous prefix', () {
    final captured = <int>[];
    final result = probe.inspect(
      latin1.encode('BT /F1 10 Tf (A) Tj () Tj (B) Tj ET'),
      emptyOperandIsUnknownForLab: true,
      onEveryFontOperand: (font, bytes) {
        captured.add(bytes.length);
        bytes.fillRange(0, bytes.length, 0);
      },
    );
    expect(captured, <int>[1]);
    expect(result['first_page_first_leaf_uncaptured_operands_unknown'], 2);
    expect(result['first_page_first_leaf_operand_capture_truncated'], true);
    expect(result.containsKey('first_page_first_leaf_unicode_coverage_status'), false);
    expect(result['first_page_text_authority'],
        'GLYPH_OPERANDS_ONLY_NOT_AWARD_NUMBERS');
  });

  test('G0am lab leading empty leaves zero verified operands', () {
    var captured = 0;
    final result = probe.inspect(
      latin1.encode('BT /F1 10 Tf () Tj (A) Tj ET'),
      emptyOperandIsUnknownForLab: true,
      onEveryFontOperand: (font, bytes) {
        captured++;
        bytes.fillRange(0, bytes.length, 0);
      },
    );
    expect(captured, 0);
    expect(result['first_page_first_leaf_uncaptured_operands_unknown'], 2);
    expect(result['first_page_first_leaf_operand_capture_truncated'], true);
  });

  test('G0al 256-byte exact boundary is captured, 257-byte is UNKNOWN', () {
    for (final size in <int>[256, 257]) {
      var captured = 0;
      final operand = List<String>.filled(size, 'A').join();
      final result = probe.inspect(
        latin1.encode('BT /F1 10 Tf ($operand) Tj ET'),
        onEveryFontOperand: (font, bytes) {
          captured++;
          bytes.fillRange(0, bytes.length, 0);
        },
      );
      expect(captured, size == 256 ? 1 : 0);
      expect(result['first_page_first_leaf_uncaptured_operands_unknown'],
          size == 256 ? 0 : 1);
    }
  });

  test('G0ak 128/129 operand prefix preserves explicit unknown suffix', () {
    for (final count in <int>[128, 129]) {
      var captured = 0;
      final many = 'BT /F1 10 Tf ${List<String>.filled(count, '(A) Tj').join(' ')} ET';
      final result = probe.inspect(latin1.encode(many),
        onEveryFontOperand: (font, bytes) {
          captured++;
          bytes.fillRange(0, bytes.length, 0);
        },
      );
      expect(captured, 128);
      expect(result['first_page_first_leaf_uncaptured_operands_unknown'],
          count - 128);
      expect(result['first_page_first_leaf_operand_capture_truncated'],
          count > 128);
    }
  });

  test('G0ak first skipped operand prevents discontiguous resumption', () {
    var captured = 0;
    final large = List<String>.filled(256, 'A').join();
    final almost = List<String>.filled(250, 'B').join();
    final tooLarge = List<String>.filled(7, 'C').join();
    final many = 'BT /F1 10 Tf ${List<String>.filled(63, '($large) Tj').join(' ')} '
        '($almost) Tj ($tooLarge) Tj (D) Tj ET';
    final result = probe.inspect(latin1.encode(many),
      onEveryFontOperand: (font, bytes) {
        captured++;
        bytes.fillRange(0, bytes.length, 0);
      },
    );
    expect(captured, 64);
    expect(result['first_page_first_leaf_uncaptured_operands_unknown'], 2);
    expect(result['first_page_first_leaf_operand_capture_truncated'], true);
  });

  test('G0ak 16KiB aggregate cap reports omitted operand', () {
    var captured = 0;
    final operand = List<String>.filled(256, 'A').join();
    final many = 'BT /F1 10 Tf ${List<String>.filled(65, '($operand) Tj').join(' ')} ET';
    final result = probe.inspect(latin1.encode(many),
      onEveryFontOperand: (font, bytes) {
        captured++;
        bytes.fillRange(0, bytes.length, 0);
      },
    );
    expect(captured, 64);
    expect(result['first_page_first_leaf_uncaptured_operands_unknown'], 1);
    expect(result['first_page_first_leaf_operand_capture_truncated'], true);
  });

}
