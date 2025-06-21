import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:http_parser/http_parser.dart';
import 'auth_service.dart';

class ApiService {
  // Use different base URLs depending on platform
  // 10.0.2.2 is the special IP for Android emulator to access host machine
  static String get baseUrl {
    if (kIsWeb) {
      return 'https://present-factually-monkey.ngrok-free.app/api';
    } else if (Platform.isAndroid) {
      return 'https://present-factually-monkey.ngrok-free.app/api';
    } else {
      return 'https://present-factually-monkey.ngrok-free.app/api';
    }
  }

  // Server URL without /api path for accessing media files
  static String get serverBaseUrl {
    if (kIsWeb) {
      return 'https://present-factually-monkey.ngrok-free.app';
    } else if (Platform.isAndroid) {
      return 'https://present-factually-monkey.ngrok-free.app';
    } else {
      return 'https://present-factually-monkey.ngrok-free.app';
    }
  }

  final logger = Logger();
  final AuthService _authService = AuthService();

  Map<String, String> get _headers => {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };

  Future<bool> isServerReachable() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/chat-history/'), headers: _headers)
          .timeout(const Duration(seconds: 5));

      return response.statusCode != 502 &&
          response.statusCode != 503 &&
          response.statusCode != 504;
    } catch (e) {
      logger.e('Server not reachable: $e');
      return false;
    }
  }

  // Original non-streaming method (kept for backward compatibility)
  Future<Map<String, dynamic>> sendMessage(
    String message, {
    File? image,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/chat/');

      // Use MultipartRequest for all platforms
      var request = http.MultipartRequest('POST', uri);
      request.fields['prompt'] = message;

      if (image != null) {
        try {
          String filename = image.path.split('/').last;
          String extension = filename.split('.').last.toLowerCase();

          // Determine content type based on file extension
          String contentType = 'image/jpeg';
          if (extension == 'png') {
            contentType = 'image/png';
          }

          var multipartFile = await http.MultipartFile.fromPath(
            'image',
            image.path,
            contentType: MediaType.parse(contentType),
          );
          request.files.add(multipartFile);

          logger.d('Added image to request: $filename');
        } catch (e) {
          logger.e('Error adding image to request: $e');
          throw Exception('Failed to process image: $e');
        }
      }

      var streamedResponse = await request.send().timeout(
        const Duration(seconds: 30),
      );

      var response = await http.Response.fromStream(streamedResponse);
      logger.d('Message response: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to send message: ${response.body}');
      }
    } on TimeoutException {
      logger.e('Request timed out');
      throw Exception('Request timed out. Please try again.');
    } catch (e) {
      logger.e('Error sending message: $e');
      throw Exception('Failed to communicate with server: $e');
    }
  } // NEW: Streaming message method using custom SSE implementation with better real-time handling

  Stream<Map<String, dynamic>> sendMessageStream(
    String message, {
    File? image,
  }) async* {
    StreamController<Map<String, dynamic>> controller = StreamController();

    try {
      logger.d('Starting streaming request for message: $message');

      final uri = Uri.parse('$baseUrl/chat-stream/');

      // Create multipart request for streaming
      var request = http.MultipartRequest('POST', uri);

      // Add authentication headers
      final authHeaders = await _authService.getAuthHeaders();
      if (authHeaders != null) {
        request.headers.addAll(authHeaders);
      }

      request.fields['prompt'] = message;

      if (image != null) {
        try {
          String filename = image.path.split('/').last;
          String extension = filename.split('.').last.toLowerCase();

          String contentType = 'image/jpeg';
          if (extension == 'png') {
            contentType = 'image/png';
          }

          var multipartFile = await http.MultipartFile.fromPath(
            'image',
            image.path,
            contentType: MediaType.parse(contentType),
          );
          request.files.add(multipartFile);

          logger.d('Added image to streaming request: $filename');
        } catch (e) {
          logger.e('Error adding image to streaming request: $e');
          yield {'type': 'error', 'error': 'Failed to process image: $e'};
          return;
        }
      }

      // Send the request and get streaming response
      final streamedResponse = await request.send();

      if (streamedResponse.statusCode != 200) {
        yield {
          'type': 'error',
          'error': 'Failed to start streaming: ${streamedResponse.statusCode}',
        };
        return;
      }

      // Process the stream with aggressive real-time handling
      String buffer = '';

      // Use listen to handle stream chunks more aggressively
      late StreamSubscription subscription;
      subscription = streamedResponse.stream.listen(
        (List<int> chunk) {
          String chunkString = utf8.decode(chunk, allowMalformed: true);
          buffer += chunkString;

          logger.d(
            'Raw chunk received: ${chunkString.replaceAll('\n', '\\n')}',
          );

          // Process all complete lines immediately
          List<String> lines = buffer.split('\n');
          // Keep the last line in buffer as it might be incomplete
          buffer = lines.removeLast();

          for (String line in lines) {
            line = line.trim();
            if (line.startsWith('data: ')) {
              try {
                final jsonData = line.substring(6);
                if (jsonData.trim().isNotEmpty && jsonData != '[DONE]') {
                  final data = json.decode(jsonData);
                  logger.d('Processing chunk immediately: $data');

                  // Add to controller immediately
                  if (!controller.isClosed) {
                    controller.add(data);
                  }

                  // Check for completion
                  if (data['type'] == 'complete' || data['type'] == 'error') {
                    subscription.cancel();
                    controller.close();
                    return;
                  }
                }
              } catch (e) {
                logger.e('Error parsing chunk: $e');
              }
            }
          }
        },
        onError: (error) {
          logger.e('Stream error: $error');
          if (!controller.isClosed) {
            controller.addError(error);
            controller.close();
          }
        },
        onDone: () {
          logger.d('Stream completed');
          // Process any remaining buffer
          if (buffer.trim().isNotEmpty) {
            String line = buffer.trim();
            if (line.startsWith('data: ')) {
              try {
                final jsonData = line.substring(6);
                if (jsonData.trim().isNotEmpty && jsonData != '[DONE]') {
                  final data = json.decode(jsonData);
                  if (!controller.isClosed) {
                    controller.add(data);
                  }
                }
              } catch (e) {
                logger.e('Error parsing final chunk: $e');
              }
            }
          }

          if (!controller.isClosed) {
            controller.close();
          }
        },
      );

      // Yield all items from the controller stream
      await for (final item in controller.stream) {
        yield item;
      }
    } catch (e) {
      logger.e('Error in streaming request: $e');
      yield {
        'type': 'error',
        'error': 'Failed to establish streaming connection: $e',
      };
    }
  }

  Future<List<Map<String, dynamic>>> getChatHistory() async {
    try {
      final url = '$baseUrl/chat-history/';
      final response = await http
          .get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(response.body);
        // Process image URLs to make them absolute
        for (var item in data) {
          if (item['image'] != null && item['image'].toString().isNotEmpty) {
            // Make sure the image URL is absolute
            if (!item['image'].toString().startsWith('http')) {
              item['image'] = '$serverBaseUrl${item['image']}';
            }
          }
        }
        return data.cast<Map<String, dynamic>>();
      } else {
        String errorMsg = 'Failed to load chat history';
        try {
          final errorData = json.decode(response.body);
          if (errorData.containsKey('error')) {
            errorMsg = errorData['error'];
          }
        } catch (_) {}
        throw Exception('$errorMsg (${response.statusCode})');
      }
    } catch (e) {
      logger.e('Error getting chat history: $e');
      throw Exception('Failed to communicate with server: $e');
    }
  }
}
