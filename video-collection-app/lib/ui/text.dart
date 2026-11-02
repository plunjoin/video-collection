import 'dart:ui' show Brightness;

import 'package:flutter/gestures.dart' show PointerEvent;
import 'package:flutter/painting.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart' as fw;

import 'layout.dart';
import 'theme.dart';

/// 自研文本组件:[Text]/[DefaultTextStyle]/[RichText]/[SelectableText]。
///
/// 文本排版使用引擎层 TextPainter(painting 层基础设施),段落渲染由自写的
/// [RenderParagraphBox] 完成:软换行、maxLines、ellipsis、textAlign、
/// 继承 DefaultTextStyle。

/// 默认文本样式继承作用域。
class DefaultTextStyle extends fw.InheritedWidget {
  final TextStyle style;
  final int? maxLines;
  final TextOverflow overflow;
  final bool softWrap;
  final TextAlign textAlign;

  const DefaultTextStyle({
    fw.Key? key,
    required this.style,
    this.maxLines,
    this.overflow = TextOverflow.clip,
    this.softWrap = true,
    this.textAlign = TextAlign.start,
    required fw.Widget child,
  }) : super(key: key, child: child);

  static DefaultTextStyle of(fw.BuildContext context) {
    return context
            .getInheritedWidgetOfExactType<DefaultTextStyle>() ??
        const _FallbackDefaultTextStyle();
  }

  /// 与当前作用域合并出新样式并作为新的继承作用域。
  static fw.Widget merge({
    fw.Key? key,
    TextStyle? style,
    int? maxLines,
    TextOverflow? overflow,
    bool? softWrap,
    TextAlign? textAlign,
    required fw.Widget child,
  }) {
    return _DefaultTextStyleMerge(
      key: key,
      style: style,
      maxLines: maxLines,
      overflow: overflow,
      softWrap: softWrap,
      textAlign: textAlign,
      child: child,
    );
  }

  @override
  bool updateShouldNotify(DefaultTextStyle oldWidget) =>
      style != oldWidget.style ||
      maxLines != oldWidget.maxLines ||
      overflow != oldWidget.overflow ||
      softWrap != oldWidget.softWrap ||
      textAlign != oldWidget.textAlign;
}

/// 无作用域时的兜底默认样式(空样式,交给 Text 再从主题取色)。
class _FallbackDefaultTextStyle extends DefaultTextStyle {
  const _FallbackDefaultTextStyle()
      : super(style: const TextStyle(), child: const SizedBox.shrink());
}

class _DefaultTextStyleMerge extends fw.StatelessWidget {
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;
  final TextAlign? textAlign;
  final fw.Widget child;

  const _DefaultTextStyleMerge({
    fw.Key? key,
    this.style,
    this.maxLines,
    this.overflow,
    this.softWrap,
    this.textAlign,
    required this.child,
  }) : super(key: key);

  @override
  fw.Widget build(fw.BuildContext context) {
    final parent = DefaultTextStyle.of(context);
    return DefaultTextStyle(
      style: parent.style.merge(style ?? const TextStyle()),
      maxLines: maxLines ?? parent.maxLines,
      overflow: overflow ?? parent.overflow,
      softWrap: softWrap ?? parent.softWrap,
      textAlign: textAlign ?? parent.textAlign,
      child: child,
    );
  }
}

/// 文本组件(替代 material/widgets 的 Text)。
class Text extends fw.StatelessWidget {
  final String data;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final bool? softWrap;
  final TextScaler? textScaler;
  final String? semanticsLabel;
  final bool? wrapWords;
  final TextHeightBehavior? textHeightBehavior;

  const Text(
    this.data, {
    fw.Key? key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.textDirection,
    this.softWrap,
    this.textScaler,
    this.semanticsLabel,
    this.wrapWords,
    this.textHeightBehavior,
  }) : super(key: key);

  @override
  fw.Widget build(fw.BuildContext context) {
    final theme = Theme.of(context);
    final inherited = DefaultTextStyle.of(context);
    var effective = inherited.style;
    if (style != null) effective = effective.merge(style!);
    if (effective.color == null) {
      effective = effective.copyWith(
        color: theme.brightness == Brightness.dark
            ? const Color(0xFFF9FAFF)
            : const Color(0xFF353B58),
      );
    }
    if (effective.fontFamily == null) {
      effective = effective.copyWith(
        fontFamily: theme.fontFamily,
        fontFamilyFallback: theme.fontFamilyFallback,
      );
    }
    return _StyledText(
      text: data,
      style: effective,
      maxLines: maxLines ?? inherited.maxLines,
      overflow: overflow ?? inherited.overflow,
      textAlign: textAlign ?? inherited.textAlign,
      softWrap: softWrap ?? inherited.softWrap,
      textScaler: textScaler ?? TextScaler.noScaling,
      textDirection: textDirection ?? TextDirection.ltr,
      textHeightBehavior: textHeightBehavior,
      semanticsLabel: semanticsLabel,
    );
  }
}

class _StyledText extends fw.LeafRenderObjectWidget {
  final String text;
  final TextStyle style;
  final int? maxLines;
  final TextOverflow overflow;
  final TextAlign textAlign;
  final bool softWrap;
  final TextScaler textScaler;
  final TextDirection textDirection;
  final TextHeightBehavior? textHeightBehavior;
  final String? semanticsLabel;

  const _StyledText({
    required this.text,
    required this.style,
    required this.maxLines,
    required this.overflow,
    required this.textAlign,
    required this.softWrap,
    required this.textScaler,
    required this.textDirection,
    this.textHeightBehavior,
    this.semanticsLabel,
  });

  @override
  fw.RenderObject createRenderObject(fw.BuildContext context) {
    return RenderParagraphBox(
      text: text,
      style: style,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
      softWrap: softWrap,
      textScaler: textScaler,
      textDirection: textDirection,
      textHeightBehavior: textHeightBehavior,
    );
  }

  @override
  void updateRenderObject(
    fw.BuildContext context,
    covariant RenderParagraphBox renderObject,
  ) {
    renderObject
      ..text = text
      ..style = style
      ..maxLines = maxLines
      ..overflow = overflow
      ..textAlign = textAlign
      ..softWrap = softWrap
      ..textScaler = textScaler
      ..textDirection = textDirection
      ..textHeightBehavior = textHeightBehavior;
  }
}

/// 自写段落渲染盒子:测量与绘制都走 TextPainter。
class RenderParagraphBox extends RenderBox {
  String _text;
  TextStyle _style;
  int? _maxLines;
  TextOverflow _overflow;
  TextAlign _textAlign;
  bool _softWrap;
  TextScaler _textScaler;
  TextDirection _textDirection;
  TextHeightBehavior? _textHeightBehavior;

  TextPainter? _painter;
  bool _needsTextLayout = true;

  RenderParagraphBox({
    required String text,
    required TextStyle style,
    required int? maxLines,
    required TextOverflow overflow,
    required TextAlign textAlign,
    required bool softWrap,
    required TextScaler textScaler,
    required TextDirection textDirection,
    TextHeightBehavior? textHeightBehavior,
  })  : _text = text,
        _style = style,
        _maxLines = maxLines,
        _overflow = overflow,
        _textAlign = textAlign,
        _softWrap = softWrap,
        _textScaler = textScaler,
        _textDirection = textDirection,
        _textHeightBehavior = textHeightBehavior;

  set text(String value) {
    if (_text == value) return;
    _text = value;
    _needsTextLayout = true;
    markNeedsLayout();
  }

  set style(TextStyle value) {
    if (_style == value) return;
    _style = value;
    _needsTextLayout = true;
    markNeedsLayout();
  }

  set maxLines(int? value) {
    if (_maxLines == value) return;
    _maxLines = value;
    _needsTextLayout = true;
    markNeedsLayout();
  }

  set overflow(TextOverflow value) {
    if (_overflow == value) return;
    _overflow = value;
    _needsTextLayout = true;
    markNeedsLayout();
  }

  set textAlign(TextAlign value) {
    if (_textAlign == value) return;
    _textAlign = value;
    markNeedsPaint();
  }

  set softWrap(bool value) {
    if (_softWrap == value) return;
    _softWrap = value;
    markNeedsLayout();
  }

  set textScaler(TextScaler value) {
    if (_textScaler == value) return;
    _textScaler = value;
    _needsTextLayout = true;
    markNeedsLayout();
  }

  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    markNeedsLayout();
  }

  set textHeightBehavior(TextHeightBehavior? value) {
    if (_textHeightBehavior == value) return;
    _textHeightBehavior = value;
    _needsTextLayout = true;
    markNeedsLayout();
  }

  TextPainter _ensurePainter(double maxWidth) {
    final painter = _painter ??= TextPainter(
      textDirection: _textDirection,
      maxLines: _maxLines,
      ellipsis: _overflow == TextOverflow.ellipsis ? '\u2026' : null,
      textAlign: _textAlign,
      textHeightBehavior: _textHeightBehavior,
    );
    painter.text = TextSpan(text: _text, style: _style);
    painter.textScaler = _textScaler;
    painter.layout(maxWidth: maxWidth);
    return painter;
  }

  @override
  void performLayout() {
    final constraints = this.constraints;
    final maxW = constraints.maxWidth;
    final painter = _ensurePainter(_softWrap ? maxW : double.infinity);
    _needsTextLayout = false;

    var width = painter.width;
    var height = painter.height;
    // 单行不换行时,尺寸按内容收缩
    if (!_softWrap && width > maxW) width = maxW;
    size = constraints.constrain(Size(width, height));
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    final painter = _painter ??= _newPainter();
    painter.text = TextSpan(text: _text, style: _style);
    painter.textScaler = _textScaler;
    painter.layout(maxWidth: double.infinity);
    return painter.minIntrinsicWidth;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    final painter = _painter ??= _newPainter();
    painter.text = TextSpan(text: _text, style: _style);
    painter.textScaler = _textScaler;
    painter.layout(maxWidth: double.infinity);
    return painter.maxIntrinsicWidth;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    return _measureHeight(width);
  }

  @override
  double computeMaxIntrinsicHeight(double width) => _measureHeight(width);

  double _measureHeight(double width) {
    final painter = _newPainter();
    painter.layout(maxWidth: width);
    return painter.height;
  }

  TextPainter _newPainter() {
    final painter = TextPainter(
      text: TextSpan(text: _text, style: _style),
      textDirection: _textDirection,
      maxLines: _maxLines,
      ellipsis: _overflow == TextOverflow.ellipsis ? '\u2026' : null,
      textAlign: _textAlign,
      textHeightBehavior: _textHeightBehavior,
    );
    painter.textScaler = _textScaler;
    return painter;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final painter = _painter;
    if (painter == null) return;
    // textAlign 已由 TextPainter 处理,只需在自身宽度内对齐
    var dx = offset.dx;
    final freeWidth = size.width - painter.width;
    if (freeWidth > 0) {
      switch (_textAlign) {
        case TextAlign.center:
          dx += freeWidth / 2;
        case TextAlign.right || TextAlign.end:
          dx += freeWidth;
        default:
          break;
      }
    }
    painter.paint(context.canvas, Offset(dx, offset.dy));
  }

  /// 文本自身可命中(与框架 RenderParagraph 一致):命中点落在字形范围内
  /// 或行内任意位置时,文本节点即为命中目标。
  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void dispose() {
    _painter?.dispose();
    _painter = null;
    super.dispose();
  }
}

/// 富文本(替代 widgets 的 RichText)。支持 TextSpan(painting 层)树。
class RichText extends fw.LeafRenderObjectWidget {
  final InlineSpan text;
  final TextAlign textAlign;
  final TextDirection textDirection;
  final bool softWrap;
  final int? maxLines;
  final TextOverflow overflow;
  final TextScaler textScaler;

  const RichText({
    fw.Key? key,
    required this.text,
    this.textAlign = TextAlign.start,
    this.textDirection = TextDirection.ltr,
    this.softWrap = true,
    this.maxLines,
    this.overflow = TextOverflow.clip,
    this.textScaler = TextScaler.noScaling,
  }) : super(key: key);

  @override
  fw.RenderObject createRenderObject(fw.BuildContext context) {
    return RenderRichTextBox(
      span: text,
      textAlign: textAlign,
      textDirection: textDirection,
      softWrap: softWrap,
      maxLines: maxLines,
      overflow: overflow,
      textScaler: textScaler,
    );
  }

  @override
  void updateRenderObject(
    fw.BuildContext context,
    covariant RenderRichTextBox renderObject,
  ) {
    renderObject
      ..span = text
      ..textAlign = textAlign
      ..textDirection = textDirection
      ..softWrap = softWrap
      ..maxLines = maxLines
      ..overflow = overflow
      ..textScaler = textScaler;
  }
}

/// 富文本渲染盒子:TextPainter 直接排布 InlineSpan 树。
class RenderRichTextBox extends RenderBox {
  InlineSpan _span;
  TextAlign _textAlign;
  TextDirection _textDirection;
  bool _softWrap;
  int? _maxLines;
  TextOverflow _overflow;
  TextScaler _textScaler;

  TextPainter? _painter;

  RenderRichTextBox({
    required InlineSpan span,
    required TextAlign textAlign,
    required TextDirection textDirection,
    required bool softWrap,
    required int? maxLines,
    required TextOverflow overflow,
    required TextScaler textScaler,
  })  : _span = span,
        _textAlign = textAlign,
        _textDirection = textDirection,
        _softWrap = softWrap,
        _maxLines = maxLines,
        _overflow = overflow,
        _textScaler = textScaler;

  set span(InlineSpan value) {
    if (_span == value) return;
    _span = value;
    markNeedsLayout();
  }

  set textAlign(TextAlign value) {
    _textAlign = value;
    markNeedsLayout();
  }

  set textDirection(TextDirection value) {
    _textDirection = value;
    markNeedsLayout();
  }

  set softWrap(bool value) {
    _softWrap = value;
    markNeedsLayout();
  }

  set maxLines(int? value) {
    _maxLines = value;
    markNeedsLayout();
  }

  set overflow(TextOverflow value) {
    _overflow = value;
    markNeedsLayout();
  }

  set textScaler(TextScaler value) {
    _textScaler = value;
    markNeedsLayout();
  }

  TextPainter _layout(double maxWidth) {
    final painter = _painter ??= TextPainter(
      textDirection: _textDirection,
      textAlign: _textAlign,
      maxLines: _maxLines,
      ellipsis: _overflow == TextOverflow.ellipsis ? '\u2026' : null,
    );
    painter.text = _span;
    painter.textScaler = _textScaler;
    painter.layout(maxWidth: _softWrap ? maxWidth : double.infinity);
    return painter;
  }

  @override
  void performLayout() {
    final painter = _layout(constraints.maxWidth);
    size = constraints.constrain(
      Size(
        _softWrap ? painter.width : painter.width,
        painter.height,
      ),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _painter?.paint(context.canvas, offset);
  }

  @override
  void dispose() {
    _painter?.dispose();
    _painter = null;
    super.dispose();
  }
}

/// 可选中文本:拖动选择 + 复制(替代 material 的 SelectableText)。
class SelectableText extends fw.StatefulWidget {
  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final fw.FocusNode? focusNode;
  final fw.ValueChanged<String>? onChanged;

  const SelectableText(
    this.data, {
    fw.Key? key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.focusNode,
    this.onChanged,
  }) : super(key: key);

  @override
  fw.State<SelectableText> createState() => _SelectableTextState();
}

class _SelectableTextState extends fw.State<SelectableText> {
  TextSelection _selection = const TextSelection.collapsed(offset: -1);

  @override
  fw.Widget build(fw.BuildContext context) {
    final theme = Theme.of(context);
    final inherited = DefaultTextStyle.of(context);
    var effective = inherited.style;
    if (widget.style != null) effective = effective.merge(widget.style!);
    effective = effective.copyWith(
      color: effective.color ??
          (theme.brightness == Brightness.dark
              ? const Color(0xFFF9FAFF)
              : const Color(0xFF353B58)),
      fontFamily: effective.fontFamily ?? theme.fontFamily,
      fontFamilyFallback:
          effective.fontFamilyFallback ?? theme.fontFamilyFallback,
    );

    return _SelectableRenderWidget(
      text: widget.data,
      style: effective,
      textAlign: widget.textAlign ?? TextAlign.start,
      maxLines: widget.maxLines,
      overflow: widget.overflow ?? TextOverflow.clip,
      selection: _selection,
      selectionColor: theme.colorScheme.primary.withValues(alpha: .25),
      onSelectionChanged: (selection) =>
          setState(() => _selection = selection),
    );
  }
}

class _SelectableRenderWidget extends fw.LeafRenderObjectWidget {
  final String text;
  final TextStyle style;
  final TextAlign textAlign;
  final int? maxLines;
  final TextOverflow overflow;
  final TextSelection selection;
  final Color selectionColor;
  final fw.ValueChanged<TextSelection> onSelectionChanged;

  const _SelectableRenderWidget({
    required this.text,
    required this.style,
    required this.textAlign,
    required this.maxLines,
    required this.overflow,
    required this.selection,
    required this.selectionColor,
    required this.onSelectionChanged,
  });

  @override
  fw.RenderObject createRenderObject(fw.BuildContext context) {
    return RenderSelectableParagraph(
      text: text,
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      selection: selection,
      selectionColor: selectionColor,
      onSelectionChanged: onSelectionChanged,
    );
  }

  @override
  void updateRenderObject(
    fw.BuildContext context,
    covariant RenderSelectableParagraph renderObject,
  ) {
    renderObject
      ..text = text
      ..style = style
      ..selection = selection
      ..selectionColor = selectionColor;
  }
}

/// 自写可选段落渲染盒子:命中测试 + 拖动选择 + 绘制选区高亮。
class RenderSelectableParagraph extends RenderBox {
  String _text;
  TextStyle _style;
  TextAlign _textAlign;
  int? _maxLines;
  TextOverflow _overflow;
  TextSelection _selection;
  Color _selectionColor;
  final fw.ValueChanged<TextSelection> onSelectionChanged;

  TextPainter? _painter;
  int _dragStart = -1;

  RenderSelectableParagraph({
    required String text,
    required TextStyle style,
    required TextAlign textAlign,
    required int? maxLines,
    required TextOverflow overflow,
    required TextSelection selection,
    required Color selectionColor,
    required this.onSelectionChanged,
  })  : _text = text,
        _style = style,
        _textAlign = textAlign,
        _maxLines = maxLines,
        _overflow = overflow,
        _selection = selection,
        _selectionColor = selectionColor;

  set text(String value) {
    if (_text == value) return;
    _text = value;
    markNeedsLayout();
  }

  set style(TextStyle value) {
    if (_style == value) return;
    _style = value;
    markNeedsLayout();
  }

  set selection(TextSelection value) {
    _selection = value;
    markNeedsPaint();
  }

  set selectionColor(Color value) {
    _selectionColor = value;
    markNeedsPaint();
  }

  TextPainter _layout() {
    final painter = _painter ??= TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: _textAlign,
      maxLines: _maxLines,
      ellipsis: _overflow == TextOverflow.ellipsis ? '\u2026' : null,
    );
    painter.text = TextSpan(text: _text, style: _style);
    painter.textScaler = TextScaler.noScaling;
    painter.layout(maxWidth: constraints.maxWidth);
    return painter;
  }

  @override
  void performLayout() {
    final painter = _layout();
    size = constraints.constrain(Size(painter.width, painter.height));
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, covariant BoxHitTestEntry entry) {
    final painter = _painter;
    if (painter == null) return;
    if (event is PointerDownEvent) {
      _dragStart = _clampOffset(painter, event.localPosition);
      _updateSelection(painter, _dragStart, _dragStart);
    } else if (event is PointerMoveEvent && _dragStart >= 0) {
      final end = _clampOffset(painter, event.localPosition);
      _updateSelection(painter, _dragStart, end);
    } else if (event is PointerUpEvent) {
      _dragStart = -1;
    }
  }

  int _clampOffset(TextPainter painter, Offset local) {
    final pos = painter.getPositionForOffset(local);
    return pos.offset.clamp(0, _text.length);
  }

  void _updateSelection(TextPainter painter, int start, int end) {
    if (start == end) {
      onSelectionChanged(TextSelection.collapsed(offset: start));
    } else {
      onSelectionChanged(TextSelection(
        baseOffset: start,
        extentOffset: end,
      ));
    }
  }

  /// 把当前选区写入剪贴板(供长按菜单或外部调用)。
  void copySelection() {
    if (_selection.isValid && !_selection.isCollapsed) {
      Clipboard.setData(ClipboardData(text: _selection.textInside(_text)));
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final painter = _painter;
    if (painter == null) return;
    if (_selection.isValid && !_selection.isCollapsed) {
      for (final box in painter.getBoxesForSelection(_selection)) {
        context.canvas.drawRect(
          box.toRect().shift(offset),
          Paint()..color = _selectionColor,
        );
      }
    }
    painter.paint(context.canvas, offset);
  }

  @override
  void dispose() {
    _painter?.dispose();
    _painter = null;
    super.dispose();
  }
}
