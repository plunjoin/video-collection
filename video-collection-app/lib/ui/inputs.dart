/// 自研输入组件:[TextField]/[TextFormField]/[Form]/[InputDecoration]/
/// [OutlineInputBorder]/[TextEditingController]。
///
/// 文本输入通过引擎层 TextInputConnection(services 输入法通道)接入系统
/// IME,支持中文 composing;光标/选区/composing 下划线由自写渲染盒子绘制。
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show GestureTapCallback;
import 'package:flutter/painting.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' as fw;

import 'gestures.dart';
import 'layout.dart';
import 'text.dart';
import 'theme.dart';

// ---------------------------------------------------------------------------
// 边框
// ---------------------------------------------------------------------------

/// 输入框边框接口(自研协议)。
abstract class InputBorder {
  const InputBorder();

  /// 无边框。
  static const InputBorder none = _NoneInputBorder();

  BorderSide get borderSide;

  InputBorder copyWith({BorderSide? borderSide});

  Path getOuterPath(Rect rect, {TextDirection? textDirection});

  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0,
    double gapPercentage = 0,
    TextDirection? textDirection,
  });
}

/// 无边框实现。
class _NoneInputBorder extends InputBorder {
  const _NoneInputBorder();

  @override
  BorderSide get borderSide => BorderSide.none;

  @override
  InputBorder copyWith({BorderSide? borderSide}) => this;

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => Path();

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0,
    double gapPercentage = 0,
    TextDirection? textDirection,
  }) {}
}

/// 圆角描边输入框边框。
class OutlineInputBorder extends InputBorder {
  final double gapPadding;
  final BorderRadius borderRadius;

  @override
  final BorderSide borderSide;

  const OutlineInputBorder({
    this.gapPadding = 4,
    this.borderRadius = const BorderRadius.all(Radius.circular(4)),
    this.borderSide = const BorderSide(),
  });

  @override
  OutlineInputBorder copyWith({BorderSide? borderSide}) {
    return OutlineInputBorder(
      gapPadding: gapPadding,
      borderRadius: borderRadius,
      borderSide: borderSide ?? this.borderSide,
    );
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return Path()
      ..addRRect(RRect.fromRectAndCorners(
        rect,
        topLeft: borderRadius.topLeft,
        topRight: borderRadius.topRight,
        bottomLeft: borderRadius.bottomLeft,
        bottomRight: borderRadius.bottomRight,
      ));
  }

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0,
    double gapPercentage = 0,
    TextDirection? textDirection,
  }) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderSide.width
      ..color = borderSide.color;
    canvas.drawPath(getOuterPath(rect), paint);
  }
}

// ---------------------------------------------------------------------------
// 装饰
// ---------------------------------------------------------------------------

/// 输入框装饰(自研;字段面 = 全库用点)。
class InputDecoration {
  final String? hintText;
  final TextStyle? hintStyle;
  final String? labelText;
  final TextStyle? labelStyle;
  final TextStyle? floatingLabelStyle;
  final String? helperText;
  final TextStyle? helperStyle;
  final String? errorText;
  final TextStyle? errorStyle;
  final fw.Widget? prefixIcon;
  final fw.Widget? suffixIcon;
  final bool filled;
  final Color? fillColor;
  final EdgeInsetsGeometry? contentPadding;
  final InputBorder? border;
  final InputBorder? enabledBorder;
  final InputBorder? focusedBorder;
  final InputBorder? errorBorder;
  final InputBorder? disabledBorder;
  final bool isDense;
  final Color? prefixIconColor;
  final Color? suffixIconColor;
  final bool enabled;
  final String? counterText;
  final bool alignLabelWithHint;

  const InputDecoration({
    this.hintText,
    this.hintStyle,
    this.labelText,
    this.labelStyle,
    this.floatingLabelStyle,
    this.helperText,
    this.helperStyle,
    this.errorText,
    this.errorStyle,
    this.prefixIcon,
    this.suffixIcon,
    this.filled = false,
    this.fillColor,
    this.contentPadding,
    this.border,
    this.enabledBorder,
    this.focusedBorder,
    this.errorBorder,
    this.disabledBorder,
    this.isDense = false,
    this.prefixIconColor,
    this.suffixIconColor,
    this.enabled = true,
    this.counterText,
    this.alignLabelWithHint = false,
  });

  InputDecoration copyWith({
    String? hintText,
    TextStyle? hintStyle,
    String? labelText,
    TextStyle? labelStyle,
    String? errorText,
    fw.Widget? prefixIcon,
    fw.Widget? suffixIcon,
    bool? filled,
    Color? fillColor,
    EdgeInsetsGeometry? contentPadding,
    InputBorder? border,
    InputBorder? enabledBorder,
    InputBorder? focusedBorder,
    InputBorder? errorBorder,
    InputBorder? disabledBorder,
    bool? enabled,
  }) {
    return InputDecoration(
      hintText: hintText ?? this.hintText,
      hintStyle: hintStyle ?? this.hintStyle,
      labelText: labelText ?? this.labelText,
      labelStyle: labelStyle ?? this.labelStyle,
      errorText: errorText ?? this.errorText,
      prefixIcon: prefixIcon ?? this.prefixIcon,
      suffixIcon: suffixIcon ?? this.suffixIcon,
      filled: filled ?? this.filled,
      fillColor: fillColor ?? this.fillColor,
      contentPadding: contentPadding ?? this.contentPadding,
      border: border ?? this.border,
      enabledBorder: enabledBorder ?? this.enabledBorder,
      focusedBorder: focusedBorder ?? this.focusedBorder,
      errorBorder: errorBorder ?? this.errorBorder,
      disabledBorder: disabledBorder ?? this.disabledBorder,
      enabled: enabled ?? this.enabled,
    );
  }
}

// ---------------------------------------------------------------------------
// 控制器
// ---------------------------------------------------------------------------

/// 文本编辑控制器(自研;承载 TextEditingValue 并广播变更)。
class TextEditingController extends ChangeNotifier
    implements ValueListenable<TextEditingValue> {
  TextEditingValue _value;

  TextEditingController({String text = ''})
      : _value = TextEditingValue(text: text);

  TextEditingController.fromValue(TextEditingValue? value)
      : _value = value ?? TextEditingValue.empty;

  TextEditingValue get value => _value;

  set value(TextEditingValue newValue) {
    if (newValue == _value) return;
    _value = newValue;
    notifyListeners();
  }

  String get text => _value.text;

  set text(String newText) {
    value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
      composing: TextRange.empty,
    );
  }

  TextSelection get selection => _value.selection;

  set selection(TextSelection newSelection) {
    value = TextEditingValue(
      text: text,
      selection: newSelection.copyWith(
        baseOffset: math.min(newSelection.baseOffset, text.length),
        extentOffset: math.min(newSelection.extentOffset, text.length),
      ),
      composing: TextRange.empty,
    );
  }

  void clear() {
    value = const TextEditingValue(
      text: '',
      selection: TextSelection.collapsed(offset: 0),
      composing: TextRange.empty,
    );
  }

  void clearComposing() {
    value = _value.copyWith(composing: TextRange.empty);
  }
}

// ---------------------------------------------------------------------------
// 表单
// ---------------------------------------------------------------------------

/// 自动校验时机。
enum AutovalidateMode { disabled, always, onUserInteraction }

/// 表单容器:收集并校验内部的 [TextFormField]。
class Form extends fw.StatefulWidget {
  final fw.Widget child;
  final AutovalidateMode? autovalidateMode;
  final VoidCallback? onChanged;
  final bool canPop;

  const Form({
    fw.Key? key,
    required this.child,
    this.autovalidateMode,
    this.onChanged,
    this.canPop = true,
  }) : super(key: key);

  static FormState? of(fw.BuildContext context) {
    return context.findAncestorStateOfType<FormState>();
  }

  @override
  fw.State<Form> createState() => FormState();
}

class FormState extends fw.State<Form> {
  final List<_FormFieldStateProxy> _fields = [];

  void register(_FormFieldStateProxy proxy) {
    _fields.add(proxy);
  }

  void unregister(_FormFieldStateProxy proxy) {
    _fields.remove(proxy);
  }

  void fieldChanged() {
    widget.onChanged?.call();
  }

  /// 校验全部字段,返回是否全部通过。
  bool validate() {
    var valid = true;
    for (final field in List.of(_fields)) {
      if (!field.validate()) valid = false;
    }
    return valid;
  }

  void save() {
    for (final field in List.of(_fields)) {
      field.save();
    }
  }

  void reset() {
    for (final field in List.of(_fields)) {
      field.reset();
    }
  }

  @override
  fw.Widget build(fw.BuildContext context) => widget.child;
}

/// 字段状态代理,供 FormState 调用(由 TextFormField 的 State 实现)。
abstract class _FormFieldStateProxy {
  bool validate();
  void save();
  void reset();
}

// ---------------------------------------------------------------------------
// 输入框
// ---------------------------------------------------------------------------

/// 文本输入框(替代 material 的 TextField)。
class TextField extends fw.StatefulWidget {
  final TextEditingController? controller;
  final fw.FocusNode? focusNode;
  final InputDecoration? decoration;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextStyle? style;
  final TextAlign textAlign;
  final bool autofocus;
  final bool enabled;
  final bool readOnly;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final bool obscureText;
  final List<TextInputFormatter>? inputFormatters;
  final fw.ValueChanged<String>? onChanged;
  final fw.ValueChanged<String>? onSubmitted;
  final VoidCallback? onEditingComplete;
  final GestureTapCallback? onTap;
  final Color? cursorColor;
  final bool expands;
  final Iterable<String>? autofillHints;
  final TextCapitalization? textCapitalization;
  final bool autocorrect;

  const TextField({
    fw.Key? key,
    this.controller,
    this.focusNode,
    this.decoration,
    this.keyboardType,
    this.textInputAction,
    this.style,
    this.textAlign = TextAlign.start,
    this.autofocus = false,
    this.enabled = true,
    this.readOnly = false,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.obscureText = false,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.onEditingComplete,
    this.onTap,
    this.cursorColor,
    this.expands = false,
    this.autofillHints,
    this.textCapitalization,
    this.autocorrect = false,
  }) : super(key: key);

  @override
  fw.State<TextField> createState() => _TextFieldState();
}

class _TextFieldState extends fw.State<TextField>
    with fw.SingleTickerProviderStateMixin, TextInputClient {
  TextEditingController? _internalController;
  fw.FocusNode? _internalFocusNode;
  TextInputConnection? _connection;
  Timer? _cursorBlink;
  bool _cursorVisible = true;
  final fw.GlobalKey _editableKey = fw.GlobalKey();

  @override
  TextEditingValue? get currentTextEditingValue =>
      _effectiveController.value;

  @override
  AutofillScope? get currentAutofillScope => null;

  TextEditingController get _effectiveController =>
      widget.controller ?? (_internalController ??= TextEditingController());

  fw.FocusNode get _effectiveFocusNode =>
      widget.focusNode ?? (_internalFocusNode ??= fw.FocusNode());

  bool get _hasFocus => _effectiveFocusNode.hasFocus;
  bool get _isMultiline => (widget.maxLines ?? 1) != 1;
  bool get _interactive => widget.enabled && !widget.readOnly;

  @override
  void initState() {
    super.initState();
    _effectiveFocusNode.addListener(_handleFocusChange);
    _effectiveController.addListener(_handleTextChange);
    if (widget.autofocus) {
      _effectiveFocusNode.requestFocus();
    }
  }

  @override
  void didUpdateWidget(TextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_handleTextChange);
      widget.controller?.addListener(_handleTextChange);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_handleFocusChange);
      widget.focusNode?.addListener(_handleFocusChange);
    }
  }

  @override
  void dispose() {
    _effectiveFocusNode.removeListener(_handleFocusChange);
    _internalFocusNode?.dispose();
    _effectiveController.removeListener(_handleTextChange);
    _internalController?.dispose();
    _cursorBlink?.cancel();
    _connection?.close();
    super.dispose();
  }

  void _handleFocusChange() {
    if (_hasFocus && _interactive) {
      _openConnection();
      _startCursorBlink();
    } else {
      _connection?.close();
      _connection = null;
      _cursorBlink?.cancel();
      _cursorVisible = true;
    }
    if (mounted) setState(() {});
  }

  void _openConnection() {
    _connection ??= TextInput.attach(
      this,
      TextInputConfiguration(
        inputType: widget.keyboardType ??
            (_isMultiline ? TextInputType.multiline : TextInputType.text),
        inputAction: widget.textInputAction ??
            (_isMultiline ? TextInputAction.newline : TextInputAction.done),
        obscureText: widget.obscureText,
        autocorrect: false,
      ),
    );
    _connection!.show();
    _connection!.setEditingState(_effectiveController.value);
    _pushEditableMetrics();
  }

  void _startCursorBlink() {
    _cursorBlink?.cancel();
    _cursorVisible = true;
    _cursorBlink = Timer.periodic(const Duration(milliseconds: 530), (_) {
      if (mounted && _hasFocus) {
        setState(() => _cursorVisible = !_cursorVisible);
      }
    });
  }

  void _handleTextChange() {
    // 本地(程序化)文本变化 → 同步给 IME
    if (_connection != null && _connection!.attached) {
      _connection!.setEditingState(_effectiveController.value);
    }
    _pushEditableMetrics();
    if (mounted) setState(() {});
  }

  /// 把编辑区的尺寸/变换/光标矩形上报给输入法(候选窗定位用)。
  void _pushEditableMetrics() {
    fw.WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _connection == null || !_connection!.attached) return;
      final ro = _editableKey.currentContext?.findRenderObject();
      if (ro is RenderEditableField) {
        _connection!.setEditableSizeAndTransform(
          ro.size,
          ro.getTransformTo(null),
        );
        _connection!.setComposingRect(ro.composingRect);
        _connection!.setCaretRect(ro.caretRect);
      }
    });
  }

  // ---- TextInputClient ----

  @override
  void updateEditingValue(TextEditingValue value) {
    final oldText = _effectiveController.value.text;
    _effectiveController.value = value;
    setState(() => _cursorVisible = true);
    if (oldText != value.text) {
      widget.onChanged?.call(value.text);
    }
    _pushEditableMetrics();
  }

  @override
  void performAction(TextInputAction action) {
    switch (action) {
      case TextInputAction.done:
      case TextInputAction.go:
      case TextInputAction.next:
      case TextInputAction.search:
      case TextInputAction.send:
        widget.onEditingComplete?.call();
        widget.onSubmitted?.call(_effectiveController.text);
        if (!_isMultiline) {
          _effectiveFocusNode.unfocus();
        }
      case TextInputAction.newline:
        if (_isMultiline) {
          final value = _effectiveController.value;
          final sel = value.selection;
          final newText =
              value.text.replaceRange(sel.start, sel.end, '\n');
          _effectiveController.value = TextEditingValue(
            text: newText,
            selection: TextSelection.collapsed(offset: sel.start + 1),
          );
          widget.onChanged?.call(newText);
        } else {
          widget.onSubmitted?.call(_effectiveController.text);
        }
      default:
        break;
    }
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  void connectionClosed() {
    _connection = null;
  }

  // ---- 交互 ----

  void _handleTap() {
    if (!widget.enabled) return;
    _effectiveFocusNode.requestFocus();
    widget.onTap?.call();
  }

  @override
  fw.Widget build(fw.BuildContext context) {
    final theme = Theme.of(context);
    final decoTheme = theme.inputDecorationTheme;
    final decoration = widget.decoration ?? const InputDecoration();
    final hasError = decoration.errorText != null;

    final contentPadding = decoration.contentPadding ??
        decoTheme.contentPadding ??
        const EdgeInsets.symmetric(horizontal: 16, vertical: 14);
    final fill = decoration.fillColor ??
        (decoration.filled || decoTheme.filled ? decoTheme.fillColor : null);
    final border = (hasError
            ? (decoration.errorBorder ?? decoTheme.errorBorder)
            : _hasFocus
                ? (decoration.focusedBorder ?? decoTheme.focusedBorder)
                : (decoration.enabledBorder ?? decoTheme.enabledBorder)) ??
        decoration.border ??
        decoTheme.border ??
        OutlineInputBorder(
          borderSide: BorderSide(color: theme.dividerColor),
        );

    final textStyle = (widget.style ?? DefaultTextStyle.of(context).style)
        .copyWith(
          fontFamily: widget.style?.fontFamily ?? theme.fontFamily,
          fontFamilyFallback:
              widget.style?.fontFamilyFallback ?? theme.fontFamilyFallback,
        );

    final value = _effectiveController.value;
    final hasText = value.text.isNotEmpty;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handleTap,
      child: _FieldBox(
        fill: fill,
        border: border,
        child: Padding(
          padding: contentPadding,
          child: Row(
            children: [
              if (decoration.prefixIcon != null) ...[
                IconTheme(
                  data: IconThemeData(
                    color: decoration.prefixIconColor ??
                        decoTheme.prefixIconColor ??
                        theme.iconTheme.color,
                    size: 20,
                  ),
                  child: decoration.prefixIcon!,
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.centerLeft,
                  children: [
                    if (decoration.labelText != null &&
                        !hasText &&
                        !_hasFocus)
                      Text(
                        decoration.labelText!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: decoration.labelStyle ??
                            decoTheme.labelStyle ??
                            const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF7D88AA),
                            ),
                      ),
                    if (decoration.hintText != null &&
                        !hasText &&
                        decoration.labelText == null)
                      Text(
                        decoration.hintText!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: decoration.hintStyle ??
                            decoTheme.hintStyle ??
                            const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF7D88AA),
                            ),
                      ),
                    if (decoration.labelText != null &&
                        (hasText || _hasFocus))
                      Positioned(
                        left: 0,
                        top: -3,
                        child: Text(
                          decoration.labelText!,
                          maxLines: 1,
                          style: decoration.floatingLabelStyle ??
                              decoration.labelStyle ??
                              decoTheme.floatingLabelStyle ??
                              decoTheme.labelStyle ??
                              const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF9A83FF),
                              ),
                        ),
                      ),
                    _EditableTextWidget(
                      key: _editableKey,
                      value: value,
                      style: textStyle,
                      textAlign: widget.textAlign,
                      obscureText: widget.obscureText,
                      maxLines: widget.expands ? null : widget.maxLines,
                      hasFocus: _hasFocus && _interactive,
                      cursorVisible: _cursorVisible,
                      cursorColor:
                          widget.cursorColor ?? theme.colorScheme.primary,
                      selectionColor:
                          theme.colorScheme.primary.withValues(alpha: .25),
                    ),
                  ],
                ),
              ),
              if (decoration.suffixIcon != null) ...[
                const SizedBox(width: 10),
                IconTheme(
                  data: IconThemeData(
                    color: decoration.suffixIconColor ??
                        decoTheme.suffixIconColor ??
                        theme.iconTheme.color,
                    size: 20,
                  ),
                  child: decoration.suffixIcon!,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 输入框外壳:填充 + 边框绘制。
class _FieldBox extends fw.SingleChildRenderObjectWidget {
  final Color? fill;
  final InputBorder border;

  const _FieldBox({required this.fill, required this.border, super.child});

  @override
  fw.RenderObject createRenderObject(fw.BuildContext context) {
    return RenderFieldBox(fill: fill, border: border);
  }

  @override
  void updateRenderObject(
    fw.BuildContext context,
    covariant RenderFieldBox renderObject,
  ) {
    renderObject
      ..fill = fill
      ..border = border;
  }
}

class RenderFieldBox extends RenderProxyBox {
  Color? _fill;
  InputBorder _border;

  RenderFieldBox({required Color? fill, required InputBorder border})
      : _fill = fill,
        _border = border;

  set fill(Color? value) {
    if (_fill == value) return;
    _fill = value;
    markNeedsPaint();
  }

  set border(InputBorder value) {
    if (_border == value) return;
    _border = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final rect = offset & size;
    if (_fill != null && _fill!.a > 0) {
      final outer = _border.getOuterPath(rect);
      context.canvas.drawPath(outer, Paint()..color = _fill!);
    }
    _border.paint(context.canvas, rect);
    super.paint(context, offset);
  }
}

/// 自写可编辑文本渲染件:文本 + 选区 + 光标 + composing 下划线。
class _EditableTextWidget extends fw.LeafRenderObjectWidget {
  final TextEditingValue value;
  final TextStyle style;
  final TextAlign textAlign;
  final bool obscureText;
  final int? maxLines;
  final bool hasFocus;
  final bool cursorVisible;
  final Color cursorColor;
  final Color selectionColor;

  const _EditableTextWidget({
    super.key,
    required this.value,
    required this.style,
    required this.textAlign,
    required this.obscureText,
    required this.maxLines,
    required this.hasFocus,
    required this.cursorVisible,
    required this.cursorColor,
    required this.selectionColor,
  });

  @override
  fw.RenderObject createRenderObject(fw.BuildContext context) {
    return RenderEditableField(
      value: value,
      style: style,
      textAlign: textAlign,
      obscureText: obscureText,
      maxLines: maxLines,
      hasFocus: hasFocus,
      cursorVisible: cursorVisible,
      cursorColor: cursorColor,
      selectionColor: selectionColor,
    );
  }

  @override
  void updateRenderObject(
    fw.BuildContext context,
    covariant RenderEditableField renderObject,
  ) {
    renderObject
      ..value = value
      ..style = style
      ..textAlign = textAlign
      ..obscureText = obscureText
      ..hasFocus = hasFocus
      ..cursorVisible = cursorVisible
      ..cursorColor = cursorColor
      ..selectionColor = selectionColor;
  }
}

/// 自写编辑区渲染盒子。
class RenderEditableField extends RenderBox {
  TextEditingValue _value;
  TextStyle _style;
  TextAlign _textAlign;
  bool _obscureText;
  int? _maxLines;
  bool _hasFocus;
  bool _cursorVisible;
  Color _cursorColor;
  Color _selectionColor;

  TextPainter? _painter;
  double _scrollOffset = 0;
  Rect _caretRect = Rect.zero;
  Rect _composingRect = Rect.zero;

  RenderEditableField({
    required TextEditingValue value,
    required TextStyle style,
    required TextAlign textAlign,
    required bool obscureText,
    required int? maxLines,
    required bool hasFocus,
    required bool cursorVisible,
    required Color cursorColor,
    required Color selectionColor,
  })  : _value = value,
        _style = style,
        _textAlign = textAlign,
        _obscureText = obscureText,
        _maxLines = maxLines,
        _hasFocus = hasFocus,
        _cursorVisible = cursorVisible,
        _cursorColor = cursorColor,
        _selectionColor = selectionColor;

  set value(TextEditingValue v) {
    if (_value == v) return;
    _value = v;
    markNeedsLayout();
  }

  set style(TextStyle v) {
    if (_style == v) return;
    _style = v;
    markNeedsLayout();
  }

  set textAlign(TextAlign v) {
    if (_textAlign == v) return;
    _textAlign = v;
    markNeedsLayout();
  }

  set obscureText(bool v) {
    if (_obscureText == v) return;
    _obscureText = v;
    markNeedsLayout();
  }

  set hasFocus(bool v) {
    if (_hasFocus == v) return;
    _hasFocus = v;
    markNeedsPaint();
  }

  set cursorVisible(bool v) {
    if (_cursorVisible == v) return;
    _cursorVisible = v;
    markNeedsPaint();
  }

  set cursorColor(Color v) {
    if (_cursorColor == v) return;
    _cursorColor = v;
    markNeedsPaint();
  }

  set selectionColor(Color v) {
    if (_selectionColor == v) return;
    _selectionColor = v;
    markNeedsPaint();
  }

  String get _displayText =>
      _obscureText ? '•' * _value.text.length : _value.text;

  /// 光标矩形(渲染件本地坐标,IME 上报用)。
  Rect get caretRect => _caretRect;

  /// composing 下划线矩形(渲染件本地坐标,IME 上报用)。
  Rect get composingRect => _composingRect;

  TextPainter _layoutPainter() {
    final painter = _painter ??= TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: _textAlign,
      maxLines: _maxLines,
    );
    painter.text = TextSpan(text: _displayText, style: _style);
    painter.textScaler = TextScaler.noScaling;
    painter.layout(maxWidth: math.max(0, constraints.maxWidth));
    return painter;
  }

  TextPosition get _caretPosition => TextPosition(
        offset: _value.selection.extentOffset
            .clamp(0, _displayText.length),
      );

  @override
  void performLayout() {
    final painter = _layoutPainter();
    final height =
        _maxLines == 1 ? painter.preferredLineHeight : painter.height;
    size = constraints.constrain(Size(
      math.min(painter.width, constraints.maxWidth),
      height,
    ));

    final caretOffset = painter.getOffsetForCaret(_caretPosition, Rect.zero);
    final caretHeight = painter.preferredLineHeight;
    _caretRect = Rect.fromLTWH(
      caretOffset.dx - _scrollOffset,
      math.max(0, caretOffset.dy),
      2,
      caretHeight,
    );
    final composing = _value.composing;
    if (composing.isValid && !composing.isCollapsed) {
      final boxes = painter.getBoxesForSelection(
        TextSelection(
          baseOffset: composing.start,
          extentOffset: composing.end,
        ),
      );
      if (boxes.isNotEmpty) {
        _composingRect = boxes.first.toRect();
      } else {
        _composingRect = _caretRect;
      }
    } else {
      _composingRect = _caretRect;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final painter = _layoutPainter();
    final canvas = context.canvas;
    canvas.save();
    canvas.translate(-_scrollOffset, 0);

    // 选区高亮
    final sel = _value.selection;
    if (_hasFocus && sel.isValid && !sel.isCollapsed) {
      for (final box in painter.getBoxesForSelection(sel)) {
        canvas.drawRect(
          box.toRect().shift(offset),
          Paint()..color = _selectionColor,
        );
      }
    }

    // composing 下划线(中文输入)
    final composing = _value.composing;
    if (composing.isValid && !composing.isCollapsed) {
      for (final box in painter.getBoxesForSelection(
        TextSelection(
          baseOffset: composing.start,
          extentOffset: composing.end,
        ),
      )) {
        final r = box.toRect().shift(offset);
        canvas.drawLine(
          Offset(r.left, r.bottom),
          Offset(r.right, r.bottom),
          Paint()
            ..color = _style.color ?? _cursorColor
            ..strokeWidth = 1.4,
        );
      }
    }

    painter.paint(canvas, offset);
    canvas.restore();

    // 光标
    if (_hasFocus && _cursorVisible && sel.isCollapsed && sel.isValid) {
      final caret = painter.getOffsetForCaret(_caretPosition, Rect.zero);
      canvas.drawRect(
        Rect.fromLTWH(
          offset.dx + caret.dx - _scrollOffset,
          offset.dy + math.max(0, caret.dy),
          2,
          painter.preferredLineHeight,
        ),
        Paint()..color = _cursorColor,
      );
    }

    _scrollIfNeeded(painter);
  }

  void _scrollIfNeeded(TextPainter painter) {
    final sel = _value.selection;
    if (!sel.isValid || _maxLines != 1) return;
    final caretDx = painter.getOffsetForCaret(_caretPosition, Rect.zero).dx;
    final visibleWidth = size.width;
    if (caretDx - _scrollOffset > visibleWidth - 8) {
      _scrollOffset = caretDx - visibleWidth + 8;
      markNeedsPaint();
    } else if (caretDx - _scrollOffset < 0) {
      _scrollOffset = math.max(0, caretDx - 8);
      markNeedsPaint();
    } else if (_scrollOffset > 0 &&
        painter.width - _scrollOffset < visibleWidth) {
      _scrollOffset = math.max(0, painter.width - visibleWidth);
      markNeedsPaint();
    }
  }

  @override
  void dispose() {
    _painter?.dispose();
    _painter = null;
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// 表单字段
// ---------------------------------------------------------------------------

/// 带校验的输入框(替代 material 的 TextFormField)。
class TextFormField extends fw.StatefulWidget {
  final TextEditingController? controller;
  final fw.FocusNode? focusNode;
  final InputDecoration? decoration;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextStyle? style;
  final TextAlign textAlign;
  final bool autofocus;
  final bool enabled;
  final bool readOnly;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final bool obscureText;
  final List<TextInputFormatter>? inputFormatters;
  final fw.ValueChanged<String>? onChanged;
  final fw.ValueChanged<String>? onFieldSubmitted;
  final String? Function(String?)? validator;
  final AutovalidateMode? autovalidateMode;
  final VoidCallback? onEditingComplete;
  final Iterable<String>? autofillHints;
  final bool autocorrect;

  const TextFormField({
    fw.Key? key,
    this.controller,
    this.focusNode,
    this.decoration,
    this.keyboardType,
    this.textInputAction,
    this.style,
    this.textAlign = TextAlign.start,
    this.autofocus = false,
    this.enabled = true,
    this.readOnly = false,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.obscureText = false,
    this.inputFormatters,
    this.onChanged,
    this.onFieldSubmitted,
    this.validator,
    this.autovalidateMode,
    this.onEditingComplete,
    this.autofillHints,
    this.autocorrect = false,
  }) : super(key: key);

  @override
  fw.State<TextFormField> createState() => _TextFormFieldState();
}

class _TextFormFieldState extends fw.State<TextFormField>
    implements _FormFieldStateProxy {
  String? _error;
  bool _userEdited = false;
  bool _registered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final form = Form.of(context);
    if (form != null && !_registered) {
      form.register(this);
      _registered = true;
    }
  }

  @override
  void dispose() {
    if (_registered) {
      Form.of(context)?.unregister(this);
    }
    super.dispose();
  }

  @override
  bool validate() {
    final error = widget.validator?.call(widget.controller?.text ?? '');
    if (error != _error) {
      setState(() => _error = error);
    }
    return error == null;
  }

  @override
  void save() {}

  @override
  void reset() {
    setState(() => _error = null);
    _userEdited = false;
  }

  void _handleChange(String value) {
    _userEdited = true;
    if (widget.autovalidateMode == AutovalidateMode.always ||
        (widget.autovalidateMode == AutovalidateMode.onUserInteraction)) {
      validate();
    }
    widget.onChanged?.call(value);
  }

  @override
  fw.Widget build(fw.BuildContext context) {
    final decoration = (widget.decoration ?? const InputDecoration())
        .copyWith(errorText: _error);
    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      decoration: decoration,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      style: widget.style,
      textAlign: widget.textAlign,
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      readOnly: widget.readOnly,
      maxLines: widget.maxLines,
      minLines: widget.minLines,
      maxLength: widget.maxLength,
      obscureText: widget.obscureText,
      inputFormatters: widget.inputFormatters,
      onChanged: _handleChange,
      onSubmitted: widget.onFieldSubmitted,
      onEditingComplete: widget.onEditingComplete,
      autofillHints: widget.autofillHints,
      autocorrect: widget.autocorrect,
    );
  }
}


/// 自动填充作用域占位(自研;收集语义,不参与系统 autofill)。
class AutofillGroup extends fw.StatelessWidget {
  final fw.Widget child;

  const AutofillGroup({fw.Key? key, required this.child}) : super(key: key);

  @override
  fw.Widget build(fw.BuildContext context) => child;
}
