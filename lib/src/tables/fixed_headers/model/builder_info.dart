import 'dart:math';

import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_layout_grid/flutter_layout_grid.dart';

/// Properties that be needed to build GridPlacement
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