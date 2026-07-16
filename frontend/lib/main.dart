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
import 'screens/notifications_screen.dart';
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
import 'screens/discover_groups_screen.dart';
import 'screens/new_message_screen.dart';
import 'screens/anonymous_chat_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/user_profile_screen.dart';
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
import 'theme/app_style.dart';

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
  static const discoverGroups = '/group-chats/discover';
  static const newMessage = '/messages/new';
  static const anonymousChat = '/anonymous-chat';
  static const profile = '/profile';
  static const userProfile = '/profile/:userId';
  static const notifications = '/notifications';
  static const settings = '/settings';
  static const changePassword = '/change-password';
  static const termsPrivacy = '/terms-privacy';
  static const helpSupport = '/help-support';
}

/// Shown the instant the Dart entrypoint runs — before dotenv, ApiService,
/// auto-login, or the socket connection have even started. Those calls are
/// awaited sequentially in main() and can take a long time on a cold
/// backend (e.g. Render's free tier spinning back up), and nothing was
/// painted until they all finished. That left the browser tab on a blank
/// grey <body> with zero feedback for as long as 30-60s. This widget has
/// no dependency on GoRouter, providers, or the network, so it always
/// paints on the very first frame — main() swaps it out for the real
/// MyApp (or the error screen) once setup actually completes.
class _BootSplash extends StatelessWidget {
  const _BootSplash();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.inkDusk, AppColors.emberGold],
            ),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: ShapeDecoration(
                    color: Colors.white.withOpacity(0.14),
                    shape: AppShapes.archBorder(top: 40, bottom: 20),
                  ),
                  child: const Icon(
                    Icons.people_alt_rounded,
                    size: 60,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'PensaConnect',
                  style: Theme.of(
                    context,
                  ).textTheme.displayMedium?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 6),
                Text(
                  'Ladies & Gents Wing',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white.withOpacity(0.85),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 48),
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void main() {
  // Paint something immediately — see _BootSplash doc comment above.
  runApp(const _BootSplash());

  // ✅ Web-compatible error handling
  FlutterError.onError = (FlutterErrorDetails details) {
    developer.log(
      '❌ FLUTTER ERROR: ${details.exceptionAsString()}',
      name: 'main',
      error: details.exception,
      stackTrace: details.stack,
    );
  };

  runZonedGuarded(
    () async {
      try {
        WidgetsFlutterBinding.ensureInitialized();

        // Load .env file
        developer.log("🔄 Loading .env file...", name: 'main');
        await dotenv.load(fileName: "assets/.env");

        // Debug .env variables
        developer.log("🎯 .env FILE DEBUG INFO:", name: 'main');
        developer.log(
          "   - ENABLE_LIVE_CHAT: '${dotenv.env['ENABLE_LIVE_CHAT']}'",
          name: 'main',
        );
        developer.log(
          "   - BACKEND_URL: '${dotenv.env['BACKEND_URL']}'",
          name: 'main',
        );
        developer.log(
          "   - WEBSOCKET_URL: '${dotenv.env['WEBSOCKET_URL']}'",
          name: 'main',
        );
        developer.log(
          "   - YOUTUBE_VIDEO_ID: '${dotenv.env['YOUTUBE_VIDEO_ID']}'",
          name: 'main',
        );
        developer.log(
          "   - All loaded keys: ${dotenv.env.keys.length}",
          name: 'main',
        );

        // Initialize ApiService
        developer.log("🔄 MAIN: Starting ApiService.init()...", name: 'main');
        await ApiService.init();
        developer.log("✅ MAIN: ApiService.init() completed", name: 'main');

        // Load user data
        developer.log("🔄 MAIN: Loading user data...", name: 'main');
        final authService = AuthService();
        await authService.refreshUser();

        if (authService.currentUser != null) {
          developer.log(
            "✅ MAIN: User loaded - ID=${authService.userId}, Username=${authService.username}",
            name: 'main',
          );
        } else {
          developer.log("⚠️ MAIN: No user found", name: 'main');
        }

        // Initialize Socket.IO Service
        developer.log(
          "🔄 MAIN: Initializing Socket.IO Service...",
          name: 'main',
        );
        final socketService = SocketIoService();
        try {
          await socketService.initialize();
          developer.log(
            "✅ Socket.IO Service initialized successfully",
            name: 'main',
          );
        } catch (e) {
          developer.log(
            "❌ Socket.IO Service initialization failed: $e",
            name: 'main',
          );
        }

        // Debug token status
        await ApiService.debugTokenStatus();

        // Create auth provider
        final authProvider = AuthProvider();
        final autoLoggedIn = await authProvider.tryAutoLogin();

        developer.log(
          "🔐 MAIN: Auth state - Auto-login: $autoLoggedIn",
          name: 'main',
        );

        // ✅ FIX: Sync AuthService with AuthProvider after auto-login.
        // AuthProvider.tryAutoLogin() reads the token via ApiService and
        // fetches the profile into AuthProvider.currentUser — but it never
        // writes to AuthService's storage keys, so AuthService.currentUser /
        // getUserId() stayed null even after a successful auto-login. This is
        // what caused "GroupChatDetail: Current User ID = null" downstream.
        if (authProvider.isAuthenticated &&
            authProvider.currentUser != null &&
            authService.currentUser == null) {
          developer.log(
            "🔄 MAIN: Syncing AuthService with AuthProvider (post auto-login)",
            name: 'main',
          );
          await authService.setUserFromExternal({
            'id': authProvider.currentUser!.id,
            'username': authProvider.currentUser!.username,
            'roles': authProvider.currentUser!.roles,
          });
          developer.log(
            "✅ MAIN: AuthService synced - ID=${authService.userId}, Username=${authService.username}",
            name: 'main',
          );
        }

        runApp(
          MultiProvider(
            providers: [
              // Provide AuthService so widgets can use context.read<AuthService>()
              // as an alternative to the AuthService() singleton constructor.
              ChangeNotifierProvider<AuthService>.value(value: authService),
              ChangeNotifierProvider.value(value: authProvider),
              Provider<AuthRepository>(create: (_) => AuthRepository()),
              ChangeNotifierProvider(create: (_) => ThemeProvider()),
              ChangeNotifierProvider(create: (_) => PrayerRepository()),
              Provider<TestimonyRepository>(
                create: (_) => TestimonyRepository(),
              ),
              ChangeNotifierProvider(create: (_) => ThreadsProvider()),
              ChangeNotifierProvider(create: (_) => SongProvider()),
              ChangeNotifierProvider(create: (_) => PlayerProvider()),
              ChangeNotifierProvider(create: (_) => DownloadProvider()),
              Provider<Dio>(create: (_) => Dio()),
              Provider<ForumRepository>(create: (_) => ForumRepository()),
              Provider<SocketIoService>(create: (_) => socketService),
              ProxyProvider3<
                Dio,
                AuthRepository,
                SocketIoService,
                GroupChatRepository
              >(
                update: (_, dio, auth, socket, __) =>
                    GroupChatRepository(dio, auth, socket),
              ),
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
      } catch (e, stackTrace) {
        developer.log(
          '❌ FATAL: App initialization failed: $e',
          name: 'main',
          error: e,
          stackTrace: stackTrace,
        );

        runApp(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.red,
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Failed to Start App',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
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
    },
    (error, stackTrace) {
      developer.log(
        '❌ ASYNC ERROR: $error',
        name: 'main',
        error: error,
        stackTrace: stackTrace,
      );
    },
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
        // Auth Routes
        GoRoute(path: Routes.splash, builder: (_, __) => const SplashScreen()),
        GoRoute(path: Routes.login, builder: (_, __) => const LoginScreen()),
        GoRoute(
          path: Routes.register,
          builder: (_, __) => const RegisterScreen(),
        ),
        GoRoute(path: Routes.home, builder: (_, __) => const HomeScreen()),
        GoRoute(
          path: Routes.live,
          builder: (_, __) => const LiveStreamScreen(),
        ),
        GoRoute(
          path: Routes.test,
          builder: (_, __) => const TestConnectionScreen(),
        ),
        GoRoute(
          path: Routes.events,
          builder: (context, __) => EventsScreen(
            isAdmin: context.watch<AuthProvider>().hasAnyRole(const [
              'admin',
              'moderator',
            ]),
          ),
        ),
        GoRoute(
          path: Routes.notifications,
          builder: (_, __) => const NotificationsScreen(),
        ),
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
            final extra = state.extra as Map<String, dynamic>?;
            final threadTitle = extra?['threadTitle'] as String? ?? 'Thread';
            return PostFormScreen(threadId: threadId, threadTitle: threadTitle);
          },
        ),
        // ✅ No longer wraps PrayerWallScreen in its own scoped
        // PrayerRepository. That created a *second* instance shadowing
        // the one already registered in the root MultiProvider above,
        // so a prayer toggled from anywhere else (e.g. the home feed's
        // "I prayed" action) never showed up here, and vice versa — two
        // disconnected caches for what should be one shared list.
        // PrayerWallScreen now resolves PrayerRepository from the root
        // provider like every other screen does.
        GoRoute(
          path: Routes.prayerWall,
          builder: (_, __) => const PrayerWallScreen(),
        ),
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
        GoRoute(
          path: Routes.discoverGroups,
          builder: (_, __) => const DiscoverGroupsScreen(),
        ),
        GoRoute(
          path: Routes.newMessage,
          builder: (_, __) => const NewMessageScreen(),
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
        GoRoute(
          path: Routes.profile,
          builder: (context, state) => const ProfileScreen(),
        ),
        GoRoute(
          path: Routes.userProfile,
          builder: (context, state) {
            final userId =
                int.tryParse(state.pathParameters['userId'] ?? '') ?? 0;
            return UserProfileScreen(userId: userId);
          },
        ),
        GoRoute(
          path: Routes.settings,
          builder: (_, __) => const SettingsScreen(),
        ),
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

        final publicRoutes = [Routes.splash, Routes.login, Routes.register];
        final isPublicRoute = publicRoutes.contains(location);

        if (!isAuthenticated && !isPublicRoute) {
          return Routes.login;
        }
        if (isAuthenticated && isPublicRoute && location != Routes.home) {
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
