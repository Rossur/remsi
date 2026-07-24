// services/settings_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserSettings {
  final String selectedSymbol;
  final String selectedInterval;
  final int rsiPeriod;
  final int overbought;
  final int oversold;
  final String cronSecret;
  final List<String> watchlist;
  final String fcmToken;
  final String discordWebhook;
  final String email;

  UserSettings({
    required this.selectedSymbol,
    required this.selectedInterval,
    required this.rsiPeriod,
    required this.overbought,
    required this.oversold,
    required this.cronSecret,
    required this.watchlist,
    required this.fcmToken,
    required this.discordWebhook,
    required this.email,
  });

  UserSettings copyWith({
    String? selectedSymbol,
    String? selectedInterval,
    int? rsiPeriod,
    int? overbought,
    int? oversold,
    String? cronSecret,
    List<String>? watchlist,
    String? fcmToken,
    String? discordWebhook,
    String? email,
  }) {
    return UserSettings(
      selectedSymbol: selectedSymbol ?? this.selectedSymbol,
      selectedInterval: selectedInterval ?? this.selectedInterval,
      rsiPeriod: rsiPeriod ?? this.rsiPeriod,
      overbought: overbought ?? this.overbought,
      oversold: oversold ?? this.oversold,
      cronSecret: cronSecret ?? this.cronSecret,
      watchlist: watchlist ?? this.watchlist,
      fcmToken: fcmToken ?? this.fcmToken,
      discordWebhook: discordWebhook ?? this.discordWebhook,
      email: email ?? this.email,
    );
  }
}

class UserSettingsNotifier extends StateNotifier<UserSettings> {
  UserSettingsNotifier()
      : super(UserSettings(
          selectedSymbol: 'GC=F',
          selectedInterval: '15m',
          rsiPeriod: 14,
          overbought: 70,
          oversold: 30,
          cronSecret: '',
          watchlist: ['GC=F', 'SI=F', 'CL=F', 'AAPL', 'MSFT', 'GOOG', 'TSLA'],
          fcmToken: '',
          discordWebhook: '',
          email: '',
        )) {
    _loadFromPrefs();
  }

  static const _keySymbol = 'remsi_symbol';
  static const _keyInterval = 'remsi_interval';
  static const _keyRsiPeriod = 'remsi_rsi_period';
  static const _keyOverbought = 'remsi_overbought';
  static const _keyOversold = 'remsi_oversold';
  static const _keySecret = 'remsi_cron_secret';
  static const _keyWatchlist = 'remsi_watchlist';
  static const _keyFcmToken = 'remsi_fcm_token';
  static const _keyDiscordWebhook = 'remsi_discord_webhook';
  static const _keyEmail = 'remsi_email';

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = UserSettings(
        selectedSymbol: prefs.getString(_keySymbol) ?? 'GC=F',
        selectedInterval: prefs.getString(_keyInterval) ?? '15m',
        rsiPeriod: prefs.getInt(_keyRsiPeriod) ?? 14,
        overbought: prefs.getInt(_keyOverbought) ?? 70,
        oversold: prefs.getInt(_keyOversold) ?? 30,
        cronSecret: prefs.getString(_keySecret) ?? '',
        watchlist: prefs.getStringList(_keyWatchlist) ?? ['GC=F', 'SI=F', 'CL=F', 'AAPL', 'MSFT', 'GOOG', 'TSLA'],
        fcmToken: prefs.getString(_keyFcmToken) ?? '',
        discordWebhook: prefs.getString(_keyDiscordWebhook) ?? '',
        email: prefs.getString(_keyEmail) ?? '',
      );
    } catch (e) {
      // SharedPreferences might fail to instantiate in some web sandbox edge cases
      // We gracefully keep defaults in memory
    }
  }

  Future<void> updateSymbol(String symbol) async {
    state = state.copyWith(selectedSymbol: symbol);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySymbol, symbol);
  }

  Future<void> updateInterval(String interval) async {
    state = state.copyWith(selectedInterval: interval);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyInterval, interval);
  }

  Future<void> updateRsiPeriod(int period) async {
    state = state.copyWith(rsiPeriod: period);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyRsiPeriod, period);
  }

  Future<void> updateThresholds(int overbought, int oversold) async {
    state = state.copyWith(overbought: overbought, oversold: oversold);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyOverbought, overbought);
    await prefs.setInt(_keyOversold, oversold);
  }

  Future<void> updateCronSecret(String secret) async {
    state = state.copyWith(cronSecret: secret);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySecret, secret);
  }

  Future<void> addToWatchlist(String symbol) async {
    final cleanSymbol = symbol.trim().toUpperCase();
    if (cleanSymbol.isEmpty || state.watchlist.contains(cleanSymbol)) return;
    
    final updated = List<String>.from(state.watchlist)..add(cleanSymbol);
    state = state.copyWith(watchlist: updated);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyWatchlist, updated);
  }

  Future<void> removeFromWatchlist(String symbol) async {
    final updated = List<String>.from(state.watchlist)..remove(symbol);
    state = state.copyWith(watchlist: updated);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyWatchlist, updated);
  }

  Future<void> updateNotifierSettings({
    String? fcmToken,
    String? discordWebhook,
    String? email,
  }) async {
    state = state.copyWith(
      fcmToken: fcmToken ?? state.fcmToken,
      discordWebhook: discordWebhook ?? state.discordWebhook,
      email: email ?? state.email,
    );
    final prefs = await SharedPreferences.getInstance();
    if (fcmToken != null) await prefs.setString(_keyFcmToken, fcmToken);
    if (discordWebhook != null) await prefs.setString(_keyDiscordWebhook, discordWebhook);
    if (email != null) await prefs.setString(_keyEmail, email);
  }
}


// Riverpod provider for UserSettings StateNotifier
final settingsProvider = StateNotifierProvider<UserSettingsNotifier, UserSettings>((ref) {
  return UserSettingsNotifier();
});
