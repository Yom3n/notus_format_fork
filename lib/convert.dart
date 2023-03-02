/// Provides codecs to convert Notus documents to other formats.
library notus.convert;

import 'package:notus_format/src/convert/html.dart';

import 'src/convert/markdown.dart';

export 'src/convert/markdown.dart';

/// Markdown codec for Notus documents.
const NotusMarkdownCodec notusMarkdown = NotusMarkdownCodec();

const NotusHTMLCodec notusHTML = NotusHTMLCodec();
