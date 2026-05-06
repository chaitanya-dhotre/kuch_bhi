import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/constants/app_colors.dart';
import 'core/router/app_router.dart';

class KuchBhiApp extends ConsumerWidget {
  const KuchBhiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Kuch Bhi',
      debugShowCheckedModeBanner: false,
      theme: AppColors.lightTheme(),
      darkTheme: AppColors.darkTheme(),
      themeMode: ThemeMode.system, // Will be replaced with Riverpod provider
      routerConfig: router,
    );
  }
}
