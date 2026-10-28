// Copyright (c) 2018, the Zefyr project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'package:notus_format/convert.dart';
import 'package:notus_format/notus_format.dart';
import 'package:quill_format/quill_format.dart';
import 'package:test/test.dart';

void main() {
  final bold = NotusAttribute.bold.toJson();
  final italic = NotusAttribute.italic.toJson();
  final underline = NotusAttribute.underline.toJson();
  final strikethrough = NotusAttribute.strikethrough.toJson();

  group('$NotusHTMLCodec.decode', () {
    test('decodes empty html to a single empty line', () {
      expect(notusHTML.decode(''), Delta()..insert('\n'));
    });

    test('decodes plain text lines', () {
      expect(notusHTML.decode('foo\nbar'), Delta()..insert('foo\nbar\n'));
    });

    test('decodes paragraphs with inline styles', () {
      final html =
          '<p><strong>b</strong><em>i</em><u>u</u><s>s</s></p><p></p><p>end</p>';

      final expected = Delta()
        ..insert('b', bold)
        ..insert('i', italic)
        ..insert('u', underline)
        ..insert('s', strikethrough)
        ..insert('\n\nend\n');
      expect(notusHTML.decode(html), expected);
    });

    test('decodes web headings h2, h3, h4 as levels 1, 2, 3 with alignment',
        () {
      final html = '<h2 style="text-align: left;">large</h2>'
          '<h3 style="text-align: center;">medium</h3>'
          '<h4 style="text-align: right;">small</h4>'
          '<p style="text-align: justify;">text</p>';

      final expected = Delta()
        ..insert('large')
        ..insert('\n', {'heading': 1})
        ..insert('medium')
        ..insert('\n', {'heading': 2, 'alignment': 'center'})
        ..insert('small')
        ..insert('\n', {'heading': 3, 'alignment': 'end'})
        ..insert('text')
        ..insert('\n', {'alignment': 'justify'});
      expect(notusHTML.decode(html), expected);
    });

    test('decodes span colors and drops the default text color', () {
      final html = '<p><span style="color: rgb(46, 46, 46);">default</span>'
          '<span style="color: rgb(231, 57, 219);">pink</span></p>';

      final expected = Delta()
        ..insert('default')
        ..insert('pink', {'color': 0xFFE739DB})
        ..insert('\n');
      expect(notusHTML.decode(html), expected);
    });

    test('decodes lists of paragraphs and quoted headings', () {
      final html = '<ul><li><p>a</p></li><li><p>b</p></li></ul>'
          '<ol><li>c</li></ol>'
          '<blockquote><h2>quote</h2></blockquote>';

      final expected = Delta()
        ..insert('a')
        ..insert('\n', {'block': 'ul'})
        ..insert('b')
        ..insert('\n', {'block': 'ul'})
        ..insert('c')
        ..insert('\n', {'block': 'ol'})
        ..insert('quote')
        ..insert('\n', {'heading': 1, 'block': 'quote'});
      expect(notusHTML.decode(html), expected);
    });

    test('decodes quill alignment classes and empty headings', () {
      final html = '<p class="ql-align-center">center</p><h1><br></h1>'
          '<p class="ql-align-right">right</p>';

      final expected = Delta()
        ..insert('center')
        ..insert('\n', {'alignment': 'center'})
        ..insert('\nright')
        ..insert('\n', {'alignment': 'end'});
      expect(notusHTML.decode(html), expected);
    });

    test('decodes link href and ignores other link attributes', () {
      final html = '<p><a target="_blank" rel="noopener" href="https://a.com">'
          'link</a></p>';

      final expected = Delta()
        ..insert('link', {'a': 'https://a.com'})
        ..insert('\n');
      expect(notusHTML.decode(html), expected);
    });

    test('decodes unsupported tags as their text content', () {
      final html = '<p>no <span data-name="laughing" class="emoji">😆</span>'
          ' <code>end</code></p>';

      expect(notusHTML.decode(html), Delta()..insert('no 😆 end\n'));
    });

    test('decodes html previously saved by the app', () {
      final html =
          '<p>Hi <strong>you</strong>\n<ul><li>a</li><li>b</li></ul>\nbye</p>';

      final expected = Delta()
        ..insert('Hi ')
        ..insert('you', bold)
        ..insert('\na')
        ..insert('\n', {'block': 'ul'})
        ..insert('b')
        ..insert('\n', {'block': 'ul'})
        ..insert('bye\n');
      expect(notusHTML.decode(html), expected);
    });
  });

  group('$NotusHTMLCodec.encode', () {
    test('encodes lines as paragraphs with inline styles', () {
      final delta = Delta()
        ..insert('b', bold)
        ..insert('i', italic)
        ..insert('u', underline)
        ..insert('s', strikethrough)
        ..insert('\n\nend\n\n\n');

      expect(
        notusHTML.encode(delta),
        '<p><strong>b</strong><em>i</em><u>u</u><s>s</s></p><p></p><p>end</p>',
      );
    });

    test('encodes empty document as a single empty paragraph', () {
      expect(notusHTML.encode(Delta()..insert('\n\n')), '<p></p>');
    });

    test('encodes headings as web h2, h3, h4 with alignment', () {
      final delta = Delta()
        ..insert('large')
        ..insert('\n', {'heading': 1, 'alignment': 'center'})
        ..insert('medium')
        ..insert('\n', {'heading': 2})
        ..insert('small')
        ..insert('\n', {'heading': 3, 'alignment': 'end'});

      expect(
        notusHTML.encode(delta),
        '<h2 style="text-align: center;">large</h2>'
        '<h3>medium</h3>'
        '<h4 style="text-align: right;">small</h4>',
      );
    });

    test('encodes consecutive block lines in one list or quote', () {
      final delta = Delta()
        ..insert('a')
        ..insert('\n', {'block': 'ul'})
        ..insert('b')
        ..insert('\n', {'block': 'ul'})
        ..insert('c')
        ..insert('\n', {'block': 'ol'})
        ..insert('quote')
        ..insert('\n', {'block': 'quote'});

      expect(
        notusHTML.encode(delta),
        '<ul><li><p>a</p></li><li><p>b</p></li></ul>'
        '<ol><li><p>c</p></li></ol>'
        '<blockquote><p>quote</p></blockquote>',
      );
    });

    test('encodes plain lines without paragraphs when disabled', () {
      final delta = Delta()
        ..insert('Hi ')
        ..insert('you', bold)
        ..insert('\n\ncentered')
        ..insert('\n', {'alignment': 'center'})
        ..insert('a')
        ..insert('\n', {'block': 'ul'})
        ..insert('b')
        ..insert('\n', {'block': 'ul'})
        ..insert('bye\n');

      expect(
        NotusHTMLCodec(wrapLinesInParagraphs: false).encode(delta),
        'Hi <strong>you</strong>\n\n<p style="text-align: center;">centered</p>'
        '\n<ul><li>a</li><li>b</li></ul>\nbye',
      );
    });

    test('escapes text and link urls', () {
      final delta = Delta()
        ..insert('a < b & c', {'a': 'https://a.com?x="1"&y=2'})
        ..insert('\n');

      expect(
        notusHTML.encode(delta),
        '<p><a target="_blank" rel="noopener noreferrer nofollow" '
        'href="https://a.com?x=&quot;1&quot;&amp;y=2">a &lt; b &amp; c</a></p>',
      );
    });
  });

  test('round trips html from the web editor', () {
    expect(notusHTML.encode(notusHTML.decode(webHtml)), expectedWebHtml);
  });
}

const webHtml =
    '<h2 style="text-align: left;"><span style="color: rgb(46, 46, 46);"><strong>test h1 bold</strong></span></h2><h2 style="text-align: left;"><span style="color: rgb(46, 46, 46);">test h1 <em>i</em></span></h2><h2 style="text-align: left;"><span style="color: rgb(46, 46, 46);"><em><u>test h1 underline</u></em></span></h2><blockquote><h2 style="text-align: left;"><span style="color: rgb(46, 46, 46);"><em>test h1 quote</em></span></h2></blockquote><p style="text-align: left;"></p><h2 style="text-align: left;"><span style="color: rgb(231, 57, 219);">Test h1 color</span></h2><p style="text-align: left;"></p><p style="text-align: left;"><span style="color: rgb(46, 46, 46);"><strong>CONTRACTS</strong> TO JEST</span></p><ul><li><p style="text-align: left;"><span style="color: rgb(46, 46, 46);">123</span></p></li><li><p style="text-align: left;"><span style="color: rgb(46, 46, 46);">fadsfsaf</span></p></li></ul><p style="text-align: right;"><span style="color: rgb(242, 0, 0);">RIGHT</span></p><p style="text-align: center;"><span style="color: rgb(46, 46, 46);">CENTER</span></p><h3 style="text-align: left;"><span style="color: rgb(46, 46, 46);">headline medium</span></h3><h4 style="text-align: left;"><span style="color: rgb(46, 46, 46);">headline small</span></h4><ol><li><p style="text-align: left;"><span style="color: rgb(46, 46, 46);">sadfads</span></p></li></ol><p style="text-align: left;"><span style="color: rgb(46, 46, 46);"><strong><em>link </em></strong></span><a target="_blank" rel="noopener noreferrer nofollow" href="https://google.com"><span style="color: rgb(46, 46, 46);"><strong><em>google</em></strong></span></a><span style="color: rgb(46, 46, 46);"><strong><em> </em></strong></span></p><p style="text-align: left;"><span style="color: rgb(46, 46, 46);"><strong><em>no </em></strong></span><span data-name="laughing" class="emoji" data-type="emoji">😆</span></p><p style="text-align: left;">[Position title]<span style="color: rgb(46, 46, 46);"> </span>[Unit address]</p>';

const expectedWebHtml =
    '<h2><strong>test h1 bold</strong></h2><h2>test h1 <em>i</em></h2><h2><em><u>test h1 underline</u></em></h2><blockquote><h2><em>test h1 quote</em></h2></blockquote><p></p><h2><span style="color: rgb(231, 57, 219);">Test h1 color</span></h2><p></p><p><strong>CONTRACTS</strong> TO JEST</p><ul><li><p>123</p></li><li><p>fadsfsaf</p></li></ul><p style="text-align: right;"><span style="color: rgb(242, 0, 0);">RIGHT</span></p><p style="text-align: center;">CENTER</p><h3>headline medium</h3><h4>headline small</h4><ol><li><p>sadfads</p></li></ol><p><strong><em>link </em></strong><a target="_blank" rel="noopener noreferrer nofollow" href="https://google.com"><strong><em>google</em></strong></a><strong><em> </em></strong></p><p><strong><em>no </em></strong>😆</p><p>[Position title] [Unit address]</p>';
