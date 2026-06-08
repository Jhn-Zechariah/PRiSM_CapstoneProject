// ignore_for_file: camel_case_types

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // 🔹 Added for subcollection query
import 'package:prism_app/core/widgets/build_tab_bar.dart';
import 'package:prism_app/features/medication/presentation/components/medicine_card.dart';
import 'package:prism_app/features/medication/presentation/components/add_medicine_stock.dart';
import 'package:prism_app/features/medication/presentation/components/update_medicine.dart';
import '../../../../core/widgets/app_top_bar.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:prism_app/features/medication/presentation/components/add_initial_medicine.dart';
import '../../../../core/widgets/header.dart';
import '../../../../core/widgets/search_bar.dart';
import '../../domain/model/app_medicine.dart';
import '../cubits/medicine_cubit.dart';
import '../cubits/medicine_states.dart';

class meds_Stocks extends StatefulWidget {
  final VoidCallback? onSwitchToPigMeds;

  const meds_Stocks({super.key, this.onSwitchToPigMeds});

  @override
  State<meds_Stocks> createState() => _meds_StocksState();
}

class _meds_StocksState extends State<meds_Stocks> {
  int _selectedTab = 0;
  TextEditingController searchController = TextEditingController();
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    // 🔹 Start listening to live Firestore data using the new Cubit
    context.read<MedicineCubit>().listenToMedicines();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  // 🔹 Updated to accept double for compatibility with the new Medicine model
  String _calculateStatus(double stock, double reorder) {
    if (stock <= 0) {
      return "No Stock";
    } else if (stock <= (reorder * 0.5)) {
      return "Low";
    } else if (stock <= reorder) {
      return "Average";
    } else {
      return "High";
    }
  }

  // 🔹 Use the same dialog, but pass null for a new item
  void _showAddNewItemDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) => const AddNewMedDialog(),
    );
  }

  void _showUpdateDialog(BuildContext context, Medicine item) {
    showDialog(
      context: context,
      builder: (BuildContext context) => UpdateMedicineDialog(medicine: item,),
    );
  }

  // 🔹 I also added a placeholder for your Add Stock feature!
  void _showAddStockDialog(BuildContext context, Medicine item) {
    showDialog(
      context: context,
      builder: (BuildContext context) => AddNewMedStockDialog(medicine: item),
    );
  }

  // 🔹 Helper method to fetch the latest expiry date from the nested subcollection
  Future<String> _getLatestExpiryDate(String medId) async {
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('medicines')
          .doc(medId)
          .collection('medicine_stock')
          .orderBy('expiry_date')
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        return querySnapshot.docs.first['expiry_date'] ?? 'N/A';
      }
      return 'N/A';
    } catch (e) {
      return 'Error';
    }
  }


  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppTopBar(),
          const SizedBox(height: 11),

          CustomFeatureHeader(
            title: 'Healthcare',
            icon: Symbols.vaccines,
            trailing: IconButton(
              icon: const Icon(Icons.add, size: 28),
              color: isDarkMode ? Colors.white : Colors.black,
              onPressed: _showAddNewItemDialog,
            ),
          ),

          const SizedBox(height: 10),

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
                    setState(() {
                      _searchQuery = value.toLowerCase();
                    });
                  },
                  onClear: () {
                    searchController.clear();
                    setState(() {
                      _searchQuery = "";
                    });
                  },
                ),
                const SizedBox(height: 12),

                // 🔹 BlocBuilder connected to the new MedicineCubit
                // 🔹 Changed to BlocConsumer to listen for successes AND build the list
                Expanded(
                  child: BlocConsumer<MedicineCubit, MedicineState>(
                    listener: (context, state) {
                      // 🔹 Force the page to refresh the data when an item is added/updated
                      if (state is MedicineSaveSuccess) {
                        context.read<MedicineCubit>().listenToMedicines();
                      }
                    },
                    buildWhen: (previous, current) {
                      // 🔹 Tell the UI ONLY to rebuild if the state actually contains list data.
                      // This prevents the screen from going blank during 'MedicineSaveSuccess'.
                      return current is MedicineLoading ||
                          current is MedicineLoaded ||
                          current is MedicineError;
                    },
                    builder: (context, state) {
                      if (state is MedicineLoading) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (state is MedicineLoaded) {
                        final filteredItems = state.medicines.where((med) {
                          return med.name.toLowerCase().contains(_searchQuery);
                        }).toList();

                        if (filteredItems.isEmpty) {
                          return Center(
                            child: Text(
                              _searchQuery.isNotEmpty ? "No medicines matched your search." : "No medicines found.",
                              style: TextStyle(
                                color: isDarkMode ? Colors.white54 : Colors.black54,
                              ),
                            ),
                          );
                        }

                        return ListView.builder(
                          itemCount: filteredItems.length,
                          itemBuilder: (context, index) {
                            final item = filteredItems[index];

                            return FutureBuilder<String>(
                              future: _getLatestExpiryDate(item.medId ?? ''),
                              builder: (context, snapshot) {
                                String displayExpiry = 'Loading...';
                                if (snapshot.connectionState == ConnectionState.done) {
                                  displayExpiry = snapshot.data ?? 'N/A';
                                }

                                return MedicineCard(
                                  name: item.name,
                                  category: item.category,
                                  stock: item.totalStock.round(),
                                  expiryDate: displayExpiry,
                                  status: _calculateStatus(item.totalStock, item.reorderLevel),
                                  unit: item.measurementUnit,
                                  onTap: () {},
                                  onEditMedicine: () => _showUpdateDialog(context, item),
                                  onAddStock:  () => _showAddStockDialog(context, item),
                                );
                              },
                            );
                          },
                        );
                      }

                      if (state is MedicineError) {
                        return Center(
                          child: Text('Error: ${state.message}', style: const TextStyle(color: Colors.red)),
                        );
                      }

                      return const SizedBox.shrink();
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