import 'package:flutter/material.dart';

/// AppRoot: 薄封装 Flutter 官方 MaterialApp，对外提供完全兼容的原生入口。
class AppRoot extends StatelessWidget {
  final String title;
  final ThemeData? theme;
  final ThemeData? darkTheme;
  final ThemeMode? themeMode;
  final Widget? home;
  final bool debugShowCheckedModeBanner;
  final TransitionBuilder? builder;
  final RouteFactory? onGenerateRoute;
  final GlobalKey<NavigatorState>? navigatorKey;

  const AppRoot({
    super.key,
    this.title = '',
    this.theme,
    this.darkTheme,
    this.themeMode,
    this.home,
    this.debugShowCheckedModeBanner = false,
    this.builder,
    this.onGenerateRoute,
    this.navigatorKey,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      key: key,
      navigatorKey: navigatorKey,
      title: title,
      theme: theme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      home: home,
      debugShowCheckedModeBanner: debugShowCheckedModeBanner,
      builder: builder,
      onGenerateRoute: onGenerateRoute,
    );
  }
}
