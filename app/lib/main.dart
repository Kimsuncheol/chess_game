import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app/app_dependencies.dart';
import 'app/chess_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'bishop',
    ], await rootBundle.loadString('assets/licenses/BISHOP_LICENSE.txt'));
  });
  runApp(ChessApp(dependencies: AppDependencies.placeholder()));
}
