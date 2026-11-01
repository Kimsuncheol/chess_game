import 'package:flutter/widgets.dart';

import 'app/app_dependencies.dart';
import 'app/chess_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ChessApp(dependencies: AppDependencies.placeholder()));
}
