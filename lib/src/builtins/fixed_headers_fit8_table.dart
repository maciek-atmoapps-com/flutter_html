import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_html/src/builtins/scroll_group_synchronizer.dart';
import 'package:flutter_layout_grid/flutter_layout_grid.dart';

import '../../flutter_html.dart';

/// Works after orientation changed.
class FixedHeadersFit8Table extends StatefulWidget {
  final TableElement table;
  final Map<StyledElement, InlineSpan> parsedCells;
  final ExtensionContext context;
  final double width;
  final bool shrinkWrap;

  const FixedHeadersFit8Table(
      {super.key, required this.table, required this.parsedCells, required this.context, required this.width, required this.shrinkWrap});

  @override
  State<FixedHeadersFit8Table> createState() => _FixedHeadersFit8TableState();
}

class _FixedHeadersFit8TableState extends State<FixedHeadersFit8Table> {
  late double width;

  late ScrollGroupSynchronizer _verticalScrollGroupSynchronizer;
  late ScrollGroupSynchronizer _horizontalScrollGroupSynchronizer;
  final _horizontalRowScrollController = ScrollController();

  final GlobalKey _headerContentKey = GlobalKey();
  late List<GlobalKey> intrinsicHeightRowsKeys;
  List<double?> _calculatedFullRowIntrinsicHeightList = [];
  double? _calculatedHeaderHeight;
  bool _isMeasured = false;

  @override
  void initState() {
    width = widget.width;
    _horizontalScrollGroupSynchronizer = ScrollGroupSynchronizer([_horizontalRowScrollController]);
    _verticalScrollGroupSynchronizer = ScrollGroupSynchronizer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureWidgets();
    });
    super.initState();
  }

  void _measureWidgets() {
    if(!mounted) return;
    final headerContext = _headerContentKey.currentContext;
    double? newHeaderHeight;
    bool isContextNull = false;
    if (headerContext != null) {
      newHeaderHeight = headerContext.size?.height;
    } else {
      isContextNull = true;
    }
    List<double?> newCalculatedIntrinsicHeights = _calculatedFullRowIntrinsicHeightList;
    bool isCalculatedHeightTableChanged = false;
    for (var i = 0; i < intrinsicHeightRowsKeys.length; ++i) {
      final hasIndex = i < _calculatedFullRowIntrinsicHeightList.length - 1;
      final height = hasIndex ? _calculatedFullRowIntrinsicHeightList[i] : null;
      final context = intrinsicHeightRowsKeys[i].currentContext;
      if (context != null) {
        final newHeight = context.size?.height;
        if (newHeight != null && newHeight != height) {
          isCalculatedHeightTableChanged = true;
          if (hasIndex) {
            newCalculatedIntrinsicHeights[i] = newHeight;
          } else {
            newCalculatedIntrinsicHeights.add(newHeight);
          }
        }
      } else {
        isContextNull = true;
      }
    }

    if (isContextNull) {
      if (mounted) {
        setState(() {
          _isMeasured = false;
        });
      }
      return;
    }

    if (isCalculatedHeightTableChanged || (newHeaderHeight != null && newHeaderHeight != _calculatedHeaderHeight)) {
      // Sprawdź, czy widget jest nadal zamontowany, aby uniknąć błędów
      if (mounted) {
        setState(() {
          if ((newHeaderHeight != null && newHeaderHeight != _calculatedHeaderHeight)) {
            _calculatedHeaderHeight = newHeaderHeight;
          }
          if (isCalculatedHeightTableChanged) {
            _calculatedFullRowIntrinsicHeightList = newCalculatedIntrinsicHeights;
          }
          _isMeasured = true;
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant FixedHeadersFit8Table oldWidget) {
    setState(() {
      if (oldWidget.width != widget.width) {
        width = widget.width;
      }
      _isMeasured = false;
      _calculatedFullRowIntrinsicHeightList = [];
      _calculatedHeaderHeight = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isMeasured) {
        _measureWidgets();
      }
    });
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    _horizontalScrollGroupSynchronizer.dispose();
    _verticalScrollGroupSynchronizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final minWidths = _getColWidths(widget.table.tableStructure);
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
    final bodyCells = <GridPlacement>[];
    final columnRowOffset = List.generate(columnMax, (_) => 0);
    final columnColspanOffset = List.generate(columnMax, (_) => 0);
    int rowi = 0;
    late LayoutGrid cornerLayoutGrid;
    late List<GridPlacement> headersRowGridPlacement = [];

    late List<GridPlacement> headersColumnGridPlacement = [];
    late List<GridPlacementBuildInfo> headersColumnBuildInfoElements = [];

    late List<GridPlacementBuildInfo> bodyCellsBuildInfoElements = [];
    for (var row in rows) {
      int columni = 0;
      int lastHeaderColspan = 1;
      for (var child in row.children) {
        if (columni > columnMax - 1) {
          break;
        }
        if (child is TableCellElement) {
          while (columnRowOffset[columni] > 0) {
            columnRowOffset[columni] = columnRowOffset[columni] - 1;
            columni += columnColspanOffset[columni].clamp(1, columnMax - columni - 1);
          }
          if (columni == 0 && rowi == 0) {
            final cornerGridPlacement = buildGridPlacement(columni, child, columnMax, rowi, rows, row);
            cornerLayoutGrid = LayoutGrid(
              columnSizes: [FixedTrackSize(cellWidths[columni])],
              rowSizes: [rowSizes[rowi]],
              children: [cornerGridPlacement],
            );
          } else if (columni == 0 && rowi > 0) {
            final gridBuildInfo = GridPlacementBuildInfo(columni, child, columnMax, rowi - 1, rows, row);
            final gridPlacement = buildGridPlacement(columni, child, columnMax, rowi - 1, rows, row);
            headersColumnBuildInfoElements.add(gridBuildInfo);
            headersColumnGridPlacement.add(gridPlacement);
            lastHeaderColspan = child.colspan;
          } else if (columni > 0 && rowi == 0) {
            //before headerRow we use cornerGrid so we have to use (columni - 1)
            headersRowGridPlacement.add(buildGridPlacement(columni - 1, child, columnMax, rowi, rows, row));
          } else {
            //body is separate view so we use (columni - 1)
            bodyCellsBuildInfoElements.add(GridPlacementBuildInfo(columni - lastHeaderColspan, child, columnMax, rowi - 1, rows, row));
            bodyCells.add(buildGridPlacement(columni - lastHeaderColspan, child, columnMax, rowi - 1, rows, row));
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

    // prepare data for render offstage (invisible view) to calculate its height
    List<Widget> intrinsicHeightRowsList = _prepareIntrinsicHeightRowsList(finalColumnSizes, rowSizes, bodyCells, headersColumnGridPlacement);

    // header row is the first row of table. It will be sticky
    final headerRowLayoutGrid =
        LayoutGrid(gridFit: GridFit.passthrough, columnSizes: finalColumnSizes.sublist(1), rowSizes: rowSizes, children: headersRowGridPlacement);
    final headerRowContent = IntrinsicHeight(
      key: _headerContentKey,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: (finalColumnSizes[0] as FixedTrackSize).sizeInPx, child: cornerLayoutGrid),
          Expanded(
            child: SingleChildScrollView(
              controller: _horizontalRowScrollController,
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: headerRowLayoutGrid,
            ),
          ),
        ],
      ),
    );

    // If not measured yet, render whole view to calculate height
    if (!_isMeasured) {
      return Stack(
        children: [
          Offstage(
              child: SingleChildScrollView(
            child: Column(
              children: [headerRowContent, ...intrinsicHeightRowsList],
            ),
          )),
        ],
      );
    }

    List<HeaderLayoutBuilderInfo> headerLayoutGrids = [];
    List<BodyLayoutBuilderInfo> bodyLayoutGrids = [];
    List<LayoutBuilderInfo> layoutBuilderInfoList = [];
    for (int i = 0; i < _calculatedFullRowIntrinsicHeightList.length; ++i) {
      /// Get info about header column sizes for later comparison is header column sized was changed
      final headerColumnI = headersColumnBuildInfoElements.where((e) => e.rowi == i).firstOrNull;
      int? headerColumnSpan = getColumnSpan(headerColumnI?.child, columnMax, headerColumnI?.columni);
      List<TrackSize> headerColumnSizes = headerColumnSpan == null ? [] : finalColumnSizes.sublist(0, headerColumnSpan);

      final bodyCellsI = bodyCellsBuildInfoElements.where((e) => e.rowi == i).toList(growable: false);
      List<TrackSize> bodyColumnSizes = [];
      if (bodyCellsI.isNotEmpty) {
        bodyColumnSizes = finalColumnSizes.sublist(headerColumnSpan ?? 0, bodyCellsI.length + 1);
      }

      /// Check is currentLayout is the same as previous
      bool isDifferentLayout = true;
      if ((layoutBuilderInfoList.isEmpty) ||
          !hasSameColumnSize(layoutBuilderInfoList.last.headerColumnSizes, headerColumnSizes, layoutBuilderInfoList.last.bodyColumnSizes, bodyColumnSizes)) {
        isDifferentLayout = true;
      } else {
        isDifferentLayout = false;
      }

      /// Build info about header and add it to appropriate category
      //TODO: for every new Layout we need to edit row and start from 0 (instead of 1)
      HeaderLayoutBuilderInfo? matchingHeaderLayoutBuilderInfo;
      if (headerColumnI != null) {
        final rowi = isDifferentLayout ? 0 : (layoutBuilderInfoList.last.lastHeaderIdx ?? 0) + 1;
        final headerGridPlacement = buildGridPlacement(
            headerColumnI.columni, headerColumnI.child, headerColumnI.columnMax, rowi, headerColumnI.rows, headerColumnI.row,
            height: _calculatedFullRowIntrinsicHeightList[i]);
        headerColumnSizes = finalColumnSizes.sublist(0, headerColumnSpan);
        //TODO: instead of lastIdx you can get just last element from headerLayoutGrids
        matchingHeaderLayoutBuilderInfo = headerLayoutGrids.where((e) => e.lastIdx == (i - 1) && e.columnSizes == headerColumnSizes).firstOrNull;
        if (matchingHeaderLayoutBuilderInfo != null) {
          matchingHeaderLayoutBuilderInfo.add(headerGridPlacement, lastIdx: i);
        } else {
          matchingHeaderLayoutBuilderInfo = HeaderLayoutBuilderInfo(headerColumnSizes)..add(headerGridPlacement, lastIdx: i);
          headerLayoutGrids.add(matchingHeaderLayoutBuilderInfo);
        }
      }

      BodyLayoutBuilderInfo? matchingBodyLayoutBuilderInfo;
      final List<GridPlacement> cellsFixedSizeRowElements = [];

      /// Build info about cells and add it to appropriate category
      for (var e in bodyCellsI) {
        final rowi = isDifferentLayout ? 0 : (layoutBuilderInfoList.last.lastBodyIdx ?? 0) + 1;
        final cellGridPlacement = buildGridPlacement(e.columni, e.child, e.columnMax, rowi, e.rows, e.row, height: _calculatedFullRowIntrinsicHeightList[i]);
        cellsFixedSizeRowElements.add(cellGridPlacement);
      }
      //TODO: instead of lastIdx you can get just last element from bodyLayoutGrids
      matchingBodyLayoutBuilderInfo = bodyLayoutGrids.where((e) => e.lastIdx == (i - 1) && e.columnSizes == bodyColumnSizes).firstOrNull;
      if (matchingBodyLayoutBuilderInfo != null) {
        matchingBodyLayoutBuilderInfo.add(cellsFixedSizeRowElements, lastIdx: i);
      } else {
        matchingBodyLayoutBuilderInfo = BodyLayoutBuilderInfo(bodyColumnSizes)..add(cellsFixedSizeRowElements, lastIdx: i);
        bodyLayoutGrids.add(matchingBodyLayoutBuilderInfo);
      }

      /// Add to layoutBuilderInfoList
      if (isDifferentLayout) {
        //TODO: add header and body with from row = 0;
        final layoutBuilderInfo = LayoutBuilderInfo(headerColumnSizes, bodyColumnSizes);
        layoutBuilderInfo.add(matchingHeaderLayoutBuilderInfo, matchingBodyLayoutBuilderInfo);
        layoutBuilderInfoList.add(layoutBuilderInfo);
      } else {
        //TODO: add header and body with standard way
        layoutBuilderInfoList.last.add(matchingHeaderLayoutBuilderInfo, matchingBodyLayoutBuilderInfo);
      }
    }
    //TODO: convert layoutBuilderInfoList to List<SliverToBoxAdapter> and pass it below ...sliverAdapters below SliverPersistentHeader
    final layoutToSliverAdapter = LayoutInfoToSliverAdapter(rowSizes, _verticalScrollGroupSynchronizer,
        _horizontalScrollGroupSynchronizer); //_horizontalController2, _verticalController1, _verticalController2, _horizontalSpannableController);
    final sliverToBoxAdapterList = layoutBuilderInfoList.map((e) => layoutToSliverAdapter.transform(e)).toList(growable: false);

    return SizedBox(
      height: MediaQuery.of(context).size.height - 150,
      child: CustomScrollView(
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _MySliverPersistentRowHeaderDelegate(minHeight: _calculatedHeaderHeight!, maxHeight: _calculatedHeaderHeight!, child: headerRowContent),
          ),
          ...sliverToBoxAdapterList
        ],
      ),
    );
  }

  /// Prepare list of IntrinsicHeight widgets.
  /// This widget list can be used to compute the height of all complete rows.
  /// The height of each row is determined by the tallest column within that row.
  List<Widget> _prepareIntrinsicHeightRowsList(
    List<TrackSize> finalColumnSizes,
    List<IntrinsicContentTrackSize> rowSizes,
    List<GridPlacement> bodyCells,
    List<GridPlacement> headersColumnGridPlacement,
  ) {
    final cellsLayoutGrid = LayoutGrid(columnSizes: finalColumnSizes.sublist(1), rowSizes: rowSizes, children: bodyCells);
    final headerColumnLayoutGrid = LayoutGrid(columnSizes: finalColumnSizes.sublist(0, 1), rowSizes: rowSizes, children: headersColumnGridPlacement);

    List<Widget> intrinsicHeightRowsList = [];
    intrinsicHeightRowsKeys = List.generate(headerColumnLayoutGrid.children.length, (_) => GlobalKey());

    final cellsLayoutGridChildren = (cellsLayoutGrid.children as List<GridPlacement>);
    int j = 0;
    for (int i = 0; i < headerColumnLayoutGrid.children.length; ++i) {
      final cellsRowElements = <GridPlacement>[];
      final headerElement = headerColumnLayoutGrid.children[i] as GridPlacement;
      for (; j < cellsLayoutGridChildren.length && cellsLayoutGridChildren[j].rowStart == headerElement.rowStart; ++j) {
        final currentCellsGridPlacement = cellsLayoutGridChildren[j];
        cellsRowElements.add(currentCellsGridPlacement);
      }
      final cellRowLayoutGrid =
          LayoutGrid(gridFit: GridFit.passthrough, columnSizes: finalColumnSizes.sublist(1), rowSizes: rowSizes, children: cellsRowElements);

      final headerElementLayoutGrid = LayoutGrid(
        columnSizes: finalColumnSizes.sublist(0, headerElement.columnSpan),
        rowSizes: rowSizes,
        children: [headerElement],
      );
      final currentHeaderColumnSizes = finalColumnSizes.whereIndexed((idx, e) => idx < headerElement.columnSpan);
      final headerColumnSize = currentHeaderColumnSizes.fold<double>(0.0, (previousValue, element) {
        return previousValue + (element as FixedTrackSize).sizeInPx;
      });
      final fullRow = IntrinsicHeight(
        key: intrinsicHeightRowsKeys[i],
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: headerColumnSize, child: headerElementLayoutGrid),
            Expanded(
              child: cellRowLayoutGrid,
            ),
          ],
        ),
      );
      intrinsicHeightRowsList.add(fullRow);
    }
    return intrinsicHeightRowsList;
  }

  int? getColumnSpan(TableCellElement? child, int columnMax, int? columni) {
    if (child == null || columni == null) {
      return null;
    } else {
      return min(child.colspan, columnMax - columni);
    }
  }

  GridPlacement buildGridPlacement(int columni, TableCellElement child, int columnMax, int rowi, List<TableRowLayoutElement> rows, TableRowLayoutElement row,
      {double? height}) {
    return GridPlacement(
      columnStart: columni,
      columnSpan: min(child.colspan, columnMax - columni),
      rowStart: rowi,
      rowSpan: min(child.rowspan, rows.length - rowi),
      child: CssBoxWidget(
        shrinkWrap: widget.shrinkWrap,
        style: child.style.merge(row.style),
        child: Builder(builder: (context) {
          final alignment = child.style.direction ?? Directionality.of(context);
          if (height == null) {
            return SizedBox.expand(
              child: Container(
                alignment: _getCellAlignment(child, alignment),
                child: CssBoxWidget.withInlineSpanChildren(
                  children: [widget.parsedCells[child] ?? const TextSpan(text: "error")],
                  style: Style(),
                ),
              ),
            );
          } else {
            return SizedBox(
              width: double.infinity,
              height: height,
              child: Container(
                alignment: _getCellAlignment(child, alignment),
                child: CssBoxWidget.withInlineSpanChildren(
                  children: [widget.parsedCells[child] ?? const TextSpan(text: "error")],
                  style: Style(),
                ),
              ),
            );
          }
        }),
      ),
    );
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

  List<double> _getColWidths(List<StyledElement> children) {
    final widths = <double>[];
    for (final child in children) {
      List<double> partialWidths = [];
      if (child is TableRowLayoutElement) {
        partialWidths = _getColWidthsFromRow(child);
      } else {
        partialWidths = _getColWidths(child.children);
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

  List<double> _getColWidthsFromRow(TableRowLayoutElement row) {
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

  void _getCellInfo(StyledElement element, WidthInfo info) {
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

  bool hasSameColumnSize(
      List<TrackSize> headerColumnSizes, List<TrackSize> headerColumnSizes2, List<TrackSize> bodyColumnSizes, List<TrackSize> bodyColumnSizes2) {
    const eq = ListEquality();
    return eq.equals(headerColumnSizes, headerColumnSizes2) && eq.equals(bodyColumnSizes, bodyColumnSizes2);
  }
}

class _MySliverPersistentRowHeaderDelegate extends SliverPersistentHeaderDelegate {
  _MySliverPersistentRowHeaderDelegate({
    required this.minHeight,
    required this.maxHeight,
    required this.child,
  });

  final double minHeight;
  final double maxHeight;
  final Widget child;

  @override
  double get minExtent => minHeight;

  @override
  double get maxExtent => maxHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    // Możesz tutaj dodać logikę, jeśli chcesz, aby wygląd nagłówka
    // zmieniał się w zależności od shrinkOffset (jak bardzo został "ściśnięty").
    // Dla prostego, statycznego nagłówka, który tylko się przypina:
    return SizedBox.expand(child: child);
  }

  @override
  bool shouldRebuild(_MySliverPersistentRowHeaderDelegate oldDelegate) {
    // Przebuduj, jeśli zmieniła się minimalna/maksymalna wysokość lub dziecko.
    return maxHeight != oldDelegate.maxHeight || minHeight != oldDelegate.minHeight || child != oldDelegate.child;
  }
}

/// properties that be needed to build GridPlacement
class GridPlacementBuildInfo {
  final int columni;
  final TableCellElement child;
  final int columnMax;
  final int rowi;
  final List<TableRowLayoutElement> rows;
  final TableRowLayoutElement row;

  GridPlacementBuildInfo(this.columni, this.child, this.columnMax, this.rowi, this.rows, this.row);
}

class HeaderLayoutBuilderInfo {
  int? lastIdx;
  final List<TrackSize> columnSizes;
  final List<GridPlacement> gridPlacements = [];

  HeaderLayoutBuilderInfo(this.columnSizes);

  void add(GridPlacement gridPlacement, {required int lastIdx}) {
    gridPlacements.add(gridPlacement);
    this.lastIdx = lastIdx;
  }
}

class BodyLayoutBuilderInfo {
  int? lastIdx;
  final List<TrackSize> columnSizes;
  final List<List<GridPlacement>> gridPlacements = [];

  BodyLayoutBuilderInfo(this.columnSizes);

  void add(List<GridPlacement> gridPlacement, {required int lastIdx}) {
    gridPlacements.add(gridPlacement);
    this.lastIdx = lastIdx;
  }
}

class LayoutBuilderInfo {
  int? lastIdx;
  int? lastBodyIdx;
  int? lastHeaderIdx;
  final List<TrackSize> headerColumnSizes;
  final List<TrackSize> bodyColumnSizes;
  final List<HeaderLayoutBuilderInfo?> headersLayoutBuilderInfo = [];
  final List<BodyLayoutBuilderInfo?> bodiesLayoutBuilderInfo = [];

  LayoutBuilderInfo(this.headerColumnSizes, this.bodyColumnSizes);

  void add(HeaderLayoutBuilderInfo? headerLayoutBuilderInfo, BodyLayoutBuilderInfo? bodyLayoutBuilderInfo) {
    headersLayoutBuilderInfo.add(headerLayoutBuilderInfo);
    bodiesLayoutBuilderInfo.add(bodyLayoutBuilderInfo);
    lastHeaderIdx = headerLayoutBuilderInfo?.gridPlacements.lastOrNull?.rowStart;
    lastBodyIdx = bodyLayoutBuilderInfo?.gridPlacements.lastOrNull?.lastOrNull?.rowStart;
    lastIdx = max(lastHeaderIdx ?? 0, lastBodyIdx ?? 0);
  }
}

class LayoutInfoToSliverAdapter {
  final List<TrackSize> rowSizes;
  final ScrollGroupSynchronizer _verticalScrollGroupSynchronizer;
  final ScrollGroupSynchronizer _horizontalScrollGroupSynchronizer;

  LayoutInfoToSliverAdapter(this.rowSizes, this._verticalScrollGroupSynchronizer, this._horizontalScrollGroupSynchronizer);

  SliverToBoxAdapter transform(LayoutBuilderInfo layoutBuilderInfo) {
    final List<GridPlacement> headerChildren = [];
    final List<GridPlacement> bodyChildren = [];

    for (var e in layoutBuilderInfo.headersLayoutBuilderInfo) {
      if (e?.gridPlacements != null) {
        headerChildren.addAll(e!.gridPlacements);
      }
    }

    final headerLayoutGrid = LayoutGrid(
      columnSizes: layoutBuilderInfo.headerColumnSizes,
      rowSizes: rowSizes,
      children: headerChildren,
    );
    LayoutGrid? bodyLayoutGrid;
    if (layoutBuilderInfo.bodyColumnSizes.isNotEmpty) {
      for (var e in layoutBuilderInfo.bodiesLayoutBuilderInfo) {
        if (e?.gridPlacements != null) {
          for (var gridPlacementList in e!.gridPlacements) {
            bodyChildren.addAll(gridPlacementList);
          }
        }
      }
      bodyLayoutGrid = LayoutGrid(
        columnSizes: layoutBuilderInfo.bodyColumnSizes,
        rowSizes: rowSizes,
        children: bodyChildren,
      );
    }

    final bodyVerticalController = ScrollController();
    final bodyHorizontalController = ScrollController();
    _verticalScrollGroupSynchronizer.addController(bodyVerticalController);
    _horizontalScrollGroupSynchronizer.addController(bodyHorizontalController);

    if (layoutBuilderInfo.bodyColumnSizes.isNotEmpty) {
      final stickyColumnVerticalController = ScrollController();
      final stickyColumnHorizontalController = ScrollController();
      _verticalScrollGroupSynchronizer.addController(stickyColumnVerticalController);
      _horizontalScrollGroupSynchronizer.addController(stickyColumnHorizontalController);

      final sliver = SliverToBoxAdapter(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SingleChildScrollView(
              controller: stickyColumnVerticalController,
              scrollDirection: Axis.vertical,
              physics: const ClampingScrollPhysics(),
              child: headerLayoutGrid,
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: bodyVerticalController,
                scrollDirection: Axis.vertical,
                physics: const ClampingScrollPhysics(),
                child: SingleChildScrollView(
                    controller: bodyHorizontalController, scrollDirection: Axis.horizontal, physics: const ClampingScrollPhysics(), child: bodyLayoutGrid),
              ),
            ),
          ],
        ),
      );
      return sliver;
    } else {
      /// For full spannable headers
      final sliver = SliverToBoxAdapter(
        child: SingleChildScrollView(
          controller: bodyHorizontalController,
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SingleChildScrollView(
                controller: bodyVerticalController, scrollDirection: Axis.vertical, physics: const ClampingScrollPhysics(), child: headerLayoutGrid),
          ]),
        ),
      );
      return sliver;
    }
  }
}
