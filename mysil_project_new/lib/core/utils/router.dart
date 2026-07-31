import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../presentation/screens/splash/splash_screen.dart';
import '../../presentation/screens/home/home_screen.dart';
import '../../presentation/screens/auth/login_screen.dart';
import '../../presentation/screens/auth/signup_screen.dart';
import '../../presentation/screens/auth/social_signup_screen.dart';
import '../../presentation/screens/auth/auto_login_screen.dart';
import '../../presentation/screens/auth/login_locked_screen.dart';
import '../../presentation/screens/auth/password_reset_screen.dart';
import '../../presentation/screens/main_screen.dart';
import '../../presentation/screens/walk/walk_log_feed_screen.dart';
import '../../presentation/screens/walk/walk_suggestion_screen.dart';
import '../../presentation/screens/walk/walk_ready_screen.dart';
import '../../presentation/screens/walk/walk_declined_screen.dart';
import '../../presentation/screens/walk/walk_in_progress_screen.dart';
import '../../presentation/screens/walk/walk_disconnected_screen.dart';
import '../../presentation/screens/walk/walk_summary_screen.dart';
import '../../presentation/screens/walk/walk_dashboard_screen.dart';
import '../../presentation/screens/walk/walk_path_detail_screen.dart';
import '../../presentation/screens/walk/walk_path_exception_screen.dart';
import '../../presentation/screens/walk/ai_photo_style_screen.dart';
import '../../presentation/screens/indoor/indoor_home_screen.dart';
import '../../presentation/screens/indoor/charging_sleep_screen.dart';
import '../../presentation/screens/indoor/autonomous_roaming_screen.dart';
import '../../presentation/screens/indoor/call_name_setting_screen.dart';
import '../../presentation/screens/indoor/proactive_play_request_screen.dart';
import '../../presentation/screens/indoor/intimacy_mood_screen.dart';
import '../../presentation/screens/indoor/welcome_home_screen.dart';
import '../../presentation/screens/notification/notification_settings_screen.dart';
import '../../presentation/screens/user/my_page_screen.dart';
import '../../presentation/screens/user/reauth_screen.dart';
import '../../presentation/screens/user/profile_edit_screen.dart';
import '../../presentation/screens/user/account_withdrawal_screen.dart';
import '../../presentation/screens/robot/device_registration_qr_screen.dart';
import '../../presentation/screens/robot/device_connection_management_screen.dart';
import '../../presentation/screens/pet/pet_list_screen.dart';
import '../../presentation/screens/pet/pet_profile_edit_screen.dart';
import '../../presentation/screens/pet/pet_delete_confirm_screen.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _shellNavigatorKey = GlobalKey<NavigatorState>();

final GoRouter router = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/splash',
  routes: [
    GoRoute(
      path: '/splash',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/auto-login',
      builder: (context, state) => const AutoLoginScreen(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/signup',
      builder: (context, state) => const SignupScreen(),
    ),
    GoRoute(
      // 구글로 처음 로그인한 회원의 닉네임 설정 단계
      path: '/social-signup',
      builder: (context, state) => const SocialSignupScreen(),
    ),
    GoRoute(
      path: '/login-locked',
      builder: (context, state) => const LoginLockedScreen(),
    ),
    GoRoute(
      path: '/password-reset',
      builder: (context, state) => const PasswordResetScreen(),
    ),
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) => MainScreen(child: child),
      routes: [
        GoRoute(
          path: '/home',
          builder: (context, state) => const HomeScreen(),
        ),
        GoRoute(
          path: '/walk',
          builder: (context, state) => const WalkLogFeedScreen(),
          routes: [
            GoRoute(
              path: 'suggestion',
              builder: (context, state) => const WalkSuggestionScreen(),
            ),
            GoRoute(
              path: 'ready',
              builder: (context, state) => const WalkReadyScreen(),
            ),
            GoRoute(
              path: 'declined',
              builder: (context, state) => const WalkDeclinedScreen(),
            ),
            GoRoute(
              path: 'in-progress',
              builder: (context, state) => const WalkInProgressScreen(),
            ),
            GoRoute(
              path: 'disconnected',
              builder: (context, state) => const WalkDisconnectedScreen(),
            ),
            GoRoute(
              path: 'summary',
              builder: (context, state) => const WalkSummaryScreen(),
            ),
            GoRoute(
              path: 'dashboard',
              builder: (context, state) => const WalkDashboardScreen(),
            ),
            GoRoute(
              path: 'path-detail',
              // 어떤 산책의 경로인지는 extra 로 넘긴다.
              //   context.push('/walk/path-detail', extra: walkId)
              // 넘기지 않으면 진행/최근 산책을 보여준다.
              builder: (context, state) => WalkPathDetailScreen(
                walkId: state.extra is int ? state.extra as int : null,
              ),
              routes: [
                GoRoute(
                  path: 'exception',
                  builder: (context, state) => const WalkPathExceptionScreen(),
                ),
              ],
            ),
            GoRoute(
              path: 'ai-photo',
              builder: (context, state) => const AiPhotoStyleScreen(),
            ),
          ],
        ),
        GoRoute(
          path: '/indoor',
          builder: (context, state) => const IndoorHomeScreen(),
          routes: [
            GoRoute(
              path: 'charging',
              builder: (context, state) => const ChargingSleepScreen(),
            ),
            GoRoute(
              path: 'roaming',
              builder: (context, state) => const AutonomousRoamingScreen(),
            ),
            GoRoute(
              path: 'name-setting',
              builder: (context, state) => const CallNameSettingScreen(),
            ),
            GoRoute(
              path: 'play-request',
              builder: (context, state) => const ProactivePlayRequestScreen(),
            ),
            GoRoute(
              path: 'intimacy',
              builder: (context, state) => const IntimacyMoodScreen(),
            ),
            GoRoute(
              path: 'welcome-home',
              builder: (context, state) => const WelcomeHomeScreen(),
            ),
            GoRoute(
              path: 'notifications',
              builder: (context, state) => const NotificationSettingsScreen(),
            ),
          ],
        ),
        GoRoute(
          path: '/user',
          builder: (context, state) => const MyPageScreen(),
          routes: [
            GoRoute(
              path: 'profile-edit',
              builder: (context, state) => const ProfileEditScreen(),
            ),
            GoRoute(
              path: 'reauth',
              builder: (context, state) => const ReauthScreen(),
            ),
            GoRoute(
              path: 'withdrawal',
              builder: (context, state) => const AccountWithdrawalScreen(),
            ),
            GoRoute(
              path: 'pet-list',
              builder: (context, state) => const PetListScreen(),
              routes: [
                GoRoute(
                  path: 'edit',
                  builder: (context, state) => const PetProfileEditScreen(),
                ),
              ],
            ),
            GoRoute(
              path: 'robot-mgmt',
              builder: (context, state) => const DeviceConnectionManagementScreen(),
              routes: [
                GoRoute(
                  path: 'register',
                  builder: (context, state) => const DeviceRegistrationQrScreen(),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/pet-delete-confirm',
      builder: (context, state) => const PetDeleteConfirmScreen(),
    ),
  ],
);
