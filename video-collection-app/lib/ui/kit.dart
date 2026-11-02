/// bllii 自研 UI 组件库 — 唯一对外入口。
///
/// 业务代码 `import '../ui/kit.dart'`(或对应相对路径)替代
/// `package:flutter/material.dart`。
///
/// 边界约定:
/// - **全部自研**:所有承载视觉与交互的组件(本目录各文件)。
/// - **继续复用引擎/基础设施**:dart:ui、painting(样式与绘制描述)、
///   rendering(渲染协议)、gestures(手势识别器)、services(输入法/
///   系统通道)、foundation、animation、scheduler,以及 widgets 库里
///   不可见的框架管道(见下方 show 列表)。
library;

// ---- 引擎与基础设施层(非组件,直接放行) ----
export 'package:flutter/animation.dart';
export 'package:flutter/foundation.dart' hide Category;
export 'package:characters/characters.dart' show Characters, CharacterRange;
export 'package:flutter/gestures.dart';
export 'package:flutter/painting.dart';
export 'package:flutter/scheduler.dart';
export 'package:flutter/services.dart';
// rendering 层放行,但隐藏与我自研组件重名的父数据/枚举
// (Flex/Stack/Wrap 的语义由本库同名实现接管)。
export 'package:flutter/rendering.dart'
    hide
        FlexParentData,
        FlexFit,
        StackParentData,
        WrapParentData,
        WrapAlignment,
        WrapCrossAlignment,
        SliverGridDelegate,
        SliverGridDelegateWithFixedCrossAxisCount,
        SliverGridDelegateWithMaxCrossAxisExtent;

// ---- 框架管道(不可见基础设施:构建上下文/键/绑定/焦点/度量/方向) ----
export 'package:flutter/widgets.dart'
    show
        Widget,
        BuildContext,
        Key,
        UniqueKey,
        ValueKey,
        ObjectKey,
        GlobalKey,
        LabeledGlobalKey,
        StatelessWidget,
        StatefulWidget,
        State,
        TickerProviderStateMixin,
        SingleTickerProviderStateMixin,
        WidgetsBinding,
        WidgetsBindingObserver,
        WidgetsFlutterBinding,
        runApp,
        InheritedWidget,
        KeyEventResult,
        Focus,
        Element,
        StatefulElement,
        FocusTraversalGroup,
        Builder,
        LayoutBuilder,
        StatefulBuilder,
        PreferredSizeWidget,
        Directionality,
        FocusNode,
        FocusScope,
        FocusScopeNode,
        FocusManager,
        MediaQuery,
        MediaQueryData,
        View,
        RouteSettings,
        defaultTargetPlatform,
        TargetPlatform,
        debugPrint;

// ---- 自研组件 ----
export 'app.dart';
export 'buttons.dart';
export 'container.dart';
export 'controls.dart';
export 'fonts.dart';
export 'gestures.dart';
export 'image.dart';
export 'inputs.dart';
export 'layout.dart';
export 'nav.dart';
export 'overlay.dart';
export 'scroll.dart';
export 'text.dart';
export 'theme.dart';
export 'tooltip.dart';
