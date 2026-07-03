import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/action_button.dart';
import 'payment_confirmation_screen.dart';

class TableSelectionScreen extends StatefulWidget {
  final Map<String, dynamic> venue;
  final String date;
  final String package;

  const TableSelectionScreen({
    super.key,
    required this.venue,
    required this.date,
    required this.package,
  });

  @override
  State<TableSelectionScreen> createState() => _TableSelectionScreenState();
}

class _TableSelectionScreenState extends State<TableSelectionScreen> {
  String? _selectedTableId;

  // Mock table layout data
  final List<Map<String, dynamic>> _tables = [
    {
      'id': 'V1',
      'type': 'VIP',
      'top': 0.15,
      'left': 0.15,
      'status': 'available',
    },
    {
      'id': 'V2',
      'type': 'VIP',
      'top': 0.15,
      'left': 0.45,
      'status': 'available',
    },
    {
      'id': 'V3',
      'type': 'VIP',
      'top': 0.15,
      'left': 0.75,
      'status': 'occupied',
    },
    {
      'id': 'B1',
      'type': 'Booth',
      'top': 0.45,
      'left': 0.15,
      'status': 'available',
    },
    {
      'id': 'B2',
      'type': 'Booth',
      'top': 0.45,
      'left': 0.45,
      'status': 'available',
    },
    {
      'id': 'B3',
      'type': 'Booth',
      'top': 0.45,
      'left': 0.75,
      'status': 'available',
    },
    {
      'id': 'S1',
      'type': 'Standard',
      'top': 0.75,
      'left': 0.25,
      'status': 'available',
    },
    {
      'id': 'S2',
      'type': 'Standard',
      'top': 0.75,
      'left': 0.65,
      'status': 'occupied',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(color: LunaraTheme.midnightBlack),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              const SizedBox(height: 20),
              _buildLegend(),
              const SizedBox(height: 32),
              Expanded(child: _buildFloorPlan()),
              _buildControlPanel(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SELECT TABLE',
                style: LunaraTheme.headingStyle.copyWith(fontSize: 18),
              ),
              Text(
                'FLOOR PLAN: MAIN ROOM',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 10,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _legendItem('AVAILABLE', LunaraTheme.accentVivid),
        const SizedBox(width: 24),
        _legendItem('OCCUPIED', Colors.white10),
        const SizedBox(width: 24),
        _legendItem('SELECTED', LunaraTheme.primaryDeep),
      ],
    );
  }

  Widget _legendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildFloorPlan() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: GlassCard(
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(32),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                // Dancefloor area
                Center(
                  child: Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: LunaraTheme.primaryRich.withValues(
                            alpha: 0.1,
                          ),
                          blurRadius: 40,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        'DANCEFLOOR',
                        style: TextStyle(
                          color: LunaraTheme.primaryRich.withValues(
                            alpha: 0.5,
                          ),
                          fontSize: 10,
                          letterSpacing: 4,
                        ),
                      ),
                    ),
                  ),
                ),
                // DJ Booth
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      width: 80,
                      height: 30,
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(15),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'DJ',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.3),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Bar Area
                Positioned(
                  bottom: 20,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      width: 200,
                      height: 40,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white10, width: 2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Center(
                        child: Text(
                          'BAR',
                          style: TextStyle(
                            color: Colors.white10,
                            fontSize: 12,
                            letterSpacing: 8,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Tables
                ..._tables.map((table) => _buildTable(table, constraints)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildTable(Map<String, dynamic> table, BoxConstraints constraints) {
    bool isSelected = _selectedTableId == table['id'];
    bool isOccupied = table['status'] == 'occupied';

    Color tableColor = isOccupied
        ? Colors.white10
        : (isSelected ? LunaraTheme.primaryDeep : LunaraTheme.accentVivid);

    return Positioned(
      top: table['top'] * constraints.maxHeight,
      left: table['left'] * constraints.maxWidth,
      child: GestureDetector(
        onTap: isOccupied
            ? null
            : () => setState(() => _selectedTableId = table['id']),
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: tableColor.withValues(alpha: 0.2),
                shape: BoxShape.circle,
                border: Border.all(color: tableColor, width: 2),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: LunaraTheme.primaryDeep.withValues(alpha: 0.4),
                          blurRadius: 15,
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: Text(
                  table['id'],
                  style: TextStyle(
                    color: isOccupied ? Colors.white10 : Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlPanel() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SELECTED TABLE',
                    style: TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _selectedTableId ?? 'NONE',
                    style: LunaraTheme.headingStyle.copyWith(fontSize: 20),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'SERVICE FEE',
                    style: TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _selectedTableId != null ? '\$150' : '\$0',
                    style: LunaraTheme.headingStyle.copyWith(
                      fontSize: 20,
                      color: LunaraTheme.accentVivid,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          LunaraActionButton(
            text: 'CONFIRM TABLE',
            onPressed: () {
              debugPrint(
                'CONFIRM TABLE clicked. Selected ID: $_selectedTableId',
              );
              if (_selectedTableId != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PaymentConfirmationScreen(
                      venue: widget.venue,
                      package: widget.package,
                      date: widget.date,
                      table: 'Table $_selectedTableId',
                      totalPrice: '\$150',
                    ),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('PLEASE SELECT A TABLE FIRST'),
                    backgroundColor: LunaraTheme.primaryDeep,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
