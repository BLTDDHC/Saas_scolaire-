import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'data/services/store_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storeService = StoreService();
  await storeService.init();

  runApp(
    ChangeNotifierProvider<StoreService>.value(
      value: storeService,
      child: const EduProApp(),
    ),
  );
}
