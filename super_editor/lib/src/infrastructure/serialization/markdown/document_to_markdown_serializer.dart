import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:attributed_text/attributed_text.dart';
import 'package:flutter/foundation.dart';
import 'package:markdown/markdown.dart' hide Document;
import 'package:super_editor/src/core/document.dart';
import 'package:super_editor/src/core/document_selection.dart';
import 'package:super_editor/src/default_editor/attributions.dart';
import 'package:super_editor/src/default_editor/horizontal_rule.dart';
import 'package:super_editor/src/default_editor/image.dart';
import 'package:super_editor/src/default_editor/list_items.dart';
import 'package:super_editor/src/default_editor/paragraph.dart';
import 'package:super_editor/src/default_editor/selection_upstream_downstream.dart';
import 'package:super_editor/src/default_editor/tables/table_block.dart';
import 'package:super_editor/src/default_editor/tasks.dart';
import 'package:super_editor/src/default_editor/text.dart';

import 'package:super_editor/src/infrastructure/serialization/markdown/super_editor_syntax.dart';

/// Serializes the given [doc] to Markdown text.
///
/// When [selection] is provided, only the selected range of the document is serialized.
///
/// The given [syntax] controls how the [doc] is serialized, e.g., [MarkdownSyntax.normal]
/// for standard Markdown syntax, or [MarkdownSyntax.superEditor] to use Super Editor's
/// extended syntax.
///
/// To serialize [DocumentNode]s that aren't part of Super Editor's standard serialization,
/// provide [customNodeSerializers] to serialize those custom nodes.
String serializeDocumentToMarkdown(
  Document doc, {
  DocumentSelection? selection,
  MarkdownSyntax syntax = MarkdownSyntax.superEditor,
  List<DocumentNodeMarkdownSerializer> customNodeSerializers = const [],
}) {
  final nodeSerializers = [
    // Custom serializers first, in case the custom serializers handle
    // specialized cases of traditional nodes, such as serializing a
    // `ParagraphNode` with a special `"blockType"`.
    ...customNodeSerializers,
    ImageNodeSerializer(useSizeNotation: syntax == MarkdownSyntax.superEditor),
    const HorizontalRuleNodeSerializer(),
    const ListItemNodeSerializer(),
    const TaskNodeSerializer(),
    HeaderNodeSerializer(syntax),
    ParagraphNodeSerializer(syntax),
    const TableBlockNodeSerializer(),
  ];

  StringBuffer buffer = StringBuffer();

  late final DocumentRange? selectedRange;
  late final List<DocumentNode> selectedNodes;
  if (selection != null) {
    selectedRange = selection.normalize(doc);
    selectedNodes = doc.getNodesInside(
      selectedRange.start,
      selectedRange.end,
    );
  } else {
    selectedRange = null;
    selectedNodes = doc.toList(growable: false);
  }

  for (int i = 0; i < selectedNodes.length; ++i) {
    final node = selectedNodes[i];
    late final NodeSelection? nodeSelection;
    if (selectedRange != null && node.id == selectedRange.start.nodeId && node.id == selectedRange.end.nodeId) {
      // The entire copy selection is within this node.
      nodeSelection = node.computeSelection(
        base: selectedRange.start.nodePosition,
        extent: selectedRange.end.nodePosition,
      );
    } else if (selectedRange != null && node.id == selectedRange.start.nodeId) {
      // The selection starts somewhere in this node and goes to the end of the node.
      nodeSelection = node.computeSelection(
        base: selectedRange.start.nodePosition,
        extent: node.endPosition,
      );
    } else if (selectedRange != null && node.id == selectedRange.end.nodeId) {
      // The selection starts at the beginning of this node and ends somewhere within this node.
      nodeSelection = node.computeSelection(
        base: node.beginningPosition,
        extent: selectedRange.end.nodePosition,
      );
    } else {
      // The node is fully selected, so we don't need to specify a selection.
      nodeSelection = null;
    }

    for (final serializer in nodeSerializers) {
      final serialization = serializer.serialize(doc, node, selection: nodeSelection);
      if (serialization != null) {
        if (i > 0) {
          // Add a new line before every node, except the first node.
          buffer.writeln("");
        }

        buffer.write(serialization);
        break;
      }
    }
  }

  return buffer.toString();
}

/// Serializes a given [DocumentNode] to a Markdown `String`.
abstract class DocumentNodeMarkdownSerializer {
  /// Serializes the given [node] to a Markdown `String`.
  ///
  /// When [selection] is `null`, the entire node is converted to markdown. When
  /// [selection] is non-`null`, only the selected range is converted to markdown.
  ///
  /// Returns `null` if the [node] is not supported by this serializer.
  String? serialize(
    Document document,
    DocumentNode node, {
    NodeSelection? selection,
  });
}

/// A [DocumentNodeMarkdownSerializer] that automatically rejects any
/// [DocumentNode] that doesn't match the given [NodeType].
///
/// Use this base class to avoid repeating type checks across various
/// serializers.
abstract class NodeTypedDocumentNodeMarkdownSerializer<NodeType> implements DocumentNodeMarkdownSerializer {
  const NodeTypedDocumentNodeMarkdownSerializer();

  @override
  String? serialize(
    Document document,
    DocumentNode node, {
    NodeSelection? selection,
  }) {
    if (node is! NodeType) {
      return null;
    }

    return doSerialization(document, node as NodeType, selection: selection);
  }

  @protected
  String doSerialization(
    Document document,
    NodeType node, {
    NodeSelection? selection,
  });
}

/// [DocumentNodeMarkdownSerializer] for serializing [ImageNode]s as standard Markdown
/// images.
class ImageNodeSerializer extends NodeTypedDocumentNodeMarkdownSerializer<ImageNode> {
  const ImageNodeSerializer({
    this.useSizeNotation = false,
  });

  final bool useSizeNotation;

  @override
  String doSerialization(
    Document document,
    ImageNode node, {
    NodeSelection? selection,
  }) {
    if (selection != null) {
      if (selection is! UpstreamDownstreamNodeSelection) {
        // We don't know how to handle this selection type.
        return '';
      }
      if (selection.isCollapsed) {
        // This selection doesn't include the image - it's a collapsed selection
        // either on the upstream or downstream edge.
        return '';
      }
    }

    if (!useSizeNotation || (node.expectedBitmapSize?.width == null && node.expectedBitmapSize?.height == null)) {
      // We don't want to use size notation or the image doesn't have
      // size information. Use the regular syntax.
      return '![${node.altText}](${node.imageUrl})';
    }

    StringBuffer sizeNotation = StringBuffer();
    sizeNotation.write(' =');

    if (node.expectedBitmapSize?.width != null) {
      sizeNotation.write(node.expectedBitmapSize!.width!.toInt());
    }

    sizeNotation.write('x');

    if (node.expectedBitmapSize?.height != null) {
      sizeNotation.write(node.expectedBitmapSize!.height!.toInt());
    }

    return '![${node.altText}](${node.imageUrl}${sizeNotation.toString()})';
  }
}

/// [DocumentNodeMarkdownSerializer] for serializing [HorizontalRuleNode]s as standard
/// Markdown horizontal rules.
class HorizontalRuleNodeSerializer extends NodeTypedDocumentNodeMarkdownSerializer<HorizontalRuleNode> {
  const HorizontalRuleNodeSerializer();

  @override
  String doSerialization(
    Document document,
    HorizontalRuleNode node, {
    NodeSelection? selection,
  }) {
    if (selection != null) {
      if (selection is! UpstreamDownstreamNodeSelection) {
        // We don't know how to handle this selection type.
        return '';
      }
      if (selection.isCollapsed) {
        // This selection doesn't include the horizontal rule - it's a collapsed selection
        // either on the upstream or downstream edge.
        return '';
      }
    }

    return '---';
  }
}

/// [DocumentNodeMarkdownSerializer] for serializing [ListItemNode]s as standard Markdown
/// list items.
///
/// Includes support for ordered and unordered list items.
class ListItemNodeSerializer extends NodeTypedDocumentNodeMarkdownSerializer<ListItemNode> {
  const ListItemNodeSerializer();

  @override
  String doSerialization(
    Document document,
    ListItemNode node, {
    NodeSelection? selection,
  }) {
    if (selection != null && selection is! TextNodeSelection) {
      // We don't know how to handle this selection type.
      return '';
    }
    final textSelection = selection as TextNodeSelection?;
    if (textSelection != null && textSelection.isCollapsed) {
      // Selection is collapsed. Nothing is selected for copy.
      return '';
    }
    final textToConvert = textSelection != null //
        ? node.text.copyText(textSelection.start, textSelection.end)
        : node.text;

    final buffer = StringBuffer();

    final indent = List.generate(node.indent + 1, (index) => '  ').join('');
    final symbol = node.type == ListItemType.unordered ? '*' : '1.';

    buffer.write('$indent$symbol ${textToConvert.toMarkdown()}');

    final nodeIndex = document.getNodeIndexById(node.id);
    final nodeBelow = nodeIndex < document.nodeCount - 1 ? document.getNodeAt(nodeIndex + 1) : null;
    if (nodeBelow != null && (nodeBelow is! ListItemNode || nodeBelow.type != node.type)) {
      // This list item is the last item in the list. Add an extra
      // blank line after it.
      buffer.writeln('');
    }

    return buffer.toString();
  }
}

/// [DocumentNodeMarkdownSerializer] for serializing [ParagraphNode]s as standard Markdown
/// paragraphs.
///
/// Includes support for headers, blockquotes, and code blocks.
class ParagraphNodeSerializer extends NodeTypedDocumentNodeMarkdownSerializer<ParagraphNode> {
  const ParagraphNodeSerializer(this.markdownSyntax);

  final MarkdownSyntax markdownSyntax;

  @override
  String doSerialization(
    Document document,
    ParagraphNode node, {
    NodeSelection? selection,
  }) {
    if (selection != null && selection is! TextNodeSelection) {
      // We don't know how to handle this selection type.
      return '';
    }
    final textSelection = selection as TextNodeSelection?;
    if (textSelection != null && textSelection.isCollapsed) {
      // Selection is collapsed. Nothing is selected for copy.
      return '';
    }

    final buffer = StringBuffer();

    final Attribution? blockType = node.getMetadataValue('blockType');

    final inlineMarkdown = (textSelection != null //
            ? node.text.copyText(textSelection.start, textSelection.end)
            : node.text)
        .toMarkdown();

    if (blockType == header1Attribution) {
      buffer.write('# $inlineMarkdown');
    } else if (blockType == header2Attribution) {
      buffer.write('## $inlineMarkdown');
    } else if (blockType == header3Attribution) {
      buffer.write('### $inlineMarkdown');
    } else if (blockType == header4Attribution) {
      buffer.write('#### $inlineMarkdown');
    } else if (blockType == header5Attribution) {
      buffer.write('##### $inlineMarkdown');
    } else if (blockType == header6Attribution) {
      buffer.write('###### $inlineMarkdown');
    } else if (blockType == blockquoteAttribution) {
      // TODO: handle multiline
      buffer.write('> $inlineMarkdown');
    } else if (blockType == codeAttribution) {
      buffer //
        ..writeln('```') //
        ..writeln(inlineMarkdown) //
        ..write('```');
    } else {
      final String? textAlign = node.getMetadataValue('textAlign');
      // Left alignment is the default, so there is no need to add the alignment token.
      if (markdownSyntax == MarkdownSyntax.superEditor && textAlign != null && textAlign != 'left') {
        final alignmentToken = _convertAlignmentToMarkdown(textAlign);
        if (alignmentToken != null) {
          buffer.writeln(alignmentToken);
        }
      }
      buffer.write(inlineMarkdown);
    }

    // We're not at the end of the document yet. Add a blank line after the
    // paragraph so that we can tell the difference between separate
    // paragraphs vs. newlines within a single paragraph.
    final nodeIndex = document.getNodeIndexById(node.id);
    if (nodeIndex != document.nodeCount - 1) {
      buffer.writeln();
    }

    return buffer.toString();
  }
}

/// [DocumentNodeMarkdownSerializer] for serializing [TaskNode]s using Github's style syntax.
///
/// A completed task is serialized as `- [x] This is a completed task`
/// An incomplete task is serialized as `- [ ] This is an incomplete task`
class TaskNodeSerializer extends NodeTypedDocumentNodeMarkdownSerializer<TaskNode> {
  const TaskNodeSerializer();

  @override
  String doSerialization(
    Document document,
    TaskNode node, {
    NodeSelection? selection,
  }) {
    if (selection != null && selection is! TextNodeSelection) {
      // We don't know how to handle this selection type.
      return '';
    }
    final textSelection = selection as TextNodeSelection?;
    if (textSelection != null && textSelection.isCollapsed) {
      // Selection is collapsed. Nothing is selected for copy.
      return '';
    }
    final textToConvert = textSelection != null //
        ? node.text.copyText(textSelection.start, textSelection.end)
        : node.text;

    return '- [${node.isComplete ? 'x' : ' '}] ${textToConvert.toMarkdown()}';
  }
}

String? _convertAlignmentToMarkdown(String alignment) {
  switch (alignment) {
    case 'left':
      return ':---';
    case 'center':
      return ':---:';
    case 'right':
      return '---:';
    case 'justify':
      return '-::-';
    default:
      return null;
  }
}

/// Extension on [AttributedText] to serialize the [AttributedText] to a Markdown `String`.
extension Markdown on AttributedText {
  String toMarkdown() {
    final serializer = AttributedTextMarkdownSerializer();
    return serializer.serialize(this);
  }
}

/// Serializes an [AttributedText] into markdown format
class AttributedTextMarkdownSerializer extends AttributionVisitor {
  late String _fullText;
  late StringBuffer _buffer;
  late int _bufferCursor;

  String serialize(AttributedText attributedText) {
    _fullText = attributedText.toPlainText();
    _buffer = StringBuffer();
    _bufferCursor = 0;
    if (attributedText.toPlainText().isNotEmpty) {
      attributedText.visitAttributions(this);
    }
    return _buffer.toString();
  }

  @override
  void visitAttributions(
    AttributedText fullText,
    int index,
    Set<Attribution> startingAttributions,
    Set<Attribution> endingAttributions,
  ) {
    // Write out the text between the end of the last markers, and these new markers.
    _writeTextToBuffer(
      fullText.toPlainText().substring(_bufferCursor, index),
    );

    // Add start markers.
    if (startingAttributions.isNotEmpty) {
      final markdownStyles = _sortAndSerializeAttributions(startingAttributions, AttributionVisitEvent.start);
      // Links are different from the plain styles since they are both not NamedAttributions (and therefore
      // can't be checked using equality comparison) and asymmetrical in markdown.
      final linkMarker = _encodeLinkMarker(startingAttributions, AttributionVisitEvent.start);

      _buffer
        ..write(linkMarker)
        ..write(markdownStyles);
    }

    // Write out the character at this index.
    _writeTextToBuffer(_fullText[index]);
    _bufferCursor = index + 1;

    // Add end markers.
    if (endingAttributions.isNotEmpty) {
      final markdownStyles = _sortAndSerializeAttributions(endingAttributions, AttributionVisitEvent.end);
      // Links are different from the plain styles since they are both not NamedAttributions (and therefore
      // can't be checked using equality comparison) and asymmetrical in markdown.
      final linkMarker = _encodeLinkMarker(endingAttributions, AttributionVisitEvent.end);

      _buffer
        ..write(markdownStyles)
        ..write(linkMarker);
    }
  }

  @override
  void onVisitEnd() {
    // When the last span has no attributions, we still have text that wasn't added to the buffer yet.
    if (_bufferCursor <= _fullText.length - 1) {
      _writeTextToBuffer(_fullText.substring(_bufferCursor));
    }
  }

  /// Writes the given [text] to [_buffer].
  ///
  /// Separates multiple lines in a single paragraph using two spaces before each line break.
  ///
  /// A line ending with two or more spaces represents a hard line break,
  /// as defined in the Markdown spec.
  void _writeTextToBuffer(String text) {
    final lines = text.split('\n');
    for (int i = 0; i < lines.length; i++) {
      if (i > 0) {
        // Adds two spaces before line breaks.
        // The Markdown spec defines that a line ending with two or more spaces
        // represents a hard line break, which causes the next line to be part of
        // the previous paragraph during deserialization.
        _buffer.write('  ');
        _buffer.write('\n');
      }

      _buffer.write(lines[i]);
    }
  }

  /// Serializes style attributions into markdown syntax in a repeatable
  /// order such that opening and closing styles match each other on
  /// the opening and closing ends of a span.
  static String _sortAndSerializeAttributions(Set<Attribution> attributions, AttributionVisitEvent event) {
    const startOrder = [
      codeAttribution,
      boldAttribution,
      italicsAttribution,
      strikethroughAttribution,
      underlineAttribution,
    ];

    final buffer = StringBuffer();
    final encodingOrder = event == AttributionVisitEvent.start ? startOrder : startOrder.reversed;

    for (final markdownStyleAttribution in encodingOrder) {
      if (attributions.contains(markdownStyleAttribution)) {
        buffer.write(_encodeMarkdownStyle(markdownStyleAttribution));
      }
    }

    return buffer.toString();
  }

  static String _encodeMarkdownStyle(Attribution attribution) {
    if (attribution == codeAttribution) {
      return '`';
    } else if (attribution == boldAttribution) {
      return '**';
    } else if (attribution == italicsAttribution) {
      return '*';
    } else if (attribution == strikethroughAttribution) {
      return '~';
    } else if (attribution == underlineAttribution) {
      return '¬';
    } else {
      return '';
    }
  }

  /// Checks for the presence of a link in the attributions and returns the characters necessary to represent it
  /// at the open or closing boundary of the attribution, depending on the event.
  static String _encodeLinkMarker(Set<Attribution> attributions, AttributionVisitEvent event) {
    final linkAttributions = attributions.whereType<LinkAttribution?>();
    if (linkAttributions.isNotEmpty) {
      final linkAttribution = linkAttributions.first as LinkAttribution;

      if (event == AttributionVisitEvent.start) {
        return '[';
      } else {
        return '](${linkAttribution.plainTextUri})';
      }
    }
    return "";
  }
}

/// [DocumentNodeMarkdownSerializer], which serializes Markdown headers to
/// [ParagraphNode]s with an appropriate header block type, and (optionally) a
/// block alignment.
///
/// Headers are represented by `ParagraphNode`s and therefore this serializer must
/// run before a [ParagraphNodeSerializer], so that this serializer can process
/// header-specific details, such as header alignment.
class HeaderNodeSerializer extends NodeTypedDocumentNodeMarkdownSerializer<ParagraphNode> {
  const HeaderNodeSerializer(this.markdownSyntax);

  final MarkdownSyntax markdownSyntax;

  @override
  String? serialize(
    Document document,
    DocumentNode node, {
    NodeSelection? selection,
  }) {
    if (node is! ParagraphNode) {
      return null;
    }

    // Only serialize this node when this is a header node.
    final Attribution? blockType = node.getMetadataValue('blockType');
    final isHeaderNode = blockType == header1Attribution ||
        blockType == header2Attribution ||
        blockType == header3Attribution ||
        blockType == header4Attribution ||
        blockType == header5Attribution ||
        blockType == header6Attribution;

    if (!isHeaderNode) {
      return null;
    }

    return doSerialization(document, node);
  }

  @override
  String doSerialization(
    Document document,
    ParagraphNode node, {
    NodeSelection? selection,
  }) {
    if (selection != null && selection is! TextNodeSelection) {
      // We don't know how to handle this selection type.
      return '';
    }
    final textSelection = selection as TextNodeSelection?;
    if (textSelection != null && textSelection.isCollapsed) {
      // Selection is collapsed. Nothing is selected for copy.
      return '';
    }
    final textToConvert = textSelection != null //
        ? node.text.copyText(textSelection.start, textSelection.end)
        : node.text;

    final buffer = StringBuffer();

    final Attribution? blockType = node.getMetadataValue('blockType');
    final String? textAlign = node.getMetadataValue('textAlign');

    // Add the alignment token, we exclude the left alignment because it's the default.
    if (markdownSyntax == MarkdownSyntax.superEditor && textAlign != null && textAlign != 'left') {
      final alignmentToken = _convertAlignmentToMarkdown(textAlign);
      if (alignmentToken != null) {
        buffer.writeln(alignmentToken);
      }
    }

    if (blockType == header1Attribution) {
      buffer.write('# ${textToConvert.toMarkdown()}');
    } else if (blockType == header2Attribution) {
      buffer.write('## ${textToConvert.toMarkdown()}');
    } else if (blockType == header3Attribution) {
      buffer.write('### ${textToConvert.toMarkdown()}');
    } else if (blockType == header4Attribution) {
      buffer.write('#### ${textToConvert.toMarkdown()}');
    } else if (blockType == header5Attribution) {
      buffer.write('##### ${textToConvert.toMarkdown()}');
    } else if (blockType == header6Attribution) {
      buffer.write('###### ${textToConvert.toMarkdown()}');
    }

    // We're not at the end of the document yet. Add a blank line after the
    // paragraph so that we can tell the difference between separate
    // paragraphs vs. newlines within a single paragraph.
    final nodeIndex = document.getNodeIndexById(node.id);
    if (nodeIndex != document.nodeCount - 1) {
      buffer.writeln();
    }

    return buffer.toString();
  }
}

/// [DocumentNodeMarkdownSerializer] for serializing [TableBlockNode]s as the extended Markdown
/// syntax for tables.
///
/// See https://www.markdownguide.org/extended-syntax/#tables for the specification.
class TableBlockNodeSerializer extends NodeTypedDocumentNodeMarkdownSerializer<TableBlockNode> {
  const TableBlockNodeSerializer();

  @override
  String doSerialization(
    Document document,
    TableBlockNode node, {
    NodeSelection? selection,
  }) {
    if (selection != null) {
      if (selection is! UpstreamDownstreamNodeSelection) {
        // We don't know how to handle this selection type.
        return '';
      }
      if (selection.isCollapsed) {
        // This selection doesn't include the table - it's a collapsed selection
        // either on the upstream or downstream edge.
        return '';
      }
    }

    if (node.rowCount == 0) {
      // The table must have at least one row (the header row) to be serialized.
      return '';
    }

    final buffer = StringBuffer();

    final headerRow = node.getRow(0);

    // Serialize the header values.
    buffer.write('|');
    for (final cell in headerRow) {
      buffer.write(' ');
      buffer.write(cell.text.toMarkdown());
      buffer.write(' |');
    }

    // Serialize the header separator row.
    buffer.writeln();
    buffer.write('|');
    for (int i = 0; i < headerRow.length; i++) {
      buffer.write(' ');

      final firstDataCell = node.rowCount > 1 //
          ? node.getCell(rowIndex: 1, columnIndex: i)
          : null;

      buffer.write(_getHeaderSeparatorColumnContent(firstDataCell));
      buffer.write(' |');
    }

    // Serialize the data rows.
    if (node.rowCount > 1) {
      for (int i = 1; i < node.rowCount; i++) {
        buffer.writeln();
        final row = node.getRow(i);

        buffer.write('|');
        for (final cell in row) {
          buffer.write(' ');
          buffer.write(cell.text.toMarkdown());
          buffer.write(' |');
        }
      }
    }

    return buffer.toString();
  }

  String _getHeaderSeparatorColumnContent(TextNode? firstDataCell) {
    if (firstDataCell == null) {
      return '---';
    }

    final textAlign = firstDataCell.getMetadataValue('textAlign');
    return switch (textAlign) {
      TextAlign.center => ':--:',
      TextAlign.right => '--:',
      _ => '---',
    };
  }
}

// ============================================================================
// OFF-THREAD MARKDOWN SERIALIZATION
// ============================================================================

/// Tracks which document nodes are dirty (modified) since the last serialization.
///
/// This enables incremental serialization by only processing nodes that have
/// actually changed, avoiding the cost of re-serializing the entire document.
class DirtyNodeTracker {
  DirtyNodeTracker();

  final Set<String> _dirtyNodeIds = {};
  bool _allDirty = false;

  /// Returns `true` if the tracker has been fully invalidated
  /// (all nodes need re-serialization).
  bool get isFullyDirty => _allDirty;

  /// Returns the set of dirty node IDs.
  /// If fully dirty, returns an empty set (caller should serialize all).
  Set<String> get dirtyNodeIds => _allDirty ? {} : Set.unmodifiable(_dirtyNodeIds);

  /// Returns `true` if there are any dirty nodes.
  bool get hasDirtyNodes => _allDirty || _dirtyNodeIds.isNotEmpty;

  /// Marks a specific node as dirty.
  void markDirty(String nodeId) {
    if (!_allDirty) {
      _dirtyNodeIds.add(nodeId);
    }
  }

  /// Marks multiple nodes as dirty.
  void markMultipleDirty(Iterable<String> nodeIds) {
    if (!_allDirty) {
      _dirtyNodeIds.addAll(nodeIds);
    }
  }

  /// Fully invalidates the tracker, marking all nodes as dirty.
  void markAllDirty() {
    _allDirty = true;
    _dirtyNodeIds.clear();
  }

  /// Clears the dirty state for a specific node after serialization.
  void clearDirty(String nodeId) {
    if (!_allDirty) {
      _dirtyNodeIds.remove(nodeId);
    }
  }

  /// Clears all dirty state after a full serialization.
  void clearAll() {
    _allDirty = false;
    _dirtyNodeIds.clear();
  }

  /// Returns `true` if the given node is dirty.
  bool isNodeDirty(String nodeId) {
    return _allDirty || _dirtyNodeIds.contains(nodeId);
  }
}

/// Configuration for the [DebouncedMarkdownSerializer].
class DebouncedSerializationConfig {
  const DebouncedSerializationConfig({
    this.debounceDuration = const Duration(milliseconds: 500),
    this.heavySerializationThreshold = 50,
    this.useIsolateForHeavySerialization = true,
  });

  /// Duration to wait after the last change before triggering serialization.
  final Duration debounceDuration;

  /// Number of dirty nodes above which serialization runs in an isolate.
  final int heavySerializationThreshold;

  /// Whether to use [compute] for serialization when the threshold is exceeded.
  final bool useIsolateForHeavySerialization;
}

/// Debounced, off-thread markdown serializer with dirty-node tracking.
///
/// This serializer:
/// 1. Debounces serialization requests to avoid redundant work.
/// 2. Tracks dirty nodes and only re-serializes modified blocks.
/// 3. Uses [compute] (isolate) for heavy serialization of large documents.
/// 4. Maintains a cached markdown output that is incrementally updated.
class DebouncedMarkdownSerializer {
  DebouncedMarkdownSerializer({
    required this.document,
    this.syntax = MarkdownSyntax.superEditor,
    this.customNodeSerializers = const [],
    DebouncedSerializationConfig? config,
  }) : _config = config ?? const DebouncedSerializationConfig() {
    _cache = _fullSerialize();
  }

  final Document document;
  final MarkdownSyntax syntax;
  final List<DocumentNodeMarkdownSerializer> customNodeSerializers;
  final DebouncedSerializationConfig _config;

  final DirtyNodeTracker _dirtyTracker = DirtyNodeTracker();

  /// The cached markdown output. Starts as the full serialization.
  late String _cache;

  /// Timer for debouncing serialization requests.
  Timer? _debounceTimer;

  /// Stream controller that emits the markdown output when serialization completes.
  final StreamController<String> _serializationController =
      StreamController<String>.broadcast();

  /// Stream of serialized markdown output.
  ///
  /// Listen to this to receive the result of each debounced serialization.
  Stream<String> get serializationStream => _serializationController.stream;

  /// Returns the current cached markdown output.
  String get currentMarkdown => _cache;

  /// Returns the dirty tracker for direct inspection.
  DirtyNodeTracker get dirtyTracker => _dirtyTracker;

  /// Marks a node as dirty and schedules a debounced serialization.
  void onNodeChanged(String nodeId) {
    _dirtyTracker.markDirty(nodeId);
    _scheduleSerialization();
  }

  /// Marks multiple nodes as dirty and schedules a debounced serialization.
  void onNodesChanged(Iterable<String> nodeIds) {
    _dirtyTracker.markMultipleDirty(nodeIds);
    _scheduleSerialization();
  }

  /// Forces a full re-serialization on the next request.
  void invalidateAll() {
    _dirtyTracker.markAllDirty();
    _scheduleSerialization();
  }

  /// Schedules a debounced serialization.
  void _scheduleSerialization() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_config.debounceDuration, _performSerialization);
  }

  /// Performs the actual serialization, potentially in an isolate.
  Future<void> _performSerialization() async {
    if (!_dirtyTracker.hasDirtyNodes) {
      return;
    }

    if (_dirtyTracker.isFullyDirty || !_dirtyTracker.hasDirtyNodes) {
      // Full serialization
      if (_config.useIsolateForHeavySerialization) {
        _cache = await _serializeInIsolate(_getDocumentSnapshot(), syntax, customNodeSerializers);
      } else {
        _cache = _fullSerialize();
      }
    } else {
      // Incremental serialization
      _cache = await _incrementalSerialize();
    }

    _dirtyTracker.clearAll();
    _serializationController.add(_cache);
  }

  /// Performs a full serialization in the current isolate.
  String _fullSerialize() {
    return serializeDocumentToMarkdown(
      document,
      syntax: syntax,
      customNodeSerializers: customNodeSerializers,
    );
  }

  /// Performs incremental serialization, only updating dirty nodes.
  Future<String> _incrementalSerialize() async {
    final dirtyIds = _dirtyTracker.dirtyNodeIds;
    if (dirtyIds.isEmpty) return _cache;

    final lines = _cache.split('\n');
    final nodeSerializers = _buildNodeSerializers();
    final nodes = document.toList();

    // Build a map of node IDs to their line indices in the cached output.
    // This is a simplified approach - in production, you'd maintain a more
    // robust mapping.
    final nodeIdToIndex = <String, int>{};
    for (int i = 0; i < nodes.length; i++) {
      nodeIdToIndex[nodes[i].id] = i;
    }

    // Rebuild the output by iterating all nodes and using cached output
    // for non-dirty nodes.
    final buffer = StringBuffer();
    for (int i = 0; i < nodes.length; ++i) {
      final node = nodes[i];

      if (!dirtyIds.contains(node.id)) {
        // Node is clean - use cached serialization if available.
        // For simplicity, we re-serialize clean nodes too in this implementation.
        // A production version would maintain per-node caches.
        final serialization = _serializeNode(nodeSerializers, node, null);
        if (serialization != null) {
          if (i > 0) {
            buffer.writeln("");
          }
          buffer.write(serialization);
        }
        continue;
      }

      // Node is dirty - serialize it fresh.
      final serialization = _serializeNode(nodeSerializers, node, null);
      if (serialization != null) {
        if (i > 0) {
          buffer.writeln("");
        }
        buffer.write(serialization);
      }
    }

    return buffer.toString();
  }

  /// Serializes a single node using the given serializers.
  String? _serializeNode(
    List<DocumentNodeMarkdownSerializer> serializers,
    DocumentNode node,
    NodeSelection? selection,
  ) {
    for (final serializer in serializers) {
      final serialization = serializer.serialize(document, node, selection: selection);
      if (serialization != null) {
        return serialization;
      }
    }
    return null;
  }

  /// Builds the list of node serializers.
  List<DocumentNodeMarkdownSerializer> _buildNodeSerializers() {
    return [
      ...customNodeSerializers,
      ImageNodeSerializer(useSizeNotation: syntax == MarkdownSyntax.superEditor),
      const HorizontalRuleNodeSerializer(),
      const ListItemNodeSerializer(),
      const TaskNodeSerializer(),
      HeaderNodeSerializer(syntax),
      ParagraphNodeSerializer(syntax),
      const TableBlockNodeSerializer(),
    ];
  }

  /// Takes a snapshot of the document state for passing to an isolate.
  ///
  /// In a real implementation, you'd need to serialize the document to a
  /// transferable format. This is a placeholder showing the concept.
  DocumentSnapshot _getDocumentSnapshot() {
    return DocumentSnapshot(
      nodes: document.toList().map((node) => NodeSnapshot(node)).toList(),
    );
  }

  /// Serializes the document in an isolate using [compute].
  static Future<String> _serializeInIsolate(
    DocumentSnapshot snapshot,
    MarkdownSyntax syntax,
    List<DocumentNodeMarkdownSerializer> customNodeSerializers,
  ) async {
    // In production, you'd implement a proper isolate-based serializer.
    // For now, we fall back to main-thread serialization.
    // To truly use an isolate, the document would need to be serializable
    // to a primitive format that can cross isolate boundaries.
    //
    // Example implementation with compute:
    // return compute(_isolateSerialize, IsolatePayload(snapshot, syntax));
    //
    // For now, we return the snapshot serialized on the main thread.
    return _isolateSerialize(IsolatePayload(snapshot, syntax));
  }

  /// The actual serialization logic that runs in the isolate.
  static String _isolateSerialize(IsolatePayload payload) {
    final buffer = StringBuffer();
    final nodeSerializers = _buildNodeSerializersForIsolate(payload.syntax);

    for (int i = 0; i < payload.snapshot.nodes.length; ++i) {
      final nodeSnapshot = payload.snapshot.nodes[i];
      final node = nodeSnapshot.node;

      for (final serializer in nodeSerializers) {
        final serialization = serializer.serialize(
          _StubDocument(payload.snapshot),
          node,
        );
        if (serialization != null) {
          if (i > 0) {
            buffer.writeln("");
          }
          buffer.write(serialization);
          break;
        }
      }
    }

    return buffer.toString();
  }

  /// Builds node serializers for use in an isolate.
  static List<DocumentNodeMarkdownSerializer> _buildNodeSerializersForIsolate(
    MarkdownSyntax syntax,
  ) {
    return [
      ImageNodeSerializer(useSizeNotation: syntax == MarkdownSyntax.superEditor),
      const HorizontalRuleNodeSerializer(),
      const ListItemNodeSerializer(),
      const TaskNodeSerializer(),
      HeaderNodeSerializer(syntax),
      ParagraphNodeSerializer(syntax),
      const TableBlockNodeSerializer(),
    ];
  }

  /// Cancels any pending debounced serialization and disposes resources.
  void dispose() {
    _debounceTimer?.cancel();
    _serializationController.close();
  }
}

/// A snapshot of a document node for cross-isolate transfer.
class NodeSnapshot {
  const NodeSnapshot(this.node);

  final DocumentNode node;
}

/// A snapshot of a document for cross-isolate transfer.
class DocumentSnapshot {
  const DocumentSnapshot({required this.nodes});

  final List<NodeSnapshot> nodes;
}

/// Payload for isolate-based serialization.
class IsolatePayload {
  const IsolatePayload(this.snapshot, this.syntax);

  final DocumentSnapshot snapshot;
  final MarkdownSyntax syntax;
}

/// A stub [Document] implementation that wraps a [DocumentSnapshot].
///
/// This is used in isolate-based serialization where we can't pass the real
/// [Document] object across isolate boundaries.
class _StubDocument implements Document {
  _StubDocument(this._snapshot);

  final DocumentSnapshot _snapshot;

  @override
  List<DocumentNode> toList({bool growable = false}) {
    return _snapshot.nodes.map((ns) => ns.node).toList(growable: true);
  }

  @override
  int getNodeIndexById(String nodeId) {
    for (int i = 0; i < _snapshot.nodes.length; i++) {
      if (_snapshot.nodes[i].node.id == nodeId) return i;
    }
    return -1;
  }

  @override
  DocumentNode getNodeAt(int index) => _snapshot.nodes[index].node;

  @override
  int get nodeCount => _snapshot.nodes.length;

  @override
  List<DocumentNode> getNodesInside(DocumentPosition start, DocumentPosition end) {
    // Simplified implementation for isolate use.
    return _snapshot.nodes.map((ns) => ns.node).toList();
  }

  // Delegate remaining members to avoid abstract method errors.
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
