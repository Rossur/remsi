// services/api_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/market_data.dart';
import 'settings_provider.dart';

// Helper to resolve the correct backend API URL dynamically
String getBaseUrl() {
  if (kIsWeb) {
    // Uri.base.origin works perfectly on Flutter Web without dart:html imports
    final origin = Uri.base.origin;
    // In local development, Vercel dev usually runs on port 3000 or the local node server runs on 3000
    if (origin.contains('localhost:')) {
      // If the flutter web is running on a different local port (e.g. 5555),
      // we target the standard local server at port 3000
      if (!origin.contains(':3000')) {
        return 'http://localhost:3000';
      }
    }
    return origin;
  }
  // Production fallback for mobile native compilation (iOS/Android)
  return 'https://remsi-omega.vercel.app';
}

class ApiService {
  final String baseUrl = getBaseUrl();

  // Fetches quick overview results from /api/check
  Future<TickerCheckResponse> fetchCheckResults({
    String? secret,
    List<String>? symbols,
    String? fcmToken,
    String? discordWebhook,
    String? email,
    int? rsiPeriod,
    int? overbought,
    int? oversold,
  }) async {
    final Map<String, String> queryParams = {};
    if (secret != null && secret.isNotEmpty) queryParams['secret'] = secret;
    if (symbols != null && symbols.isNotEmpty) queryParams['symbols'] = symbols.join(',');
    if (fcmToken != null && fcmToken.isNotEmpty) queryParams['fcmToken'] = fcmToken;
    if (discordWebhook != null && discordWebhook.isNotEmpty) queryParams['discordWebhook'] = discordWebhook;
    if (email != null && email.isNotEmpty) queryParams['email'] = email;
    if (rsiPeriod != null) queryParams['rsiPeriod'] = rsiPeriod.toString();
    if (overbought != null) queryParams['overbought'] = overbought.toString();
    if (oversold != null) queryParams['oversold'] = oversold.toString();

    final uri = Uri.parse('$baseUrl/api/check').replace(queryParameters: queryParams);

    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        return TickerCheckResponse.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to load check results: ${response.statusCode} (${response.body})');
      }
    } catch (e) {
      throw Exception('Network error fetching check results: $e');
    }
  }

  // Fetches comprehensive chart and backtest data from /api/history
  Future<HistoryResponse> fetchHistory({
    required String symbol,
    required String interval,
    required int rsiPeriod,
    required int overbought,
    required int oversold,
  }) async {
    final queryParams = {
      'symbol': symbol,
      'interval': interval,
      'rsiPeriod': rsiPeriod.toString(),
      'overbought': overbought.toString(),
      'oversold': oversold.toString(),
    };

    final uri = Uri.parse('$baseUrl/api/history').replace(queryParameters: queryParams);

    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        return HistoryResponse.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to load history data: ${response.statusCode} (${response.body})');
      }
    } catch (e) {
      throw Exception('Network error fetching history: $e');
    }
  // Registers device FCM token and watchlist in Upstash Redis via /api/subscribe
  Future<bool> subscribeDevice({
    required String fcmToken,
    List<String>? tickers,
  }) async {
    final uri = Uri.parse('$baseUrl/api/subscribe');
    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'fcmToken': fcmToken,
          if (tickers != null && tickers.isNotEmpty) 'tickers': tickers,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error registering subscriber: $e');
      return false;
    }
  }
}

// Riverpod Provider for ApiService
final apiServiceProvider = Provider((ref) => ApiService());

// Riverpod FutureProvider for check overview
final checkResultsProvider = FutureProvider<TickerCheckResponse>((ref) async {
  final api = ref.watch(apiServiceProvider);
  final settings = ref.watch(settingsProvider);
  return api.fetchCheckResults(
    secret: settings.cronSecret,
    symbols: settings.watchlist,
    fcmToken: settings.fcmToken,
    discordWebhook: settings.discordWebhook,
    email: settings.email,
    rsiPeriod: settings.rsiPeriod,
    overbought: settings.overbought,
    oversold: settings.oversold,
  );
});

// Parameter class for fetching history dynamically
class HistoryParams {
  final String symbol;
  final String interval;
  final int rsiPeriod;
  final int overbought;
  final int oversold;

  HistoryParams({
    required this.symbol,
    required this.interval,
    required this.rsiPeriod,
    required this.overbought,
    required this.oversold,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HistoryParams &&
          runtimeType == other.runtimeType &&
          symbol == other.symbol &&
          interval == other.interval &&
          rsiPeriod == other.rsiPeriod &&
          overbought == other.overbought &&
          oversold == other.oversold;

  @override
  int get hashCode =>
      symbol.hashCode ^
      interval.hashCode ^
      rsiPeriod.hashCode ^
      overbought.hashCode ^
      oversold.hashCode;
}

// Riverpod Family FutureProvider for details and charts
final historyProvider = FutureProvider.family<HistoryResponse, HistoryParams>((ref, HistoryParams params) async {
  final api = ref.watch(apiServiceProvider);
  return api.fetchHistory(
    symbol: params.symbol,
    interval: params.interval,
    rsiPeriod: params.rsiPeriod,
    overbought: params.overbought,
    oversold: params.oversold,
  );
});
