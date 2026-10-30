// C500-G0w: synthetic-only PDF text-show operand grammar, never award authority.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import '../../../tool/c500_g0_content_glyph_probe.dart';

void main() {
  const probe = C500G0GlyphProbe();

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
      '% BT (99999999) Tj ET\nBT (\\0612345678) Tj ET',
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
    expect(() => probe.inspect(latin1.encode('BT (12345678) Tj')),
        throwsA(isA<C500G0GlyphException>().having(
            (e) => e.code, 'code', 'C500_G0W_TEXT_STRUCTURE_UNVERIFIED')));
  });
}
