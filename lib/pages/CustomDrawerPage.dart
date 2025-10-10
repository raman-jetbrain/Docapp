import 'package:docapp/dashboardpage.dart';
import 'package:flutter/material.dart';


class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    // Get device width (we’ll use only half)
    final width = MediaQuery.of(context).size.width * 0.6; // This will make it 60% of the screen

    return SizedBox(
      width: width, // only half of screen
      child: Drawer(
        backgroundColor: Colors.white,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 🔹 Custom header with background image
              Container(
                height: 200,
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage("assets/images/Background2.jpeg"), // put your image
                    fit: BoxFit.cover,
                  ),
                ),
                child: Container(
                  color: Colors.black.withOpacity(0.3), // dark overlay for text clarity
                  child: const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: Colors.white,
                            child: Icon(Icons.store, color: Colors.black, size: 30),
                          ),
                          SizedBox(width: 12),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "POS User",
                                style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white),
                              ),
                              Text(
                                "info@posapp.com",
                                style: TextStyle(color: Colors.white70),
                              ),
                            ],
                          )
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // 🔹 Drawer items
              ListTile(
                leading: const Icon(Icons.dashboard),
                title: const Text("Dashboard"),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) =>  Dashboardpage()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.point_of_sale),
                title: const Text("Sales"),
                onTap: () {
                  Navigator.pushReplacementNamed(context, '/sales');
                },
              ),
              ListTile(
                leading: const Icon(Icons.receipt_long),
                title: const Text("Orders"),
                onTap: () {
                  Navigator.pushReplacementNamed(context, '/orders');
                },
              ),
              ListTile(
                leading: const Icon(Icons.payments),
                title: const Text("Payments"),
                onTap: () {
                  Navigator.pushReplacementNamed(context, '/payments');
                },
              ),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text("Add Item"),
                onTap: () {
                  Navigator.pushReplacementNamed(context, '/sales');
                },
              ),

              const Divider(),

              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text("Settings"),
                onTap: () {
                  Navigator.pushReplacementNamed(context, '/settings');
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text("Logout"),
                onTap: () {
                  Navigator.pop(context); // just close drawer for now
                },
              ),

              const Spacer(),

              const Padding(
                padding: EdgeInsets.all(12.0),
                child: Text(
                  "© 2024 POS App",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}