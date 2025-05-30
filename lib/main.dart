import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

void main() {
  runApp(const AIChatApp());
}

class AIChatApp extends StatelessWidget {
  const AIChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Assistant'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const ChatHistoryPage()),
            ),
          ),
        ],
      ),
      body: const Center(child: Text('Main App Content')),
      floatingActionButton: const ChatWidget(),
    );
  }
}

class ChatWidget extends StatefulWidget {
  const ChatWidget({super.key});

  @override
  State<ChatWidget> createState() => _ChatWidgetState();
}

class _ChatWidgetState extends State<ChatWidget> {
  final TextEditingController _controller = TextEditingController();
  List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList('chat_history') ?? [];
      setState(() {
        _messages.clear();
        for (var e in saved) {
          if (e.isNotEmpty) {
            try {
              final jsonData = jsonDecode(e);
              if (jsonData != null && jsonData is Map<String, dynamic>) {
                final msg = ChatMessage.fromJson(jsonData);
                _messages.add(msg);
              }
            } catch (e) {
              print('Error parsing message: $e');
              // Skip invalid entries gracefully
            }
          }
        }
      });
    } catch (e) {
      print('Error loading messages: $e');
    }
  }

  Future<void> _saveMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        'chat_history',
        _messages.map((msg) => jsonEncode(msg.toJson())).toList(),
      );
    } catch (e) {
      print('Error saving messages: $e');
    }
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    // Add user message to chat
    setState(() {
      _messages.add(ChatMessage(
        text: text,
        isUser: true,
        timestamp: DateTime.now(),
      ));
      _isLoading = true;
    });

    // API endpoint URL - exactly as in Python sample
    const String url = "http://127.0.0.1:7860/api/v1/run/bb02171a-c683-40bd-b09d-81963cea2a77";
    
    // Request payload configuration - exactly matching Python sample
    final Map<String, dynamic> payload = {
      "input_value": text,      // The input value to be processed by the flow
      "output_type": "chat",    // Specifies the expected output format
      "input_type": "chat"      // Specifies the input format
    };

    // Request headers - exactly as in Python sample
    final Map<String, String> headers = {
      "Content-Type": "application/json"
    };

    try {
      // Send API request - equivalent to requests.request("POST", url, json=payload, headers=headers)
      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode(payload),
      );

      // Debug prints
      print('API Request URL: $url');
      print('API Request Payload: $payload');
      print('Response Status Code: ${response.statusCode}');
      print('Response Headers: ${response.headers}');
      print('Response Body: ${response.body}');

      // Equivalent to response.raise_for_status() in Python
      if (response.statusCode >= 200 && response.statusCode < 300) {
        // Success response
        final String responseText = response.body;
        
        if (responseText.isNotEmpty) {
          try {
            // Try to parse as JSON first
            final dynamic responseData = jsonDecode(responseText);
            
            String aiResponse = '';
            
            if (responseData is Map<String, dynamic>) {
              // Parse the specific response structure from your API
              try {
                // Navigate through the nested JSON structure
                final outputs = responseData['outputs'] as List?;
                if (outputs != null && outputs.isNotEmpty) {
                  final firstOutput = outputs[0] as Map<String, dynamic>?;
                  if (firstOutput != null) {
                    final outputResults = firstOutput['outputs'] as List?;
                    if (outputResults != null && outputResults.isNotEmpty) {
                      final firstResult = outputResults[0] as Map<String, dynamic>?;
                      if (firstResult != null) {
                        // Try multiple paths to get the message
                        final results = firstResult['results'] as Map<String, dynamic>?;
                        if (results != null) {
                          final message = results['message'] as Map<String, dynamic>?;
                          if (message != null) {
                            // Get the text from the message
                            aiResponse = message['text']?.toString() ?? 
                                        message['message']?.toString() ?? '';
                          }
                        }
                        
                        // Alternative path: check messages array
                        if (aiResponse.isEmpty) {
                          final messages = firstResult['messages'] as List?;
                          if (messages != null && messages.isNotEmpty) {
                            final firstMessage = messages[0] as Map<String, dynamic>?;
                            if (firstMessage != null) {
                              aiResponse = firstMessage['message']?.toString() ?? '';
                            }
                          }
                        }
                        
                        // Another alternative: check artifacts
                        if (aiResponse.isEmpty) {
                          final artifacts = firstResult['artifacts'] as Map<String, dynamic>?;
                          if (artifacts != null) {
                            aiResponse = artifacts['message']?.toString() ?? '';
                          }
                        }
                      }
                    }
                  }
                }
                
                // If we still don't have a response, try fallback methods
                if (aiResponse.isEmpty) {
                  aiResponse = responseData['message']?.toString() ?? 
                             responseData['text']?.toString() ?? 
                             responseData['response']?.toString() ?? 
                             'No message found in response';
                }
                
              } catch (parseError) {
                print('Error parsing nested response: $parseError');
                aiResponse = 'Error parsing API response structure';
              }
            } else if (responseData is String) {
              aiResponse = responseData;
            } else {
              // If it's not a recognized format, use the raw response
              aiResponse = responseText;
            }

            // Add AI response to chat
            setState(() {
              _messages.add(ChatMessage(
                text: aiResponse,
                isUser: false,
                timestamp: DateTime.now(),
              ));
            });
            
            // Save messages to local storage
            await _saveMessages();
            
          } catch (jsonError) {
            // If JSON parsing fails, treat response as plain text
            print('JSON parsing failed, treating as plain text: $jsonError');
            setState(() {
              _messages.add(ChatMessage(
                text: responseText,
                isUser: false,
                timestamp: DateTime.now(),
              ));
            });
            await _saveMessages();
          }
        } else {
          throw Exception('Empty response body received from API');
        }
      } else {
        // Error response - equivalent to requests.exceptions.RequestException
        throw Exception('API request failed with status ${response.statusCode}: ${response.reasonPhrase}');
      }
      
    } catch (e) {
      // Handle all exceptions - equivalent to except blocks in Python
      print('Error making API request: $e');
      setState(() {
        _messages.add(ChatMessage(
          text: 'Error: Failed to get response from AI. Please try again.\nDetails: $e',
          isUser: false,
          timestamp: DateTime.now(),
        ));
      });
    } finally {
      // Clean up - always executed
      setState(() => _isLoading = false);
      _controller.clear();
    }
  }

  void _toggleExpand() {
    setState(() => _isExpanded = !_isExpanded);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _isExpanded ? 350 : 60,
      height: _isExpanded ? 500 : 60,
      child: Card(
        elevation: 8,
        child: _isExpanded
            ? Column(
                children: [
                  AppBar(
                    title: const Text('Chat with AI'),
                    leading: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: _toggleExpand,
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(8),
                      reverse: true,
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final message = _messages[_messages.length - 1 - index];
                        return ChatBubble(message: message);
                      },
                    ),
                  ),
                  if (_isLoading) const LinearProgressIndicator(),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            decoration: const InputDecoration(
                              hintText: 'Type your message...',
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: _sendMessage,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.send),
                          onPressed: () => _sendMessage(_controller.text),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : Center(
                child: IconButton(
                  icon: const Icon(Icons.chat, size: 30),
                  onPressed: _toggleExpand,
                ),
              ),
      ),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'isUser': isUser,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      text: json['text']?.toString() ?? '',
      isUser: json['isUser'] ?? false,
      timestamp: json['timestamp'] != null 
          ? DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

class ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 250),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: message.isUser
              ? Theme.of(context).primaryColor
              : Colors.grey[300],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: message.isUser ? Colors.white : Colors.black,
          ),
        ),
      ),
    );
  }
}

class ChatHistoryPage extends StatelessWidget {
  const ChatHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chat History')),
      body: FutureBuilder<List<ChatMessage>>(
        future: _loadChatHistory(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error loading history: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No chat history yet'));
          }
          return ListView.builder(
            itemCount: snapshot.data!.length,
            itemBuilder: (context, index) {
              final message = snapshot.data![index];
              return ListTile(
                title: Text(message.text),
                subtitle: Text(
                  '${message.isUser ? 'You' : 'AI'} - ${message.timestamp.toString()}',
                ),
                tileColor: message.isUser ? Colors.blue[50] : Colors.grey[50],
              );
            },
          );
        },
      ),
    );
  }

  Future<List<ChatMessage>> _loadChatHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList('chat_history') ?? [];
      final messages = <ChatMessage>[];
      
      for (var e in saved) {
        if (e.isNotEmpty) {
          try {
            final jsonData = jsonDecode(e);
            if (jsonData != null && jsonData is Map<String, dynamic>) {
              messages.add(ChatMessage.fromJson(jsonData));
            }
          } catch (e) {
            print('Error parsing chat history message: $e');
          }
        }
      }
      
      return messages;
    } catch (e) {
      print('Error loading chat history: $e');
      return [];
    }
  }
}