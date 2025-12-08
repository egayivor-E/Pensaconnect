import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:go_router/go_router.dart';
import 'package:pensaconnect/config/config.dart';
import 'package:pensaconnect/models/forum_model.dart';
import 'package:pensaconnect/models/profile_view_model.dart';
import 'package:pensaconnect/models/user.dart';
import 'package:pensaconnect/models/worship_song.dart';
import 'package:pensaconnect/providers/app_providers.dart';
import 'package:pensaconnect/repositories/forum_repository.dart';
import 'package:pensaconnect/repositories/group_chat_repository.dart';
import 'package:pensaconnect/repositories/testimony_repository.dart';
import 'package:pensaconnect/screens/CreateStudyPlanScreen.dart';
import 'package:pensaconnect/screens/admin_upload_screen.dart';
import 'package:pensaconnect/services/api_service.dart';
import 'package:pensaconnect/services/socketio_service.dart'; // ✅ ADD THIS IMPORT
import 'package:provider/provider.dart';
import 'providers/threads_provider.dart';

// Screens
import 'repositories/auth_repository.dart' show AuthRepository;
import 'repositories/prayer_repository.dart';
import 'screens/bible_study_detail_screen.dart';
import 'screens/post_detail_screen.dart';
import 'screens/post_form_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/home_screen.dart';
import 'screens/live_stream_screen.dart';
import 'screens/test_connection_screen.dart';
import 'screens/events_screen.dart';
import 'screens/bible_study_screen.dart';
import 'screens/thread_form_screen.dart';
import 'screens/threads_screen.dart';
import 'screens/worship_screen.dart';
import 'screens/worship_player_screen.dart';
import 'screens/forums_screen.dart';
import 'screens/forum_detail_screen.dart';
import 'screens/prayer_wall_screen.dart';
import 'screens/testimonies_screen.dart';
import 'screens/group_chats_screen.dart';
import 'screens/group_chat_detail_screen.dart';
import 'screens/anonymous_chat_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/testimony_detail_screen.dart';
import 'screens/add_testimony_screen.dart';
import 'screens/change_password_screen.dart';
import 'screens/terms_privacy_screen.dart';
import 'screens/help_support_screen.dart';

// Providers
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';

class Routes {
  static const splash = '/splash';
  static const login = '/login';
  static const register = '/register';
  static const home = '/home';
  static const live = '/live';
  static const test = '/test';
  static const events = '/events';
  static const bible = '/bible';
  static const worship = '/worship';
  static const forums = '/forums';
  static const prayerWall = '/prayer-wall';
  static const testimonies = '/testimonies';
  static const groupChats = '/group-chats';
  static const anonymousChat = '/anonymous-chat';
  static const profile = '/profile';
  static const settings = '/settings';
  static const changePassword = '/change-password';
  static const termsPrivacy = '/terms-privacy';
  static const helpSupport = '/help-support';
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ================================
  // ENVIRONMENT LOADING
  // ================================
  if (!kReleaseMode) {
    // DEVELOPMENT: Load .env file
    print("🔄 DEVELOPMENT MODE: Loading .env file...");
    await dotenv.load(fileName: ".env");
  } else {
    // PRODUCTION: No .env file needed
    print("🚀 PRODUCTION MODE: Using hardcoded production URLs");
  }

  // Print debug info
  Config.debugModeInfo();
  Config.printConfig();

  print("🔄 MAIN: Starting ApiService.init()...");
  await ApiService.init();
  print("✅ MAIN: ApiService.init() completed");

  // ✅ Initialize Socket.IO Service
  print("🔄 Initializing Socket.IO Service...");
  try {
    await SocketIoService().initialize();
    print("✅ Socket.IO Service initialized");
  } catch (e) {
    print("❌ Socket.IO Service initialization failed: $e");
  }

  // Debug: Check token status after init
  await ApiService.debugTokenStatus();

  final authProvider = AuthProvider();
  final autoLoggedIn = await authProvider.tryAutoLogin();

  runApp(
    MultiProvider(
      providers: [
        // ✅ Reuse existing authProvider instance
        ChangeNotifierProvider.value(value: authProvider),

        // ✅ Single instance of AuthRepository
        Provider<AuthRepository>(create: (_) => AuthRepository()),

        // ✅ Theme, Prayer, Threads, Testimony
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => PrayerRepository()),
        Provider<TestimonyRepository>(create: (_) => TestimonyRepository()),
        ChangeNotifierProvider(create: (_) => ThreadsProvider()),

        ChangeNotifierProvider(create: (_) => SongProvider()),
        ChangeNotifierProvider(create: (_) => PlayerProvider()),
        ChangeNotifierProvider(create: (_) => DownloadProvider()),

        // ✅ Dio instance for HTTP
        Provider<Dio>(create: (_) => Dio()),

        Provider<ForumRepository>(create: (_) => ForumRepository()),

        // ✅ GroupChatRepository depends on Dio & AuthRepository
        Provider<GroupChatRepository>(
          create: (context) => GroupChatRepository(
            context.read<Dio>(),
            context.read<AuthRepository>(),
          ),
        ),

        // ✅ ProfileViewModel depends on all required repositories
        ChangeNotifierProvider(
          create: (context) => ProfileViewModel(
            authRepo: context.read<AuthRepository>(),
            prayerRepo: context.read<PrayerRepository>(),
            testimonyRepo: context.read<TestimonyRepository>(),
            groupRepo: context.read<GroupChatRepository>(),
          ),
        ),

        // ✅ Socket.IO Service Provider
        Provider<SocketIoService>(create: (_) => SocketIoService()),
      ],
      child: MyApp(autoLoggedIn: autoLoggedIn),
    ),
  );
}

class MyApp extends StatelessWidget {
  final bool autoLoggedIn;
  const MyApp({super.key, required this.autoLoggedIn});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'PensaConnect',
      theme: themeProvider.getThemeData(Brightness.light),
      darkTheme: themeProvider.getThemeData(Brightness.dark),
      themeMode: themeProvider.themeMode,
      routerConfig: _router(context),
    );
  }

  GoRouter _router(BuildContext context) {
    return GoRouter(
      initialLocation: Routes.splash,
      routes: [
        // 🔹 Auth
        GoRoute(path: Routes.splash, builder: (_, __) => const SplashScreen()),
        GoRoute(path: Routes.login, builder: (_, __) => const LoginScreen()),
        GoRoute(
          path: Routes.register,
          builder: (_, __) => const RegisterScreen(),
        ),

        // 🔹 Home
        GoRoute(path: Routes.home, builder: (_, __) => const HomeScreen()),

        // 🔹 Live / Test
        GoRoute(
          path: Routes.live,
          builder: (_, __) => const LiveStreamScreen(),
        ),
        GoRoute(
          path: Routes.test,
          builder: (_, __) => const TestConnectionScreen(),
        ),

        // 🔹 Events
        GoRoute(path: Routes.events, builder: (_, __) => const EventsScreen()),

        // 🔹 Bible Study
        GoRoute(
          path: Routes.bible,
          builder: (_, __) => const BibleStudyScreen(),
          routes: [
            GoRoute(
              path: 'detail/:type/:id',
              builder: (context, state) {
                final item = state.extra;
                if (item == null) {
                  return const Scaffold(
                    body: Center(child: Text('No data passed')),
                  );
                }
                return BibleStudyDetailScreen(item: item);
              },
            ),
            GoRoute(
              path: 'study-plan/create',
              builder: (context, state) => const CreateStudyPlanScreen(),
            ),
          ],
        ),

        // 🔹 Worship
        GoRoute(
          path: Routes.worship,
          builder: (_, __) => const WorshipScreen(),
        ),
        GoRoute(
          path: '/worship/player',
          builder: (_, state) {
            final extra = state.extra! as Map;
            return WorshipPlayerScreen(
              songs: List<WorshipSong>.from(extra['songs']),
              initialIndex: extra['initialIndex'],
            );
          },
        ),
        GoRoute(
          path: '/worship/upload',
          builder: (context, state) => const AdminUploadScreen(),
        ),

        // 🔹 Forums
        GoRoute(path: Routes.forums, builder: (_, __) => const ThreadsScreen()),

        GoRoute(
          path: '/threads/new',
          builder: (_, __) => const ThreadFormScreen(),
        ),

        GoRoute(
          path: '/threads/:threadId',
          builder: (context, state) {
            final params = state.extra as Map<String, dynamic>? ?? {};
            final threadId =
                int.tryParse(state.pathParameters['threadId'] ?? '') ?? 0;
            final threadTitle = params['title'] as String? ?? 'Thread';

            return ForumDetailScreen(
              threadId: threadId,
              threadTitle: threadTitle,
            );
          },
        ),

        GoRoute(
          path: '/posts/:postId',
          builder: (context, state) {
            final postId =
                int.tryParse(state.pathParameters['postId'] ?? '') ?? 0;

            // ✅ Get threadId passed via `extra`
            final extra = state.extra as Map<String, dynamic>?;
            final threadId = extra?['threadId'] as int? ?? 0;

            return PostDetailScreen(threadId: threadId, postId: postId);
          },
        ),

        GoRoute(
          path: '/threads/:threadId/new-post',
          builder: (context, state) {
            final threadId =
                int.tryParse(state.pathParameters['threadId'] ?? '') ?? 0;
            return PostFormScreen(threadId: threadId, threadTitle: '');
          },
        ),

        // 🔹 Prayer Wall
        GoRoute(
          path: Routes.prayerWall,
          builder: (context, state) {
            return ChangeNotifierProvider(
              create: (_) => PrayerRepository(),
              child: const PrayerWallScreen(),
            );
          },
        ),

        // 🔹 Testimonies
        GoRoute(
          path: Routes.testimonies,
          builder: (_, __) => const TestimoniesScreen(),
        ),
        GoRoute(
          path: '/testimonies/add',
          builder: (_, __) => const AddTestimonyScreen(),
        ),
        GoRoute(
          path: '/testimonies/:id',
          builder: (context, state) {
            final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
            return TestimonyDetailScreen(id: id);
          },
        ),

        // 🔹 Group Chats
        GoRoute(
          path: Routes.groupChats,
          builder: (_, __) => const GroupChatsScreen(),
        ),
        GoRoute(
          path: '/group-chats/detail',
          builder: (context, state) {
            final extras = state.extra as Map<String, dynamic>? ?? {};
            return GroupChatDetailScreen(
              groupId: extras['groupId'] as int? ?? 0,
              groupName: extras['groupName'] as String? ?? 'Group Chat',
            );
          },
        ),

        // 🔹 Anonymous Chat
        GoRoute(
          path: Routes.anonymousChat,
          builder: (context, state) {
            final extras = state.extra as Map<String, dynamic>? ?? {};
            return AnonymousChatScreen(
              chatId: extras['chatId'] as String? ?? 'anonymous',
              topic: extras['topic'] as String? ?? 'Anonymous Chat',
            );
          },
        ),

        // 🔹 Profile & Settings
        GoRoute(
          path: Routes.profile,
          builder: (context, state) => const ProfileScreen(),
        ),

        GoRoute(
          path: Routes.settings,
          builder: (_, __) => const SettingsScreen(),
        ),

        // 🔹 Account / Support related routes
        GoRoute(
          path: Routes.changePassword,
          builder: (_, __) => const ChangePasswordScreen(),
        ),
        GoRoute(
          path: Routes.termsPrivacy,
          builder: (_, __) => const TermsAndPrivacyScreen(),
        ),
        GoRoute(
          path: Routes.helpSupport,
          builder: (_, __) => const HelpAndSupportScreen(),
        ),
      ],

      redirect: (BuildContext context, GoRouterState state) {
        final authProvider = context.read<AuthProvider>();
        final isAuthenticated = authProvider.isAuthenticated;

        final location = state.uri.toString();

        final isSplash = location == Routes.splash;
        final isLogin = location == Routes.login;
        final isRegister = location == Routes.register;

        if (!isAuthenticated && !isLogin && !isSplash && !isRegister) {
          return Routes.login;
        }
        if (isAuthenticated && (isLogin || isSplash || isRegister)) {
          return Routes.home;
        }
        return null;
      },

      errorBuilder: (context, state) => Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('404 - Page Not Found'),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => context.go(Routes.home),
                child: const Text('Return Home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
