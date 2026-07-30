import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/network/dio_client.dart';
import 'core/storage/session_cache.dart';
import 'core/storage/token_storage.dart';
import 'core/utils/router.dart';
import 'data/repositories/auth_repository_impl.dart';
import 'data/repositories/notification_repository_impl.dart';
import 'data/repositories/pet_repository_impl.dart';
import 'data/repositories/robot_repository_impl.dart';
import 'data/repositories/walk_diary_repository_impl.dart';
import 'data/repositories/walk_photo_repository_impl.dart';
import 'data/repositories/walk_repository_impl.dart';
import 'presentation/viewmodels/auth_view_model.dart';
import 'presentation/viewmodels/notification_view_model.dart';
import 'presentation/viewmodels/pet_view_model.dart';
import 'presentation/viewmodels/robot_view_model.dart';
import 'presentation/viewmodels/walk_diary_view_model.dart';
import 'presentation/viewmodels/walk_photo_view_model.dart';
import 'presentation/viewmodels/walk_view_model.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final tokenStorage = TokenStorage();
  final sessionCache = SessionCache();

  // 토큰 재발급까지 실패하면 세션을 끊고 로그인 화면으로 되돌린다.
  // AuthViewModel이 아래에서 만들어지므로 late 참조로 연결한다.
  AuthViewModel? authViewModel;
  final dioClient = DioClient(
    tokenStorage: tokenStorage,
    onSessionExpired: () async {
      authViewModel?.onSessionExpired();
      router.go('/login');
    },
  );
  final apiClient = dioClient.client;

  final authRepository = AuthRepositoryImpl(
    client: apiClient,
    tokenStorage: tokenStorage,
    sessionCache: sessionCache,
  );
  final petRepository = PetRepositoryImpl(
    client: apiClient,
    sessionCache: sessionCache,
  );
  final robotRepository = RobotRepositoryImpl(
    client: apiClient,
    sessionCache: sessionCache,
    tokenStorage: tokenStorage,
  );
  final walkRepository = WalkRepositoryImpl(client: apiClient);
  final photoRepository = WalkPhotoRepositoryImpl(client: apiClient);
  final diaryRepository = WalkDiaryRepositoryImpl(client: apiClient);
  final notificationRepository = NotificationRepositoryImpl(
    client: apiClient,
    tokenStorage: tokenStorage,
  );

  authViewModel = AuthViewModel(authRepository);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authViewModel),
        ChangeNotifierProvider(create: (_) => PetViewModel(petRepository)),
        ChangeNotifierProvider(create: (_) => RobotViewModel(robotRepository)),
        ChangeNotifierProvider(create: (_) => WalkViewModel(walkRepository)),
        ChangeNotifierProvider(
            create: (_) => WalkPhotoViewModel(photoRepository)),
        ChangeNotifierProvider(
            create: (_) => WalkDiaryViewModel(diaryRepository)),
        ChangeNotifierProvider(
          create: (_) => NotificationViewModel(notificationRepository),
        ),
      ],
      child: const MysilApp(),
    ),
  );
}

class MysilApp extends StatelessWidget {
  const MysilApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'MYSIL',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.brown),
      ),
      routerConfig: router,
    );
  }
}
