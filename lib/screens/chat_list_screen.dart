import 'package:flutter/material.dart';

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Mock chat data
    final List<Map<String, String>> chats = [
      {
        'name': 'Alice',
        'lastMessage': 'Hey, how are you?',
        'avatar': '',
        'time': '09:30 AM',
      },
      {
        'name': 'Bob',
        'lastMessage': 'Let\'s meet tomorrow.',
        'avatar': '',
        'time': 'Yesterday',
      },
      {
        'name': 'Charlie',
        'lastMessage': 'Thanks for the update!',
        'avatar': '',
        'time': 'Mon',
      },
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? Colors.white,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor ?? Colors.black,
        elevation: Theme.of(context).appBarTheme.elevation ?? 0,
      ),
      body: ListView.separated(
        itemCount: chats.length,
        separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey[300]),
        itemBuilder: (context, index) {
          final chat = chats[index];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.blue[100],
              child: Text(chat['name']![0]),
            ),
            title: Text(
              chat['name']!,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              chat['lastMessage']!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Text(
              chat['time']!,
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            onTap: () {
              Navigator.pushNamed(context, '/chat_screen_individual', arguments: {
                'name': chat['name'],
              });
            },
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            tileColor: Theme.of(context).cardColor,
            hoverColor: Colors.blue[50],
          );
        },
      ),
    );
  }
}
