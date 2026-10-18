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

  @override
  void initState() {
    super.initState();
    // Medicines are streamed by the cubit from login; this asks it to also
    // look up each medicine's nearest expiry (in parallel, once per medicine).
    context.read<MedicineCubit>().ensureExpiries();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
                  child: BlocBuilder<MedicineCubit, MedicineState>(
                    // Intake updates don't affect this list
                    buildWhen: (prev, curr) =>
                        prev.medicines != curr.medicines ||
                        prev.medicinesLoading != curr.medicinesLoading ||
                        prev.medicinesError != curr.medicinesError ||
                        prev.nextExpiries != curr.nextExpiries,
                    builder: (context, state) {

                      // 1. Data on hand is always drawn, even while refreshing
                      if (state.medicines.isNotEmpty) {
                        final filteredItems = state.medicines
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

                            final displayExpiry = state.nextExpiries[id] ?? 'Loading...';

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

                      // 2. Nothing loaded yet
                      if (state.medicinesLoading) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      // 3. Errors
                      if (state.medicinesError != null) {
                        return Center(
                          child: Text('Error: ${state.medicinesError}', style: const TextStyle(color: Colors.red)),
                        );
                      }

                      // 4. Loaded, but the user has no medicines yet
                      return Center(
                        child: Text(
                          'No medicines found.',
                          style: TextStyle(color: isDarkMode ? Colors.white54 : Colors.black54),
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