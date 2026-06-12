// screens/chart_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/settings_provider.dart';
import '../models/market_data.dart';
import '../services/optimizer.dart';


class ChartScreen extends ConsumerStatefulWidget {
  const ChartScreen({super.key});

  @override
  ConsumerState<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends ConsumerState<ChartScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _showBB = false;
  bool _showEMA = true;

  // Mobile Chart Interaction Optimizations
  double? _zoomStartIndex;
  int? _hoveredIndex;
  String? _initializedForKey;
  bool _rsiExpanded = true;
  bool _macdExpanded = true;

  // Paper Trading State
  double _paperBalance = 10000.0;
  double? _paperPositionEntry;
  double _paperPositionShares = 0.0;
  List<Map<String, dynamic>> _paperLedger = [];

  Future<void> _loadPaperTradingState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _paperBalance = prefs.getDouble('paper_balance') ?? 10000.0;
        _paperPositionEntry = prefs.getDouble('paper_position_entry');
        _paperPositionShares = prefs.getDouble('paper_position_shares') ?? 0.0;
        final ledgerRaw = prefs.getString('paper_ledger');
        if (ledgerRaw != null) {
          final List<dynamic> list = jsonDecode(ledgerRaw);
          _paperLedger = list.map((item) => Map<String, dynamic>.from(item)).toList();
        } else {
          _paperLedger = [];
        }
      });
    } catch (e) {
      // Graceful fallback
    }
  }

  Future<void> _savePaperTradingState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('paper_balance', _paperBalance);
      if (_paperPositionEntry != null) {
        await prefs.setDouble('paper_position_entry', _paperPositionEntry!);
      } else {
        await prefs.remove('paper_position_entry');
      }
      await prefs.setDouble('paper_position_shares', _paperPositionShares);
      await prefs.setString('paper_ledger', jsonEncode(_paperLedger));
    } catch (e) {
      // Graceful fallback
    }
  }

  void _showOptimizerDialog(List<HistoryDataPoint> data) {
    showDialog(
      context: context,
      builder: (context) {
        return _OptimizerDialogWidget(
          closes: data.map((d) => d.close).toList(),
          settingsNotifier: ref.read(settingsProvider.notifier),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadPaperTradingState();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final historyAsync = ref.watch(historyProvider(
      HistoryParams(
        symbol: settings.selectedSymbol,
        interval: settings.selectedInterval,
        rsiPeriod: settings.rsiPeriod,
        overbought: settings.overbought,
        oversold: settings.oversold,
      ),
    ));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${settings.selectedSymbol} (${settings.selectedInterval})',
          style: const TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF0B0E17),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF8B5CF6),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(text: 'Charts'),
            Tab(text: 'Backtest'),
            Tab(text: 'Confluence'),
          ],
        ),
      ),
      body: Container(
        color: const Color(0xFF0B0E17),
        child: historyAsync.when(
          data: (response) {
            return TabBarView(
              controller: _tabController,
              children: [
                _buildChartsTab(response),
                _buildBacktestTab(response.backtestSummary, response.trades),
                _buildConfluenceTab(response),
              ],
            );
          },
          loading: () => const Center(
            child: CircularProgressIndicator(color: Color(0xFF8B5CF6)),
          ),
          error: (error, stack) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text(
                'Error loading chart details:\n$error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Helper: Double getters to manage visible data windows
  double getMinX(int dataLength) {
    if (dataLength <= 30) return 0.0;
    return _zoomStartIndex ?? 0.0;
  }

  double getMaxX(int dataLength) {
    if (dataLength <= 30) return (dataLength - 1).toDouble();
    return (getMinX(dataLength) + 30.0);
  }

  // CHARTS TAB
  Widget _buildChartsTab(HistoryResponse response) {
    if (response.dataPoints.isEmpty) {
      return const Center(child: Text('No chart data points available.'));
    }

    final data = response.dataPoints;
    final settings = ref.watch(settingsProvider);

    // Initialize horizontal scroll to the end (latest bars) if symbol or interval changes
    final currentKey = '${settings.selectedSymbol}_${settings.selectedInterval}';
    if (_zoomStartIndex == null || _initializedForKey != currentKey) {
      _initializedForKey = currentKey;
      _zoomStartIndex = (data.length - 30).toDouble().clamp(0.0, double.infinity);
      _hoveredIndex = null;
    }

    final doubleMinX = getMinX(data.length);
    final doubleMaxX = getMaxX(data.length);

    // Calculate Y scale dynamically for visible price window
    final int startIdx = doubleMinX.toInt().clamp(0, data.length - 1);
    final int endIdx = doubleMaxX.toInt().clamp(0, data.length - 1);
    final visibleData = data.sublist(startIdx, endIdx + 1);

    double minPrice = 0.0;
    double maxPrice = 0.0;
    if (visibleData.isNotEmpty) {
      final closes = visibleData.map((d) => d.close).toList();
      if (_showEMA) {
        closes.addAll(visibleData.where((d) => d.ema != null).map((d) => d.ema!));
      }
      if (_showBB) {
        closes.addAll(visibleData.where((d) => d.bbUpper != null).map((d) => d.bbUpper!));
        closes.addAll(visibleData.where((d) => d.bbLower != null).map((d) => d.bbLower!));
      }
      minPrice = closes.reduce((a, b) => a < b ? a : b) * 0.998;
      maxPrice = closes.reduce((a, b) => a > b ? a : b) * 1.002;
    } else {
      minPrice = data.map((d) => d.close).reduce((a, b) => a < b ? a : b) * 0.99;
      maxPrice = data.map((d) => d.close).reduce((a, b) => a > b ? a : b) * 1.01;
    }

    // Calculate MACD scale symmetrically for visible window
    double minMacd = -1.0;
    double maxMacd = 1.0;
    if (visibleData.isNotEmpty) {
      final List<double> macdVals = [];
      for (final d in visibleData) {
        if (d.macd != null) macdVals.add(d.macd!);
        if (d.macdSignal != null) macdVals.add(d.macdSignal!);
        if (d.macdHist != null) macdVals.add(d.macdHist!);
      }
      if (macdVals.isNotEmpty) {
        final rawMin = macdVals.reduce((a, b) => a < b ? a : b);
        final rawMax = macdVals.reduce((a, b) => a > b ? a : b);
        final absMax = rawMin.abs() > rawMax.abs() ? rawMin.abs() : rawMax.abs();
        minMacd = -absMax * 1.15;
        maxMacd = absMax * 1.15;
      }
    }

    // Build unique symbol list including selected one to prevent dropdown assertions
    final dropdownSymbols = {'GC=F', 'SI=F', settings.selectedSymbol}.toList();

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16.0),
      children: [
        // 0. QUICK CONTROLS CARD
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: const Color(0x99131926),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Row(
            children: [
              // Symbol Dropdown Selector
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: settings.selectedSymbol,
                    dropdownColor: const Color(0xFF131926),
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                    items: dropdownSymbols.map((sym) {
                      String label = sym;
                      if (sym == 'GC=F') label = 'Gold (GC=F)';
                      else if (sym == 'SI=F') label = 'Silver (SI=F)';
                      return DropdownMenuItem(
                        value: sym,
                        child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        ref.read(settingsProvider.notifier).updateSymbol(val);
                      }
                    },
                  ),
                ),
              ),
              Container(width: 1, height: 24, color: Colors.white12),
              const SizedBox(width: 12),
              // Interval Dropdown Selector
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: settings.selectedInterval,
                    dropdownColor: const Color(0xFF131926),
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                    items: const [
                      DropdownMenuItem(value: '5m', child: Text('5m Timeframe', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold))),
                      DropdownMenuItem(value: '15m', child: Text('15m Timeframe', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold))),
                      DropdownMenuItem(value: '1h', child: Text('1h Timeframe', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold))),
                      DropdownMenuItem(value: 'daily', child: Text('Daily', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold))),
                      DropdownMenuItem(value: 'weekly', child: Text('Weekly', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold))),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        ref.read(settingsProvider.notifier).updateInterval(val);
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),

        // Live Readout HUD Sticky Panel
        _buildHUDPanel(data, settings.selectedSymbol, settings.selectedInterval),

        // Chart Controls Toggles
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            const Text('EMA9', style: TextStyle(color: Colors.white70, fontSize: 12)),
            Switch(
              value: _showEMA,
              activeColor: const Color(0xFF8B5CF6),
              onChanged: (v) => setState(() => _showEMA = v),
            ),
            const SizedBox(width: 8),
            const Text('B-Bands', style: TextStyle(color: Colors.white70, fontSize: 12)),
            Switch(
              value: _showBB,
              activeColor: const Color(0xFF06B6D4),
              onChanged: (v) => setState(() => _showBB = v),
            ),
          ],
        ),

        // 1. PRICE CHART CARD
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Price Chart',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
            ),
            InkWell(
              onTap: () => _showOptimizerDialog(data),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.bolt, color: Color(0xFF8B5CF6), size: 14),
                    SizedBox(width: 4),
                    Text('Optimize RSI', style: TextStyle(color: Color(0xFF8B5CF6), fontSize: 11, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final chartWidth = constraints.maxWidth - 45 - 16;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (details) {
                setState(() {
                  _zoomStartIndex = (_zoomStartIndex ?? (data.length - 30).toDouble()) -
                      details.delta.dx * (30.0 / chartWidth);
                  _zoomStartIndex = _zoomStartIndex!.clamp(
                    0.0,
                    (data.length - 30).toDouble().clamp(0.0, double.infinity),
                  );

                  final localX = details.localPosition.dx;
                  final ratio = (localX / chartWidth).clamp(0.0, 1.0);
                  _hoveredIndex = (doubleMinX + ratio * (doubleMaxX - doubleMinX)).round().clamp(
                        0,
                        data.length - 1,
                      );
                });
              },
              onTapDown: (details) {
                setState(() {
                  final localX = details.localPosition.dx;
                  final ratio = (localX / chartWidth).clamp(0.0, 1.0);
                  _hoveredIndex = (doubleMinX + ratio * (doubleMaxX - doubleMinX)).round().clamp(
                        0,
                        data.length - 1,
                      );
                });
              },
              child: Container(
                height: 250,
                padding: const EdgeInsets.only(right: 16, top: 16),
                decoration: BoxDecoration(
                  color: const Color(0x99131926),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: LineChart(
                  LineChartData(
                    gridData: const FlGridData(show: true, drawVerticalLine: false),
                    titlesData: _buildTitlesData(data, doubleMinX, doubleMaxX),
                    borderData: FlBorderData(show: false),
                    minX: doubleMinX,
                    maxX: doubleMaxX,
                    minY: minPrice,
                    maxY: maxPrice,
                    lineBarsData: _buildPriceLines(data),
                    extraLinesData: ExtraLinesData(
                      verticalLines: _hoveredIndex != null
                          ? [
                              VerticalLine(
                                  x: _hoveredIndex!.toDouble(),
                                  color: Colors.white.withOpacity(0.25),
                                  strokeWidth: 1.5,
                                  dashArray: [4, 4]),
                            ]
                          : [],
                    ),
                    lineTouchData: const LineTouchData(enabled: false),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 24),

        // 2. RSI CHART CARD (Collapsible Accordion)
        _buildCollapsibleCard(
          title: 'RSI Indicator',
          subtitle: 'Latest: ${data.last.rsi?.toStringAsFixed(1) ?? 'N/A'}',
          isExpanded: _rsiExpanded,
          onToggle: () => setState(() => _rsiExpanded = !_rsiExpanded),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final chartWidth = constraints.maxWidth - 45 - 16;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (details) {
                  setState(() {
                    _zoomStartIndex = (_zoomStartIndex ?? (data.length - 30).toDouble()) -
                        details.delta.dx * (30.0 / chartWidth);
                    _zoomStartIndex = _zoomStartIndex!.clamp(
                      0.0,
                      (data.length - 30).toDouble().clamp(0.0, double.infinity),
                    );

                    final localX = details.localPosition.dx;
                    final ratio = (localX / chartWidth).clamp(0.0, 1.0);
                    _hoveredIndex = (doubleMinX + ratio * (doubleMaxX - doubleMinX)).round().clamp(
                          0,
                          data.length - 1,
                        );
                  });
                },
                onTapDown: (details) {
                  setState(() {
                    final localX = details.localPosition.dx;
                    final ratio = (localX / chartWidth).clamp(0.0, 1.0);
                    _hoveredIndex = (doubleMinX + ratio * (doubleMaxX - doubleMinX)).round().clamp(
                          0,
                          data.length - 1,
                        );
                  });
                },
                child: Container(
                  height: 150,
                  padding: const EdgeInsets.only(right: 16, top: 16, bottom: 8),
                  child: LineChart(
                    LineChartData(
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: 10,
                        checkToShowHorizontalLine: (value) => value == 30 || value == 70 || value == 50,
                      ),
                      titlesData: _buildTitlesData(data, doubleMinX, doubleMaxX),
                      borderData: FlBorderData(show: false),
                      minX: doubleMinX,
                      maxX: doubleMaxX,
                      minY: 10,
                      maxY: 90,
                      lineBarsData: [
                        LineChartBarData(
                          spots: data
                              .asMap()
                              .entries
                              .where((e) => e.value.rsi != null)
                              .map((e) => FlSpot(e.key.toDouble(), e.value.rsi!))
                              .toList(),
                          isCurved: true,
                          barWidth: 2,
                          color: const Color(0xFF8B5CF6),
                          dotData: const FlDotData(show: false),
                        ),
                      ],
                      extraLinesData: ExtraLinesData(
                        verticalLines: _hoveredIndex != null
                            ? [
                                VerticalLine(
                                  x: _hoveredIndex!.toDouble(),
                                  color: Colors.white.withOpacity(0.25),
                                  strokeWidth: 1.5,
                                  dashArray: [4, 4],
                                ),
                              ]
                            : [],
                        horizontalLines: [
                          HorizontalLine(
                            y: ref.read(settingsProvider).overbought.toDouble(),
                            color: const Color(0x66EF4444),
                            strokeWidth: 1.5,
                            dashArray: [5, 5],
                          ),
                          HorizontalLine(
                            y: ref.read(settingsProvider).oversold.toDouble(),
                            color: const Color(0x6622C55E),
                            strokeWidth: 1.5,
                            dashArray: [5, 5],
                          ),
                        ],
                      ),
                      lineTouchData: const LineTouchData(enabled: false),
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        // 3. MACD OSCILLATOR CARD (Collapsible Accordion)
        _buildCollapsibleCard(
          title: 'MACD Oscillator',
          subtitle: data.last.macd != null
              ? 'MACD: ${data.last.macd!.toStringAsFixed(2)} / Sig: ${data.last.macdSignal!.toStringAsFixed(2)}'
              : '',
          isExpanded: _macdExpanded,
          onToggle: () => setState(() => _macdExpanded = !_macdExpanded),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final chartWidth = constraints.maxWidth - 45 - 16;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (details) {
                  setState(() {
                    _zoomStartIndex = (_zoomStartIndex ?? (data.length - 30).toDouble()) -
                        details.delta.dx * (30.0 / chartWidth);
                    _zoomStartIndex = _zoomStartIndex!.clamp(
                      0.0,
                      (data.length - 30).toDouble().clamp(0.0, double.infinity),
                    );

                    final localX = details.localPosition.dx;
                    final ratio = (localX / chartWidth).clamp(0.0, 1.0);
                    _hoveredIndex = (doubleMinX + ratio * (doubleMaxX - doubleMinX)).round().clamp(
                          0,
                          data.length - 1,
                        );
                  });
                },
                onTapDown: (details) {
                  setState(() {
                    final localX = details.localPosition.dx;
                    final ratio = (localX / chartWidth).clamp(0.0, 1.0);
                    _hoveredIndex = (doubleMinX + ratio * (doubleMaxX - doubleMinX)).round().clamp(
                          0,
                          data.length - 1,
                        );
                  });
                },
                child: Container(
                  height: 180,
                  padding: const EdgeInsets.only(right: 16, top: 16, bottom: 8),
                  child: LineChart(
                    LineChartData(
                      gridData: const FlGridData(show: true, drawVerticalLine: false),
                      titlesData: _buildTitlesData(data, doubleMinX, doubleMaxX),
                      borderData: FlBorderData(show: false),
                      minX: doubleMinX,
                      maxX: doubleMaxX,
                      minY: minMacd,
                      maxY: maxMacd,
                      lineBarsData: _buildMacdLines(data),
                      extraLinesData: ExtraLinesData(
                        verticalLines: _hoveredIndex != null
                            ? [
                                VerticalLine(
                                  x: _hoveredIndex!.toDouble(),
                                  color: Colors.white.withOpacity(0.25),
                                  strokeWidth: 1.5,
                                  dashArray: [4, 4],
                                ),
                              ]
                            : [],
                      ),
                      lineTouchData: const LineTouchData(enabled: false),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 24),
        _buildPaperTradingCard(data[(_hoveredIndex ?? (data.length - 1)).clamp(0, data.length - 1)], settings.selectedSymbol),
      ],
    );
  }

  // Live HUD Readout Panel
  Widget _buildHUDPanel(List<HistoryDataPoint> data, String symbol, String interval) {
    int index = _hoveredIndex ?? (data.length - 1);
    if (index < 0 || index >= data.length) {
      index = data.length - 1;
    }
    final pt = data[index];
    final date = DateTime.fromMillisecondsSinceEpoch(pt.time * 1000);
    final dateStr = DateFormat(interval == 'daily' || interval == 'weekly' ? 'yyyy-MM-dd' : 'MM-dd HH:mm').format(date);

    final prevClose = index > 0 ? data[index - 1].close : pt.close;
    final isUp = pt.close >= prevClose;
    final priceColor = isUp ? const Color(0xFF22C55E) : const Color(0xFFEF4444);

    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF131926).withOpacity(0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _hoveredIndex != null ? const Color(0xFF3B82F6) : const Color(0xFF22C55E),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _hoveredIndex != null ? 'LIVE INSPECT' : 'LATEST DATA',
                    style: TextStyle(
                      color: _hoveredIndex != null ? const Color(0xFF3B82F6) : const Color(0xFF22C55E),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  if (_hoveredIndex != null) ...[
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () {
                        setState(() {
                          _hoveredIndex = null;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'RESET',
                          style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              Text(
                dateStr,
                style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                _buildHUDMetric('Price', '\$${pt.close.toStringAsFixed(2)}', priceColor),
                _buildHUDDivider(),
                _buildHUDMetric(
                  'EMA9',
                  pt.ema != null ? '\$${pt.ema!.toStringAsFixed(2)}' : 'N/A',
                  const Color(0xFF8B5CF6),
                ),
                _buildHUDDivider(),
                _buildHUDMetric(
                  'RSI',
                  pt.rsi != null ? pt.rsi!.toStringAsFixed(1) : 'N/A',
                  pt.rsi != null && pt.rsi! >= 70
                      ? const Color(0xFFEF4444)
                      : (pt.rsi != null && pt.rsi! <= 30 ? const Color(0xFF22C55E) : const Color(0xFF06B6D4)),
                ),
                _buildHUDDivider(),
                _buildHUDMetric(
                  'MACD',
                  pt.macd != null ? pt.macd!.toStringAsFixed(2) : 'N/A',
                  const Color(0xFF06B6D4),
                ),
                _buildHUDDivider(),
                _buildHUDMetric(
                  'Signal',
                  pt.macdSignal != null ? pt.macdSignal!.toStringAsFixed(2) : 'N/A',
                  const Color(0xFFF59E0B),
                ),
                _buildHUDDivider(),
                _buildHUDMetric(
                  'Hist',
                  pt.macdHist != null ? pt.macdHist!.toStringAsFixed(2) : 'N/A',
                  pt.macdHist != null && pt.macdHist! >= 0 ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHUDMetric(String label, String value, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(color: valueColor, fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'Outfit'),
        ),
      ],
    );
  }

  Widget _buildHUDDivider() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      width: 1,
      height: 20,
      color: Colors.white12,
    );
  }

  // Collapsible Card Widget for indicator sections
  Widget _buildCollapsibleCard({
    required String title,
    required String subtitle,
    required bool isExpanded,
    required VoidCallback onToggle,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0x99131926),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: const TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                      ],
                    ],
                  ),
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: Colors.white70,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            const Divider(color: Colors.white10, height: 1),
            child,
          ],
        ],
      ),
    );
  }

  List<LineChartBarData> _buildMacdLines(List<HistoryDataPoint> data) {
    final List<LineChartBarData> lines = [];

    // 1. MACD Line
    lines.add(
      LineChartBarData(
        spots: data
            .asMap()
            .entries
            .where((e) => e.value.macd != null)
            .map((e) => FlSpot(e.key.toDouble(), e.value.macd!))
            .toList(),
        isCurved: true,
        barWidth: 2,
        color: const Color(0xFF06B6D4), // Cyan
        dotData: const FlDotData(show: false),
      ),
    );

    // 2. Signal Line
    lines.add(
      LineChartBarData(
        spots: data
            .asMap()
            .entries
            .where((e) => e.value.macdSignal != null)
            .map((e) => FlSpot(e.key.toDouble(), e.value.macdSignal!))
            .toList(),
        isCurved: true,
        barWidth: 2,
        color: const Color(0xFFF59E0B), // Orange
        dotData: const FlDotData(show: false),
      ),
    );

    // 3. Histogram bars (drawn as individual thin line segments)
    for (int i = 0; i < data.length; i++) {
      final histVal = data[i].macdHist;
      if (histVal == null) continue;

      final color = histVal >= 0 ? const Color(0xFF22C55E) : const Color(0xFFEF4444);

      lines.add(
        LineChartBarData(
          spots: [
            FlSpot(i.toDouble(), 0),
            FlSpot(i.toDouble(), histVal),
          ],
          isCurved: false,
          barWidth: 2,
          color: color.withOpacity(0.6),
          dotData: const FlDotData(show: false),
        ),
      );
    }

    return lines;
  }

  // Helper: Price Line Bars Builder
  List<LineChartBarData> _buildPriceLines(List<HistoryDataPoint> data) {
    final List<LineChartBarData> lines = [];

    // 1. Close Price Line
    lines.add(
      LineChartBarData(
        spots: data.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.close)).toList(),
        isCurved: true,
        barWidth: 2.5,
        color: Colors.white,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(
          show: true,
          gradient: LinearGradient(
            colors: [Colors.white.withOpacity(0.08), Colors.white.withOpacity(0)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
      ),
    );

    // 2. EMA9 Line
    if (_showEMA) {
      lines.add(
        LineChartBarData(
          spots: data
              .asMap()
              .entries
              .where((e) => e.value.ema != null)
              .map((e) => FlSpot(e.key.toDouble(), e.value.ema!))
              .toList(),
          isCurved: true,
          barWidth: 1.5,
          color: const Color(0xFF8B5CF6), // Violet
          dotData: const FlDotData(show: false),
        ),
      );
    }

    // 3. Bollinger Bands
    if (_showBB) {
      // Upper Band
      lines.add(
        LineChartBarData(
          spots: data
              .asMap()
              .entries
              .where((e) => e.value.bbUpper != null)
              .map((e) => FlSpot(e.key.toDouble(), e.value.bbUpper!))
              .toList(),
          isCurved: true,
          barWidth: 1,
          color: const Color(0xFF06B6D4).withOpacity(0.6), // Cyan
          dotData: const FlDotData(show: false),
        ),
      );
      // Lower Band
      lines.add(
        LineChartBarData(
          spots: data
              .asMap()
              .entries
              .where((e) => e.value.bbLower != null)
              .map((e) => FlSpot(e.key.toDouble(), e.value.bbLower!))
              .toList(),
          isCurved: true,
          barWidth: 1,
          color: const Color(0xFF06B6D4).withOpacity(0.6),
          dotData: const FlDotData(show: false),
        ),
      );
    }

    return lines;
  }

  // Helper: Titles Data for FlChart
  FlTitlesData _buildTitlesData(List<HistoryDataPoint> data, double minX, double maxX) {
    return FlTitlesData(
      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 45,
          getTitlesWidget: (value, meta) {
            return Text(
              value.toStringAsFixed(0),
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            );
          },
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          getTitlesWidget: (value, meta) {
            final idx = value.toInt();
            final minVisible = minX.toInt();
            final maxVisible = maxX.toInt();
            final visibleCount = maxVisible - minVisible;
            final step = visibleCount > 0 ? (visibleCount / 4).round() : 1;

            if (idx >= minVisible && idx <= maxVisible && (idx - minVisible) % step == 0) {
              final date = DateTime.fromMillisecondsSinceEpoch(data[idx].time * 1000);
              return Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  DateFormat('MM-dd HH:mm').format(date),
                  style: const TextStyle(color: Colors.white38, fontSize: 8),
                ),
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  // BACKTEST TAB
  Widget _buildBacktestTab(BacktestSummary summary, List<BacktestTrade> trades) {
    final bool isProfit = summary.netProfit >= 0;

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16.0),
      children: [
        // Summary Performance Grid Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0x99131926),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Net Profit', style: TextStyle(color: Colors.white70)),
                  Text(
                    '${isProfit ? '+' : ''}\$${summary.netProfit.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: isProfit ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(color: Colors.white10),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildStatItem('Win Rate', '${summary.winRate.toStringAsFixed(1)}%', Colors.blueAccent),
                  _buildStatItem('Total Trades', summary.totalTrades.toString(), Colors.amberAccent),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildStatItem('Strategy Return', '${summary.strategyReturn.toStringAsFixed(2)}%',
                      isProfit ? const Color(0xFF22C55E) : const Color(0xFFEF4444)),
                  _buildStatItem(
                    'Buy & Hold',
                    '${summary.buyAndHoldReturn.toStringAsFixed(2)}%',
                    summary.buyAndHoldReturn >= 0 ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        const Text(
          'Trade History Log',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 12),

        if (trades.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 32.0),
              child: Text('No trades executed during backtest period.', style: TextStyle(color: Colors.white30)),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: trades.length,
            itemBuilder: (context, index) {
              final trade = trades[index];
              final bool tradeProfit = trade.profit >= 0;

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0x66131926),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: tradeProfit ? const Color(0x2622C55E) : const Color(0x26EF4444),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                trade.type,
                                style: TextStyle(
                                  color: tradeProfit ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              DateFormat('MM-dd HH:mm').format(
                                DateTime.fromMillisecondsSinceEpoch(trade.entryTime * 1000),
                              ),
                              style: const TextStyle(color: Colors.white54, fontSize: 11),
                            )
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Entry: \$${trade.entryPrice.toStringAsFixed(2)} → Exit: \$${trade.exitPrice.toStringAsFixed(2)}',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        )
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${tradeProfit ? '+' : ''}\$${trade.profit.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: tradeProfit ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          '${tradeProfit ? '+' : ''}${trade.returnPercent.toStringAsFixed(2)}%',
                          style: TextStyle(
                            color: tradeProfit ? const Color(0xFF22C55E).withOpacity(0.8) : const Color(0xFFEF4444).withOpacity(0.8),
                            fontSize: 10,
                          ),
                        )
                      ],
                    )
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ],
    );
  }

  // CONFLUENCE TAB
  Widget _buildConfluenceTab(HistoryResponse response) {
    final pt = response.dataPoints[(_hoveredIndex ?? (response.dataPoints.length - 1)).clamp(0, response.dataPoints.length - 1)];
    final score = pt.confluenceScore ?? 5.5;

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16.0),
      children: [
        // RADIAL GAUGE CARD
        Container(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          margin: const EdgeInsets.only(bottom: 24),
          decoration: BoxDecoration(
            color: const Color(0x99131926),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Center(
            child: ConfluenceGauge(score: score),
          ),
        ),

        // Technical Indicators Summary stats
        _buildSectionHeader('Confluence Metrics'),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0x99131926),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Column(
            children: [
              _buildMetricRow('Average RSI Value', response.avgRsi.toStringAsFixed(1)),
              const Divider(color: Colors.white10),
              _buildMetricRow('RSI Standard Deviation', response.rsiStdDev.toStringAsFixed(2)),
              const Divider(color: Colors.white10),
              _buildMetricRow('Latest ATR Value', response.latestAtr.toStringAsFixed(2)),
              const Divider(color: Colors.white10),
              _buildMetricRow('Latest ATR %', '${response.latestAtrPercent.toStringAsFixed(2)}%'),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Divergence Alerts
        _buildSectionHeader('Scanned Divergences'),
        const SizedBox(height: 8),
        if (response.divergences.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0x0AFFFFFF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline, color: Color(0xFF22C55E), size: 20),
                SizedBox(width: 8),
                Text('No RSI divergences detected currently.', style: TextStyle(color: Colors.white54, fontSize: 13)),
              ],
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: response.divergences.length,
            itemBuilder: (context, index) {
              final div = response.divergences[index];
              final isBullish = div.type == 'bullish';

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isBullish ? const Color(0x1422C55E) : const Color(0x14EF4444),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isBullish ? const Color(0x3322C55E) : const Color(0x33EF4444),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      isBullish ? Icons.trending_up : Icons.trending_down,
                      color: isBullish ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${div.type.toUpperCase()} DIVERGENCE',
                            style: TextStyle(
                              color: isBullish ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            div.msg,
                            style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                          )
                        ],
                      ),
                    )
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFF06B6D4),
          fontSize: 13,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _buildMetricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildPaperTradingCard(HistoryDataPoint pt, String symbol) {
    final currentPrice = pt.close;
    final bool hasPosition = _paperPositionEntry != null;
    
    double pnl = 0.0;
    double returnPct = 0.0;
    if (hasPosition) {
      pnl = (currentPrice - _paperPositionEntry!) * _paperPositionShares;
      returnPct = ((currentPrice - _paperPositionEntry!) / _paperPositionEntry!) * 100;
    }
    final bool isProfit = pnl >= 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x99131926),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.account_balance_wallet_outlined, color: Color(0xFF06B6D4), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'PAPER TRADING SIMULATOR',
                    style: TextStyle(
                      color: const Color(0xFF06B6D4),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
              TextButton(
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                onPressed: () {
                  setState(() {
                    _paperBalance = 10000.0;
                    _paperPositionEntry = null;
                    _paperPositionShares = 0.0;
                    _paperLedger = [];
                    _savePaperTradingState();
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Simulator reset to default capital.')),
                  );
                },
                child: const Text('Reset', style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Account Balance', style: TextStyle(color: Colors.white38, fontSize: 11)),
                  const SizedBox(height: 4),
                  Text(
                    '\$${(hasPosition ? 0.0 : _paperBalance).toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Position Equity', style: TextStyle(color: Colors.white38, fontSize: 11)),
                  const SizedBox(height: 4),
                  Text(
                    '\$${(hasPosition ? (currentPrice * _paperPositionShares) : 0.0).toStringAsFixed(2)}',
                    style: TextStyle(
                      color: hasPosition ? const Color(0xFF06B6D4) : Colors.white24,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          
          if (hasPosition) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Position Details', style: TextStyle(color: Colors.white38, fontSize: 10)),
                      const SizedBox(height: 4),
                      Text(
                        'Entry: \$${_paperPositionEntry!.toStringAsFixed(2)} (${_paperPositionShares.toStringAsFixed(3)} shares)',
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Unrealized PnL', style: TextStyle(color: Colors.white38, fontSize: 10)),
                      const SizedBox(height: 4),
                      Text(
                        '${isProfit ? '+' : ''}\$${pnl.toStringAsFixed(2)} (${returnPct.toStringAsFixed(2)}%)',
                        style: TextStyle(
                          color: isProfit ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          
          const SizedBox(height: 16),
          
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF22C55E),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: hasPosition ? null : () {
                    setState(() {
                      _paperPositionShares = _paperBalance / currentPrice;
                      _paperPositionEntry = currentPrice;
                      _paperBalance = 0.0;
                      _savePaperTradingState();
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Bought LONG position at \$${currentPrice.toStringAsFixed(2)}')),
                    );
                  },
                  child: const Text('BUY LONG', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: !hasPosition ? null : () {
                    final finalPnl = (currentPrice - _paperPositionEntry!) * _paperPositionShares;
                    setState(() {
                      final rawBalance = currentPrice * _paperPositionShares;
                      
                      _paperLedger.add({
                        'symbol': symbol,
                        'entryPrice': _paperPositionEntry,
                        'exitPrice': currentPrice,
                        'shares': _paperPositionShares,
                        'profit': finalPnl,
                        'time': DateTime.now().millisecondsSinceEpoch ~/ 1000,
                      });
                      
                      _paperBalance = rawBalance;
                      _paperPositionEntry = null;
                      _paperPositionShares = 0.0;
                      
                      _savePaperTradingState();
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Position closed. PnL: \$${finalPnl.toStringAsFixed(2)}')),
                    );
                  },
                  child: const Text('CLOSE POSITION', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          
          if (_paperLedger.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(color: Colors.white10),
            const SizedBox(height: 8),
            const Text(
              'SIMULATION LEDGER',
              style: TextStyle(color: Colors.white30, fontSize: 10, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 120),
              child: ListView.builder(
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(),
                itemCount: _paperLedger.length,
                itemBuilder: (context, idx) {
                  final trade = _paperLedger[_paperLedger.length - 1 - idx];
                  final bool profit = (trade['profit'] as num).toDouble() >= 0;
                  final double profVal = (trade['profit'] as num).toDouble();
                  final double entry = (trade['entryPrice'] as num).toDouble();
                  final double exit = (trade['exitPrice'] as num).toDouble();
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${trade['symbol']}: \$${entry.toStringAsFixed(1)} → \$${exit.toStringAsFixed(1)}',
                          style: const TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                        Text(
                          '${profit ? '+' : ''}\$${profVal.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: profit ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ConfluenceGauge extends StatelessWidget {
  final double score;

  const ConfluenceGauge({super.key, required this.score});

  @override
  Widget build(BuildContext context) {
    Color scoreColor;
    String ratingText;

    if (score >= 8.0) {
      scoreColor = const Color(0xFF22C55E);
      ratingText = 'STRONG BUY';
    } else if (score >= 6.5) {
      scoreColor = const Color(0xFF06B6D4);
      ratingText = 'BUY';
    } else if (score >= 4.5) {
      scoreColor = const Color(0xFF94A3B8);
      ratingText = 'NEUTRAL';
    } else if (score >= 3.0) {
      scoreColor = const Color(0xFFF97316);
      ratingText = 'SELL';
    } else {
      scoreColor = const Color(0xFFEF4444);
      ratingText = 'STRONG SELL';
    }

    return Column(
      children: [
        SizedBox(
          width: 180,
          height: 100,
          child: CustomPaint(
            painter: _GaugePainter(score: score, color: scoreColor),
          ),
        ),
        Text(
          score.toStringAsFixed(1),
          style: TextStyle(
            color: scoreColor,
            fontSize: 28,
            fontWeight: FontWeight.w800,
            fontFamily: 'Outfit',
          ),
        ),
        Text(
          ratingText,
          style: TextStyle(
            color: scoreColor.withOpacity(0.8),
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double score;
  final Color color;

  _GaugePainter({required this.score, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height);
    final radius = size.width / 2 - 10;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    paint.color = Colors.white.withOpacity(0.08);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      pi,
      pi,
      false,
      paint,
    );

    paint.color = color;
    final double scorePct = ((score - 1.0) / 9.0).clamp(0.0, 1.0);
    final double sweepAngle = scorePct * pi;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      pi,
      sweepAngle,
      false,
      paint,
    );

    final needlePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final needleAngle = pi + sweepAngle;
    final needleTip = Offset(
      center.dx + radius * cos(needleAngle),
      center.dy + radius * sin(needleAngle),
    );

    canvas.drawCircle(center, 6, needlePaint);
    canvas.drawCircle(needleTip, 4, needlePaint);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) {
    return oldDelegate.score != score || oldDelegate.color != color;
  }
}

class _OptimizerDialogWidget extends StatefulWidget {
  final List<double> closes;
  final UserSettingsNotifier settingsNotifier;

  const _OptimizerDialogWidget({
    required this.closes,
    required this.settingsNotifier,
  });

  @override
  State<_OptimizerDialogWidget> createState() => _OptimizerDialogWidgetState();
}

class _OptimizerDialogWidgetState extends State<_OptimizerDialogWidget> {
  bool _expandedMode = false;
  bool _running = false;
  List<OptimizationResult> _results = [];
  String _status = 'Ready to optimize.';

  Future<void> _runOptimize() async {
    setState(() {
      _running = true;
      _status = 'Running indicator calculations...';
    });

    await Future.delayed(const Duration(milliseconds: 100));

    try {
      final results = OptimizerEngine.runOptimization(
        closes: widget.closes,
        expandedMode: _expandedMode,
      );

      setState(() {
        _results = results;
        _running = false;
        _status = 'Scan complete. Found ${results.length} candidate combinations.';
      });
    } catch (e) {
      setState(() {
        _running = false;
        _status = 'Optimization failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final best = _results.isNotEmpty ? _results.first : null;

    return Dialog(
      backgroundColor: const Color(0xFF131926),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(20),
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'RSI Optimization Engine',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, fontFamily: 'Outfit'),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                  onPressed: () => Navigator.pop(context),
                )
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Find parameters that maximize return. Robustness Mode evaluates neighbor neighborhoods to avoid overfitting.',
              style: TextStyle(color: Colors.white54, fontSize: 11, height: 1.4),
            ),
            const SizedBox(height: 16),
            
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Text('Fast Scan', style: TextStyle(fontSize: 11)),
                    selected: !_expandedMode,
                    selectedColor: const Color(0xFF8B5CF6),
                    backgroundColor: const Color(0xFF1E1E38),
                    labelStyle: TextStyle(color: !_expandedMode ? Colors.white : Colors.white70),
                    onSelected: (val) {
                      if (!_running) setState(() => _expandedMode = false);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: const Text('Robustness Scan', style: TextStyle(fontSize: 11)),
                    selected: _expandedMode,
                    selectedColor: const Color(0xFF8B5CF6),
                    backgroundColor: const Color(0xFF1E1E38),
                    labelStyle: TextStyle(color: _expandedMode ? Colors.white : Colors.white70),
                    onSelected: (val) {
                      if (!_running) setState(() => _expandedMode = true);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            if (_running) ...[
              const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(color: Color(0xFF8B5CF6)),
                    SizedBox(height: 12),
                    Text('Analyzing parameter matrix...', style: TextStyle(color: Colors.white54, fontSize: 11)),
                  ],
                ),
              )
            ] else ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8B5CF6),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _runOptimize,
                  child: const Text('Start Optimization Scan', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
            ],
            
            const SizedBox(height: 16),
            Text(
              _status,
              style: const TextStyle(color: Colors.white38, fontSize: 11, fontStyle: FontStyle.italic),
            ),
            
            if (best != null) ...[
              const SizedBox(height: 16),
              const Divider(color: Colors.white10),
              const SizedBox(height: 12),
              const Text(
                'RECOMMENDED PARAMETERS',
                style: TextStyle(color: Color(0xFF06B6D4), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
              const SizedBox(height: 12),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildParamMetric('RSI Period', best.rsiPeriod.toString()),
                  _buildParamMetric('Overbought', best.overbought.toString()),
                  _buildParamMetric('Oversold', best.oversold.toString()),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildParamMetric('Est. Return', '${best.strategyReturn.toStringAsFixed(1)}%'),
                  _buildParamMetric('Win Rate', '${best.winRate.toStringAsFixed(1)}%'),
                  if (_expandedMode)
                    _buildParamMetric('Robustness', '${best.robustnessScore.toStringAsFixed(1)}%'),
                ],
              ),
              
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF06B6D4),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    widget.settingsNotifier.updateRsiPeriod(best.rsiPeriod);
                    widget.settingsNotifier.updateThresholds(best.overbought, best.oversold);
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Applied: RSI ${best.rsiPeriod}, OB ${best.overbought}, OS ${best.oversold}')),
                    );
                  },
                  child: const Text('Apply Optimal Parameters', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildParamMetric(String label, String val) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9)),
        const SizedBox(height: 2),
        Text(val, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    );
  }
}

