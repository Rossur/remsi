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

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _secretController = TextEditingController(text: settings.cronSecret);
  }

  @override
  void dispose() {
    _secretController.dispose();
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
          color: Color(0xFF0F0F1A),
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
                color: const Color(0x1F2B2B40),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
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

            // Indicators Section
            _buildSectionHeader('Indicator Parameters'),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0x1F2B2B40),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
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
