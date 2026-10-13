import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/tremor_provider.dart';

class DebugScreen extends StatelessWidget {
  const DebugScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<TremorProvider>(context);
    final records = provider.debugRecords.reversed.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Depuración'),
        backgroundColor: Colors.purple.shade100,
        actions: [
          IconButton(
            icon: const Icon(Icons.show_chart, color: Colors.purple),
            onPressed: () {
              final csv = provider.exportRaw60sCsv();
              Share.share(csv, subject: 'ParkinsonWatch_RAW60s.csv');
            },
            tooltip: 'Exportar RAW (60s)',
          ),
          IconButton(
            icon: const Icon(Icons.download, color: Colors.purple),
            onPressed: records.isEmpty
                ? null
                : () {
                    final csv = provider.exportDebugCsv();
                    Share.share(csv, subject: 'ParkinsonWatch_Debug.csv');
                  },
            tooltip: 'Exportar CSV STATUS/EXT/DIAG',
          ),
        ],
      ),
      body: Column(
        children: [
          // Banner de Alerta de Incoherencia (PASO 3)
          if (provider.incoherenceCount > 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.orange.shade100,
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange.shade900),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "El reloj detectó temblor pero lo clasificó como voluntario: actualiza el firmware (orden de clasificación)\n[Incoherencias en sesión: ${provider.incoherenceCount}]",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: records.isEmpty
                ? const Center(
                    child: Text(
                      'Esperando paquetes de datos...',
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columnSpacing: 12,
                        headingRowColor: WidgetStateProperty.all(Colors.purple.shade50),
                        columns: const [
                          DataColumn(label: Text('t_ms', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('clase', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('confirmado', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('detectado', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('f_hz', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('amp_dps', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('mov_dps', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('band_pct', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('duty_pct', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('episodio_s', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('accel_mg', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('ratio', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('ang_deg', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('rotacional', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('ruta', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('votos', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('activos', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('compuerta', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('lin', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('prel3', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('vol110', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('sigma_min', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('rms_pc', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('incoherente', style: TextStyle(fontWeight: FontWeight.bold))),
                        ],
                        rows: records.map((r) {
                          return DataRow(
                            cells: [
                              DataCell(Text('${r.tMs}')),
                              DataCell(
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _getSeverityColor(r.tremorClass).withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    r.tremorClass,
                                    style: TextStyle(
                                      color: _getSeverityColor(r.tremorClass),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  r.confirmed ? 'SÍ' : 'NO',
                                  style: TextStyle(
                                    color: r.confirmed ? Colors.red : Colors.grey,
                                    fontWeight: r.confirmed ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  r.detected ? 'SÍ' : 'NO',
                                  style: TextStyle(
                                    color: r.detected ? Colors.orange.shade800 : Colors.grey,
                                    fontWeight: r.detected ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ),
                              DataCell(Text(r.fHz.toStringAsFixed(1))),
                              DataCell(Text(r.ampDps.toStringAsFixed(1))),
                              DataCell(Text(r.movDps.toStringAsFixed(1))),
                              DataCell(Text('${r.bandPct}')),
                              DataCell(Text('${r.dutyPct}')),
                              DataCell(Text('${r.episodioS}')),
                              DataCell(Text(r.accelMg != null ? '${r.accelMg}' : '--')),
                              DataCell(Text(r.ratio != null ? r.ratio!.toStringAsFixed(2) : '--')),
                              DataCell(Text(r.angDeg != null ? r.angDeg!.toStringAsFixed(2) : '--')),
                              DataCell(Text(r.rotacional != null ? (r.rotacional! ? 'SÍ' : 'NO') : '--')),
                              DataCell(Text(r.ruta != null ? '${r.ruta}' : '--')),
                              DataCell(Text(r.votos != null ? '${r.votos}' : '--')),
                              DataCell(Text(r.activos != null ? '${r.activos}' : '--')),
                              DataCell(Text(r.compuerta != null ? (r.compuerta! ? 'SÍ' : 'NO') : '--')),
                              DataCell(Text(r.lin != null ? r.lin!.toStringAsFixed(3) : '--')),
                              DataCell(Text(r.prel3 != null ? '${r.prel3}' : '--')),
                              DataCell(Text(r.vol110 != null ? '${r.vol110}' : '--')),
                              DataCell(Text(r.sigmaMin != null ? r.sigmaMin!.toStringAsFixed(2) : '--')),
                              DataCell(Text(r.rmsPc != null ? r.rmsPc!.toStringAsFixed(1) : '--')),
                              DataCell(
                                Text(
                                  r.isIncoherent ? 'SÍ' : 'NO',
                                  style: TextStyle(
                                    color: r.isIncoherent ? Colors.red : Colors.grey,
                                    fontWeight: r.isIncoherent ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Color _getSeverityColor(String tremorClass) {
    switch (tremorClass) {
      case 'SIN_TEMBLOR':
        return const Color(0xFF2E7D32);
      case 'LEVE':
        return const Color(0xFFF9A825);
      case 'MODERADO':
        return const Color(0xFFD27800);
      case 'GRAVE':
        return const Color(0xFFC81414);
      case 'VOLUNTARIO':
        return const Color(0xFF1E5AC8);
      default:
        return Colors.grey;
    }
  }
}
