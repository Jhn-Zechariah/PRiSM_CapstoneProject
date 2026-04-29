// ignore_for_file: camel_case_types

import 'package:flutter/material.dart';
import 'package:prism_app/features/auth/presentation/components/build_tab_bar.dart';
import '../features/auth/presentation/components/app_top_bar.dart';
import 'package:material_symbols_icons/symbols.dart';

class pig_meds extends StatefulWidget {
  final VoidCallback? onSwitchToStock;

  const pig_meds({super.key, this.onSwitchToStock});

  @override
  State<pig_meds> createState() => _pig_medsState();
}

class _pig_medsState extends State<pig_meds> {
  int _selectedTab = 1;

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

                    if (index == 0) {
                      // Handle Stock tab selection
                      widget.onSwitchToStock?.call();
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
