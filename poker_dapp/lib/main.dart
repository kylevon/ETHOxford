import 'package:flutter/material.dart';
import 'game_screen.dart';

void main() {
  runApp(PokerApp());
}

class PokerApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Poker DApp',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.grey[100],
      ),
      builder: (context, child) {
        return ScaffoldMessenger(
          child: child ?? Container(),
        );
      },
      home: GameScreen(),
    );
  }
}
