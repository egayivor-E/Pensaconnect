import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:go_router/go_router.dart';
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
import 'package:pensaconnect/services/socketio_service.dart';
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
import 'services/auth_service.dart';

// ✅ FIX: Web-compatible import for flutter_secure_storage
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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

void main() {
  // ✅ Web-compatible error handling
  FlutterError.onError = (FlutterErrorDetails details) {
    developer.log(
      '❌ FLUTTER ERROR: ${details.exceptionAsString()}',
      name: 'main',
      error: details.exception,
      stackTrace: details.stack,
    );
  };

  runZonedGuarded(() async {
    try {
      WidgetsFlutterBinding.ensureInitialized();

      // Load .env file
      developer.log("🔄 Loading .env file...", name: 'main');
      await dotenv.load(fileName: ".env");

      // Debug .env variables
      developer.log("🎯 .env FILE DEBUG INFO:", name: 'main');
      developer.log("   - ENABLE_LIVE_CHAT: '${dotenv.env['ENABLE_LIVE_CHAT']}'", name: 'main');
      developer.log("   - BACKEND_URL: '${dotenv.env['BACKEND_URL']}'", name: 'main');
      developer.log("   - WEBSOCKET_URL: '${dotenv.env['WEBSOCKET_URL']}'", name: 'main');
      developer.log("   - YOUTUBE_VIDEO_ID: '${dotenv.env['YOUTUBE_VIDEO_ID']}'", name: 'main');
      developer.log("   - All loaded keys: ${dotenv.env.keys.length}", name: 'main');

      // Initialize ApiService
      developer.log("🔄 MAIN: Starting ApiService.init()...", name: 'main');
      await ApiService.init();
      developer.log("✅ MAIN: ApiService.init() completed", name: 'main');

      // ✅ FIX: Properly initialize AuthService
      developer.log("🔄 MAIN: Initializing AuthService...", name: 'main');
      final authService = AuthService();
      
      // IMPORTANT: Initialize the auth service properly
      await authService.initialize();
      
      // Verify user is loaded
      if (authService.currentUser != null) {
        developer.log(
          "✅ MAIN: User loaded - ID=${authService.userId}, Username=${authService.username}",
          name: 'main'
        );
      } else {
        developer.log("⚠️ MAIN: No user found - trying to refresh...", name: 'main');
        await authService.refreshUser(retries: 3);
        
        if (authService.currentUser != null) {
          developer.log(
            "✅ MAIN: User refreshed - ID=${authService.userId}, Username=${authService.username}",
            name: 'main'
          );
        } else {
          developer.log("⚠️ MAIN: No user found after refresh", name: 'main');
        }
      }

      // Initialize Socket.IO Service
      developer.log("🔄 MAIN: Initializing Socket.IO Service...", name: 'main');
      final socketService = SocketIoService();
      try {
        await socketService.initialize();
        developer.log("✅ Socket.IO Service initialized successfully", name: 'main');
      } catch (e) {
        developer.log("❌ Socket.IO Service initialization failed: $e", name: 'main');
      }

      // Debug token status
      await ApiService.debugTokenStatus();

      // ✅ FIX: Create auth provider with proper initialization
      final authProvider = AuthProvider();
      
      // Check if we should auto-login
      final autoLoggedIn = await authProvider.tryAutoLogin();
      
      // Sync auth provider with auth service
      if (authService.currentUser != null && !authProvider.isAuthenticated) {
        developer.log("🔄 MAIN: Syncing AuthProvider with AuthService", name: 'main');
        await authProvider.login(
          authService.currentUser!['email'] ?? '',
          '', // Password not needed for sync
          token: await authService.getToken(),
          refreshToken: await authService.getRefreshToken(),
        );
      }

      developer.log("🔐 MAIN: Auth state - Auto-login: $autoLoggedIn, IsAuthenticated: ${authProvider.isAuthenticated}", name: 'main');

      // ✅ FIX: Run app with all providers
      runApp(
        MultiProvider(
          providers: [
            // Provide auth service globally
            Provider<AuthService>.value(value: authService),
            
            // Auth provider
            ChangeNotifierProvider.value(value: authProvider),
            
            // Repositories
            Provider<AuthRepository>(create: (_) => AuthRepository()),
            
            // Theme provider
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
            
            // Prayer repository
            ChangeNotifierProvider(create: (_) => PrayerRepository()),
            
            // Testimony repository
            Provider<TestimonyRepository>(create: (_) => TestimonyRepository()),
            
            // Threads provider
            ChangeNotifierProvider(create: (_) => ThreadsProvider()),
            
            // Worship providers
            ChangeNotifierProvider(create: (_) => SongProvider()),
            ChangeNotifierProvider(create: (_) => PlayerProvider()),
            ChangeNotifierProvider(create: (_) => DownloadProvider()),
            
            // Dio
            Provider<Dio>(create: (_) => Dio()),
            
            // Forum repository
            Provider<ForumRepository>(create: (_) => ForumRepository()),
            
            // Socket service
            Provider<SocketIoService>.value(value: socketService),
            
            // Group chat repository with dependencies
            ProxyProvider3<Dio, AuthRepository, SocketIoService, GroupChatRepository>(
              update: (_, dio, auth, socket, __) => GroupChatRepository(
                dio,
                auth,
                socket,
              ),
            ),
            
            // Profile view model
            ChangeNotifierProvider(
              create: (context) => ProfileViewModel(
                authRepo: context.read<AuthRepository>(),
                prayerRepo: context.read<PrayerRepository>(),
                testimonyRepo: context.read<TestimonyRepository>(),
                groupRepo: context.read<GroupChatRepository>(),
              ),
            ),
          ],
          child: MyApp(autoLoggedIn: autoLoggedIn),
        ),
      );
      
      // ✅ FIX: Debug final auth state
      await Future.delayed(const Duration(milliseconds: 500));
      developer.log("🔍 FINAL AUTH STATE CHECK:", name: 'main');
      await authService.debugAuthState();
      
    } catch (e, stackTrace) {
      developer.log(
        '❌ FATAL: App initialization failed: $e',
        name: 'main',
        error: e,
        stackTrace: stackTrace,
      );
      
      // Show error screen
      runApp(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 64, color: Colors.red),
                    const SizedBox(height: 20),
                    const Text(
                      'Failed to Start App',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      e.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () => main(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
  }, (error, stackTrace) {
    developer.log(
      '❌ ASYNC ERROR: $error',
      name: 'main',
      error: error,
      stackTrace: stackTrace,
    );
  });
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
        // Auth Routes
        GoRoute(path: Routes.splash, builder: (_, __) => const SplashScreen()),
        GoRoute(path: Routes.login, builder: (_, __) => const LoginScreen()),
        GoRoute(path: Routes.register, builder: (_, __) => const RegisterScreen()),
        GoRoute(path: Routes.home, builder: (_, __) => const HomeScreen()),
        GoRoute(path: Routes.live, builder: (_, __) => const LiveStreamScreen()),
        GoRoute(path: Routes.test, builder: (_, __) => const TestConnectionScreen()),
        GoRoute(path: Routes.events, builder: (_, __) => const EventsScreen()),
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
        GoRoute(path: Routes.worship, builder: (_, __) => const WorshipScreen()),
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
        GoRoute(path: Routes.forums, builder: (_, __) => const ThreadsScreen()),
        GoRoute(path: '/threads/new', builder: (_, __) => const ThreadFormScreen()),
        GoRoute(
          path: '/threads/:threadId',
          builder: (context, state) {
            final params = state.extra as Map<String, dynamic>? ?? {};
            final threadId = int.tryParse(state.pathParameters['threadId'] ?? '') ?? 0;
            final threadTitle = params['title'] as String? ?? 'Thread';
            return ForumDetailScreen(threadId: threadId, threadTitle: threadTitle);
          },
        ),
        GoRoute(
          path: '/posts/:postId',
          builder: (context, state) {
            final postId = int.tryParse(state.pathParameters['postId'] ?? '') ?? 0;
            final extra = state.extra as Map<String, dynamic>?;
            final threadId = extra?['threadId'] as int? ?? 0;
            return PostDetailScreen(threadId: threadId, postId: postId);
          },
        ),
        GoRoute(
          path: '/threads/:threadId/new-post',
          builder: (context, state) {
            final threadId = int.tryParse(state.pathParameters['threadId'] ?? '') ?? 0;
            return PostFormScreen(threadId: threadId, threadTitle: '');
          },
        ),
        GoRoute(
          path: Routes.prayerWall,
          builder: (context, state) {
            return ChangeNotifierProvider(
              create: (_) => PrayerRepository(),
              child: const PrayerWallScreen(),
            );
          },
        ),
        GoRoute(path: Routes.testimonies, builder: (_, __) => const TestimoniesScreen()),
        GoRoute(path: '/testimonies/add', builder: (_, __) => const AddTestimonyScreen()),
        GoRoute(
          path: '/testimonies/:id',
          builder: (context, state) {
            final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
            return TestimonyDetailScreen(id: id);
          },
        ),
        GoRoute(path: Routes.groupChats, builder: (_, __) => const GroupChatsScreen()),
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
        GoRoute(path: Routes.profile, builder: (context, state) => const ProfileScreen()),
        GoRoute(path: Routes.settings, builder: (_, __) => const SettingsScreen()),
        GoRoute(path: Routes.changePassword, builder: (_, __) => const ChangePasswordScreen()),
        GoRoute(path: Routes.termsPrivacy, builder: (_, __) => const TermsAndPrivacyScreen()),
        GoRoute(path: Routes.helpSupport, builder: (_, __) => const HelpAndSupportScreen()),
      ],
      redirect: (BuildContext context, GoRouterState state) {
        final authProvider = context.read<AuthProvider>();
        final authService = context.read<AuthService>();
        final isAuthenticated = authProvider.isAuthenticated || authService.currentUser != null;
        final location = state.uri.toString();

        final publicRoutes = [Routes.splash, Routes.login, Routes.register];
        final isPublicRoute = publicRoutes.contains(location);

        // ✅ FIX: Log redirect decisions
        developer.log(
          "🔄 Redirect check: isAuthenticated=$isAuthenticated, location=$location, isPublicRoute=$isPublicRoute",
          name: 'MyApp',
        );

        if (!isAuthenticated && !isPublicRoute) {
          developer.log("🔀 Redirecting to login (not authenticated)", name: 'MyApp');
          return Routes.login;
        }
        if (isAuthenticated && isPublicRoute && location != Routes.home) {
          developer.log("🔀 Redirecting to home (already authenticated)", name: 'MyApp');
          return Routes.home;
        }
        return null;
      },
      errorBuilder: (context, state) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 20),
                const Text(
                  '404 - Page Not Found',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Text(
                  'The page you\'re looking for doesn\'t exist.',
                  style: TextStyle(color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: () => context.go(Routes.home),
                  icon: const Icon(Icons.home),
                  label: const Text('Return Home'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
