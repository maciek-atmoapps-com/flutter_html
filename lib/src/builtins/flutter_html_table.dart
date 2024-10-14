library flutter_html_table;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_layout_grid/flutter_layout_grid.dart';

/// [TableHtmlExtension] adds support for the <table> element to the flutter_html library.
/// <tr>, <tbody>, <tfoot>, <thead>, <th>, <td>, <col>, and <colgroup> are also
/// supported.
///
/// Currently, nested tables are not supported.
///
///
final RegExp _regExp = RegExp(r'[\w/\(\)]+');

class TableHtmlExtension extends HtmlExtension {
  const TableHtmlExtension();

  @override
  Set<String> get supportedTags => {
        "table",
        "tr",
        "tbody",
        "tfoot",
        "thead",
        "th",
        "td",
        "col",
        "colgroup",
      };

  @override
  StyledElement prepare(ExtensionContext context, List<StyledElement> children) {
    if (context.elementName == "table") {
      final cellDescendants = _getCellDescendants(children);

      final colWidths = _getColWidths(children);

      return TableElement(
        name: context.elementName,
        elementId: context.id,
        elementClasses: context.classes.toList(),
        tableStructure: children,
        cellDescendants: cellDescendants,
        style: Style(display: Display.block),
        node: context.node,
        minWidths: colWidths,
      );
    }

    if (context.elementName == "th" || context.elementName == "td") {
      return TableCellElement(
        style: context.elementName == "th"
            ? Style(
                fontWeight: FontWeight.bold,
                textAlign: TextAlign.center,
                verticalAlign: VerticalAlign.middle,
              )
            : Style(
                verticalAlign: VerticalAlign.middle,
              ),
        children: children,
        node: context.node,
        name: context.elementName,
        elementClasses: context.classes.toList(),
        elementId: context.id,
      );
    }

    if (context.elementName == "tbody" || context.elementName == "thead" || context.elementName == "tfoot") {
      return TableSectionLayoutElement(
        name: context.elementName,
        elementId: context.id,
        elementClasses: context.classes.toList(),
        children: children,
        style: Style(),
        node: context.node,
      );
    }

    if (context.elementName == "tr") {
      return TableRowLayoutElement(
        name: context.elementName,
        elementId: context.id,
        elementClasses: context.classes.toList(),
        children: children,
        style: Style(),
        node: context.node,
      );
    }

    if (context.elementName == "col" || context.elementName == "colgroup") {
      return TableStyleElement(
        name: context.elementName,
        elementId: context.id,
        elementClasses: context.classes.toList(),
        children: children,
        style: Style(),
        node: context.node,
      );
    }

    throw UnimplementedError("This isn't possible");
  }

  List<int> _getColWidths(List<StyledElement> children) {
    final widths = <int>[];
    for (final child in children) {
      List<int> partialWidths = [];
      if (child is TableRowLayoutElement) {
        partialWidths = _getColWidthsFromRow(child);
      } else {
        partialWidths = _getColWidths(child.children);
      }
      if (partialWidths.isEmpty) continue;
      for (int i = 0; i < partialWidths.length; ++i) {
        int partial = partialWidths[i];
        if (widths.length <= i) {
          widths.add(partial);
        } else if (widths[i] < partial) {
          widths[i] = partial;
        }
      }
    }
    return widths;
  }

  List<int> _getColWidthsFromRow(TableRowLayoutElement row) {
    List<int> widths = [];
    for (final cell in row.children) {
      int minWidth = 0;
      if (cell is TableCellElement) {
        // Get entire text
        StringBuffer text = StringBuffer();
        for (final child in cell.children) {
          text.write(_getText(child));
        }

        final words = _regExp.allMatches(text.toString()).map((match) => match.group(0)!).toList();
        for (final word in words) {
          int wordWidth = TextPainter.computeWidth(
            text: TextSpan(
                text: word,
                style: TextStyle(
                  fontSize: cell.style.fontSize?.value ?? 16,
                  fontFamily: cell.style.fontFamily,
                  fontWeight: FontWeight.w700,
                )),
            textDirection: TextDirection.ltr,
          ).toInt();
          if (wordWidth > minWidth) {
            minWidth = wordWidth;
          }
        }
      }
      minWidth += 32;
      widths.add(minWidth);
    }
    return widths;
  }

  String _getText(StyledElement element) {
    if (element is TextContentElement) return element.text ?? '';
    StringBuffer buffer = StringBuffer();
    for (final child in element.children) {
      buffer.write(_getText(child));
    }
    return buffer.toString();
  }

  @override
  InlineSpan build(ExtensionContext context) {
    if (context.elementName == "table") {
      return WidgetSpan(
        child: CssBoxWidget(
          style: context.styledElement!.style,
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              final width = MediaQuery.sizeOf(ctx).width;
              return _layoutCells(
                context.styledElement as TableElement,
                context.builtChildrenMap!,
                context,
                width,
              );
            },
          ),
        ),
      );
    }

    return WidgetSpan(
      child: CssBoxWidget.withInlineSpanChildren(
        children: context.inlineSpanChildren!,
        style: Style(),
      ),
    );
  }
}

/// Recursively gets a flattened list of the table's
/// cell descendants
List<TableCellElement> _getCellDescendants(List<StyledElement> children) {
  final descendants = <TableCellElement>[];

  for (final child in children) {
    if (child is TableCellElement) {
      descendants.add(child);
    }

    descendants.addAll(_getCellDescendants(child.children));
  }

  return descendants;
}

Widget _layoutCells(TableElement table, Map<StyledElement, InlineSpan> parsedCells, ExtensionContext context, double width) {
  width -= 32;
  double requiredWidth = 0;
  for (final minWidth in table.minWidths) {
    requiredWidth += minWidth;
  }

  List<int> cellWidths;
  if (requiredWidth < width) {
    final extra = (width - requiredWidth) ~/ table.minWidths.length;
    cellWidths = List.generate(table.minWidths.length, (index) => table.minWidths[index] + extra);
  } else {
    cellWidths = table.minWidths;
    width = requiredWidth + 32;
  }

  final rows = <TableRowLayoutElement>[];
  List<TrackSize> columnSizes = <TrackSize>[];
  for (var child in table.tableStructure) {
    if (child is TableStyleElement) {
      // Map <col> tags to predetermined column track sizes
      columnSizes = child.children
          .where((c) => c.name == "col")
          .map((c) {
            final span = int.tryParse(c.attributes["span"] ?? "1") ?? 1;
            final colWidth = c.attributes["width"];
            return List.generate(span, (index) {
              if (colWidth != null && colWidth.endsWith("%")) {
                final percentageSize = double.tryParse(colWidth.substring(0, colWidth.length - 1));
                return percentageSize != null && !percentageSize.isNaN ? FlexibleTrackSize(percentageSize / 100) : const IntrinsicContentTrackSize();
              } else if (colWidth != null) {
                final fixedPxSize = double.tryParse(colWidth);
                return fixedPxSize != null ? FixedTrackSize(fixedPxSize) : const IntrinsicContentTrackSize();
              } else {
                return const IntrinsicContentTrackSize();
              }
            });
          })
          .expand((element) => element)
          .toList(growable: false);
    } else if (child is TableSectionLayoutElement) {
      rows.addAll(child.children.whereType());
    } else if (child is TableRowLayoutElement) {
      child.style.width = Width(width);
      for (final cell in child.children) {
        int counter = 0;
        if (cell is TableCellElement) {
          cell.style.width = Width(cellWidths[counter].toDouble());
          ++counter;
        }
      }
      rows.add(child);
    }
  }

  // All table rows have a height intrinsic to their (spanned) contents
  final rowSizes = List.generate(
    rows.length,
    (_) => const IntrinsicContentTrackSize(),
  );

  // Calculate column bounds
  int columnMax = 0;
  List<int> rowSpanOffsets = [];
  for (final row in rows) {
    final cols = row.children.whereType<TableCellElement>().fold(0, (int value, child) => value + child.colspan) +
        rowSpanOffsets.fold<int>(0, (int offset, child) => child);
    columnMax = max(cols, columnMax);
    rowSpanOffsets = [
      ...rowSpanOffsets.map((value) => value - 1).where((value) => value > 0),
      ...row.children.whereType<TableCellElement>().map((cell) => cell.rowspan - 1),
    ];
  }

  // Place the cells in the rows/columns
  final cells = <GridPlacement>[];
  final columnRowOffset = List.generate(columnMax, (_) => 0);
  final columnColspanOffset = List.generate(columnMax, (_) => 0);
  int rowi = 0;
  for (var row in rows) {
    int columni = 0;
    for (var child in row.children) {
      if (columni > columnMax - 1) {
        break;
      }
      if (child is TableCellElement) {
        while (columnRowOffset[columni] > 0) {
          columnRowOffset[columni] = columnRowOffset[columni] - 1;
          columni += columnColspanOffset[columni].clamp(1, columnMax - columni - 1);
        }
        cells.add(GridPlacement(
          columnStart: columni,
          columnSpan: min(child.colspan, columnMax - columni),
          rowStart: rowi,
          rowSpan: min(child.rowspan, rows.length - rowi),
          child: CssBoxWidget(
            style: child.style.merge(row.style),
            child: Builder(builder: (context) {
              final alignment =
                  child.style.direction ?? Directionality.of(context);
              return SizedBox.expand(
                child: Container(
                  alignment: _getCellAlignment(child, alignment),
                  child: CssBoxWidget.withInlineSpanChildren(
                    children: [
                      parsedCells[child] ?? const TextSpan(text: "error")
                    ],
                    style: Style(),
                  ),
                ),
              );
            }),
          ),
        ));
        columnRowOffset[columni] = child.rowspan - 1;
        columnColspanOffset[columni] = child.colspan;
        columni += child.colspan;
      }
    }
    while (columni < columnRowOffset.length) {
      columnRowOffset[columni] = columnRowOffset[columni] - 1;
      columni++;
    }
    rowi++;
  }

  // Create column tracks (insofar there were no colgroups that already defined them)
  List<TrackSize> finalColumnSizes = columnSizes.take(columnMax).toList();
  finalColumnSizes += List.generate(max(0, columnMax - finalColumnSizes.length), (_) => const IntrinsicContentTrackSize());

  if (finalColumnSizes.isEmpty || rowSizes.isEmpty) {
    // No actual cells to show
    return const SizedBox();
  }

  return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: requiredWidth,
        child: LayoutGrid(
          gridFit: GridFit.loose,
          columnSizes: finalColumnSizes,
          rowSizes: rowSizes,
          children: cells,
        ),
      ));
}

Alignment _getCellAlignment(TableCellElement cell, TextDirection alignment) {
  Alignment verticalAlignment;

  switch (cell.style.verticalAlign) {
    case VerticalAlign.baseline:
    case VerticalAlign.sub:
    case VerticalAlign.sup:
    case VerticalAlign.top:
      verticalAlignment = Alignment.topCenter;
      break;
    case VerticalAlign.middle:
      verticalAlignment = Alignment.center;
      break;
    case VerticalAlign.bottom:
      verticalAlignment = Alignment.bottomCenter;
      break;
  }

  switch (cell.style.textAlign) {
    case TextAlign.left:
      return verticalAlignment + Alignment.centerLeft;
    case TextAlign.right:
      return verticalAlignment + Alignment.centerRight;
    case TextAlign.center:
      return verticalAlignment + Alignment.center;
    case null:
    case TextAlign.start:
    case TextAlign.justify:
      switch (alignment) {
        case TextDirection.rtl:
          return verticalAlignment + Alignment.centerRight;
        case TextDirection.ltr:
          return verticalAlignment + Alignment.centerLeft;
      }
    case TextAlign.end:
      switch (alignment) {
        case TextDirection.rtl:
          return verticalAlignment + Alignment.centerLeft;
        case TextDirection.ltr:
          return verticalAlignment + Alignment.centerRight;
      }
  }
}

class TableCellElement extends StyledElement {
  int colspan = 1;
  int rowspan = 1;

  TableCellElement({
    required super.name,
    required super.elementId,
    required super.elementClasses,
    required super.children,
    required super.style,
    required super.node,
  }) {
    colspan = _parseSpan(this, "colspan");
    rowspan = _parseSpan(this, "rowspan");
  }

  static int _parseSpan(StyledElement element, String attributeName) {
    final spanValue = element.attributes[attributeName];
    return int.tryParse(spanValue ?? "1") ?? 1;
  }
}

class TableElement extends StyledElement {
  final List<StyledElement> tableStructure;
  final List<int> minWidths;

  TableElement({
    required super.name,
    required super.elementId,
    required super.elementClasses,
    required List<TableCellElement> cellDescendants,
    required this.tableStructure,
    required super.style,
    required super.node,
    this.minWidths = const [],
  }) : super(children: cellDescendants);
}

class TableSectionLayoutElement extends StyledElement {
  TableSectionLayoutElement({
    required super.name,
    required super.elementId,
    required super.elementClasses,
    required super.children,
    required super.style,
    required super.node,
  });
}

class TableRowLayoutElement extends StyledElement {
  TableRowLayoutElement({
    required super.name,
    required super.elementId,
    required super.elementClasses,
    required super.children,
    required super.style,
    required super.node,
  });
}

class TableStyleElement extends StyledElement {
  TableStyleElement({
    required super.name,
    required super.elementId,
    required super.elementClasses,
    required super.children,
    required super.style,
    required super.node,
  });
}
