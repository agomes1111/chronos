import 'package:shared_preferences/shared_preferences.dart';

class CacheService {
  SharedPreferences? cache;

  Future<void> ensureInitialized() async {
    cache = await SharedPreferences.getInstance();
  }

  Future<bool> storeString({required String k, required String v}) async {
    if (cache == null) {
      throw StateError('cache_service_not_initialized');
    }

    return await cache!.setString(k, v);
  }

  Future<String?> getString(String k) async {
    if (cache == null) {
      throw StateError('cache_service_not_initialized');
    }

    return cache!.getString(k);
  }
}
