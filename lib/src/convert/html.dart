// Copyright (c) 2018, the Zefyr project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' show parseFragment;
import 'package:notus_format/notus_format.dart' show NotusAttribute;
import 'package:quill_format/quill_format.dart';

/// Converts between Notus documents and the HTML produced by the web editor.
///
/// Web headings h2, h3 and h4 map to Notus heading levels 1, 2 and 3.
class NotusHTMLCodec extends Codec<Delta, String> {
  const NotusHTMLCodec({this.wrapLinesInParagraphs = true});

  /// When false, plain lines are encoded without `<p>` tags and separated
  /// with new line characters.
  final bool wrapLinesInParagraphs;

  @override
  Converter<String, Delta> get decoder => _HtmlNotusDecoder();

  @override
  Converter<Delta, String> get encoder =>
      _NotusHtmlEncoder(wrapLinesInParagraphs);
}

const _defaultTextColor = 0xFF2E2E2E;

final _headingKey = NotusAttribute.heading.key;
final _blockKey = NotusAttribute.block.key;
final _alignmentKey = NotusAttribute.alignment.key;
final _linkKey = NotusAttribute.link.key;
final _colorKey = NotusAttribute.color.key;

final _inlineKeysOutermostFirst = [
  _linkKey,
  _colorKey,
  NotusAttribute.bold.key,
  NotusAttribute.italic.key,
  NotusAttribute.underline.key,
  NotusAttribute.strikethrough.key,
];

const _inlineTagAttributeKeys = {
  'strong': 'b',
  'b': 'b',
  'em': 'i',
  'i': 'i',
  'u': 'u',
  's': 's',
  'strike': 's',
  'del': 's',
};

const _lineTags = {'p', 'div', 'li', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6'};

const _headingLevelsByTag = {
  'h1': 1,
  'h2': 1,
  'h3': 2,
  'h4': 3,
  'h5': 3,
  'h6': 3,
};

const _blocksByTag = {
  'ul': 'ul',
  'ol': 'ol',
  'blockquote': 'quote',
  'pre': 'code',
};

const _listTags = {'ul', 'ol'};

final _textAlignRegExp = RegExp(r'(?:^|;)\s*text-align\s*:\s*([\w-]+)');
final _quillAlignClassRegExp = RegExp(r'(?:^|\s)ql-align-([\w-]+)');
final _colorRegExp = RegExp(r'(?:^|;)\s*color\s*:\s*([^;]+)');
final _rgbRegExp = RegExp(r'^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)');
final _hexColorRegExp = RegExp(r'^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$');

class _HtmlNotusDecoder extends Converter<String, Delta> {
  @override
  Delta convert(String input) => _DeltaBuilder().build(parseFragment(input));
}

class _DeltaBuilder {
  final _delta = Delta();
  bool _hasLineContent = false;
  int _lineCount = 0;
  int _pendingEmptyLines = 0;
  bool _skipNewlineAfterBlock = false;

  Delta build(DocumentFragment fragment) {
    for (final node in fragment.nodes) {
      _visit(node, const {}, const {});
    }
    if (_hasLineContent) {
      _endLine(const {});
    }
    if (_delta.isEmpty) {
      _delta.insert('\n');
    }
    return _delta;
  }

  void _visit(
    Node node,
    Map<String, dynamic> inlineAttributes,
    Map<String, dynamic> lineAttributes,
  ) {
    if (node is Text) {
      _addText(node.data, inlineAttributes, lineAttributes);
      return;
    }
    if (node is! Element) return;

    if (node.localName == 'br') {
      _endLine(lineAttributes);
      return;
    }
    final blockLineAttributes = _blockLineAttributes(node, lineAttributes);
    if (blockLineAttributes == null) {
      final childInlineAttributes = _inlineAttributes(node, inlineAttributes);
      for (final child in node.nodes) {
        _visit(child, childInlineAttributes, lineAttributes);
      }
      return;
    }

    if (_hasLineContent) {
      _endLine(lineAttributes);
    }
    final lineCountBefore = _lineCount;
    final isList = _listTags.contains(node.localName);
    for (final child in node.nodes) {
      if (isList && child is Text && child.data.trim().isEmpty) continue;
      _visit(child, inlineAttributes, blockLineAttributes);
    }
    final isEmptyLineTag =
        _lineTags.contains(node.localName) && _lineCount == lineCountBefore;
    if (_hasLineContent || isEmptyLineTag) {
      _endLine(blockLineAttributes);
    }
    _skipNewlineAfterBlock = true;
  }

  void _addText(
    String data,
    Map<String, dynamic> inlineAttributes,
    Map<String, dynamic> lineAttributes,
  ) {
    String text = data
        .replaceAll(String.fromCharCode(0x200B), '')
        .replaceAll(String.fromCharCode(0xA0), ' ');
    if (_skipNewlineAfterBlock && text.startsWith('\n')) {
      text = text.substring(1);
    }
    if (text.isEmpty) return;
    _skipNewlineAfterBlock = false;

    final lines = text.split('\n');
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].isNotEmpty) {
        _insertText(lines[i], inlineAttributes);
      }
      if (i < lines.length - 1) {
        _endLine(lineAttributes);
      }
    }
  }

  void _insertText(String text, Map<String, dynamic> inlineAttributes) {
    _insertPendingEmptyLines();
    _delta.insert(
      text,
      inlineAttributes.isEmpty
          ? null
          : Map<String, dynamic>.from(inlineAttributes),
    );
    _hasLineContent = true;
  }

  /// Empty lines outside blocks lose their styles and are inserted only once
  /// more content follows, so trailing empty lines are dropped.
  void _endLine(Map<String, dynamic> lineAttributes) {
    _lineCount++;
    if (!_hasLineContent && !lineAttributes.containsKey(_blockKey)) {
      _pendingEmptyLines++;
      return;
    }
    _insertPendingEmptyLines();
    _delta.insert(
      '\n',
      lineAttributes.isEmpty ? null : Map<String, dynamic>.from(lineAttributes),
    );
    _hasLineContent = false;
  }

  void _insertPendingEmptyLines() {
    if (_pendingEmptyLines == 0) return;
    _delta.insert('\n' * _pendingEmptyLines);
    _pendingEmptyLines = 0;
  }

  Map<String, dynamic>? _blockLineAttributes(
    Element element,
    Map<String, dynamic> lineAttributes,
  ) {
    final tag = element.localName;
    final headingLevel = _headingLevelsByTag[tag];
    final block = _blocksByTag[tag];
    if (!_lineTags.contains(tag) && block == null) return null;

    final result = Map<String, dynamic>.from(lineAttributes);
    if (headingLevel != null) {
      result[_headingKey] = headingLevel;
    }
    if (block != null) {
      result[_blockKey] = block;
    }
    final textAlign = _textAlignRegExp
            .firstMatch(element.attributes['style'] ?? '') ??
        _quillAlignClassRegExp.firstMatch(element.attributes['class'] ?? '');
    if (textAlign != null) {
      final alignment = _alignmentFromTextAlign(textAlign.group(1)!);
      if (alignment == null) {
        result.remove(_alignmentKey);
      } else {
        result[_alignmentKey] = alignment;
      }
    }
    return result;
  }

  String? _alignmentFromTextAlign(String textAlign) {
    switch (textAlign) {
      case 'center':
        return NotusAttribute.center.value;
      case 'right':
      case 'end':
        return NotusAttribute.end.value;
      case 'justify':
        return NotusAttribute.justify.value;
      default:
        return null;
    }
  }

  Map<String, dynamic> _inlineAttributes(
    Element element,
    Map<String, dynamic> inlineAttributes,
  ) {
    final result = Map<String, dynamic>.from(inlineAttributes);
    final tagAttributeKey = _inlineTagAttributeKeys[element.localName];
    if (tagAttributeKey != null) {
      result[tagAttributeKey] = true;
    }
    final href = element.attributes['href'];
    if (element.localName == 'a' && href != null) {
      result[_linkKey] = href;
    }
    final colorMatch =
        _colorRegExp.firstMatch(element.attributes['style'] ?? '');
    if (colorMatch != null) {
      final color = _parseColor(colorMatch.group(1)!.trim());
      if (color == null || color == _defaultTextColor) {
        result.remove(_colorKey);
      } else {
        result[_colorKey] = color;
      }
    }
    return result;
  }

  int? _parseColor(String value) {
    final rgb = _rgbRegExp.firstMatch(value);
    if (rgb != null) {
      final channels =
          [1, 2, 3].map((i) => int.parse(rgb.group(i)!).clamp(0, 255)).toList();
      return 0xFF000000 | channels[0] << 16 | channels[1] << 8 | channels[2];
    }
    final hex = _hexColorRegExp.firstMatch(value);
    if (hex != null) {
      String digits = hex.group(1)!;
      if (digits.length == 3) {
        digits = digits.split('').map((digit) => digit * 2).join();
      }
      return 0xFF000000 | int.parse(digits, radix: 16);
    }
    return null;
  }
}

class _NotusHtmlEncoder extends Converter<Delta, String> {
  _NotusHtmlEncoder(this.wrapLinesInParagraphs);

  final bool wrapLinesInParagraphs;

  static const _textEscape = HtmlEscape(HtmlEscapeMode.element);
  static const _attributeEscape = HtmlEscape(HtmlEscapeMode.attribute);

  @override
  String convert(Delta input) {
    final topLevelHtml = <String>[];
    final blockLines = <_Line>[];
    String? openBlock;
    void closeBlock() {
      final block = openBlock;
      if (block != null) {
        topLevelHtml.add(_blockHtml(block, blockLines));
      }
      blockLines.clear();
    }

    for (final line in _splitLines(input)) {
      final block = line.attributes[_blockKey] as String?;
      if (block != openBlock) {
        closeBlock();
        openBlock = block;
      }
      if (block == null) {
        topLevelHtml.add(_lineHtml(line));
      } else {
        blockLines.add(line);
      }
    }
    closeBlock();
    return topLevelHtml.join(wrapLinesInParagraphs ? '' : '\n');
  }

  String _blockHtml(String block, List<_Line> lines) {
    if (block == NotusAttribute.code.value) {
      final code = lines.map((line) => _inlineHtml(line.runs)).join('\n');
      return '<pre><code>$code</code></pre>';
    }
    if (block == NotusAttribute.bq.value) {
      final separator = wrapLinesInParagraphs ? '' : '\n';
      return '<blockquote>${lines.map(_lineHtml).join(separator)}</blockquote>';
    }
    final items = lines.map((line) => '<li>${_lineHtml(line)}</li>').join();
    return '<$block>$items</$block>';
  }

  List<_Line> _splitLines(Delta delta) {
    final lines = <_Line>[];
    List<_Run> runs = [];
    for (final operation in delta.toList()) {
      final data = operation.data;
      if (!operation.isInsert || data is! String) continue;
      final attributes = operation.attributes ?? const <String, dynamic>{};
      final segments = data.split('\n');
      for (int i = 0; i < segments.length; i++) {
        if (segments[i].isNotEmpty) {
          runs.add(_Run(segments[i], attributes));
        }
        if (i < segments.length - 1) {
          lines.add(_Line(runs, attributes));
          runs = [];
        }
      }
    }
    if (runs.isNotEmpty) {
      lines.add(_Line(runs, const {}));
    }
    while (lines.length > 1 && lines.last.isEmptyPlainLine) {
      lines.removeLast();
    }
    return lines;
  }

  String _lineHtml(_Line line) {
    final headingLevel = line.attributes[_headingKey] as int?;
    final textAlign = _textAlign(line.attributes[_alignmentKey] as String?);
    final inlineHtml = _inlineHtml(line.runs);
    if (headingLevel == null && textAlign == null && !wrapLinesInParagraphs) {
      return inlineHtml;
    }
    final tag = headingLevel == null ? 'p' : 'h${headingLevel + 1}';
    final style = textAlign == null ? '' : ' style="text-align: $textAlign;"';
    return '<$tag$style>$inlineHtml</$tag>';
  }

  String? _textAlign(String? alignment) {
    if (alignment == NotusAttribute.center.value) return 'center';
    if (alignment == NotusAttribute.end.value) return 'right';
    if (alignment == NotusAttribute.justify.value) return 'justify';
    return null;
  }

  /// Opens tags outermost first so that runs sharing styles share tags.
  String _inlineHtml(List<_Run> runs) {
    final buffer = StringBuffer();
    final openStyles = <MapEntry<String, dynamic>>[];
    void closeStylesFrom(int index) {
      for (int i = openStyles.length - 1; i >= index; i--) {
        buffer.write(_inlineCloseTag(openStyles[i].key));
      }
      openStyles.removeRange(index, openStyles.length);
    }

    for (final run in runs) {
      final styles = _inlineKeysOutermostFirst
          .where((key) => run.attributes[key] != null)
          .map((key) => MapEntry<String, dynamic>(key, run.attributes[key]))
          .toList();
      int sharedCount = 0;
      while (sharedCount < openStyles.length &&
          sharedCount < styles.length &&
          openStyles[sharedCount].key == styles[sharedCount].key &&
          openStyles[sharedCount].value == styles[sharedCount].value) {
        sharedCount++;
      }
      closeStylesFrom(sharedCount);
      for (final style in styles.skip(sharedCount)) {
        buffer.write(_inlineOpenTag(style));
        openStyles.add(style);
      }
      buffer.write(_textEscape.convert(run.text));
    }
    closeStylesFrom(0);
    return buffer.toString();
  }

  String _inlineOpenTag(MapEntry<String, dynamic> style) {
    if (style.key == _linkKey) {
      final href = _attributeEscape.convert(style.value as String);
      return '<a target="_blank" rel="noopener noreferrer nofollow" '
          'href="$href">';
    }
    if (style.key == _colorKey) {
      final color = style.value as int;
      final red = color >> 16 & 0xFF;
      final green = color >> 8 & 0xFF;
      final blue = color & 0xFF;
      return '<span style="color: rgb($red, $green, $blue);">';
    }
    return '<${_inlineTag(style.key)}>';
  }

  String _inlineCloseTag(String key) {
    if (key == _linkKey) return '</a>';
    if (key == _colorKey) return '</span>';
    return '</${_inlineTag(key)}>';
  }

  String _inlineTag(String key) {
    if (key == NotusAttribute.bold.key) return 'strong';
    if (key == NotusAttribute.italic.key) return 'em';
    return key;
  }
}

class _Line {
  _Line(this.runs, this.attributes);

  final List<_Run> runs;
  final Map<String, dynamic> attributes;

  bool get isEmptyPlainLine => runs.isEmpty && attributes.isEmpty;
}

class _Run {
  _Run(this.text, this.attributes);

  final String text;
  final Map<String, dynamic> attributes;
}
