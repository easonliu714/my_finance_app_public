// C500-G0w: isolated one-page PDF text-show operand lexer.
// A PDF content stream contains font glyph codes, NOT Unicode invoice numbers.
// This helper never produces an award match or global NOT_WIN authority.
import 'dart:convert';

class C500G0GlyphException implements Exception {
  const C500G0GlyphException(this.code);
  final String code;
  @override
  String toString() => code;
}

class C500G0GlyphProbe {
  const C500G0GlyphProbe();

  Map<String, Object?> inspect(List<int> decoded) {
    if (decoded.isEmpty || decoded.length > 8 * 1024 * 1024) {
      throw const C500G0GlyphException('C500_G0W_CONTENT_BUDGET');
    }
    final lexer = _C500G0GlyphLexer(decoded);
    var beginText = 0, endText = 0, tj = 0, tjArray = 0;
    var literal = 0, hex = 0, rawEightDigits = 0;
    var inText = false;
    _C500G0GlyphToken? previous;

    void consume(_C500G0GlyphToken value) {
      if (value.kind == 'literal') {
        literal++;
      } else if (value.kind == 'hex') {
        hex++;
      } else {
        throw const C500G0GlyphException('C500_G0W_TEXT_OPERAND_INVALID');
      }
      // Raw font-encoded glyph bytes are deliberately NOT decoded as text.
      // Count-only signal; never expose digits or use them for a win decision.
      var run = 0;
      for (final byte in value.bytes) {
        if (byte >= 48 && byte <= 57) {
          run++;
        } else {
          if (run == 8) rawEightDigits++;
          run = 0;
        }
      }
      if (run == 8) rawEightDigits++;
    }

    _C500G0GlyphToken? token;
    while ((token = lexer.next()) != null) {
      final current = token!;
      if (current.kind == 'word') {
        switch (current.word) {
          case 'BT':
            if (inText) {
              throw const C500G0GlyphException('C500_G0W_NESTED_BT');
            }
            inText = true;
            beginText++;
            previous = null;
            continue;
          case 'ET':
            if (!inText) {
              throw const C500G0GlyphException('C500_G0W_UNBALANCED_ET');
            }
            inText = false;
            endText++;
            previous = null;
            continue;
          case 'Tj':
            if (!inText || previous == null ||
                (previous.kind != 'literal' && previous.kind != 'hex')) {
              throw const C500G0GlyphException('C500_G0W_TEXT_OPERAND_INVALID');
            }
            consume(previous);
            tj++;
            break;
          case 'TJ':
            if (!inText || previous?.kind != 'array') {
              throw const C500G0GlyphException('C500_G0W_TEXT_ARRAY_INVALID');
            }
            final items = previous!.items;
            if (items.isEmpty) {
              throw const C500G0GlyphException('C500_G0W_TEXT_ARRAY_INVALID');
            }
            for (final item in items) {
              if (item.kind == 'literal' || item.kind == 'hex') {
                consume(item);
              } else if (item.kind != 'number') {
                throw const C500G0GlyphException('C500_G0W_TEXT_ARRAY_INVALID');
              }
            }
            tjArray++;
            break;
          case "'":
          case '"':
            if (inText) {
              throw const C500G0GlyphException('C500_G0W_TEXT_SHOW_UNSUPPORTED');
            }
            break;
          case 'BI':
            // Inline-image binary must not be lexed as PDF text operators.
            throw const C500G0GlyphException('C500_G0W_INLINE_IMAGE_UNSUPPORTED');
        }
      }
      previous = current;
    }
    if (inText || beginText != endText || beginText == 0 ||
        tj + tjArray == 0) {
      throw const C500G0GlyphException('C500_G0W_TEXT_STRUCTURE_UNVERIFIED');
    }
    return <String, Object?>{
      'first_page_bt_et_pairs': beginText,
      'first_page_tj_operators': tj,
      'first_page_tj_array_operators': tjArray,
      'first_page_literal_glyph_operands': literal,
      'first_page_hex_glyph_operands': hex,
      'first_page_raw_ascii_eight_digit_runs_untrusted': rawEightDigits,
      'first_page_font_cmap': 'NOT_VERIFIED',
      'first_page_text_authority': 'GLYPH_OPERANDS_ONLY_NOT_AWARD_NUMBERS',
    };
  }
}

class _C500G0GlyphToken {
  const _C500G0GlyphToken(this.kind, {
    this.word = '',
    this.bytes = const <int>[],
    this.items = const <_C500G0GlyphToken>[],
  });
  final String kind;
  final String word;
  final List<int> bytes;
  final List<_C500G0GlyphToken> items;
}

class _C500G0GlyphLexer {
  _C500G0GlyphLexer(this.data);
  final List<int> data;
  int offset = 0;
  int tokens = 0;
  static const int maxTokenBytes = 64 * 1024;
  static const int maxTokens = 200000;

  bool _space(int c) => c == 0 || c == 9 || c == 10 ||
      c == 12 || c == 13 || c == 32;
  bool _delimiter(int c) => c == 40 || c == 41 || c == 60 ||
      c == 62 || c == 91 || c == 93 || c == 123 ||
      c == 125 || c == 47 || c == 37;
  bool _octal(int c) => c >= 48 && c <= 55;
  int _hex(int c) {
    if (c >= 48 && c <= 57) return c - 48;
    if (c >= 65 && c <= 70) return c - 55;
    if (c >= 97 && c <= 102) return c - 87;
    return -1;
  }

  _C500G0GlyphToken? next() {
    final token = _primitive();
    if (token == null || token.kind != '[') return token;
    final items = <_C500G0GlyphToken>[];
    while (true) {
      final item = _primitive();
      if (item == null) {
        throw const C500G0GlyphException('C500_G0W_ARRAY_UNTERMINATED');
      }
      if (item.kind == ']') break;
      if (item.kind == '[' || items.length >= 10000) {
        throw const C500G0GlyphException('C500_G0W_ARRAY_LIMIT');
      }
      items.add(item);
    }
    return _C500G0GlyphToken('array', items: items);
  }

  _C500G0GlyphToken? _primitive() {
    while (offset < data.length) {
      final c = data[offset];
      if (_space(c)) {
        offset++;
        continue;
      }
      if (c == 37) {
        while (offset < data.length &&
            data[offset] != 10 && data[offset] != 13) {
          offset++;
        }
        continue;
      }
      break;
    }
    if (offset >= data.length) return null;
    if (++tokens > maxTokens) {
      throw const C500G0GlyphException('C500_G0W_TOKEN_LIMIT');
    }
    final c = data[offset++];
    if (c == 40) {
      final output = <int>[];
      var depth = 1;
      while (offset < data.length) {
        final value = data[offset++];
        if (value == 92) {
          if (offset >= data.length) {
            throw const C500G0GlyphException('C500_G0W_LITERAL_UNTERMINATED');
          }
          final next = data[offset++];
          if (next == 10) continue;
          if (next == 13) {
            if (offset < data.length && data[offset] == 10) offset++;
            continue;
          }
          if (_octal(next)) {
            var code = next - 48;
            for (var i = 0; i < 2 && offset < data.length &&
                _octal(data[offset]); i++) {
              code = code * 8 + data[offset++] - 48;
            }
            output.add(code & 255);
          } else {
            const escapes = <int, int>{
              110: 10, 114: 13, 116: 9, 98: 8, 102: 12,
            };
            output.add(escapes[next] ?? next);
          }
        } else if (value == 40) {
          if (++depth > 8) {
            throw const C500G0GlyphException('C500_G0W_LITERAL_DEPTH');
          }
          output.add(value);
        } else if (value == 41) {
          if (--depth == 0) {
            return _C500G0GlyphToken('literal', bytes: output);
          }
          output.add(value);
        } else {
          output.add(value);
        }
        if (output.length > maxTokenBytes) {
          throw const C500G0GlyphException('C500_G0W_OPERAND_LIMIT');
        }
      }
      throw const C500G0GlyphException('C500_G0W_LITERAL_UNTERMINATED');
    }
    if (c == 60) {
      if (offset < data.length && data[offset] == 60) {
        offset++;
        return const _C500G0GlyphToken('dictionary');
      }
      final output = <int>[];
      var high = -1;
      while (offset < data.length) {
        final value = data[offset++];
        if (value == 62) {
          if (high >= 0) output.add(high << 4);
          return _C500G0GlyphToken('hex', bytes: output);
        }
        if (_space(value)) continue;
        final nibble = _hex(value);
        if (nibble < 0) {
          throw const C500G0GlyphException('C500_G0W_HEX_INVALID');
        }
        if (high < 0) {
          high = nibble;
        } else {
          output.add((high << 4) | nibble);
          high = -1;
        }
        if (output.length > maxTokenBytes) {
          throw const C500G0GlyphException('C500_G0W_OPERAND_LIMIT');
        }
      }
      throw const C500G0GlyphException('C500_G0W_HEX_UNTERMINATED');
    }
    if (c == 62 && offset < data.length && data[offset] == 62) {
      offset++;
      return const _C500G0GlyphToken('dictionary');
    }
    if (c == 91) return const _C500G0GlyphToken('[');
    if (c == 93) return const _C500G0GlyphToken(']');
    if (c == 47) {
      final start = offset;
      while (offset < data.length && !_space(data[offset]) &&
          !_delimiter(data[offset])) {
        offset++;
      }
      if (offset - start > maxTokenBytes) {
        throw const C500G0GlyphException('C500_G0W_OPERAND_LIMIT');
      }
      return const _C500G0GlyphToken('name');
    }
    final start = offset - 1;
    while (offset < data.length && !_space(data[offset]) &&
        !_delimiter(data[offset])) {
      offset++;
    }
    if (offset - start > maxTokenBytes) {
      throw const C500G0GlyphException('C500_G0W_OPERAND_LIMIT');
    }
    final word = latin1.decode(data.sublist(start, offset));
    if (RegExp(r'^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$').hasMatch(word)) {
      return _C500G0GlyphToken('number', word: word);
    }
    return _C500G0GlyphToken('word', word: word);
  }
}
