// screens/dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../services/settings_provider.dart';
import '../models/market_data.dart';
import 'chart_screen.dart';
import 'settings_screen.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  String _getSymbolFriendlyName(String symbol) {
    if (symbol == 'GC=F') return 'Gold Futures (COMEX)';
    if (symbol == 'SI=F') return 'Silver Futures (COMEX)';
    return symbol;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checkAsync = ref.watch(checkResultsProvider);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            colors: [
              Color(0xFF131926), // slate dark core
              Color(0xFF0B0E17), // very dark indigo edges
            ],
            center: Alignment.topCenter,
            radius: 1.5,
          ),
        ),
        child: SafeArea(
          child: RefreshIndicator(
            color: const Color(0xFF8B5CF6),
            backgroundColor: const Color(0xFF131926),
            onRefresh: () async {
              ref.refresh(checkResultsProvider);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
              children: [
                // 1. HEADER ROW
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'REMSI',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            foreground: Paint()
                              ..shader = const LinearGradient(
                                colors: [Color(0xFF8B5CF6), Color(0xFF06B6D4)],
                              ).createShader(const Rect.fromLTWH(0.0, 0.0, 200.0, 70.0)),
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Real-time Market RSI Analysis Engine',
                          style: TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.refresh, color: Colors.white70, size: 22),
                          onPressed: () {
                            ref.refresh(checkResultsProvider);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.settings, color: Colors.white70, size: 22),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const SettingsScreen()),
                            );
                          },
                        ),
                      ],
                    )
                  ],
                ),
                const SizedBox(height: 24),

                // 2. MAIN STATE LOADER
                checkAsync.when(
                  data: (response) {
                    final results = response.results;

                    // Group results by Symbol
                    final Set<String> symbols = results.map((r) => r.symbol).toSet();

                    // Filter out active alerts (oversold / overbought status)
                    final activeAlerts = results.where((r) => r.status != 'normal').toList();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // MOMENTUM HEATMAP CARD
                        Container(
                          padding: const EdgeInsets.all(16.0),
                          decoration: BoxDecoration(
                            color: const Color(0x99131926),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withOpacity(0.08)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.25),
                                blurRadius: 15,
                                offset: const Offset(0, 10),
                              )
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Heatmap Header Label
                              Row(
                                children: [
                                  const Icon(Icons.grid_on_rounded, color: Color(0xFF06B6D4), size: 16),
                                  const SizedBox(width: 8),
                                  Text(
                                    'MOMENTUM HEATMAP',
                                    style: TextStyle(
                                      color: const Color(0xFF06B6D4),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),

                              // Table Header Row
                              Row(
                                children: [
                                  const Expanded(
                                    flex: 4,
                                    child: Text(
                                      'ASSET',
                                      style: TextStyle(color: Colors.white30, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 7,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: const [
                                        SizedBox(width: 42, child: Center(child: Text('5M', style: TextStyle(color: Colors.white30, fontSize: 10, fontWeight: FontWeight.bold)))),
                                        SizedBox(width: 42, child: Center(child: Text('15M', style: TextStyle(color: Colors.white30, fontSize: 10, fontWeight: FontWeight.bold)))),
                                        SizedBox(width: 42, child: Center(child: Text('1H', style: TextStyle(color: Colors.white30, fontSize: 10, fontWeight: FontWeight.bold)))),
                                        SizedBox(width: 42, child: Center(child: Text('D', style: TextStyle(color: Colors.white30, fontSize: 10, fontWeight: FontWeight.bold)))),
                                        SizedBox(width: 42, child: Center(child: Text('W', style: TextStyle(color: Colors.white30, fontSize: 10, fontWeight: FontWeight.bold)))),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(color: Colors.white10, height: 16),

                              // Render Heatmap Tickers
                              if (symbols.isEmpty)
                                const Center(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(vertical: 20.0),
                                    child: Text('No assets configured.', style: TextStyle(color: Colors.white38)),
                                  ),
                                )
                              else
                                ...symbols.map((sym) => _buildHeatmapRow(context, ref, sym, results)).toList(),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),

                        // ACTIVE ALERTS FEED
                        Padding(
                          padding: const EdgeInsets.only(left: 4.0, bottom: 12.0),
                          child: Row(
                            children: [
                              const Icon(Icons.notifications_active_outlined, color: Color(0xFF8B5CF6), size: 16),
                              const SizedBox(width: 8),
                              Text(
                                'ACTIVE ALERT FEED',
                                style: TextStyle(
                                  color: const Color(0xFF8B5CF6),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ],
                          ),
                        ),

                        if (activeAlerts.isEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
                            decoration: BoxDecoration(
                              color: const Color(0x66131926),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white.withOpacity(0.04)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.check_circle_outline, color: Color(0xFF22C55E), size: 18),
                                const SizedBox(width: 8),
                                const Text(
                                  'All assets are normal. No active RSI warnings.',
                                  style: TextStyle(color: Colors.white54, fontSize: 12),
                                ),
                              ],
                            ),
                          )
                        else
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: activeAlerts.length,
                            itemBuilder: (context, idx) {
                              final alert = activeAlerts[idx];
                              final isOversold = alert.status == 'oversold';
                              
                              Color alertColor = isOversold ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
                              Color glowColor = isOversold ? const Color(0x1A22C55E) : const Color(0x1AEF4444);

                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0x80131926),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: alertColor.withOpacity(0.25)),
                                  boxShadow: [
                                    BoxShadow(
                                      color: glowColor,
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    )
                                  ],
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: alertColor.withOpacity(0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      isOversold ? Icons.trending_up : Icons.trending_down,
                                      color: alertColor,
                                      size: 18,
                                    ),
                                  ),
                                  title: Text(
                                    '${alert.symbol} (${alert.interval.toUpperCase()})',
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14),
                                  ),
                                  subtitle: Text(
                                    '${_getSymbolFriendlyName(alert.symbol)} is ${alert.status.toUpperCase()}',
                                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                                  ),
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        'RSI: ${alert.rsi.toStringAsFixed(1)}',
                                        style: TextStyle(
                                          color: alertColor,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '\$${alert.close.toStringAsFixed(2)}',
                                        style: const TextStyle(color: Colors.white30, fontSize: 10),
                                      )
                                    ],
                                  ),
                                  onTap: () {
                                    ref.read(settingsProvider.notifier).updateSymbol(alert.symbol);
                                    ref.read(settingsProvider.notifier).updateInterval(alert.interval);
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => const ChartScreen()),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                      ],
                    );
                  },
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.only(top: 80.0),
                      child: CircularProgressIndicator(color: Color(0xFF8B5CF6)),
                    ),
                  ),
                  error: (error, stackTrace) => Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 60.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
                          const SizedBox(height: 16),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24.0),
                            child: Text(
                              'Failed to connect to Vercel:\n$error',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF8B5CF6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () {
                              ref.refresh(checkResultsProvider);
                            },
                            child: const Text('Try Again'),
                          )
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeatmapRow(BuildContext context, WidgetRef ref, String symbol, List<CheckResult> results) {
    final timeframes = ['5m', '15m', '1h', 'daily', 'weekly'];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          // Ticker Symbol Column
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  symbol,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _getSymbolFriendlyName(symbol),
                  style: const TextStyle(
                    color: Colors.white30,
                    fontSize: 9,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Heatmap grid of columns
          Expanded(
            flex: 7,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: timeframes.map((tf) {
                final item = results.firstWhere(
                  (r) => r.symbol == symbol && r.interval == tf,
                  orElse: () => CheckResult(symbol: symbol, interval: tf, close: 0.0, rsi: -1.0, status: 'normal'),
                );
                return _buildHeatmapCell(context, ref, item);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeatmapCell(BuildContext context, WidgetRef ref, CheckResult item) {
    final bool hasData = item.rsi >= 0;
    if (!hasData) {
      return Container(
        width: 42,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.015),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white.withOpacity(0.03)),
        ),
        child: const Center(
          child: Text(
            '-',
            style: TextStyle(color: Colors.white24, fontSize: 12),
          ),
        ),
      );
    }

    final bool isOversold = item.status == 'oversold';
    final bool isOverbought = item.status == 'overbought';

    Color cellColor = const Color(0xFF8B5CF6).withOpacity(0.1); // normal violet
    Color borderColor = const Color(0xFF8B5CF6).withOpacity(0.25);
    Color textColor = const Color(0xFFC084FC); // light violet

    if (isOversold) {
      cellColor = const Color(0xFF22C55E).withOpacity(0.12); // green
      borderColor = const Color(0xFF22C55E).withOpacity(0.35);
      textColor = const Color(0xFF4ADE80);
    } else if (isOverbought) {
      cellColor = const Color(0xFFEF4444).withOpacity(0.12); // red
      borderColor = const Color(0xFFEF4444).withOpacity(0.35);
      textColor = const Color(0xFFF87171);
    }

    return GestureDetector(
      onTap: () {
        ref.read(settingsProvider.notifier).updateSymbol(item.symbol);
        ref.read(settingsProvider.notifier).updateInterval(item.interval);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const ChartScreen()),
        );
      },
      child: Container(
        width: 42,
        height: 36,
        decoration: BoxDecoration(
          color: cellColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: borderColor, width: 1.2),
          boxShadow: [
            if (isOversold || isOverbought)
              BoxShadow(
                color: isOversold ? const Color(0x1F22C55E) : const Color(0x1FEF4444),
                blurRadius: 4,
                spreadRadius: 1,
              )
          ],
        ),
        child: Center(
          child: Text(
            item.rsi.toStringAsFixed(0),
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
