import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app/app_dependencies.dart';
import 'app/chess_app.dart';
import 'services/storage/local_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'bishop',
    ], await rootBundle.loadString('assets/licenses/BISHOP_LICENSE.txt'));
  });
  final storageDirectory = await FileLocalStorage.resolveDefaultDirectory();
  runApp(ChessApp(dependencies: AppDependencies.persistent(storageDirectory)));
}
