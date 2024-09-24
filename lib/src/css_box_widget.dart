import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_html/src/render_paragraph.dart';

class CssBoxWidget extends StatelessWidget {
  const CssBoxWidget({
    super.key,
    required this.child,
    required this.style,
    this.textDirection,
    this.childIsReplaced = false,
    this.shrinkWrap = false,
    this.top = false,
  });

  /// Generates a CSSBoxWidget that contains a list of InlineSpan children.
  CssBoxWidget.withInlineSpanChildren({
    super.key,
    required List<InlineSpan> children,
    required this.style,
    this.textDirection,
    this.childIsReplaced = false,
    this.shrinkWrap = false,
    this.top = false,
  }) : child = _generateWidgetChild(children, style);

  /// The child to be rendered within the CSS Box.
  final Widget child;

  /// The style to use to compute this box's margins/padding/box decoration/width/height/etc.
  ///
  /// Note that this style will only apply to this box, and will not cascade to its child.
  final Style style;

  /// Sets the direction the text of this widget should flow. If unset or null,
  /// the nearest Directionality ancestor is used as a default. If that cannot
  /// be found, this Widget's renderer will raise an assertion.
  final TextDirection? textDirection;

  /// Indicates whether this child is a replaced element that manages its own width
  /// (e.g. img, video, iframe, audio, etc.)
  final bool childIsReplaced;

  /// Whether or not the content should ignore auto horizontal margins and not
  /// necessarily take up the full available width unless necessary
  final bool shrinkWrap;

  /// For the root widget, so textScaleFactor, etc are only applied once
  final bool top;

  @override
  Widget build(BuildContext context) {
    final markerBox = style.listStylePosition == ListStylePosition.outside
        ? _generateMarkerBoxSpan(style)
        : null;

    final direction = _checkTextDirection(context, textDirection);
    final padding = style.padding?.resolve(direction);

    return _CSSBoxRenderer(
      width: style.width ?? Width.auto(),
      height: style.height ?? Height.auto(),
      paddingSize: padding?.collapsedSize ?? Size.zero,
      borderSize: style.border?.dimensions.collapsedSize ?? Size.zero,
      margins: style.margin ?? Margins.zero,
      display: style.display ?? Display.inline,
      childIsReplaced: childIsReplaced,
      emValue: _calculateEmValue(style, context),
      textDirection: direction,
      shrinkWrap: shrinkWrap,
      children: [
        Container(
          decoration: BoxDecoration(
            border: style.border,
            color: style.backgroundColor, //Colors the padding and content boxes
          ),
          width: _shouldExpandToFillBlock() ? double.infinity : null,
          padding: padding,
          child: top
              ? child
              : MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaleFactor: 1.0),
                  child: child,
                ),
        ),
        if (markerBox != null) ClickableRichText(text: markerBox),
      ],
    );
  }

  /// Takes a list of InlineSpan children and generates a RichText Widget
  /// containing those children.
  static Widget _generateWidgetChild(List<InlineSpan> children, Style style) {
    if (children.isEmpty) {
      return Container();
    }

    // Generate an inline marker box if the list-style-position is set to
    // inside. Otherwise the marker box will be added elsewhere.
    if (style.listStylePosition == ListStylePosition.inside) {
      final inlineMarkerBox = _generateMarkerBoxSpan(style);
      if (inlineMarkerBox != null) {
        children.insert(0, inlineMarkerBox);
      }
    }

    return ClickableRichText(
      text: TextSpan(
        style: style.generateTextStyle().copyWith(background: Paint()..color = Colors.yellow),
        children: children,
      ),
      textAlign: style.textAlign ?? TextAlign.start,
      textDirection: style.direction,
      maxLines: style.maxLines,
      overflow: style.textOverflow ?? TextOverflow.clip,
    );
  }

  static InlineSpan? _generateMarkerBoxSpan(Style style) {
    if (style.display == Display.listItem) {
      // First handle listStyleImage
      if (style.listStyleImage != null) {
        return WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Image.network(
            style.listStyleImage!.uriText,
            errorBuilder: (_, __, ___) {
              if (style.marker?.content.replacementContent?.isNotEmpty ??
                  false) {
                return ClickableRichText(
                  text: TextSpan(
                    text: style.marker!.content.replacementContent!,
                    style: style.marker!.style?.generateTextStyle().copyWith(background: Paint()..color = Colors.green),
                  ),
                );
              }

              return Container();
            },
          ),
        );
      }

      // Display list marker with given style
      if (style.marker?.content.replacementContent?.isNotEmpty ?? false) {
        return TextSpan(
          text: style.marker!.content.replacementContent!,
          style: style.marker!.style?.generateTextStyle().copyWith(background: Paint()..color = Colors.red),
        );
      }
    }

    return null;
  }

  /// Whether or not the content-box should expand its width to fill the
  /// width available to it or if it should just let its inner content
  /// determine the content-box's width.
  bool _shouldExpandToFillBlock() {
    return (style.display == Display.block ||
            style.display == Display.listItem) &&
        !childIsReplaced &&
        !shrinkWrap;
  }

  TextDirection _checkTextDirection(
      BuildContext context, TextDirection? direction) {
    final textDirection = direction ?? Directionality.maybeOf(context);

    assert(
      textDirection != null,
      "CSSBoxWidget needs either a Directionality ancestor or a provided textDirection",
    );

    return textDirection!;
  }
}

class _CSSBoxRenderer extends MultiChildRenderObjectWidget {
  _CSSBoxRenderer({
    Key? key,
    required super.children,
    required this.display,
    required this.margins,
    required this.width,
    required this.height,
    required this.borderSize,
    required this.paddingSize,
    required this.textDirection,
    required this.childIsReplaced,
    required this.emValue,
    required this.shrinkWrap,
  }) : super(key: key);

  /// The Display type of the element
  final Display display;

  /// The computed margin values for this element
  final Margins margins;

  /// The width of the element
  final Width width;

  /// The height of the element
  final Height height;

  /// The collapsed size of the element's border
  final Size borderSize;

  /// The collapsed size of the element's padding
  final Size paddingSize;

  /// The direction for this widget's text to flow.
  final TextDirection textDirection;

  /// Whether or not the child being rendered is a replaced element
  /// (this changes the rules for rendering)
  final bool childIsReplaced;

  /// The calculated size of 1em in pixels
  final double emValue;

  /// Whether or not this container should shrinkWrap its contents.
  /// (see definition on [CSSBoxWidget])
  final bool shrinkWrap;

  @override
  RenderCSSBox createRenderObject(BuildContext context) {
    return RenderCSSBox(
      display: display,
      width: width..normalize(emValue),
      height: height..normalize(emValue),
      margins: _preProcessMargins(margins, shrinkWrap),
      borderSize: borderSize,
      paddingSize: paddingSize,
      textDirection: textDirection,
      childIsReplaced: childIsReplaced,
      shrinkWrap: shrinkWrap,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderCSSBox renderObject) {
    renderObject
      ..display = display
      ..width = (width..normalize(emValue))
      ..height = (height..normalize(emValue))
      ..margins = _preProcessMargins(margins, shrinkWrap)
      ..borderSize = borderSize
      ..paddingSize = paddingSize
      ..textDirection = textDirection
      ..childIsReplaced = childIsReplaced
      ..shrinkWrap = shrinkWrap;
  }

  Margins _preProcessMargins(Margins margins, bool shrinkWrap) {
    late Margin leftMargin;
    late Margin rightMargin;
    Margin topMargin = margins.top ?? margins.blockStart ?? Margin.zero();
    Margin bottomMargin = margins.bottom ?? margins.blockEnd ?? Margin.zero();

    switch (textDirection) {
      case TextDirection.rtl:
        leftMargin = margins.left ?? margins.inlineEnd ?? Margin.zero();
        rightMargin = margins.right ?? margins.inlineStart ?? Margin.zero();
        break;
      case TextDirection.ltr:
        leftMargin = margins.left ?? margins.inlineStart ?? Margin.zero();
        rightMargin = margins.right ?? margins.inlineEnd ?? Margin.zero();
        break;
    }

    //Preprocess margins to a pixel value
    leftMargin.normalize(emValue);
    rightMargin.normalize(emValue);
    topMargin.normalize(emValue);
    bottomMargin.normalize(emValue);

    // See https://drafts.csswg.org/css2/#inline-width
    // and https://drafts.csswg.org/css2/#inline-replaced-width
    // and https://drafts.csswg.org/css2/#inlineblock-width
    // and https://drafts.csswg.org/css2/#inlineblock-replaced-width
    if (display == Display.inline || display == Display.inlineBlock) {
      if (margins.left?.unit == Unit.auto) {
        leftMargin = Margin.zero();
      }
      if (margins.right?.unit == Unit.auto) {
        rightMargin = Margin.zero();
      }
    }

    //Shrink-wrap margins if applicable
    if (shrinkWrap && leftMargin.unit == Unit.auto) {
      leftMargin = Margin.zero();
    }

    if (shrinkWrap && rightMargin.unit == Unit.auto) {
      rightMargin = Margin.zero();
    }

    return Margins(
      top: topMargin,
      right: rightMargin,
      bottom: bottomMargin,
      left: leftMargin,
    );
  }
}

@visibleForTesting

/// Implements the CSS layout algorithm
class RenderCSSBox extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, CSSBoxParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, CSSBoxParentData> {
  RenderCSSBox({
    required Display display,
    required Width width,
    required Height height,
    required Margins margins,
    required Size borderSize,
    required Size paddingSize,
    required TextDirection textDirection,
    required bool childIsReplaced,
    required bool shrinkWrap,
  })  : _display = display,
        _width = width,
        _height = height,
        _margins = margins,
        _borderSize = borderSize,
        _paddingSize = paddingSize,
        _textDirection = textDirection,
        _childIsReplaced = childIsReplaced,
        _shrinkWrap = shrinkWrap;

  Display _display;

  Display get display => _display;

  set display(Display display) {
    _display = display;
    markNeedsLayout();
  }

  Width _width;

  Width get width => _width;

  set width(Width width) {
    _width = width;
    markNeedsLayout();
  }

  Height _height;

  Height get height => _height;

  set height(Height height) {
    _height = height;
    markNeedsLayout();
  }

  Margins _margins;

  Margins get margins => _margins;

  set margins(Margins margins) {
    _margins = margins;
    markNeedsLayout();
  }

  Size _borderSize;

  Size get borderSize => _borderSize;

  set borderSize(Size size) {
    _borderSize = size;
    markNeedsLayout();
  }

  Size _paddingSize;

  Size get paddingSize => _paddingSize;

  set paddingSize(Size size) {
    _paddingSize = size;
    markNeedsLayout();
  }

  TextDirection _textDirection;

  TextDirection get textDirection => _textDirection;

  set textDirection(TextDirection textDirection) {
    _textDirection = textDirection;
    markNeedsLayout();
  }

  bool _childIsReplaced;

  bool get childIsReplaced => _childIsReplaced;

  set childIsReplaced(bool childIsReplaced) {
    _childIsReplaced = childIsReplaced;
    markNeedsLayout();
  }

  bool _shrinkWrap;

  bool get shrinkWrap => _shrinkWrap;

  set shrinkWrap(bool shrinkWrap) {
    _shrinkWrap = shrinkWrap;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! CSSBoxParentData) {
      child.parentData = CSSBoxParentData();
    }
  }

  static double getIntrinsicDimension(RenderBox? firstChild,
      double Function(RenderBox child) mainChildSizeGetter) {
    double extent = 0.0;
    RenderBox? child = firstChild;
    while (child != null) {
      final CSSBoxParentData childParentData =
          child.parentData! as CSSBoxParentData;
      extent = math.max(extent, mainChildSizeGetter(child));
      assert(child.parentData == childParentData);
      child = childParentData.nextSibling;
    }
    return extent;
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    return getIntrinsicDimension(
        firstChild, (RenderBox child) => child.getMinIntrinsicWidth(height));
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    return getIntrinsicDimension(
        firstChild, (RenderBox child) => child.getMaxIntrinsicWidth(height));
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    return getIntrinsicDimension(
        firstChild, (RenderBox child) => child.getMinIntrinsicHeight(width));
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    return getIntrinsicDimension(
        firstChild, (RenderBox child) => child.getMaxIntrinsicHeight(width));
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    return firstChild?.getDistanceToActualBaseline(baseline);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    return _computeSize(
      constraints: constraints,
      layoutChild: ChildLayoutHelper.dryLayoutChild,
    ).parentSize;
  }

  _Sizes _computeSize(
      {required BoxConstraints constraints,
      required ChildLayouter layoutChild}) {
    if (childCount == 0) {
      return _Sizes(constraints.biggest, Size.zero);
    }

    Size containingBlockSize = constraints.biggest;
    double width = containingBlockSize.width;
    double height = containingBlockSize.height;

    assert(firstChild != null);
    RenderBox child = firstChild!;

    final CSSBoxParentData parentData = child.parentData! as CSSBoxParentData;
    RenderBox? markerBoxChild = parentData.nextSibling;

    // Calculate child size
    final childConstraints = constraints.copyWith(
      maxWidth: (this.width.unit != Unit.auto)
          ? this.width.value
          : containingBlockSize.width -
              (margins.left?.value ?? 0) -
              (margins.right?.value ?? 0),
      maxHeight: (this.height.unit != Unit.auto)
          ? this.height.value
          : containingBlockSize.height -
              (margins.top?.value ?? 0) -
              (margins.bottom?.value ?? 0),
      minWidth: (this.width.unit != Unit.auto) ? this.width.value : 0,
      minHeight: (this.height.unit != Unit.auto) ? this.height.value : 0,
    );
    final Size childSize = layoutChild(child, childConstraints);
    if (markerBoxChild != null) {
      layoutChild(markerBoxChild, childConstraints);
    }

    // Calculate used values of margins based on rules
    final usedMargins = _calculateUsedMargins(childSize, containingBlockSize);
    final horizontalMargins =
        (usedMargins.left?.value ?? 0) + (usedMargins.right?.value ?? 0);
    final verticalMargins =
        (usedMargins.top?.value ?? 0) + (usedMargins.bottom?.value ?? 0);

    //Calculate Width and Height of CSS Box
    height = childSize.height;
    switch (display) {
      case Display.block:
        width = (shrinkWrap || childIsReplaced)
            ? childSize.width + horizontalMargins
            : containingBlockSize.width;
        height = childSize.height + verticalMargins;
        break;
      case Display.inline:
        width = childSize.width + horizontalMargins;
        height = childSize.height;
        break;
      case Display.inlineBlock:
        width = childSize.width + horizontalMargins;
        height = childSize.height + verticalMargins;
        break;
      case Display.listItem:
        width = shrinkWrap
            ? childSize.width + horizontalMargins
            : containingBlockSize.width;
        height = childSize.height + verticalMargins;
        break;
      case Display.none:
        width = 0;
        height = 0;
        break;
    }

    return _Sizes(constraints.constrain(Size(width, height)), childSize);
  }

  @override
  void performLayout() {
    final BoxConstraints constraints = this.constraints;

    final sizes = _computeSize(
      constraints: constraints,
      layoutChild: ChildLayoutHelper.layoutChild,
    );
    size = sizes.parentSize;

    assert(firstChild != null);
    RenderBox child = firstChild!;

    final CSSBoxParentData childParentData =
        child.parentData! as CSSBoxParentData;

    // Calculate used margins based on constraints and child size
    final usedMargins =
        _calculateUsedMargins(sizes.childSize, constraints.biggest);
    final leftMargin = usedMargins.left?.value ?? 0;
    final topMargin = usedMargins.top?.value ?? 0;

    double leftOffset = 0;
    double topOffset = 0;
    switch (display) {
      case Display.block:
        leftOffset = leftMargin;
        topOffset = topMargin;
        break;
      case Display.inline:
        leftOffset = leftMargin;
        break;
      case Display.inlineBlock:
        leftOffset = leftMargin;
        topOffset = topMargin;
        break;
      case Display.listItem:
        leftOffset = leftMargin;
        topOffset = topMargin;
        break;
      case Display.none:
        //No offset
        break;
    }
    childParentData.offset = Offset(leftOffset, topOffset);
    assert(child.parentData == childParentData);

    // Now, layout the marker box if it exists:
    RenderBox? markerBox = childParentData.nextSibling;
    if (markerBox != null) {
      final markerBoxParentData = markerBox.parentData! as CSSBoxParentData;
      final distance = (child.getDistanceToBaseline(TextBaseline.alphabetic,
                  onlyReal: true) ??
              0) +
          topOffset;
      final offsetHeight = distance -
          (markerBox.getDistanceToBaseline(TextBaseline.alphabetic) ??
              markerBox.size.height);
      switch (_textDirection) {
        case TextDirection.rtl:
          markerBoxParentData.offset = Offset(
            child.size.width,
            offsetHeight,
          );
          break;
        case TextDirection.ltr:
          markerBoxParentData.offset = Offset(
            -markerBox.size.width,
            offsetHeight,
          );
          break;
      }
    }
  }

  Margins _calculateUsedMargins(Size childSize, Size containingBlockSize) {
    //We assume that margins have already been preprocessed
    // (i.e. they are non-null and either px units or auto.
    assert(margins.left != null && margins.right != null);
    assert(margins.left!.unit == Unit.px || margins.left!.unit == Unit.auto);
    assert(margins.right!.unit == Unit.px || margins.right!.unit == Unit.auto);

    Margin marginLeft = margins.left!;
    Margin marginRight = margins.right!;

    bool widthIsAuto = width.unit == Unit.auto;
    bool marginLeftIsAuto = marginLeft.unit == Unit.auto;
    bool marginRightIsAuto = marginRight.unit == Unit.auto;

    if (display == Display.block) {
      if (childIsReplaced) {
        widthIsAuto = false;
      }

      if (shrinkWrap) {
        widthIsAuto = false;
      }

      //If width is not auto and the width of the margin box is larger than the
      // width of the containing block, then consider left and right margins to
      // have a 0 value.
      if (!widthIsAuto) {
        if ((childSize.width + marginLeft.value + marginRight.value) >
            containingBlockSize.width) {
          //Treat auto values of margin left and margin right as 0 for following rules
          marginLeft = Margin(0);
          marginRight = Margin(0);
          marginLeftIsAuto = false;
          marginRightIsAuto = false;
        }
      }

      // If all values are non-auto, the box is overconstrained.
      // One of the margins will need to be adjusted so that the
      // entire width of the containing block is used.
      if (!widthIsAuto &&
          !marginLeftIsAuto &&
          !marginRightIsAuto &&
          !shrinkWrap &&
          !childIsReplaced) {
        //Ignore either left or right margin based on textDirection.

        switch (textDirection) {
          case TextDirection.rtl:
            final difference =
                containingBlockSize.width - childSize.width - marginRight.value;
            marginLeft = Margin(difference);
            break;
          case TextDirection.ltr:
            final difference =
                containingBlockSize.width - childSize.width - marginLeft.value;
            marginRight = Margin(difference);
            break;
        }
      }

      // If there is exactly one value specified as auto, compute it value from the equality (our widths are already set)
      if (widthIsAuto && !marginLeftIsAuto && !marginRightIsAuto) {
        widthIsAuto = false;
      } else if (!widthIsAuto && marginLeftIsAuto && !marginRightIsAuto) {
        marginLeft = Margin(
            containingBlockSize.width - childSize.width - marginRight.value);
        marginLeftIsAuto = false;
      } else if (!widthIsAuto && !marginLeftIsAuto && marginRightIsAuto) {
        marginRight = Margin(
            containingBlockSize.width - childSize.width - marginLeft.value);
        marginRightIsAuto = false;
      }

      //If width is set to auto, any other auto values become 0, and width
      // follows from the resulting equality.
      if (widthIsAuto) {
        if (marginLeftIsAuto) {
          marginLeft = Margin(0);
          marginLeftIsAuto = false;
        }
        if (marginRightIsAuto) {
          marginRight = Margin(0);
          marginRightIsAuto = false;
        }
        widthIsAuto = false;
      }

      //If both margin-left and margin-right are auto, their used values are equal.
      // This horizontally centers the element within the containing block.
      if (marginLeftIsAuto && marginRightIsAuto) {
        final newMargin =
            Margin((containingBlockSize.width - childSize.width) / 2);
        marginLeft = newMargin;
        marginRight = newMargin;
        marginLeftIsAuto = false;
        marginRightIsAuto = false;
      }

      //Assert that all auto values have been assigned.
      assert(!marginLeftIsAuto && !marginRightIsAuto && !widthIsAuto);
    }

    return Margins(
      left: marginLeft,
      right: marginRight,
      top: margins.top,
      bottom: margins.bottom,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }
}

extension Normalize on Dimension {
  void normalize(double emValue) {
    switch (unit) {
      case Unit.rem:
      // Because CSSBoxWidget doesn't have any information about any
      // sort of tree structure, treat rem the same as em. The HtmlParser
      // widget handles rem/em values before they get to CSSBoxWidget.
      case Unit.em:
        value *= emValue;
        unit = Unit.px;
        return;
      case Unit.px:
      case Unit.auto:
      case Unit.percent:
        return;
    }
  }
}

double _calculateEmValue(Style style, BuildContext buildContext) {
  return (style.fontSize?.emValue ?? 16) *
      MediaQuery.textScaleFactorOf(buildContext) *
      MediaQuery.of(buildContext).devicePixelRatio;
}

class CSSBoxParentData extends ContainerBoxParentData<RenderBox> {}

class _Sizes {
  final Size parentSize;
  final Size childSize;

  const _Sizes(this.parentSize, this.childSize);
}

class ClickableRichText extends MultiChildRenderObjectWidget {
  /// Creates a paragraph of rich text.
  ///
  /// The [maxLines] property may be null (and indeed defaults to null), but if
  /// it is not null, it must be greater than zero.
  ///
  /// The [textDirection], if null, defaults to the ambient [Directionality],
  /// which in that case must not be null.
  ClickableRichText({
    super.key,
    required this.text,
    this.textAlign = TextAlign.start,
    this.textDirection,
    this.softWrap = true,
    this.overflow = TextOverflow.clip,
    @Deprecated(
      'Use textScaler instead. '
      'Use of textScaleFactor was deprecated in preparation for the upcoming nonlinear text scaling support. '
      'This feature was deprecated after v3.12.0-2.0.pre.',
    )
    double textScaleFactor = 1.0,
    TextScaler textScaler = TextScaler.noScaling,
    this.maxLines,
    this.locale,
    this.strutStyle,
    this.textWidthBasis = TextWidthBasis.parent,
    this.textHeightBehavior,
    this.selectionRegistrar,
    this.selectionColor,
  })  : assert(maxLines == null || maxLines > 0),
        assert(selectionRegistrar == null || selectionColor != null),
        assert(textScaleFactor == 1.0 || identical(textScaler, TextScaler.noScaling), 'Use textScaler instead.'),
        textScaler = _effectiveTextScalerFrom(textScaler, textScaleFactor),
        super(children: WidgetSpan.extractFromInlineSpan(text, _effectiveTextScalerFrom(textScaler, textScaleFactor)));

  static TextScaler _effectiveTextScalerFrom(TextScaler textScaler, double textScaleFactor) {
    return switch ((textScaler, textScaleFactor)) {
      (final TextScaler scaler, 1.0) => scaler,
      (TextScaler.noScaling, final double textScaleFactor) => TextScaler.linear(textScaleFactor),
      (final TextScaler scaler, _) => scaler,
    };
  }

  /// The text to display in this widget.
  final InlineSpan text;

  /// How the text should be aligned horizontally.
  final TextAlign textAlign;

  /// The directionality of the text.
  ///
  /// This decides how [textAlign] values like [TextAlign.start] and
  /// [TextAlign.end] are interpreted.
  ///
  /// This is also used to disambiguate how to render bidirectional text. For
  /// example, if the [text] is an English phrase followed by a Hebrew phrase,
  /// in a [TextDirection.ltr] context the English phrase will be on the left
  /// and the Hebrew phrase to its right, while in a [TextDirection.rtl]
  /// context, the English phrase will be on the right and the Hebrew phrase on
  /// its left.
  ///
  /// Defaults to the ambient [Directionality], if any. If there is no ambient
  /// [Directionality], then this must not be null.
  final TextDirection? textDirection;

  /// Whether the text should break at soft line breaks.
  ///
  /// If false, the glyphs in the text will be positioned as if there was unlimited horizontal space.
  final bool softWrap;

  /// How visual overflow should be handled.
  final TextOverflow overflow;

  /// Deprecated. Will be removed in a future version of Flutter. Use
  /// [textScaler] instead.
  ///
  /// The number of font pixels for each logical pixel.
  ///
  /// For example, if the text scale factor is 1.5, text will be 50% larger than
  /// the specified font size.
  @Deprecated(
    'Use textScaler instead. '
    'Use of textScaleFactor was deprecated in preparation for the upcoming nonlinear text scaling support. '
    'This feature was deprecated after v3.12.0-2.0.pre.',
  )
  double get textScaleFactor => textScaler.textScaleFactor;

  /// {@macro flutter.painting.textPainter.textScaler}
  final TextScaler textScaler;

  /// An optional maximum number of lines for the text to span, wrapping if necessary.
  /// If the text exceeds the given number of lines, it will be truncated according
  /// to [overflow].
  ///
  /// If this is 1, text will not wrap. Otherwise, text will be wrapped at the
  /// edge of the box.
  final int? maxLines;

  /// Used to select a font when the same Unicode character can
  /// be rendered differently, depending on the locale.
  ///
  /// It's rarely necessary to set this property. By default its value
  /// is inherited from the enclosing app with `Localizations.localeOf(context)`.
  ///
  /// See [RenderParagraph.locale] for more information.
  final Locale? locale;

  /// {@macro flutter.painting.textPainter.strutStyle}
  final StrutStyle? strutStyle;

  /// {@macro flutter.painting.textPainter.textWidthBasis}
  final TextWidthBasis textWidthBasis;

  /// {@macro dart.ui.textHeightBehavior}
  final ui.TextHeightBehavior? textHeightBehavior;

  /// The [SelectionRegistrar] this rich text is subscribed to.
  ///
  /// If this is set, [selectionColor] must be non-null.
  final SelectionRegistrar? selectionRegistrar;

  /// The color to use when painting the selection.
  ///
  /// This is ignored if [selectionRegistrar] is null.
  ///
  /// See the section on selections in the [RichText] top-level API
  /// documentation for more details on enabling selection in [RichText]
  /// widgets.
  final Color? selectionColor;

  @override
  ClickableRenderParagraph createRenderObject(BuildContext context) {
    assert(textDirection != null || debugCheckHasDirectionality(context));
    return ClickableRenderParagraph(
      text,
      textAlign: textAlign,
      textDirection: textDirection ?? Directionality.of(context),
      softWrap: softWrap,
      overflow: overflow,
      textScaler: textScaler,
      maxLines: maxLines,
      strutStyle: strutStyle,
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      locale: locale ?? Localizations.maybeLocaleOf(context),
      registrar: selectionRegistrar,
      selectionColor: selectionColor,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderParagraph renderObject) {
    assert(textDirection != null || debugCheckHasDirectionality(context));
    renderObject
      ..text = text
      ..textAlign = textAlign
      ..textDirection = textDirection ?? Directionality.of(context)
      ..softWrap = softWrap
      ..overflow = overflow
      ..textScaler = textScaler
      ..maxLines = maxLines
      ..strutStyle = strutStyle
      ..textWidthBasis = textWidthBasis
      ..textHeightBehavior = textHeightBehavior
      ..locale = locale ?? Localizations.maybeLocaleOf(context)
      ..registrar = selectionRegistrar
      ..selectionColor = selectionColor;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(EnumProperty<TextAlign>('textAlign', textAlign, defaultValue: TextAlign.start));
    properties.add(EnumProperty<TextDirection>('textDirection', textDirection, defaultValue: null));
    properties.add(
        FlagProperty('softWrap', value: softWrap, ifTrue: 'wrapping at box width', ifFalse: 'no wrapping except at line break characters', showName: true));
    properties.add(EnumProperty<TextOverflow>('overflow', overflow, defaultValue: TextOverflow.clip));
    properties.add(DiagnosticsProperty<TextScaler>('textScaler', textScaler, defaultValue: TextScaler.noScaling));
    properties.add(IntProperty('maxLines', maxLines, ifNull: 'unlimited'));
    properties.add(EnumProperty<TextWidthBasis>('textWidthBasis', textWidthBasis, defaultValue: TextWidthBasis.parent));
    properties.add(StringProperty('text', text.toPlainText()));
    properties.add(DiagnosticsProperty<Locale>('locale', locale, defaultValue: null));
    properties.add(DiagnosticsProperty<StrutStyle>('strutStyle', strutStyle, defaultValue: null));
    properties.add(DiagnosticsProperty<TextHeightBehavior>('textHeightBehavior', textHeightBehavior, defaultValue: null));
  }
}