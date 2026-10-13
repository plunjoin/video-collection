import 'package:flutter_test/flutter_test.dart';
import 'package:video_collection_app/services/api_service.dart';

void main() {
  test('release build uses the baked API address', () {
    expect(
      resolveApiBaseUrl(
        releaseMode: true,
        definedUrl: 'https://api.example.com/',
        androidEmulator: true,
      ),
      'https://api.example.com',
    );
    expect(
      resolveApiBaseUrl(
        releaseMode: true,
        definedUrl: '',
        androidEmulator: false,
      ),
      '',
    );
  });

  test('debug build keeps a local default until an address is defined', () {
    expect(
      resolveApiBaseUrl(
        releaseMode: false,
        definedUrl: '',
        androidEmulator: true,
      ),
      'http://10.0.2.2:80',
    );
    expect(
      resolveApiBaseUrl(
        releaseMode: false,
        definedUrl: 'http://192.168.1.8:80/',
        androidEmulator: false,
      ),
      'http://192.168.1.8:80',
    );
    expect(allowsApiBaseUrlOverride, isTrue);
  });
}
