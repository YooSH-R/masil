import 'package:flutter/material.dart';

class MysilAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final bool showLogo;

  const MysilAppBar({
    super.key,
    required this.title,
    this.actions,
    this.showLogo = false,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: showLogo 
        ? Image.asset('assets/images/mysil_logo.png', height: 32)
        : Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.brown)),
      centerTitle: showLogo,
      actions: actions,
      backgroundColor: Colors.white,
      elevation: 0,
      iconTheme: const IconThemeData(color: Colors.brown),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
