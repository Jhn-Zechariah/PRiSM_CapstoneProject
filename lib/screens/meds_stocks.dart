// ignore_for_file: camel_case_types

import 'package:flutter/material.dart';
import 'package:prism_app/features/auth/presentation/components/build_tab_bar.dart';
import '../features/auth/presentation/components/app_top_bar.dart';
import 'package:material_symbols_icons/symbols.dart';

class meds_Stocks extends StatefulWidget {
  final VoidCallback? onSwitchToPigMeds;

  const meds_Stocks({super.key, this.onSwitchToPigMeds});

  @override
  State<meds_Stocks> createState() => _meds_StocksState();
}

class _meds_StocksState extends State<meds_Stocks> {
  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppTopBar(),
          const SizedBox(height: 16),

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
                      // Handle Stock tab selection
                      widget.onSwitchToPigMeds?.call();
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
