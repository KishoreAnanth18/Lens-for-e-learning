import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

void main() {
  runApp(const LensELearningApp());
}

class LensELearningApp extends StatelessWidget {
  const LensELearningApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lens for E-Learning',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lens for E-Learning'),
      ),
      body: const Center(
        child: Text('Welcome to Lens for E-Learning'),
      ),
    );
  }
}
