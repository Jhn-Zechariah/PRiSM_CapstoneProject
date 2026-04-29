// ignore_for_file: camel_case_types

import 'package:flutter/material.dart';
import 'package:prism_app/features/auth/presentation/components/build_tab_bar.dart';
import '../features/auth/presentation/components/app_top_bar.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../features/auth/presentation/components/search_bar.dart';

class meds_Stocks extends StatefulWidget {
  final VoidCallback? onSwitchToPigMeds;

  const meds_Stocks({super.key, this.onSwitchToPigMeds});

  @override
  State<meds_Stocks> createState() => _meds_StocksState();
}

class _meds_StocksState extends State<meds_Stocks> {
  int _selectedTab = 0;

  TextEditingController searchController = TextEditingController();

  List<Map<String, dynamic>> medicines = [];
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    fetchMedicines(); // initial load
  }

  // Replace this with your real DB/API call
  Future<void> fetchMedicines({String query = ""}) async {
    setState(() {
      isLoading = true;
    });

    await Future.delayed(const Duration(milliseconds: 500));

    final search = query.toLowerCase();

    List<Map<String, dynamic>> results = medicines.where((med) {
      return (med["name"] ?? "").toString().toLowerCase().contains(search);
    }).toList();

    setState(() {
      medicines = results;
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppTopBar(),
          const SizedBox(height: 16),

          // 🔹 HEADER
          Row(
            children: [
              const Icon(Symbols.vaccines, size: 32),
              const SizedBox(width: 12),
              const Text(
                'Healthcare',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.add, size: 28),
                onPressed: () {},
              ),
            ],
          ),

          // CONTENT
          Expanded(
            child: Column(
              children: [
                CustomTabBar(
                  selectedIndex: _selectedTab,
                  tabs: const ["Stock", "Pig Medications"],
                  onTabSelected: (index) {
                    setState(() {
                      _selectedTab = index;
                    });

                    if (index == 1) {
                      widget.onSwitchToPigMeds?.call();
                    }
                  },
                ),

                const SizedBox(height: 12),

                // SEARCH BAR
                MedicineSearchBar(
                  controller: searchController,
                  onChanged: (value) {
                    fetchMedicines(query: value);
                  },
                  onClear: () {
                    searchController.clear();
                    fetchMedicines();
                  },
                ),

                const SizedBox(height: 12),

                // 📋 MEDICINE LIST
                Expanded(
                  child: isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : medicines.isEmpty
                      ? const Center(child: Text("No medicines found"))
                      : ListView.builder(
                          itemCount: medicines.length,
                          itemBuilder: (context, index) {
                            final med = medicines[index];

                            return Card(
                              child: ListTile(
                                leading: const Icon(Icons.medication_outlined),
                                title: Text(med["name"]),
                                subtitle: Text("Stock: ${med["stock"]}"),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
