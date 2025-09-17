import 'package:flutter/material.dart';

class PosterEditScreen extends StatelessWidget {
  final String posterTemplatePath;
  final String eventName;

  const PosterEditScreen({
    super.key,
    required this.posterTemplatePath,
    required this.eventName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Editing: $eventName Poster'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.download), onPressed: () {}),
          IconButton(icon: const Icon(Icons.share), onPressed: () {}),
        ],
      ),
      body: Stack(
        children: [
          // Main canvas with the poster image
          Positioned.fill(
            child: Image.asset(posterTemplatePath, fit: BoxFit.contain),
          ),
          // Placeholder for the editable elements
          // This is where you would place draggable text boxes, etc.
          Positioned(
            top: 200,
            left: 50,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                eventName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            buildEditOption(icon: Icons.add, label: 'Add'),
            buildEditOption(icon: Icons.style, label: 'Styles'),
            buildEditOption(icon: Icons.aspect_ratio, label: 'Resize'),
            buildEditOption(icon: Icons.wallpaper, label: 'Background'),
          ],
        ),
      ),
    );
  }

  // A helper method for creating the bottom bar icons
  Widget buildEditOption({required IconData icon, required String label}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(icon),
          onPressed: () {},
        ),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}