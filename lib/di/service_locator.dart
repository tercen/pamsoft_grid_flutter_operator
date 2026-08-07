import 'package:get_it/get_it.dart';
import 'package:pamsoft_grid_flutter_operator/implementations/services/mock_image_service.dart';
import 'package:pamsoft_grid_flutter_operator/implementations/services/mock_grid_service.dart';
import 'package:pamsoft_grid_flutter_operator/implementations/services/mock_storage_service.dart';
import 'package:pamsoft_grid_flutter_operator/implementations/services/tercen_image_service.dart';
import 'package:pamsoft_grid_flutter_operator/implementations/services/tercen_grid_service.dart';
import 'package:pamsoft_grid_flutter_operator/implementations/services/mock_properties_service.dart';
import 'package:pamsoft_grid_flutter_operator/implementations/services/tercen_properties_service.dart';
import 'package:pamsoft_grid_flutter_operator/services/image_service.dart';
import 'package:pamsoft_grid_flutter_operator/services/grid_service.dart';
import 'package:pamsoft_grid_flutter_operator/services/properties_service.dart';
import 'package:pamsoft_grid_flutter_operator/services/storage_service.dart';
import 'package:pamsoft_grid_flutter_operator/utils/tercen_url_parser.dart';
import 'package:sci_tercen_client/sci_client_service_factory.dart' as tercen;

/// Global service locator instance.
final GetIt getIt = GetIt.instance;

/// Alias for backwards compatibility
final GetIt locator = getIt;

/// Sets up the service locator with dependency registrations.
///
/// Call this function before running the app to register all services.
///
/// Parameters:
///   - [useMocks]: If true, registers mock implementations. If false, registers
///     real implementations (when available). Defaults to true.
void setupServiceLocator({bool useMocks = true}) {
  if (useMocks) {
    // Register mock services
    locator.registerSingleton<ImageService>(MockImageService());
    locator.registerSingleton<GridService>(MockGridService());
    locator.registerSingleton<StorageService>(MockStorageService());
    locator.registerSingleton<PropertiesService>(MockPropertiesService());
  } else {
    // Register Tercen services with mock fallback
    final factory = locator<tercen.ServiceFactory>();
    final urlParser = locator<TercenUrlParser>();

    // Create mock services for fallback
    final mockImageService = MockImageService();
    final mockGridService = MockGridService();

    // Register Tercen services that fall back to mocks on error
    locator.registerSingleton<ImageService>(
      TercenImageService(factory, urlParser, mockImageService),
    );
    locator.registerSingleton<GridService>(
      TercenGridService(factory, urlParser, mockGridService),
    );
    locator.registerSingleton<StorageService>(MockStorageService());
    locator.registerSingleton<PropertiesService>(
      TercenPropertiesService(factory, urlParser),
    );
  }
}

/// Resets the service locator.
///
/// Useful for testing to ensure a clean state between tests.
Future<void> resetServiceLocator() async {
  await locator.reset();
}
