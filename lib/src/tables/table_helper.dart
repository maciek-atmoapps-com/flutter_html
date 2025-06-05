import 'package:flutter/material.dart';

import '../../flutter_html.dart';

class TableHelper {
  Alignment getCellAlignment(TableCellElement cell, TextDirection alignment) {
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


  List<double> getColWidths(List<StyledElement> children) {
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
}

class WidthInfo {
  double width = 0;
  double requiredWidth = 0;
  bool join = false;
}
