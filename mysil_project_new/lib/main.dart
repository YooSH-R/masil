import 'package:flutter/material.dart';
import 'package:kakao_map_plugin/kakao_map_plugin.dart';
import 'package:provider/provider.dart';

import 'core/config/map_config.dart';
import 'core/network/dio_client.dart';
import 'core/services/place_name_resolver.dart';
import 'core/services/walk_route_source.dart';
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

  // 카카오맵(JavaScript API) 초기화. 키가 없으면 지도 화면이 안내를 띄운다.
  if (MapConfig.isKakaoMapConfigured) {
    AuthRepository.initialize(
      appKey: MapConfig.kakaoJsAppKey,
      // baseUrl 을 넘기지 않으면 WebView origin 이 about:blank 가 되어
      // 카카오 도메인 검사에 걸린다. 콘솔에 등록한 도메인과 같아야 한다.
      baseUrl: MapConfig.kakaoMapBaseUrl,
    );
  }

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
        // routeSource: 산책 중 이동경로가 들어오는 입구.
        // 백엔드가 마실이 디바이스의 GPS 푸시를 붙이면, WalkRouteSource 를
        // 구현한 클래스(예: MqttWalkRouteSource)로 이 한 줄만 바꾸면 된다.
        // 화면·폴리라인·시간 표시는 그대로 동작한다.
        ChangeNotifierProvider(
          create: (_) => WalkViewModel(
            walkRepository,
            routeSource: MockWalkRouteSource(),
          ),
        ),
        ChangeNotifierProvider(
            create: (_) => WalkPhotoViewModel(photoRepository)),
        // placeResolver: 좌표 → 장소명(역지오코딩). 산책 일지의 `산책 장소`에 쓴다.
        // 백엔드가 장소명을 내려주게 되면 이 인자를 빼면 된다.
        ChangeNotifierProvider(
            create: (_) => WalkDiaryViewModel(diaryRepository,
                placeResolver: PlaceNameResolver())),
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
