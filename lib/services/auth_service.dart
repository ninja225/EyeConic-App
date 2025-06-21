import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jwt_decoder/jwt_decoder.dart';

class AuthService {
  // Use different base URLs depending on platform
  static String get baseUrl {
    if (kIsWeb) {
      return 'http://localhost:8000/api/users';
    } else if (Platform.isAndroid) {
      return 'https://present-factually-monkey.ngrok-free.app/api/users';
    } else {
      return 'http://localhost:8000/api/users';
    }
  }

  final logger = Logger();

  // Secure storage for tokens (initialize in methods)
  FlutterSecureStorage get _secureStorage => const FlutterSecureStorage();

  // Keys for storage
  static const String _accessTokenKey = 'access_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _userInfoKey = 'user_info';

  Map<String, String> get _headers => {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };

  Map<String, String> _headersWithAuth(String token) => {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };

  /// Register a new user
  Future<Map<String, dynamic>> register({
    required String firstName,
    required String lastName,
    required String username,
    required String email,
    required String password1,
    required String password2,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/register/'),
            headers: _headers,
            body: json.encode({
              'first_name': firstName,
              'last_name': lastName,
              'username': username,
              'email': email,
              'password1': password1,
              'password2': password2,
            }),
          )
          .timeout(const Duration(seconds: 10));

      final responseData = json.decode(response.body);

      if (response.statusCode == 201) {
        logger.d('User registered successfully');
        return {
          'success': true,
          'message': 'Registration successful! Please login.',
          'data': responseData,
        };
      } else {
        logger.e(
          'Registration failed: ${response.statusCode} - ${response.body}',
        );
        return {
          'success': false,
          'message': _extractErrorMessage(responseData),
          'errors': responseData,
        };
      }
    } catch (e) {
      logger.e('Error during registration: $e');
      return {
        'success': false,
        'message': 'Network error. Please check your connection.',
        'error': e.toString(),
      };
    }
  }

  /// Login user and store tokens
  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/login/'),
            headers: _headers,
            body: json.encode({'username': username, 'password': password}),
          )
          .timeout(const Duration(seconds: 10));

      final responseData = json.decode(response.body);

      if (response.statusCode == 200) {
        // Store tokens securely
        await _secureStorage.write(
          key: _accessTokenKey,
          value: responseData['access'],
        );
        await _secureStorage.write(
          key: _refreshTokenKey,
          value: responseData['refresh'],
        );

        // Store user info
        final userInfo = {
          'username': username,
          'loginTime': DateTime.now().millisecondsSinceEpoch,
        };
        await _secureStorage.write(
          key: _userInfoKey,
          value: json.encode(userInfo),
        );

        logger.d('Login successful');
        return {
          'success': true,
          'message': 'Login successful!',
          'tokens': responseData,
          'userInfo': userInfo,
        };
      } else {
        logger.e('Login failed: ${response.statusCode} - ${response.body}');
        return {
          'success': false,
          'message': _extractErrorMessage(responseData),
          'errors': responseData,
        };
      }
    } catch (e) {
      logger.e('Error during login: $e');
      return {
        'success': false,
        'message': 'Network error. Please check your connection.',
        'error': e.toString(),
      };
    }
  }

  /// Logout user and clear tokens
  Future<Map<String, dynamic>> logout() async {
    try {
      final refreshToken = await _secureStorage.read(key: _refreshTokenKey);

      if (refreshToken != null) {
        // Call backend logout to blacklist the refresh token
        final response = await http
            .post(
              Uri.parse('$baseUrl/logout/'),
              headers: _headersWithAuth(await getAccessToken() ?? ''),
              body: json.encode({'refresh': refreshToken}),
            )
            .timeout(const Duration(seconds: 5));

        logger.d('Logout response: ${response.statusCode}');
      }

      // Clear all stored auth data
      await _clearAuthData();

      return {'success': true, 'message': 'Logged out successfully'};
    } catch (e) {
      logger.e('Error during logout: $e');
      // Still clear local data even if backend call fails
      await _clearAuthData();
      return {'success': true, 'message': 'Logged out successfully'};
    }
  }

  /// Clear all authentication data
  Future<void> _clearAuthData() async {
    await _secureStorage.delete(key: _accessTokenKey);
    await _secureStorage.delete(key: _refreshTokenKey);
    await _secureStorage.delete(key: _userInfoKey);
  }

  /// Get stored access token
  Future<String?> getAccessToken() async {
    try {
      return await _secureStorage.read(key: _accessTokenKey);
    } catch (e) {
      logger.e('Error reading access token: $e');
      return null;
    }
  }

  /// Get stored refresh token
  Future<String?> getRefreshToken() async {
    try {
      return await _secureStorage.read(key: _refreshTokenKey);
    } catch (e) {
      logger.e('Error reading refresh token: $e');
      return null;
    }
  }

  /// Get user information
  Future<Map<String, dynamic>?> getUserInfo() async {
    try {
      final userInfoStr = await _secureStorage.read(key: _userInfoKey);
      if (userInfoStr != null) {
        return json.decode(userInfoStr);
      }
      return null;
    } catch (e) {
      logger.e('Error reading user info: $e');
      return null;
    }
  }

  /// Check if user is authenticated
  Future<bool> isAuthenticated() async {
    try {
      final accessToken = await getAccessToken();
      if (accessToken == null) return false;

      // Check if token is expired
      if (JwtDecoder.isExpired(accessToken)) {
        logger.d('Access token expired, attempting refresh');
        return await refreshAccessToken();
      }

      return true;
    } catch (e) {
      logger.e('Error checking authentication: $e');
      return false;
    }
  }

  /// Refresh access token using refresh token
  Future<bool> refreshAccessToken() async {
    try {
      final refreshToken = await getRefreshToken();
      if (refreshToken == null) return false;

      // Check if refresh token is expired
      if (JwtDecoder.isExpired(refreshToken)) {
        logger.d('Refresh token expired, user needs to login again');
        await _clearAuthData();
        return false;
      }

      // For this implementation, we'll use the simple JWT refresh endpoint
      // Since the backend doesn't have a dedicated refresh endpoint,
      // we'll need to handle token refresh through re-authentication when needed

      // In a full implementation, you'd have a refresh endpoint like:
      // POST /api/users/token/refresh/ with { "refresh": "token" }

      logger.d('Token refresh not implemented, user needs to login again');
      await _clearAuthData();
      return false;
    } catch (e) {
      logger.e('Error refreshing token: $e');
      await _clearAuthData();
      return false;
    }
  }

  /// Get authorization headers for API calls
  Future<Map<String, String>?> getAuthHeaders() async {
    final accessToken = await getAccessToken();
    if (accessToken == null) return null;

    return _headersWithAuth(accessToken);
  }

  /// Extract error message from API response
  String _extractErrorMessage(Map<String, dynamic> responseData) {
    if (responseData.containsKey('detail')) {
      return responseData['detail'];
    }

    if (responseData.containsKey('non_field_errors')) {
      return responseData['non_field_errors'][0];
    }

    // Handle field-specific errors
    final errorMessages = <String>[];
    responseData.forEach((key, value) {
      if (value is List && value.isNotEmpty) {
        errorMessages.add('$key: ${value[0]}');
      } else if (value is String) {
        errorMessages.add('$key: $value');
      }
    });

    return errorMessages.isNotEmpty
        ? errorMessages.join(', ')
        : 'An error occurred';
  }

  /// Check token expiration time
  Future<DateTime?> getTokenExpirationTime() async {
    try {
      final accessToken = await getAccessToken();
      if (accessToken == null) return null;

      final decodedToken = JwtDecoder.decode(accessToken);
      final exp = decodedToken['exp'] as int;
      return DateTime.fromMillisecondsSinceEpoch(exp * 1000);
    } catch (e) {
      logger.e('Error getting token expiration: $e');
      return null;
    }
  }
}
