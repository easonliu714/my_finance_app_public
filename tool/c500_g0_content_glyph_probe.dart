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

  Map<String, Object?> inspect(List<int> decoded, {
    void Function(String fontName, List<int> bytes)? onFirstFontOperand,
    // G0ak: private bounded prefix; uncaptured suffix remains UNKNOWN.
    void Function(String fontName, List<int> bytes)? onEveryFontOperand,
    // G0am: lab-only classification. Empty glyph strings remain UNKNOWN and
    // permanently terminate the verified prefix; strict default still throws.
    bool emptyOperandIsUnknownForLab = false,
    // G0an: isolated source lab may prove a syntactically empty Tj/TJ string
    // contributes zero glyphs. It never counts as decoded Unicode or award.
    bool emptyOperandIsNoGlyphForLab = false,
  }) {
    if (decoded.isEmpty || decoded.length > 8 * 1024 * 1024) {
      throw const C500G0GlyphException('C500_G0W_CONTENT_BUDGET');
    }
    final lexer = _C500G0GlyphLexer(decoded);
    var beginText = 0, endText = 0, tj = 0, tjArray = 0;
    var literal = 0, hex = 0, rawEightDigits = 0;
    var inText = false;
    // G0x: bind each text-show to an explicit text-state font selection.
    // A selected font name is NOT proof of a /Resources entry or ToUnicode.
    String? selectedFont;
    final selectedFontNames = <String>{};
    var fontSelections = 0;
    final sampledFonts = <String>{};
    var capturedOperandCount = 0, capturedOperandBytes = 0;
    var uncapturedOperandCount = 0;
    var zeroGlyphOperandCount = 0;
    String firstOmissionReason = 'NONE';
    _C500G0GlyphToken? previous;
    _C500G0GlyphToken? beforePrevious;

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
      // G0ag: capture only the first bounded text-show operand for each
      // selected font, privately for downstream XRef binding. Never emit bytes.
      final font = selectedFont;
      if (font != null && value.bytes.isNotEmpty && sampledFonts.add(font)) {
        onFirstFontOperand?.call(font, List<int>.of(value.bytes));
      }
      // G0ak: retain a strict 128-operand / 16KiB prefix. Count omitted
      // operands as UNKNOWN; never promote a prefix to full-leaf evidence.
      // Invalid individual operands still fail closed before any copy.
      if (font != null && onEveryFontOperand != null) {
        if (value.bytes.isEmpty) {
          if (emptyOperandIsNoGlyphForLab) {
            // PDF Tj/TJ empty string has no character codes to map. This is
            // structural evidence only: never increment decoded glyph count.
            // Continue the contiguous nonempty operand prefix without
            // pretending that an omitted glyph was verified.
            zeroGlyphOperandCount++;
            return;
          }
          if (!emptyOperandIsUnknownForLab) {
            throw const C500G0GlyphException('C500_G0AJ_CAPTURE_BUDGET');
          }
          if (uncapturedOperandCount == 0) firstOmissionReason = 'EMPTY_GLYPH_UNKNOWN';
          uncapturedOperandCount++;
          return;
        }
        // G0al: a >256-byte text-show is not a corrupt PDF. Its full
        // glyph bytes cannot fit the verified bounded capture. Mark this
        // operand UNKNOWN and permanently stop the contiguous prefix.
        // Never raise the cap, decode a truncated glyph, or claim NOT_WIN.
        if (value.bytes.length > 256) {
          if (uncapturedOperandCount == 0) firstOmissionReason = 'PER_OPERAND_256';
          uncapturedOperandCount++;
          return;
        }
        // Once an operand is omitted, never resume capture with a smaller
        // later operand: a discontiguous sample is not a verified prefix.
        if (uncapturedOperandCount > 0 ||
            capturedOperandCount >= 128 ||
            value.bytes.length > 16384 - capturedOperandBytes) {
          if (uncapturedOperandCount == 0) {
            firstOmissionReason = capturedOperandCount >= 128
                ? 'OPERAND_COUNT_128' : 'AGGREGATE_16K';
          }
          uncapturedOperandCount++;
        } else {
          onEveryFontOperand(font, List<int>.of(value.bytes));
          capturedOperandCount++;
          capturedOperandBytes += value.bytes.length;
        }
      }
    }

    _C500G0GlyphToken? token;
    while ((token = lexer.next()) != null) {
      final current = token!;
      // G0z: snapshot nullable look-behind operands before branch validation.
      // Dart does not promote mutable loop-carried tokens across these checks;
      // only validated local snapshots may be dereferenced.
      final prior = previous;
      final prior2 = beforePrevious;
      if (current.kind == 'word') {
        switch (current.word) {
          case 'BT':
            if (inText) {
              throw const C500G0GlyphException('C500_G0W_NESTED_BT');
            }
            inText = true;
            beginText++;
            previous = null;
            beforePrevious = null;
            continue;
          case 'ET':
            if (!inText) {
              throw const C500G0GlyphException('C500_G0W_UNBALANCED_ET');
            }
            inText = false;
            endText++;
            previous = null;
            beforePrevious = null;
            continue;
          case 'Tj':
            if (!inText || prior == null ||
                (prior.kind != 'literal' && prior.kind != 'hex')) {
              throw const C500G0GlyphException('C500_G0W_TEXT_OPERAND_INVALID');
            }
            if (selectedFont == null) {
              throw const C500G0GlyphException('C500_G0X_FONT_NOT_SELECTED');
            }
            consume(prior);
            tj++;
            break;
          case 'TJ':
            if (!inText || prior == null || prior.kind != 'array') {
              throw const C500G0GlyphException('C500_G0W_TEXT_ARRAY_INVALID');
            }
            if (selectedFont == null) {
              throw const C500G0GlyphException('C500_G0X_FONT_NOT_SELECTED');
            }
            final items = prior.items;
            if (items.isEmpty) {
              throw const C500G0GlyphException('C500_G0W_TEXT_ARRAY_INVALID');
            }
            // G0y: a positioning-only TJ array is not text evidence.
            var glyphItemCount = 0;
            for (final item in items) {
              if (item.kind == 'literal' || item.kind == 'hex') {
                consume(item);
                // G0an: empty TJ strings are structural no-glyph items,
                // never sufficient to make a positioning-only TJ text proof.
                if (item.bytes.isNotEmpty) glyphItemCount++;
              } else if (item.kind != 'number') {
                throw const C500G0GlyphException('C500_G0W_TEXT_ARRAY_INVALID');
              }
            }
            if (glyphItemCount == 0) {
              throw const C500G0GlyphException('C500_G0Y_TJ_NO_GLYPHS');
            }
            tjArray++;
            break;
          case 'Tf':
            if (!inText || prior == null || prior.kind != 'number' ||
                prior2 == null || prior2.kind != 'name' ||
                prior2.word.isEmpty) {
              throw const C500G0GlyphException('C500_G0X_FONT_SELECTION_INVALID');
            }
            // G0y: a syntactically selected font must have a finite,
            // positive, bounded text size. This does not verify /Resources.
            final fontSize = double.tryParse(prior.word);
            if (fontSize == null || !fontSize.isFinite ||
                fontSize <= 0 || fontSize > 1000000) {
              throw const C500G0GlyphException('C500_G0Y_FONT_SIZE_INVALID');
            }
            selectedFont = prior2.word;
            selectedFontNames.add(selectedFont);
            if (selectedFontNames.length > 16) {
              throw const C500G0GlyphException('C500_G0X_FONT_VARIETY_LIMIT');
            }
            fontSelections++;
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
      beforePrevious = previous;
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
      'first_page_text_font_selection_operators': fontSelections,
      'first_page_first_leaf_uncaptured_operands_unknown': uncapturedOperandCount,
      'first_page_first_leaf_zero_glyph_operands_structural_only': zeroGlyphOperandCount,
      'first_page_first_leaf_first_omission_reason': firstOmissionReason,
      'first_page_first_leaf_operand_capture_truncated':
          uncapturedOperandCount > 0,
      'first_page_text_font_names_unverified': selectedFontNames.toList()..sort(),
      'first_page_text_font_binding': 'TEXT_STATE_ONLY_NO_RESOURCE_OR_CMAP',
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
      return _C500G0GlyphToken('name',
          word: latin1.decode(data.sublist(start, offset)));
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
