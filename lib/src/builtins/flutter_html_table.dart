library flutter_html_table;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_layout_grid/flutter_layout_grid.dart';

import '../tables/fixed_headers/fixed_headers_table_widget.dart';
import '../tables/table_helper.dart';

/// [TableHtmlExtension] adds support for the <table> element to the flutter_html library.
/// <tr>, <tbody>, <tfoot>, <thead>, <th>, <td>, <col>, and <colgroup> are also
/// supported.
///
/// Currently, nested tables are not supported.
///
///
class TableHtmlExtension extends HtmlExtension {
  /// It use shrinkWrap option to CssBoxWidgets. But in build method it fill available width.
  /// Use only if something wrong with the view.
  /// Uses shrinkWrap option in many widgets can be very expensive, because it means that you have to measure everything.
  final bool shrinkAndFill;
  bool hasFixedHeaders = false;
  final tableHelper = TableHelper();

  TableHtmlExtension({this.shrinkAndFill = false});

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
      hasFixedHeaders = context.attributes.containsKey("data-fixed-header");

      final cellDescendants = _getCellDescendants(children);

      return TableElement(
        name: context.elementName,
        elementId: context.id,
        elementClasses: context.classes.toList(),
        tableStructure: children,
        cellDescendants: cellDescendants,
        style: Style(display: Display.block),
        node: context.node,
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

  @override
  InlineSpan build(ExtensionContext context) {
    if (context.elementName == "table") {
      return WidgetSpan(
        child: CssBoxWidget(
          shrinkWrap: shrinkAndFill,
          style: context.styledElement!.style,
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              double width;
              if (constraints.hasBoundedWidth) {
                width = constraints.maxWidth;
              } else {
                width = MediaQuery.sizeOf(ctx).width - 32;
              }
              if (hasFixedHeaders) {
                return FixedHeadersTableWidget(
                  table: context.styledElement as TableElement,
                  parsedCells: context.builtChildrenMap!,
                  context: context,
                  width: width,
                  shrinkWrap: shrinkAndFill,
                  tableHelper: tableHelper,
                );
              } else {
                return _layoutCells(
                  context.styledElement as TableElement,
                  context.builtChildrenMap!,
                  context,
                  width,
                  shrinkAndFill,
                  tableHelper,
                );
              }
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

Widget _layoutCells(
    TableElement table, Map<StyledElement, InlineSpan> parsedCells, ExtensionContext context, double width, bool shrinkAndFill, TableHelper tableHelper) {
  final minWidths = tableHelper.getColWidths(table.tableStructure);
  double requiredWidth = 0;
  for (final minWidth in minWidths) {
    requiredWidth += minWidth;
  }

  List<double> cellWidths;
  if (shrinkAndFill || requiredWidth < width) {
    final extra = (width - requiredWidth) / minWidths.length;
    cellWidths = List.generate(minWidths.length, (index) => minWidths[index] + extra);
  } else {
    cellWidths = minWidths;
    width = requiredWidth + 32;
  }

  final rows = <TableRowLayoutElement>[];
  for (var child in table.tableStructure) {
    if (child is TableSectionLayoutElement) {
      rows.addAll(child.children.whereType());
    } else if (child is TableRowLayoutElement) {
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
    // Ignore width set in CSS, there is only one proper layout...
    row.children.whereType<TableCellElement>().forEach((cell) => cell.style.width = null);
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
            shrinkWrap: shrinkAndFill,
            style: child.style.merge(row.style),
            child: Builder(builder: (context) {
              final alignment = child.style.direction ?? Directionality.of(context);
              return SizedBox.expand(
                child: Container(
                  alignment: tableHelper.getCellAlignment(child, alignment),
                  child: CssBoxWidget.withInlineSpanChildren(
                    children: [parsedCells[child] ?? const TextSpan(text: "error")],
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
  List<TrackSize> finalColumnSizes = List.generate(cellWidths.length, (index) => FixedTrackSize(cellWidths[index]));

  if (finalColumnSizes.isEmpty || rowSizes.isEmpty) {
    // No actual cells to show
    return const SizedBox();
  }

  return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        child: LayoutGrid(
          gridFit: GridFit.loose,
          columnSizes: finalColumnSizes,
          rowSizes: rowSizes,
          children: cells,
        ),
      ));
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

  TableElement({
    required super.name,
    required super.elementId,
    required super.elementClasses,
    required List<TableCellElement> cellDescendants,
    required this.tableStructure,
    required super.style,
    required super.node,
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
