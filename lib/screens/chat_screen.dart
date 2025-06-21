import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';
import '../services/streaming_api_service.dart' as StreamingAPI;
import 'login_screen.dart';

class Message {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final File? image;
  final String? imageUrl;
  final bool isError;
  final bool isSending;
  final bool isTyping;
  final bool isFromHistory;
  final bool isStreaming;
  String streamingText;

  Message({
    required this.text,
    required this.isUser,
    this.image,
    this.imageUrl,
    this.isError = false,
    this.isSending = false,
    this.isTyping = false,
    this.isFromHistory = false,
    this.isStreaming = false,
    String? streamingText,
    DateTime? timestamp,
  }) : streamingText = streamingText ?? text,
       timestamp = timestamp ?? DateTime.now();

  factory Message.sending(String text, {File? image}) {
    return Message(text: text, isUser: true, image: image, isSending: true);
  }

  factory Message.error(String text) {
    return Message(text: text, isUser: false, isError: true);
  }

  factory Message.typing() {
    return Message(text: '', isUser: false, isTyping: true);
  }

  factory Message.streaming() {
    return Message(
      text: '',
      isUser: false,
      isStreaming: true,
      streamingText: '',
    );
  }

  // Method to update streaming content
  Message updateStreamingContent(String newContent) {
    if (!isStreaming) return this;
    streamingText = newContent;
    return this;
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final List<Message> _messages = [];
  final ScrollController _scrollController = ScrollController();
  final ApiService _apiService = ApiService();
  final StreamingAPI.ApiService _streamingApiService =
      StreamingAPI.ApiService();
  final ImagePicker _picker = ImagePicker();

  bool _isComposing = false;
  bool _isSending = false;
  bool _useStreaming = true; // Toggle for streaming mode
  File? _selectedImage;
  late AnimationController _cursorController; // Only for streaming cursor

  @override
  void initState() {
    super.initState();
    _cursorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _cursorController.repeat(reverse: true); // For blinking cursor effect only

    // Add welcome message
    _messages.add(
      Message(
        text: "👋 Welcome to Eyeconic Chat!\nHow can I help you today?",
        isUser: false,
        isFromHistory: true,
        timestamp: DateTime.now(),
      ),
    );

    _checkServerAndLoadHistory();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _cursorController.dispose();
    super.dispose();
  }

  Future<void> _checkServerAndLoadHistory() async {
    try {
      final isReachable = await _apiService.isServerReachable();
      if (!mounted) return;

      if (!isReachable) {
        _showError(
          'Server is not reachable. Please check your connection and try again.',
        );
        return;
      }
      await _loadChatHistory();
    } catch (e) {
      if (!mounted) return;
      _showError('Failed to connect to server. Please try again later.');
    }
  }

  Future<void> _loadChatHistory() async {
    try {
      final history = await _apiService.getChatHistory();
      if (!mounted) return;

      setState(() {
        // Sort history by timestamp
        history.sort(
          (a, b) => DateTime.parse(
            a['timestamp'],
          ).compareTo(DateTime.parse(b['timestamp'])),
        );

        // Clear existing messages except welcome message
        if (_messages.isNotEmpty) {
          final welcomeMessage = _messages.first;
          _messages.clear();
          _messages.add(welcomeMessage);
        }

        for (var msg in history) {
          final timestamp = DateTime.parse(msg['timestamp']);
          final String? imageUrl = msg['image'] as String?;

          // Add user message
          _messages.add(
            Message(
              text: msg['prompt'],
              isUser: true,
              isFromHistory: true,
              timestamp: timestamp,
              imageUrl: imageUrl,
            ),
          );

          // Add AI response
          _messages.add(
            Message(
              text: msg['response'],
              isUser: false,
              isFromHistory: true,
              timestamp: timestamp,
            ),
          );
        }
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      _showError('Failed to load chat history');
    }
  }

  Future<void> _pickImage() async {
    try {
      setState(() => _isSending = true);

      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );

      if (!mounted) return;

      if (image != null) {
        final File imageFile = File(image.path);

        if (await imageFile.exists()) {
          if (!mounted) return;

          final fileSize = await imageFile.length();
          if (!mounted) return;

          if (fileSize > 4 * 1024 * 1024) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Image is large (${(fileSize / 1024 / 1024).toStringAsFixed(1)}MB). It has been compressed.',
                ),
                backgroundColor: Theme.of(context).colorScheme.secondary,
                duration: const Duration(seconds: 3),
              ),
            );
          }

          setState(() {
            _selectedImage = imageFile;
            _isComposing = true;
          });
        } else {
          _showError(
            'Image file could not be accessed. Please try another image.',
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      _showError('Failed to pick image: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty && _selectedImage == null) {
      return;
    }

    final messageText = _messageController.text.trim();
    final image = _selectedImage;

    setState(() {
      _isSending = true;
      _messages.add(Message.sending(messageText, image: image));
    });

    _messageController.clear();
    setState(() {
      _isComposing = false;
      _selectedImage = null;
    });

    _scrollToBottom();

    if (_useStreaming) {
      await _sendStreamingMessage(messageText, image);
    } else {
      await _sendRegularMessage(messageText, image);
    }
  }

  Future<void> _sendStreamingMessage(String messageText, File? image) async {
    try {
      // Add the user message and a streaming response placeholder
      setState(() {
        _messages.removeLast(); // Remove sending message
        _messages.add(Message(text: messageText, isUser: true, image: image));
        _messages.add(Message.streaming());
      });

      _scrollToBottom();

      print('Starting streaming message: $messageText');
      if (image != null) {
        print('Image attached: ${image.path}');
        final fileSize = await image.length();
        print(
          'Image file size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)}MB',
        );
      }

      // Start streaming with improved real-time handling
      await for (final chunk in _streamingApiService.sendMessageStream(
        messageText,
        image: image,
      )) {
        if (!mounted) return;

        print('Received streaming chunk: $chunk');

        if (chunk['type'] == 'connection') {
          print('Connected to streaming endpoint');
          continue;
        } else if (chunk['type'] == 'content') {
          // Update the streaming message with new content immediately
          if (mounted) {
            setState(() {
              if (_messages.isNotEmpty && _messages.last.isStreaming) {
                final currentContent = _messages.last.streamingText;
                final newContent = currentContent + (chunk['content'] ?? '');
                _messages.last.updateStreamingContent(newContent);
              }
            });

            // Scroll to bottom more aggressively for real-time feel
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _scrollToBottom();
            });
          }
        } else if (chunk['type'] == 'complete') {
          // Finalize the streaming message
          setState(() {
            if (_messages.isNotEmpty && _messages.last.isStreaming) {
              final finalContent = _messages.last.streamingText;
              _messages.removeLast();
              _messages.add(Message(text: finalContent, isUser: false));
            }
          });
          break;
        } else if (chunk['type'] == 'error') {
          setState(() {
            if (_messages.isNotEmpty && _messages.last.isStreaming) {
              _messages.removeLast();
            }
            _messages.add(
              Message.error(chunk['error'] ?? 'Unknown streaming error'),
            );
          });
          break;
        }
      }
    } catch (e) {
      print('Error in streaming message: $e');

      setState(() {
        if (_messages.isNotEmpty && _messages.last.isStreaming) {
          _messages.removeLast();
        }
        _messages.add(Message.error('Failed to stream response: $e'));
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
        _scrollToBottom();
      }
    }
  }

  Future<void> _sendRegularMessage(String messageText, File? image) async {
    try {
      // Add a typing indicator for the AI response
      setState(() {
        _messages.removeLast();
        _messages.add(Message(text: messageText, isUser: true, image: image));
        _messages.add(Message.typing());
      });

      _scrollToBottom();

      print('Sending message: $messageText');
      if (image != null) {
        print('Image attached: ${image.path}');
        final fileSize = await image.length();
        print(
          'Image file size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)}MB',
        );
      }
      final response = await _apiService.sendMessage(messageText, image: image);

      if (!mounted) return;

      setState(() {
        // Remove typing indicator
        if (_messages.isNotEmpty && _messages.last.isTyping) {
          _messages.removeLast();
        }
        _messages.add(
          Message(
            text: response['response'] ?? 'No response received',
            isUser: false,
          ),
        );
      });

      _scrollToBottom();
    } catch (e) {
      print('Error sending message: $e');

      String errorMessage = 'Failed to send message. Please try again.';

      if (e.toString().contains('timeout') ||
          e.toString().contains('TimeoutException')) {
        errorMessage =
            'Request timed out. The server might be busy. Please try again.';
      } else if (e.toString().contains('rate limit')) {
        errorMessage = 'API rate limit reached. Please try again later.';
      } else if (e.toString().contains('image') ||
          e.toString().contains('Image')) {
        errorMessage =
            'Failed to process image. The image may be too large or in an unsupported format.';
      } else if (e.toString().contains('Failed to communicate')) {
        errorMessage =
            'Network error. Please check your connection and try again.';
      }

      setState(() {
        // Remove typing indicator
        if (_messages.isNotEmpty && _messages.last.isTyping) {
          _messages.removeLast();
        }
        // If the user message was removed during error, add it back
        if (_messages.isEmpty || _messages.last.isUser == false) {
          _messages.add(Message(text: messageText, isUser: true, image: image));
        }
        _messages.add(Message.error(errorMessage));
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
        _scrollToBottom();
      }
    }
  }

  Future<void> _handleLogout() async {
    try {
      // Show confirmation dialog
      final shouldLogout = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Logout'),
              content: const Text('Are you sure you want to logout?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  child: const Text('Logout'),
                ),
              ],
            ),
      );

      if (shouldLogout == true) {
        // Logout from API service
        await _apiService.logout();

        if (mounted) {
          // Navigate to login screen
          Navigator.of(context).pushAndRemoveUntil(
            PageRouteBuilder(
              pageBuilder:
                  (context, animation, secondaryAnimation) =>
                      const LoginScreen(),
              transitionsBuilder: (
                context,
                animation,
                secondaryAnimation,
                child,
              ) {
                return FadeTransition(opacity: animation, child: child);
              },
              transitionDuration: const Duration(milliseconds: 600),
            ),
            (route) => false, // Remove all routes
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error during logout: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 80,
        automaticallyImplyLeading: false, // Remove back button
        title: Container(
          height: 60,
          constraints: const BoxConstraints(maxWidth: 180),
          child: Image.asset('assets/logo.png', fit: BoxFit.contain),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          // User menu
          PopupMenuButton<String>(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
              ),
              child: Icon(
                Icons.person,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            onSelected: (value) async {
              if (value == 'logout') {
                await _handleLogout();
              }
            },
            itemBuilder:
                (context) => [
                  PopupMenuItem(
                    value: 'logout',
                    child: Row(
                      children: [
                        Icon(
                          Icons.logout,
                          color: Theme.of(context).colorScheme.error,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Logout',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
          ),

          Tooltip(
            message: _useStreaming ? 'Disable Streaming' : 'Enable Streaming',
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              child: IconButton(
                onPressed: () {
                  setState(() {
                    _useStreaming = !_useStreaming;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        _useStreaming
                            ? 'Streaming mode enabled'
                            : 'Streaming mode disabled',
                      ),
                      duration: const Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Icon(
                    _useStreaming ? Icons.stream : Icons.chat_bubble_outline,
                    key: ValueKey(_useStreaming),
                    color:
                        _useStreaming
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurface.withAlpha(
                              (0.6 * 255).round(),
                            ),
                  ),
                ),
                style: IconButton.styleFrom(
                  backgroundColor:
                      _useStreaming
                          ? Theme.of(
                            context,
                          ).colorScheme.primary.withAlpha((0.1 * 255).round())
                          : Colors.transparent,
                ),
              ),
            ),
          ),
        ],
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Theme.of(
                  context,
                ).colorScheme.surface.withAlpha((0.9 * 255).round()),
                Theme.of(
                  context,
                ).scaffoldBackgroundColor.withAlpha((0.8 * 255).round()),
              ],
            ),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0.0, 0.3, 0.7, 1.0],
            colors: [
              Theme.of(
                context,
              ).colorScheme.surface.withAlpha((0.8 * 255).round()),
              Theme.of(context).scaffoldBackgroundColor,
              Theme.of(context).scaffoldBackgroundColor,
              Theme.of(
                context,
              ).colorScheme.surface.withAlpha((0.6 * 255).round()),
            ],
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final message = _messages[index];
                  final isFirstMessage =
                      index == 0 ||
                      _messages[index - 1].isUser != message.isUser;
                  final isLastMessage =
                      index == _messages.length - 1 ||
                      _messages[index + 1].isUser != message.isUser;

                  final messageContent = Align(
                    alignment:
                        message.isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.8,
                      ),
                      margin: EdgeInsets.only(
                        top: isFirstMessage ? 12 : 4,
                        bottom: isLastMessage ? 12 : 4,
                        left: message.isUser ? 48 : 0,
                        right: message.isUser ? 0 : 48,
                      ),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color:
                            message.isUser
                                ? Theme.of(context).colorScheme.primary
                                    .withAlpha((0.9 * 255).round())
                                : Theme.of(context).colorScheme.surface
                                    .withAlpha((0.9 * 255).round()),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(
                            message.isUser || !isFirstMessage ? 20 : 8,
                          ),
                          topRight: Radius.circular(
                            !message.isUser || !isFirstMessage ? 20 : 8,
                          ),
                          bottomLeft: Radius.circular(message.isUser ? 20 : 8),
                          bottomRight: Radius.circular(
                            !message.isUser ? 20 : 8,
                          ),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha((0.15 * 255).round()),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment:
                            message.isUser
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                        children: [
                          if (!message.isUser &&
                              !message.isError &&
                              !message.isSending &&
                              !message.isTyping)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6.0),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.auto_awesome,
                                    size: 14,
                                    color: Theme.of(context).colorScheme.primary
                                        .withAlpha((0.8 * 255).round()),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    "Eyeconic",
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withAlpha((0.8 * 255).round()),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (message.image != null || message.imageUrl != null)
                            Container(
                              height: 200,
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color:
                                      message.isUser
                                          ? Colors.white.withAlpha(
                                            (0.3 * 255).round(),
                                          )
                                          : Theme.of(context)
                                              .colorScheme
                                              .primary
                                              .withAlpha((0.4 * 255).round()),
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withAlpha(
                                      (0.2 * 255).round(),
                                    ),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                                image: DecorationImage(
                                  image:
                                      message.image != null
                                          ? FileImage(message.image!)
                                              as ImageProvider
                                          : NetworkImage(message.imageUrl!),
                                  fit: BoxFit.cover,
                                  opacity: message.isSending ? 0.7 : 1.0,
                                ),
                              ),
                              child:
                                  message.isSending
                                      ? Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            CircularProgressIndicator(
                                              strokeWidth: 3,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                    Colors.white,
                                                  ),
                                            ),
                                            const SizedBox(height: 12),
                                            Text(
                                              'Uploading image...',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                shadows: [
                                                  Shadow(
                                                    blurRadius: 4,
                                                    color: Colors.black
                                                        .withAlpha(
                                                          (0.7 * 255).round(),
                                                        ),
                                                    offset: const Offset(0, 1),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                      : null,
                            ),
                          if (message.isTyping)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Eyeconic is typing...',
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withAlpha((0.7 * 255).round()),
                                    fontSize: 14,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ),
                          if (message.isSending)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Theme.of(context).colorScheme.onPrimary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Sending...',
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onPrimary
                                          .withAlpha((0.8 * 255).round()),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (!message.isTyping && !message.isSending)
                            message.isStreaming
                                ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        message.streamingText,
                                        style: TextStyle(
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.onSurface,
                                          fontSize: 16,
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      width: 2,
                                      height: 20,
                                      margin: const EdgeInsets.only(
                                        left: 4,
                                        top: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                        borderRadius: BorderRadius.circular(1),
                                      ),
                                      child: AnimatedBuilder(
                                        animation: _cursorController,
                                        builder: (context, child) {
                                          return Opacity(
                                            opacity: _cursorController.value,
                                            child: child,
                                          );
                                        },
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color:
                                                Theme.of(
                                                  context,
                                                ).colorScheme.primary,
                                            borderRadius: BorderRadius.circular(
                                              1,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                                : Text(
                                  message.text,
                                  style: TextStyle(
                                    color:
                                        message.isUser
                                            ? Theme.of(
                                              context,
                                            ).colorScheme.onPrimary
                                            : message.isError
                                            ? Theme.of(
                                              context,
                                            ).colorScheme.error
                                            : Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                    fontSize: 16,
                                    height: 1.4,
                                  ),
                                ),
                        ],
                      ),
                    ),
                  ); // Return message content directly without any slide animation
                  return messageContent;
                },
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surface.withAlpha((0.95 * 255).round()),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha((0.1 * 255).round()),
                    offset: const Offset(0, -4),
                    blurRadius: 20,
                  ),
                ],
                border: Border(
                  top: BorderSide(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withAlpha((0.2 * 255).round()),
                    width: 1,
                  ),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: SafeArea(
                child: Row(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        color:
                            _selectedImage != null
                                ? Theme.of(context).colorScheme.primary
                                    .withAlpha((0.1 * 255).round())
                                : Theme.of(context).scaffoldBackgroundColor,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color:
                              _selectedImage != null
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.outline
                                      .withAlpha((0.3 * 255).round()),
                          width: 1.5,
                        ),
                      ),
                      child: IconButton(
                        icon:
                            _isSending && _selectedImage == null
                                ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                )
                                : Icon(
                                  _selectedImage != null
                                      ? Icons.image_rounded
                                      : Icons.add_photo_alternate_rounded,
                                  size: 24,
                                  color:
                                      _selectedImage != null
                                          ? Theme.of(
                                            context,
                                          ).colorScheme.primary
                                          : Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withAlpha((0.6 * 255).round()),
                                ),
                        onPressed: _isSending ? null : _pickImage,
                        tooltip:
                            _selectedImage != null
                                ? 'Change image'
                                : 'Add image',
                        padding: const EdgeInsets.all(12),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).scaffoldBackgroundColor
                              .withAlpha((0.9 * 255).round()),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color:
                                _isComposing || _selectedImage != null
                                    ? Theme.of(context).colorScheme.primary
                                        .withAlpha((0.8 * 255).round())
                                    : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_selectedImage != null)
                              Stack(
                                children: [
                                  Container(
                                    height: 100,
                                    width: double.infinity,
                                    margin: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary
                                            .withAlpha((0.6 * 255).round()),
                                        width: 2,
                                      ),
                                      image: DecorationImage(
                                        image: FileImage(_selectedImage!),
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: Material(
                                      color: Colors.black.withAlpha(
                                        (0.7 * 255).round(),
                                      ),
                                      shape: const CircleBorder(),
                                      child: IconButton(
                                        icon: const Icon(
                                          Icons.close,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _selectedImage = null;
                                            _isComposing =
                                                _messageController
                                                    .text
                                                    .isNotEmpty;
                                          });
                                        },
                                        constraints: const BoxConstraints(
                                          minWidth: 32,
                                          minHeight: 32,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 16,
                                    left: 16,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withAlpha(
                                          (0.8 * 255).round(),
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        'Image attached',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 4,
                              ),
                              child: TextField(
                                controller: _messageController,
                                onChanged: (text) {
                                  setState(() {
                                    _isComposing = text.isNotEmpty;
                                  });
                                },
                                onSubmitted: (text) {
                                  if (_isComposing || _selectedImage != null) {
                                    _sendMessage();
                                  }
                                },
                                style: TextStyle(
                                  fontSize: 16,
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                  height: 1.4,
                                ),
                                maxLines: 5,
                                minLines: 1,
                                decoration: InputDecoration(
                                  hintText: 'Type a message...',
                                  hintStyle: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withAlpha((0.5 * 255).round()),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        gradient:
                            _isComposing || _selectedImage != null
                                ? LinearGradient(
                                  colors: [
                                    Theme.of(context).colorScheme.primary,
                                    Theme.of(context).colorScheme.primary
                                        .withAlpha((0.8 * 255).round()),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                                : null,
                        color:
                            _isComposing || _selectedImage != null
                                ? null
                                : Theme.of(context).scaffoldBackgroundColor,
                        border: Border.all(
                          color:
                              _isComposing || _selectedImage != null
                                  ? Colors.transparent
                                  : Theme.of(context).colorScheme.outline
                                      .withAlpha((0.3 * 255).round()),
                          width: 1.5,
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(24),
                          onTap:
                              _isSending
                                  ? null
                                  : (_isComposing || _selectedImage != null)
                                  ? _sendMessage
                                  : null,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            child:
                                _isSending
                                    ? SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              _isComposing ||
                                                      _selectedImage != null
                                                  ? Theme.of(
                                                    context,
                                                  ).colorScheme.onPrimary
                                                  : Theme.of(
                                                    context,
                                                  ).colorScheme.primary,
                                            ),
                                      ),
                                    )
                                    : Icon(
                                      Icons.send_rounded,
                                      size: 24,
                                      color:
                                          _isComposing || _selectedImage != null
                                              ? Theme.of(
                                                context,
                                              ).colorScheme.onPrimary
                                              : Theme.of(
                                                context,
                                              ).colorScheme.onSurface.withAlpha(
                                                (0.4 * 255).round(),
                                              ),
                                    ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
