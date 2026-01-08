
import 'package:http/http.dart' as http;
import 'package:cookie_jar/cookie_jar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:eventit/config.dart';

class HttpClient {
  static http.Client? _client;
  static PersistCookieJar? _cookieJar;

  static Future<void> initialize() async {
    if (_client == null) {
      final Directory appDocDir = await getApplicationDocumentsDirectory();
      final String appDocPath = appDocDir.path;
      final String cookiePath = path.join(appDocPath, ".cookies");
      _cookieJar = PersistCookieJar(
        ignoreExpires: false,
        storage: FileStorage(cookiePath),
      );
      _client = http.Client();
      print("--- HttpClient Initialized ---");
    }
  }

  static Future<String> _getCookieHeader(Uri url) async {
    if (_cookieJar == null) await initialize();
    List<Cookie> cookies = await _cookieJar!.loadForRequest(url);
    return cookies.map((c) => '${c.name}=${c.value}').join('; ');
  }

  static Future<void> _saveCookies(Uri url, http.Response response) async {
    if (_cookieJar == null) await initialize();
    String? setCookieHeader = response.headers['set-cookie'];
    if (setCookieHeader != null) {
      List<Cookie> cookies = [Cookie.fromSetCookieValue(setCookieHeader)];
      await _cookieJar!.saveFromResponse(url, cookies);
    }
  }

  static Exception _handleError(dynamic e) {
    print("--- Network Error: $e ---");

    if (e is SocketException) {
      return Exception("Koneksi terputus. Periksa internet Anda.");
    } else if (e is TimeoutException) {
      return Exception("Koneksi lambat. Silakan coba lagi.");
    } else if (e is FormatException) {
      return Exception("Terjadi kesalahan data dari server.");
    } else {
      return Exception("Terjadi kesalahan jaringan. Silakan coba lagi.");
    }
  }

  static Future<http.Response> get(String endpoint) async {
    try {
      if (_client == null) await initialize();
      final url = Uri.parse('${AppConfig.apiBaseUrl}$endpoint');
      final cookieHeader = await _getCookieHeader(url);
      final headers = {
        'Content-Type': 'application/json',
        if (cookieHeader.isNotEmpty) 'cookie': cookieHeader,
      };

      print('--- DEBUG [GET] URL: $url');

      final response = await _client!.get(url, headers: headers).timeout(const Duration(seconds: 15));

      await _saveCookies(url, response);
      return response;

    } catch (e) {
      throw _handleError(e);
    }
  }

  static Future<http.Response> post(String endpoint, Map<String, dynamic> body) async {
    try {
      if (_client == null) await initialize();
      final url = Uri.parse('${AppConfig.apiBaseUrl}$endpoint');
      final cookieHeader = await _getCookieHeader(url);
      final headers = {
        'Content-Type': 'application/json',
        if (cookieHeader.isNotEmpty) 'cookie': cookieHeader,
      };
      final encodedBody = json.encode(body);

      print('--- DEBUG [POST] URL: $url');

      final response = await _client!.post(url, headers: headers, body: encodedBody).timeout(const Duration(seconds: 15));

      await _saveCookies(url, response);
      return response;

    } catch (e) {
      throw _handleError(e);
    }
  }

  static Future<void> clearCookies() async {
    if (_cookieJar != null) {
      await _cookieJar!.deleteAll();
    } else {
      await initialize();
      if (_cookieJar != null) {
        await _cookieJar!.deleteAll();
      }
    }
  }
}