import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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


class MedicineStocksPage extends StatefulWidget {
  final VoidCallback? onSwitchToPigMeds;

  const MedicineStocksPage({super.key, this.onSwitchToPigMeds});

  @override
  State<MedicineStocksPage> createState() => _MedicineStocksPageState();
}

class _MedicineStocksPageState extends State<MedicineStocksPage> {
  int _selectedTab = 0;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // 🗑️ REMOVED local _expiryCache map from here!

  @override
  void initState() {
    super.initState();
    final cubit = context.read<MedicineCubit>();
    cubit.listenToMedicines();

    // 🔹 FIXED: If returning to the page and the Cubit is already warm, trigger instantly
    if (cubit.state is MedicineLoaded) {
      _prefetchExpiries((cubit.state as MedicineLoaded).medicines);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _prefetchExpiries(List<Medicine> medicines) async {
    final cubit = context.read<MedicineCubit>();
    bool changed = false;

    for (final med in medicines) {
      final id = med.medId ?? '';
      // Point to cubit.expiryCache instead of local map
      if (id.isEmpty || cubit.expiryCache.containsKey(id)) continue;

      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('medicines')
            .doc(id)
            .collection('medicine_stock')
            .orderBy('expiryDate')
            .limit(1)
            .get();

        cubit.expiryCache[id] = snapshot.docs.isNotEmpty
            ? (snapshot.docs.first['expiryDate'] as String? ?? 'N/A')
            : 'N/A';
      } catch (_) {
        cubit.expiryCache[id] = 'Error';
      }

      changed = true;
    }

    if (changed && mounted) setState(() {});
  }

  String _calculateStatus(double stock, double reorder) {
    if (stock <= 0) return 'No Stock';
    if (stock <= reorder * 0.5) return 'Low';
    if (stock <= reorder) return 'Average';
    return 'High';
  }

  void _showAddNewItemDialog() {
    showDialog(context: context, builder: (_) => const AddNewMedDialog());
  }

  void _showUpdateDialog(Medicine item) {
    showDialog(context: context, builder: (_) => UpdateMedicineDialog(medicine: item));
  }

  void _showAddStockDialog(Medicine item) {
    showDialog(context: context, builder: (_) => AddNewMedStockDialog(medicine: item));
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final cubit = context.read<MedicineCubit>(); // 🔹 Grab cubit reference for builder

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
                  tabs: const ['Stock', 'Pig Medications'],
                  onTabSelected: (index) {
                    setState(() => _selectedTab = index);
                    if (index == 1) widget.onSwitchToPigMeds?.call();
                  },
                ),
                const SizedBox(height: 12),

                MedicineSearchBar(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
                  onClear: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                ),
                const SizedBox(height: 12),

                Expanded(
                  child: BlocConsumer<MedicineCubit, MedicineState>(
                    listener: (context, state) {
                      // 🔹 Trigger prefetch anytime the backup list has items
                      if (cubit.currentMedicines.isNotEmpty) {
                        _prefetchExpiries(cubit.currentMedicines);
                      }
                    },
                    // Allow UI to refresh on SaveSuccess as well
                    buildWhen: (prev, curr) => curr is MedicineLoading || curr is MedicineLoaded || curr is MedicineError || curr is MedicineSaveSuccess,
                    builder: (context, state) {

                      // 1. 🔹 PRIMARY CHECK: If our safe backup has data, ALWAYS draw it.
                      if (cubit.currentMedicines.isNotEmpty) {
                        final filteredItems = cubit.currentMedicines
                            .where((med) => med.name.toLowerCase().contains(_searchQuery))
                            .toList();

                        if (filteredItems.isEmpty) {
                          return Center(
                            child: Text(
                              _searchQuery.isNotEmpty
                                  ? 'No medicines matched your search.'
                                  : 'No medicines found.',
                              style: TextStyle(color: isDarkMode ? Colors.white54 : Colors.black54),
                            ),
                          );
                        }

                        return ListView.builder(
                          itemCount: filteredItems.length,
                          itemBuilder: (context, index) {
                            final item = filteredItems[index];
                            final id = item.medId ?? '';

                            final displayExpiry = cubit.expiryCache[id] ?? 'Loading...';

                            return MedicineCard(
                              name: item.name,
                              category: item.category,
                              stock: item.totalStock,
                              expiryDate: displayExpiry,
                              status: _calculateStatus(item.totalStock, item.reorderLevel),
                              unit: item.measurementUnit,
                              onTap: () {},
                              onEditMedicine: () => _showUpdateDialog(item),
                              onAddStock: () => _showAddStockDialog(item),
                            );
                          },
                        );
                      }

                      // 2. Fallback to loading spinner ONLY if the backup list is 100% empty
                      if (state is MedicineLoading) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      // 3. Fallback to Errors
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