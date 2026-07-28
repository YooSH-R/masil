import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/utils/router.dart';
import 'core/network/dio_client.dart';
import 'data/repositories/auth_repository_impl.dart';
import 'presentation/viewmodels/auth_view_model.dart';

void main() {
  final dioClient = DioClient();
  final authRepository = AuthRepositoryImpl(dioClient);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthViewModel(authRepository)),
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
