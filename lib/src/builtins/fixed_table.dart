import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_layout_grid/flutter_layout_grid.dart';

import '../../flutter_html.dart';

class FixedTable extends StatefulWidget {
  final TableElement table;
  final Map<StyledElement, InlineSpan> parsedCells;
  final ExtensionContext context;
  final double width;
  final bool shrinkWrap;

  const FixedTable({super.key = const Key('super'), required this.table, required this.parsedCells, required this.context, required this.width, required this.shrinkWrap});

  @override
  State<StatefulWidget> createState() => FixedTableState();
}

class FixedTableState extends State<FixedTable> {
  late double width;

  //TODO: didUpdateWidget if context was changed.

  @override
  void initState() {
    width = widget.width;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final minWidths = TableLayoutHelper.getColWidths(widget.table.tableStructure);
    double requiredWidth = 0;
    for (final minWidth in minWidths) {
      requiredWidth += minWidth;
    }

    List<double> cellWidths;
    if (!widget.shrinkWrap && requiredWidth < width) {
      final extra = (width - requiredWidth) / minWidths.length;
      cellWidths = List.generate(minWidths.length, (index) => minWidths[index] + extra);
    } else {
      cellWidths = minWidths;
      width = requiredWidth + 32;
    }

    final rows = <TableRowLayoutElement>[];
    for (var child in widget.table.tableStructure) {
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
    final globalKeyList = <GlobalKey>[];

    final List<GridPlacement> firstColumnChildren = [];
    final List<Widget> firstRowChildren = [];
    final List<GridPlacement> firstColumnSpannedChildren = [];
    final List<TrackSize> finalFirstColumnSizes = [];
    final List<TrackSize> finalFirstRowSizes = [];

    // if table is 5x5 the cells are not always 20 because some of it can have colspan so its maximum 20
    List<int> firstColumnCellsIndexes = [];
    List<int> firstRowCellsIndexes = [];
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
          final globalKey = GlobalKey();
          globalKeyList.add(globalKey);
          // cells.add(buildGridPlacement(globalKey, columni, child, columnMax, rowi, rows, row));
          final lastCellIndex = cells.length - 1;
          final columnNumber = lastCellIndex % columnMax;
          final columnSpan = min(child.colspan, columnMax - columni);
          if (columni == 0 && columnSpan < 2) {
            firstColumnCellsIndexes.add(lastCellIndex);
            final widget = buildGridPlacement(globalKey, columni, child, columnMax, rowi, rows, row);
            if(columnSpan > 1){
              firstColumnSpannedChildren.add(widget);
            }else{
              firstColumnChildren.add(widget);
            }
            finalFirstColumnSizes.add(FixedTrackSize(100/*cellWidths[columnNumber]*/));//TODO:
          }
          else if (columni > 0 && rowi == 0) {
            firstRowCellsIndexes.add(lastCellIndex);
            final widget = buildGridPlacement(globalKey, columni - 1, child, columnMax, rowi, rows, row);
            firstRowChildren.add(widget);
            finalFirstRowSizes.add(FixedTrackSize(cellWidths[columnNumber]));
          }else{
            // if columnSpan > 1 or (column > 0 and rowi > 0)
          }
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

    //firstColumnCellsIndexes
    // int j = 0;
    // for(var i=0;i< rows.length;++i){
    //   firstColumnChildren.add(cells[j]);
    //   finalFirstColumnSizes.add(FixedTrackSize(cellWidths[j]));
    //   j+=columnMax;
    // }
    final columnGridPlacements =  <GridPlacement>[];
    for(var children in firstColumnChildren){

    }

    var previousRowStart = 0;
    // final columnGridPlacements =  <GridPlacement>[];
    for(var spannedChildren in firstColumnSpannedChildren){
      final spannedIndex = spannedChildren.rowStart!;
      final partChildren = firstColumnChildren.sublist(previousRowStart, spannedIndex - 1);
      partChildren.add(spannedChildren);
      final gridPlacement = GridPlacement(
          columnStart: 0,
          rowStart: previousRowStart,
          child: LayoutGrid(
            gridFit: GridFit.loose,
            columnSizes: finalFirstColumnSizes.sublist(previousRowStart, spannedIndex + 1),
            rowSizes: rowSizes.sublist(previousRowStart, spannedIndex + 1),
            children: partChildren,
          ));
      columnGridPlacements.add(gridPlacement);
      previousRowStart = spannedIndex;
    }


    final firstColumnGridPlacement = GridPlacement(
      columnStart: 0,
      rowStart: 0,
      child: LayoutGrid(
        gridFit: GridFit.loose,
        columnSizes: finalFirstColumnSizes,
        rowSizes: rowSizes,
        children: firstColumnChildren,
      ),
    );


    final firstRowLayoutGrid = GridPlacement(
      columnStart: 1,
      rowStart: 0,
      child: LayoutGrid(
        gridFit: GridFit.loose,
        columnSizes: finalFirstRowSizes,
        rowSizes: rowSizes.sublist(0, finalFirstRowSizes.length),
        children: firstRowChildren,
      ),
    );


    double maxFirstColumnValue = finalFirstColumnSizes.map((obj) => (obj as FixedTrackSize).sizeInPx).reduce(max);
    double sumFirstRowValue = finalFirstRowSizes.map((e) => (e as FixedTrackSize).sizeInPx).fold(0.0,(sum,val) => sum + val);


    return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child:
            SizedBox(
              child: LayoutGrid(
                gridFit: GridFit.loose,
                columnSizes: [FixedTrackSize(maxFirstColumnValue), FixedTrackSize(sumFirstRowValue)],
                rowSizes: const [IntrinsicContentTrackSize(), IntrinsicContentTrackSize()],
                children: [firstColumnGridPlacement, firstRowLayoutGrid],
              ),
        ));

    // return SingleChildScrollView(
    //     scrollDirection: Axis.horizontal,
    //     child: SizedBox(
    //       child: LayoutGrid(
    //         gridFit: GridFit.loose,
    //         columnSizes: finalFirstRowSizes,
    //         rowSizes: rowSizes.sublist(0, finalFirstRowSizes.length),
    //         children: firstRowChildren,
    //       ),
    //     ));

    // return SingleChildScrollView(
    //     scrollDirection: Axis.horizontal,
    //     child: SizedBox(
    //       child: LayoutGrid(
    //         gridFit: GridFit.loose,
    //         columnSizes: finalFirstColumnSizes,
    //         rowSizes: rowSizes,
    //         children: firstColumnChildren,
    //       ),
    //     ));

    // return SingleChildScrollView(
    //     scrollDirection: Axis.horizontal,
    //     child: SizedBox(
    //       child: LayoutGrid(
    //         gridFit: GridFit.loose,
    //         columnSizes: finalColumnSizes,
    //         rowSizes: rowSizes,
    //         children: cells,
    //       ),
    //     ));
  }

  GridPlacement buildGridPlacement(GlobalKey<State<StatefulWidget>> globalKey, int columni, TableCellElement child, int columnMax, int rowi,
      List<TableRowLayoutElement> rows, TableRowLayoutElement row) {
    return GridPlacement(
      key: globalKey,
      columnStart: columni,
      columnSpan: min(child.colspan, columnMax - columni),
      rowStart: rowi,
      rowSpan: min(child.rowspan, rows.length - rowi),
      child: CssBoxWidget(
        shrinkWrap: widget.shrinkWrap,
        style: child.style.merge(row.style),
        child: Builder(builder: (context) {
          final alignment = child.style.direction ?? Directionality.of(context);
          return SizedBox.expand(
            child: Container(
              alignment: TableLayoutHelper.getCellAlignment(child, alignment),
              child: CssBoxWidget.withInlineSpanChildren(
                children: [widget.parsedCells[child] ?? const TextSpan(text: "error")],
                style: Style(),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class TableLayoutHelper {
  static List<double> getColWidths(List<StyledElement> children) {
    final widths = <double>[];
    for (final child in children) {
      List<double> partialWidths = [];
      if (child is TableRowLayoutElement) {
        partialWidths = _getColWidthsFromRow(child);
      } else {
        partialWidths = getColWidths(child.children);
      }
      if (partialWidths.isEmpty) continue;
      for (int i = 0; i < partialWidths.length; ++i) {
        double partial = partialWidths[i];
        if (widths.length <= i) {
          widths.add(partial);
        } else if (widths[i] < partial) {
          widths[i] = partial;
        }
      }
    }
    return widths;
  }

  static List<double> _getColWidthsFromRow(TableRowLayoutElement row) {
    List<double> widths = [];
    for (final cell in row.children) {
      if (cell is TableCellElement) {
        WidthInfo info = WidthInfo();
        for (final child in cell.children) {
          _getCellInfo(child, info);
        }
        double minWidth = info.requiredWidth + 32;
        widths.add(minWidth);
      }
    }
    return widths;
  }

  static void _getCellInfo(StyledElement element, WidthInfo info) {
    if (element is TextContentElement) {
      final regex = RegExp(r'\w+|\s+|[^\w\s]');
      final wordRegex = RegExp(r'\w+');
      final text = element.text;
      if (text == null || text.isEmpty) return;
      final words = regex.allMatches(text).map((m) => m.group(0)!).toList();
      for (final word in words) {
        double wordWidth = TextPainter.computeWidth(
          text: TextSpan(
              text: word,
              style: TextStyle(
                fontSize: element.style.fontSize?.value ?? 16,
                fontFamily: element.style.fontFamily,
                fontWeight: element.style.fontWeight,
                fontStyle: element.style.fontStyle,
              )),
          textDirection: TextDirection.ltr,
        );
        if (info.join && wordRegex.hasMatch(word)) {
          info.width += wordWidth;
        } else {
          info.width = wordWidth;
        }
        if (info.width > info.requiredWidth) {
          info.requiredWidth = info.width;
        }
        info.join = wordRegex.hasMatch(word);
      }
    } else {
      for (final child in element.children) {
        _getCellInfo(child, info);
      }
    }
  }

  static Alignment getCellAlignment(TableCellElement cell, TextDirection alignment) {
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
}
