import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;

import 'package:braim/services/article_extractor.dart';

String _para(int i) =>
    '<p>Paragraph $i of the article body, with several clauses, some '
    'commas, and enough length to score as real prose for the reader.</p>';

void main() {
  test('extracts the article body and skips page chrome', () {
    final doc = html_parser.parse('''
      <html><body>
        <nav><a href="/">Home</a><a href="/about">About</a></nav>
        <header><h1>Site name</h1></header>
        <div class="sidebar"><p>Trending: ten links you must click today, now, immediately, please.</p></div>
        <main>
          <article>
            <h1>The History of Koalas</h1>
            ${List.generate(8, _para).join()}
            <h2>Habitat</h2>
            <ul><li>Eucalyptus forests along the eastern coast of Australia</li></ul>
            <blockquote>They sleep up to twenty hours a day, which is honestly aspirational.</blockquote>
          </article>
        </main>
        <footer><p>Copyright 2026. All rights reserved. Privacy. Terms. Cookies galore.</p></footer>
      </body></html>
    ''');

    final text = ArticleExtractor.extract(doc);
    expect(text, isNotNull);
    expect(text, contains('The History of Koalas'));
    expect(text, contains('Paragraph 1 of the article body'));
    expect(text, contains('Paragraph 7 of the article body'));
    expect(text, contains('Habitat'));
    expect(text, contains('• Eucalyptus forests'));
    expect(text, contains('aspirational'));
    // Chrome never leaks in.
    expect(text, isNot(contains('Trending')));
    expect(text, isNot(contains('Copyright')));
  });

  test('returns null for pages that are not articles', () {
    final doc = html_parser.parse('''
      <html><body>
        <nav><a href="/">Home</a></nav>
        <div><p>Add to cart.</p><p>Free shipping on orders over 50.</p></div>
      </body></html>
    ''');
    expect(ArticleExtractor.extract(doc), isNull);
  });
}
