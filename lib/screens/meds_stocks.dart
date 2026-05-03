// ignore_for_file: camel_case_types

import 'package:flutter/material.dart';
import 'package:prism_app/features/auth/presentation/components/build_tab_bar.dart';
import 'package:prism_app/features/auth/presentation/components/medicine_card_widget.dart';
import '../features/auth/presentation/components/app_top_bar.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../features/auth/presentation/components/search_bar.dart';
import 'package:prism_app/screens/addnewitem.dart';
import 'package:prism_app/screens/updateitem.dart'; // 🔹 Added

class meds_Stocks extends StatefulWidget {
  final VoidCallback? onSwitchToPigMeds;

  const meds_Stocks({super.key, this.onSwitchToPigMeds});

  @override
  State<meds_Stocks> createState() => _meds_StocksState();
}

class _meds_StocksState extends State<meds_Stocks> {
  int _selectedTab = 0;
  TextEditingController searchController = TextEditingController();

  List<Map<String, dynamic>> _allMedicines = [];
  List<Map<String, dynamic>> medicines = [];
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    fetchMedicines();
  }

  Future<void> fetchMedicines({String query = ""}) async {
    setState(() => isLoading = true);

    await Future.delayed(const Duration(milliseconds: 300));

    final search = query.toLowerCase();
    setState(() {
      medicines = _allMedicines.where((med) {
        return (med["name"] ?? "").toString().toLowerCase().contains(search);
      }).toList();
      isLoading = false;
    });
  }

  String _calculateStatus(int stock, int reorder) {
    if (stock <= 0) {
      return "Low";
    } else if (stock <= reorder) {
      return "Average";
    } else {
      return "High";
    }
  }

  void _showAddNewItemDialog() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (BuildContext context) {
        return const AddNewItemDialog();
      },
    );

    if (result != null) {
      final int stock   = result["stock"]   ?? 0;
      final int reorder = result["reorder"] ?? 0;

      _allMedicines.add({
        "name":        result["name"]        ?? "Unknown",
        "category":    result["category"]    ?? "Medicine",
        "type":        result["type"]        ?? "Capsule",
        "stock":       stock,
        "dosage":      result["dosage"]      ?? "",
        "expiry":      result["expiry"]      ?? "N/A",
        "reorder":     reorder,
        "description": result["description"] ?? "",
        "status":      _calculateStatus(stock, reorder),
      });

      setState(() {
        medicines = List.from(_allMedicines);
        isLoading = false;
      });
    }
  }

  // 🔹 Opens Update dialog and updates item in list
  void _showUpdateDialog(Map<String, dynamic> med, int masterIndex) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (BuildContext context) {
        return UpdateItemDialog(item: med);
      },
    );

    if (result != null && masterIndex >= 0) {
      final int stock   = result["stock"]   ?? 0;
      final int reorder = result["reorder"] ?? 0;

      setState(() {
        _allMedicines[masterIndex] = {
          "name":        result["name"]        ?? "Unknown",
          "category":    result["category"]    ?? "Medicine",
          "type":        result["type"]        ?? "Capsule",
          "stock":       stock,
          "dosage":      result["dosage"]      ?? "",
          "expiry":      result["expiry"]      ?? "N/A",
          "reorder":     reorder,
          "description": result["description"] ?? "",
          "status":      _calculateStatus(stock, reorder),
        };
        medicines = List.from(_allMedicines);
      });
    }
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

          // ── Header ───────────────────────────────────────────────
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
                onPressed: _showAddNewItemDialog,
              ),
            ],
          ),

          const SizedBox(height: 12),

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

                Expanded(
                  child: isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : medicines.isEmpty
                          ? const Center(
                              child: Text(
                                "No medicines found",
                                style: TextStyle(color: Colors.black54),
                              ),
                            )
                          : ListView.builder(
                              itemCount: medicines.length,
                              itemBuilder: (context, index) {
                                final med = medicines[index];

                                // 🔹 Find real index in master list
                                final masterIndex = _allMedicines.indexWhere(
                                  (m) => m["name"] == med["name"],
                                );

                                return MedicineCard(
                                  name:       med["name"]     ?? "Unknown",
                                  category:   med["category"] ?? "General",
                                  stock:      med["stock"]    ?? 0,
                                  expiryDate: med["expiry"]   ?? "N/A",
                                  status:     med["status"]   ?? "Low",
                                  onTap: () => _showUpdateDialog(med, masterIndex), // 🔹 Added
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