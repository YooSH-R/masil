import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../viewmodels/walk_view_model.dart';

class MainScreen extends StatelessWidget {
  final Widget child;

  const MainScreen({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isWalking = context.watch<WalkViewModel>().isWalking;
    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _calculateSelectedIndex(context),
        onTap: (index) => _onItemTapped(index, context, isWalking),
        selectedItemColor: Colors.brown,
        unselectedItemColor: Colors.grey,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: '홈',
          ),
          BottomNavigationBarItem(
            icon: _WalkTabIcon(active: false, walking: isWalking),
            activeIcon: _WalkTabIcon(active: true, walking: isWalking),
            label: isWalking ? '산책 중' : '산책',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.pets_outlined),
            activeIcon: Icon(Icons.pets),
            label: '실내모드',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: '마이페이지',
          ),
        ],
      ),
    );
  }

  int _calculateSelectedIndex(BuildContext context) {
    final String location = GoRouterState.of(context).uri.path;
    if (location.startsWith('/home')) return 0;
    if (location.startsWith('/walk')) return 1;
    if (location.startsWith('/indoor')) return 2;
    if (location.startsWith('/user')) return 3;
    return 0;
  }

  void _onItemTapped(int index, BuildContext context, bool isWalking) {
    switch (index) {
      case 0:
        context.go('/home');
        break;
      case 1:
        context.go(isWalking ? '/walk/in-progress' : '/walk');
        break;
      case 2:
        context.go('/indoor');
        break;
      case 3:
        context.go('/user');
        break;
    }
  }
}

class _WalkTabIcon extends StatelessWidget {
  const _WalkTabIcon({required this.active, required this.walking});

  final bool active;
  final bool walking;

  @override
  Widget build(BuildContext context) {
    return Badge(
      isLabelVisible: walking,
      smallSize: 9,
      backgroundColor: Colors.redAccent,
      child:
          Icon(active ? Icons.directions_walk : Icons.directions_walk_outlined),
    );
  }
}
