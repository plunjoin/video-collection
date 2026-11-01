/// 自研图片组件:[Image]——network/asset/file 三种来源,基于 painting 层
/// ImageStream 解码,自写渲染盒子绘制。替代 widgets 的 Image。
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart' as fw;

import 'layout.dart';

/// 图片组件(自研;Image.network / Image.asset / Image.file)。
class Image extends fw.StatefulWidget {
  final ImageProvider provider;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Alignment alignment;
  final Color? color;
  final fw.Widget Function(fw.BuildContext, Object, StackTrace?)? errorBuilder;
  final String? semanticLabel;
  final bool excludeFromSemantics;

  const Image({
    fw.Key? key,
    required this.provider,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
    this.color,
    this.errorBuilder,
    this.semanticLabel,
    this.excludeFromSemantics = false,
  }) : super(key: key);

  Image.network(
    String url, {
    fw.Key? key,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
    this.color,
    this.errorBuilder,
    this.semanticLabel,
    this.excludeFromSemantics = false,
  })  : provider = NetworkImage(url),
        super(key: key);

  Image.asset(
    String name, {
    fw.Key? key,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
    this.color,
    this.errorBuilder,
    this.semanticLabel,
    this.excludeFromSemantics = false,
  })  : provider = AssetImage(name),
        super(key: key);

  @override
  fw.State<Image> createState() => _ImageState();
}

class _ImageState extends fw.State<Image> {
  ImageStream? _stream;
  ui.Image? _image;
  Object? _error;
  ImageStreamListener? _listener;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(Image oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider != widget.provider) {
      _resolve();
    }
  }

  void _resolve() {
    _listener ??= ImageStreamListener(
      (image, synchronousCall) {
        if (!mounted) return;
        setState(() {
          _image = image.image;
          _error = null;
        });
      },
      onError: (error, stackTrace) {
        if (!mounted) return;
        setState(() => _error = error);
      },
    );
    final newStream = widget.provider.resolve(
      ImageConfiguration(
        devicePixelRatio: fw.MediaQuery.of(context).devicePixelRatio,
        size: widget.width != null && widget.height != null
            ? Size(widget.width!, widget.height!)
            : null,
      ),
    );
    if (newStream.key != _stream?.key) {
      _stream?.removeListener(_listener!);
      _stream = newStream;
      _stream!.addListener(_listener!);
    }
  }

  @override
  void dispose() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    super.dispose();
  }

  @override
  fw.Widget build(fw.BuildContext context) {
    if (_error != null && widget.errorBuilder != null) {
      return widget.errorBuilder!(context, _error!, null);
    }
    fw.Widget result = _ImageRenderWidget(
      image: _image,
      fit: widget.fit,
      alignment: widget.alignment,
      color: widget.color,
    );
    if (widget.width != null || widget.height != null) {
      result = SizedBox(
        width: widget.width,
        height: widget.height,
        child: result,
      );
    }
    return result;
  }
}

/// 自写图片渲染件。
class _ImageRenderWidget extends fw.LeafRenderObjectWidget {
  final ui.Image? image;
  final BoxFit? fit;
  final Alignment alignment;
  final Color? color;

  const _ImageRenderWidget({
    required this.image,
    required this.fit,
    required this.alignment,
    required this.color,
  });

  @override
  fw.RenderObject createRenderObject(fw.BuildContext context) {
    return RenderImageBox(
      image: image,
      fit: fit,
      alignment: alignment,
      color: color,
    );
  }

  @override
  void updateRenderObject(
    fw.BuildContext context,
    covariant RenderImageBox renderObject,
  ) {
    renderObject
      ..image = image
      ..fit = fit
      ..alignment = alignment
      ..color = color;
  }
}

/// 自写图片渲染盒子:按 fit 计算源/目标矩形后 drawImageRect。
class RenderImageBox extends RenderBox {
  ui.Image? _image;
  BoxFit? _fit;
  Alignment _alignment;
  Color? _color;

  RenderImageBox({
    required ui.Image? image,
    required BoxFit? fit,
    required Alignment alignment,
    required Color? color,
  })  : _image = image,
        _fit = fit,
        _alignment = alignment,
        _color = color;

  set image(ui.Image? value) {
    if (_image == value) return;
    _image = value;
    markNeedsLayout();
  }

  set fit(BoxFit? value) {
    if (_fit == value) return;
    _fit = value;
    markNeedsPaint();
  }

  set alignment(Alignment value) {
    if (_alignment == value) return;
    _alignment = value;
    markNeedsPaint();
  }

  set color(Color? value) {
    if (_color == value) return;
    _color = value;
    markNeedsPaint();
  }

  @override
  void performLayout() {
    final intrinsic = _image != null
        ? Size(_image!.width.toDouble(), _image!.height.toDouble())
        : Size(constraints.minWidth, constraints.minHeight);
    size = constraints.constrain(intrinsic);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final img = _image;
    if (img == null) return;
    final dst = offset & size;
    final srcRect = Rect.fromLTWH(
      0,
      0,
      img.width.toDouble(),
      img.height.toDouble(),
    );
    final paint = Paint();
    if (_color != null) {
      paint.colorFilter = ColorFilter.mode(_color!, BlendMode.srcIn);
    }
    final fitted = applyBoxFit(_fit ?? BoxFit.contain, srcRect.size, dst.size);
    final src = Rect.fromLTWH(0, 0, fitted.source.width, fitted.source.height);
    final scaled = _alignment.inscribe(fitted.destination, dst);
    context.canvas.drawImageRect(img, src, scaled, paint);
  }
}
