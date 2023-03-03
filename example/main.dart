import 'package:notus_format/notus_format.dart';

void main() {
  final doc = NotusDocument.fromHtml('''
Sdasdf asdfasdf <b>asdf asdfas</b> gsdf g <i>fdgdfsg sdfg</i>
<ol>
<li>One</li>
<li>Two</li>
<li>Three</li>
</ol>
<ul>
<li>Point 1</li>
<li>Point 2</li>
</ul>
<pre>Some code
Sample</pre>
<blockquote>This is quote boys xDD asd awqed asd</blockquote>
<a href="Www.google.com" target=“_blank”>Www.google.com</a>
<a href="google.com">Google</a>
  ''');
  print("KURWA");
  print(doc.toDelta());
  // Listen to all changes applied to this document.
  doc.changes.listen((change) {
    print(change);
  });

  // Modify this document with insert, delete and format operations
  doc.insert(
      0, 'Notus package provides rich text document model for Zefyr editor');
  doc.format(0, 5, NotusAttribute.bold); // Makes first word bold.
  doc.format(0, 0, NotusAttribute.h1); // Makes first line a heading.
  doc.delete(23, 10); // Deletes "rich text " segment.

  // Collects style attributes at 1 character in this document.
  doc.collectStyle(1, 0); // returned style would include "bold" and "h1".

  // Dispose resources allocated by this document, e.g. closes "changes" stream.
  // After document is closed it cannot be modified.
  doc.close();
}
