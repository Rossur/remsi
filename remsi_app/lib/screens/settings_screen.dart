// screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/settings_provider.dart';
import '../services/api_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _secretController;
  late TextEditingController _watchlistController;
  late TextEditingController _discordController;
  late TextEditingController _emailController;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _secretController = TextEditingController(text: settings.cronSecret);
    _watchlistController = TextEditingController();
    _discordController = TextEditingController(text: settings.discordWebhook);
    _emailController = TextEditingController(text: settings.email);
  }

  @override
  void dispose() {
    _secretController.dispose();
    _watchlistController.dispose();
    _discordController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF0F0F1A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0B0E17),
        ),
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          children: [
            // API Credentials Section
            _buildSectionHeader('API Configuration'),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0x99131926),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Cron Authorization Secret',
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _secretController,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Enter Vercel CRON_SECRET token',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF141424),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.save, color: Color(0xFF8B5CF6)),
                        onPressed: () async {
                          final secret = _secretController.text.trim();
                          await settingsNotifier.updateCronSecret(secret);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Vercel CRON_SECRET updated locally.')),
                          );
                          // Trigger reload of overview checks
                          ref.refresh(checkResultsProvider);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Required to authorize manual refreshes if Vercel backend enforces a secret key.',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Watchlist Manager Section
            _buildSectionHeader('Watchlist Tickers'),
            Container(
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
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _watchlistController,
                          style: const TextStyle(color: Colors.white),
                          textCapitalization: TextCapitalization.characters,
                          decoration: InputDecoration(
                            hintText: 'Enter Symbol (e.g. AAPL, TSLA)',
                            hintStyle: const TextStyle(color: Colors.white38),
                            filled: true,
                            fillColor: const Color(0xFF141424),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8B5CF6),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          final sym = _watchlistController.text.trim().toUpperCase();
                          if (sym.isNotEmpty) {
                            settingsNotifier.addToWatchlist(sym);
                            _watchlistController.clear();
                            ref.refresh(checkResultsProvider);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Added $sym to watchlist.')),
                            );
                          }
                        },
                        child: const Icon(Icons.add, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: settings.watchlist.map((sym) {
                      return Chip(
                        label: Text(sym, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                        backgroundColor: const Color(0xFF141424),
                        side: BorderSide(color: Colors.white.withOpacity(0.1)),
                        deleteIcon: const Icon(Icons.close, size: 14, color: Colors.redAccent),
                        onDeleted: () {
                          settingsNotifier.removeFromWatchlist(sym);
                          ref.refresh(checkResultsProvider);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Removed $sym from watchlist.')),
                          );
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Notification Channels Section
            _buildSectionHeader('Notification Channels'),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0x99131926),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Discord Webhook URL',
                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _discordController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'https://discord.com/api/webhooks/...',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF141424),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  const Text(
                    'Email Address',
                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'your-email@example.com',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF141424),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  const Text(
                    'FCM Device Token (APNs / Android Native)',
                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF141424),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            settings.fcmToken.isEmpty ? 'Waiting for Token dispatch...' : settings.fcmToken,
                            style: const TextStyle(color: Colors.white54, fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8B5CF6),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () async {
                        final webhook = _discordController.text.trim();
                        final email = _emailController.text.trim();
                        await settingsNotifier.updateNotifierSettings(
                          discordWebhook: webhook,
                          email: email,
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Alert configurations updated.')),
                        );
                        ref.refresh(checkResultsProvider);
                      },
                      child: const Text('Save Alert Options', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Indicators Section
            _buildSectionHeader('Indicator Parameters'),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0x99131926),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Column(
                children: [
                  // RSI Period
                  _buildSliderRow(
                    label: 'RSI Period',
                    value: settings.rsiPeriod.toDouble(),
                    min: 2,
                    max: 50,
                    divisions: 48,
                    displayVal: settings.rsiPeriod.toString(),
                    onChanged: (val) {
                      settingsNotifier.updateRsiPeriod(val.toInt());
                    },
                  ),
                  const Divider(color: Colors.white10, height: 24),

                  // Overbought Threshold
                  _buildSliderRow(
                    label: 'Overbought Threshold',
                    value: settings.overbought.toDouble(),
                    min: 55,
                    max: 95,
                    divisions: 40,
                    displayVal: settings.overbought.toString(),
                    activeColor: const Color(0xFFEF4444),
                    onChanged: (val) {
                      settingsNotifier.updateThresholds(val.toInt(), settings.oversold);
                    },
                  ),
                  const Divider(color: Colors.white10, height: 24),

                  // Oversold Threshold
                  _buildSliderRow(
                    label: 'Oversold Threshold',
                    value: settings.oversold.toDouble(),
                    min: 5,
                    max: 45,
                    divisions: 40,
                    displayVal: settings.oversold.toString(),
                    activeColor: const Color(0xFF22C55E),
                    onChanged: (val) {
                      settingsNotifier.updateThresholds(settings.overbought, val.toInt());
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // App Information
            const Center(
              child: Text(
                'REMSI v1.0.0 (Flutter Web PWA)\nConnected to Vercel Serverless Backend',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white30, fontSize: 11, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFF06B6D4), // Cyan header
          fontSize: 13,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _buildSliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String displayVal,
    required ValueChanged<double> onChanged,
    Color activeColor = const Color(0xFF8B5CF6),
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold),
            ),
            Text(
              displayVal,
              style: TextStyle(color: activeColor, fontSize: 14, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          activeColor: activeColor,
          inactiveColor: Colors.white12,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
