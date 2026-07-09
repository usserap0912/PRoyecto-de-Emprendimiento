import 'package:flutter/material.dart';
import 'package:safezone/theme/app_theme.dart';
import 'package:safezone/screens/wall/wall_screen.dart';
import 'package:safezone/screens/map/risk_map_screen.dart';
import 'package:safezone/screens/sos/sos_screen.dart';
import 'package:safezone/screens/chat/community_chat_screen.dart';
import 'package:safezone/screens/chat/zonebot_screen.dart';
import 'package:safezone/screens/report/report_form_screen.dart';

class HomeScreen extends StatefulWidget {
  final String userCode;
  final int zone;

  const HomeScreen({
    super.key,
    required this.userCode,
    required this.zone,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      WallScreen(userCode: widget.userCode, zone: widget.zone),
      ZoneBotScreen(userCode: widget.userCode, zone: widget.zone),
      RiskMapScreen(userCode: widget.userCode),
      SosScreen(userCode: widget.userCode, zone: widget.zone),
      CommunityChatScreen(userCode: widget.userCode),
      ReportFormScreen(userCode: widget.userCode, zone: widget.zone),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          selectedItemColor: AppTheme.primaryGreen,
          unselectedItemColor: Colors.grey,
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          elevation: 0,
          selectedFontSize: 11,
          unselectedFontSize: 10,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.newspaper_outlined),
              activeIcon: Icon(Icons.newspaper),
              label: 'Muro',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.shield_outlined),
              activeIcon: Icon(Icons.shield),
              label: 'ZoneBot',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.map_outlined),
              activeIcon: Icon(Icons.map),
              label: 'Mapa',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.sos_outlined),
              activeIcon: Icon(Icons.sos),
              label: 'S.O.S.',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.chat_outlined),
              activeIcon: Icon(Icons.chat),
              label: 'Chat',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.add_circle_outline),
              activeIcon: Icon(Icons.add_circle),
              label: 'Reportar',
            ),
          ],
        ),
      ),
    );
  }
}
