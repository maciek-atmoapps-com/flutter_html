import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/src/tables/fixed_headers/model/builder_info.dart';
import 'package:flutter_html/src/tables/fixed_headers/scroll_group_synchronizer.dart';
import 'package:flutter_layout_grid/flutter_layout_grid.dart';

import '../../../../flutter_html.dart';
import '../table_helper.dart';
import 'adapters/layout_info_to_sliver_adapter.dart';

class FixedHeadersTableWidget extends StatefulWidget {
  final TableElement table;
  final Map<StyledElement, InlineSpan> parsedCells;
  final ExtensionContext context;
  final double width;
  final bool shrinkWrap;
  final TableHelper _tableHelper;

  const FixedHeadersTableWidget(
      {super.key,
      required this.table,
      required this.parsedCells,
      required this.context,
      required this.width,
      required this.shrinkWrap,
      required TableHelper tableHelper})
      : _tableHelper = tableHelper;

  @override
  State<FixedHeadersTableWidget> createState() => _FixedHeadersTableWidgetState();
}

class _FixedHeadersTableWidgetState extends State<FixedHeadersTableWidget> {
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
    if (!mounted) return;
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
  void didUpdateWidget(covariant FixedHeadersTableWidget oldWidget) {
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
    final minWidths = widget._tableHelper.getColWidths(widget.table.tableStructure);
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

    /// Collect build info to rebuild widget with different height
    List<GridPlacementBuildInfo> headersColumnBuildInfoElements = [];
    List<GridPlacementBuildInfo> bodyCellsBuildInfoElements = [];
    late GridPlacementBuildInfo cornerBuildInfoElement;
    List<GridPlacementBuildInfo> headerRowBuildInfoElements = [];

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
            cornerBuildInfoElement = GridPlacementBuildInfo(columni, child, columnMax, rowi, rows, row);
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
            final gridBuildInfo = GridPlacementBuildInfo(columni - 1, child, columnMax, rowi, rows, row);
            headerRowBuildInfoElements.add(gridBuildInfo);
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

    // If not measured yet, render whole view to calculate height
    if (!_isMeasured) {
      // Prepare data for render offstage (invisible view) to calculate its height.
      List<Widget> intrinsicHeightRowsList = _prepareIntrinsicHeightRowsList(finalColumnSizes, rowSizes, bodyCells, headersColumnGridPlacement);

      // Header row is the first row of table. It will be sticky.
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

    final calculatedHeaderRowContent = _recreateHeaderRowContent(cornerBuildInfoElement, headerRowBuildInfoElements, finalColumnSizes, cellWidths, rowSizes);

    // Initialize values before long for loop
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
      final headerNotNullSpan = headerColumnSpan ?? 0;
      if (bodyCellsI.isNotEmpty) {
        final headerColumnSize = bodyCellsI.fold<int>(0, (previousValue, element) {
          final columnSpan = getColumnSpan(element.child, columnMax, element.columni) ?? 0;
          return previousValue + columnSpan;
        });
        bodyColumnSizes = finalColumnSizes.sublist(headerNotNullSpan, headerColumnSize + headerNotNullSpan);
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
      HeaderLayoutBuilderInfo? matchingHeaderLayoutBuilderInfo;
      if (headerColumnI != null) {
        //if it is differentLayout we start from index 0
        //else we get lastHeaderIndex
        final rowi = isDifferentLayout ? 0 : (layoutBuilderInfoList.last.lastHeaderIdx ?? 0) + 1;
        final headerGridPlacement = buildGridPlacement(
            headerColumnI.columni, headerColumnI.child, headerColumnI.columnMax, rowi, headerColumnI.rows, headerColumnI.row,
            height: _calculatedFullRowIntrinsicHeightList[i]);
        headerColumnSizes = finalColumnSizes.sublist(0, headerColumnSpan);
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
        //if it is differentLayout we start from index 0
        //else we get last body index
        final rowi = isDifferentLayout ? 0 : (layoutBuilderInfoList.last.lastBodyIdx ?? 0) + 1;
        final cellGridPlacement = buildGridPlacement(e.columni, e.child, e.columnMax, rowi, e.rows, e.row, height: _calculatedFullRowIntrinsicHeightList[i]);
        cellsFixedSizeRowElements.add(cellGridPlacement);
      }

      matchingBodyLayoutBuilderInfo = bodyLayoutGrids.where((e) => e.lastIdx == (i - 1) && e.columnSizes == bodyColumnSizes).firstOrNull;
      if (matchingBodyLayoutBuilderInfo != null) {
        matchingBodyLayoutBuilderInfo.add(cellsFixedSizeRowElements, lastIdx: i);
      } else {
        matchingBodyLayoutBuilderInfo = BodyLayoutBuilderInfo(bodyColumnSizes)..add(cellsFixedSizeRowElements, lastIdx: i);
        bodyLayoutGrids.add(matchingBodyLayoutBuilderInfo);
      }

      /// Add to layoutBuilderInfoList
      if (isDifferentLayout) {
        final layoutBuilderInfo = LayoutBuilderInfo(headerColumnSizes, bodyColumnSizes);
        layoutBuilderInfo.add(matchingHeaderLayoutBuilderInfo, matchingBodyLayoutBuilderInfo);
        layoutBuilderInfoList.add(layoutBuilderInfo);
      } else {
        layoutBuilderInfoList.last.add(matchingHeaderLayoutBuilderInfo, matchingBodyLayoutBuilderInfo);
      }
    }

    final layoutToSliverAdapter = LayoutInfoToSliverAdapter(rowSizes, _verticalScrollGroupSynchronizer, _horizontalScrollGroupSynchronizer);
    final sliverToBoxAdapterList = layoutBuilderInfoList.map((e) => layoutToSliverAdapter.transform(e)).toList(growable: false);

    return SizedBox(
      height: MediaQuery.of(context).size.height - 150,
      child: CustomScrollView(
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _MySliverPersistentRowHeaderDelegate(
                minHeight: _calculatedHeaderHeight!, maxHeight: _calculatedHeaderHeight!, child: calculatedHeaderRowContent),
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
                alignment: widget._tableHelper.getCellAlignment(child, alignment),
                child: CssBoxWidget.withInlineSpanChildren(
                  children: [widget.parsedCells[child] ?? const TextSpan(text: "error")],
                  style: Style(),
                ),
              ),
            );
          } else {
            return Container(
                height: height,
                alignment: widget._tableHelper.getCellAlignment(child, alignment),
                child: CssBoxWidget.withInlineSpanChildren(
                  children: [widget.parsedCells[child] ?? const TextSpan(text: "error")],
                  style: Style(),
                ),
            );
          }
        }),
      ),
    );
  }

  bool hasSameColumnSize(
      List<TrackSize> headerColumnSizes, List<TrackSize> headerColumnSizes2, List<TrackSize> bodyColumnSizes, List<TrackSize> bodyColumnSizes2) {
    const eq = ListEquality();
    return eq.equals(headerColumnSizes, headerColumnSizes2) && eq.equals(bodyColumnSizes, bodyColumnSizes2);
  }

  IntrinsicHeight _recreateHeaderRowContent(GridPlacementBuildInfo cornerBuildInfoElement, List<GridPlacementBuildInfo> headerRowBuildInfoElements,
      List<TrackSize> columnSizes, List<double> cellWidths, List<IntrinsicContentTrackSize> rowSizes) {
    final cornerLayoutGrid = LayoutGrid(
      columnSizes: [FixedTrackSize(cellWidths[cornerBuildInfoElement.columni])],
      rowSizes: [FixedTrackSize(_calculatedHeaderHeight ?? 0.0)],
      children: [
        buildGridPlacement(cornerBuildInfoElement.columni, cornerBuildInfoElement.child, cornerBuildInfoElement.columnMax, cornerBuildInfoElement.rowi,
            cornerBuildInfoElement.rows, cornerBuildInfoElement.row,height: _calculatedHeaderHeight)
      ],
    );
    final headerRowLayoutGrid = LayoutGrid(
        gridFit: GridFit.passthrough,
        columnSizes: columnSizes.sublist(1),
        rowSizes: rowSizes.map((e) => FixedTrackSize(_calculatedHeaderHeight ?? 0.0)).toList(growable: false),
        children: headerRowBuildInfoElements
            .map((e) => buildGridPlacement(e.columni, e.child, e.columnMax, e.rowi, e.rows, e.row, height: _calculatedHeaderHeight))
            .toList(growable: false));

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: (columnSizes[0] as FixedTrackSize).sizeInPx, child: cornerLayoutGrid),
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
    return SizedBox.expand(child: child);
  }

  @override
  bool shouldRebuild(_MySliverPersistentRowHeaderDelegate oldDelegate) {
    return maxHeight != oldDelegate.maxHeight || minHeight != oldDelegate.minHeight || child != oldDelegate.child;
  }
}
