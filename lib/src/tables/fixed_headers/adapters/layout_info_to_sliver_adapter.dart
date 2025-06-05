import 'package:flutter/material.dart';
import 'package:flutter_html/src/tables/fixed_headers/model/builder_info.dart';
import 'package:flutter_layout_grid/flutter_layout_grid.dart';

import '../scroll_group_synchronizer.dart';

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