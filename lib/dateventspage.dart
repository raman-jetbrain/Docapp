import 'package:flutter/material.dart';
import 'package:docapp/services/api_service.dart';
import 'package:docapp/postereditpage.dart';

class DayEventsPage extends StatefulWidget {
  const DayEventsPage({super.key});

  @override
  State<DayEventsPage> createState() => _DayEventsPageState();
}

class _DayEventsPageState extends State<DayEventsPage> {
  final List<String> dailyEvents = [
    'Halloween Party',
    'Concert Night',
    'Bible Study Group',
    'Comedy Show',
  ];

  bool _showPosterGrid = false;
  bool _loading = false;
  final ApiService api = ApiService();
  List<String> posterUrls = [];

  Future<void> fetchPosters() async {
    setState(() => _loading = true);

    posterUrls.clear();
    for (var event in dailyEvents) {
      final url = await api.generatePoster(
        "YOUR_TEMPLATE_ID", // replace with your actual template ID
        event,
      );
      if (url != null) {
        posterUrls.add(url);
      }
    }

    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("September 16, 2025 Events"),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                "Today's Events",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),

            // Event List
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: dailyEvents.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(dailyEvents[index]),
                  subtitle: const Text("6:00 PM - 8:00 PM"),
                );
              },
            ),
            const Divider(),

            // Poster section
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Create a Poster",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: Icon(
                      _showPosterGrid ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    ),
                    onPressed: () {
                      setState(() {
                        _showPosterGrid = !_showPosterGrid;
                        if (_showPosterGrid) fetchPosters();
                      });
                    },
                  ),
                ],
              ),
            ),

            if (_showPosterGrid)
              _loading
                  ? const CircularProgressIndicator()
                  : GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 0.6,
                      ),
                      itemCount: posterUrls.length,
                      itemBuilder: (context, index) {
                        final url = posterUrls[index];
                        return GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => PosterEditScreen(
                                  posterTemplatePath: url,
                                  eventName: dailyEvents[index],
                                ),
                              ),
                            );
                          },
                          child: Card(
                            elevation: 4,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(url, fit: BoxFit.cover),
                            ),
                          ),
                        );
                      },
                    ),
          ],
        ),
      ),
    );
  }
}
