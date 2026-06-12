// models/market_data.dart

class CheckResult {
  final String symbol;
  final String interval;
  final double close;
  final double rsi;
  final double confluenceScore;
  final String status; // 'normal', 'oversold', 'overbought'

  CheckResult({
    required this.symbol,
    required this.interval,
    required this.close,
    required this.rsi,
    required this.confluenceScore,
    required this.status,
  });

  factory CheckResult.fromJson(Map<String, dynamic> json) {
    return CheckResult(
      symbol: json['symbol'] ?? '',
      interval: json['interval'] ?? '',
      close: double.tryParse(json['close']?.toString() ?? '0') ?? 0.0,
      rsi: double.tryParse(json['rsi']?.toString() ?? '0') ?? 0.0,
      confluenceScore: double.tryParse(json['confluenceScore']?.toString() ?? '5.5') ?? 5.5,
      status: json['status'] ?? 'normal',
    );
  }
}

class TickerCheckResponse {
  final bool success;
  final String timestamp;
  final List<CheckResult> results;

  TickerCheckResponse({
    required this.success,
    required this.timestamp,
    required this.results,
  });

  factory TickerCheckResponse.fromJson(Map<String, dynamic> json) {
    var list = json['results'] as List? ?? [];
    List<CheckResult> resultsList = list.map((i) => CheckResult.fromJson(i)).toList();
    return TickerCheckResponse(
      success: json['success'] ?? false,
      timestamp: json['timestamp'] ?? '',
      results: resultsList,
    );
  }
}

class HistoryDataPoint {
  final int time;
  final double close;
  final double? rsi;
  final double? ema;
  final double? macd;
  final double? macdSignal;
  final double? macdHist;
  final double? bbUpper;
  final double? bbLower;
  final double? bbMiddle;
  final double? atr;
  final double? confluenceScore;

  HistoryDataPoint({
    required this.time,
    required this.close,
    this.rsi,
    this.ema,
    this.macd,
    this.macdSignal,
    this.macdHist,
    this.bbUpper,
    this.bbLower,
    this.bbMiddle,
    this.atr,
    this.confluenceScore,
  });

  factory HistoryDataPoint.fromJson(Map<String, dynamic> json) {
    return HistoryDataPoint(
      time: json['time'] ?? 0,
      close: (json['close'] as num?)?.toDouble() ?? 0.0,
      rsi: (json['rsi'] as num?)?.toDouble(),
      ema: (json['ema'] as num?)?.toDouble(),
      macd: (json['macd'] as num?)?.toDouble(),
      macdSignal: (json['macdSignal'] as num?)?.toDouble(),
      macdHist: (json['macdHist'] as num?)?.toDouble(),
      bbUpper: (json['bbUpper'] as num?)?.toDouble(),
      bbLower: (json['bbLower'] as num?)?.toDouble(),
      bbMiddle: (json['bbMiddle'] as num?)?.toDouble(),
      atr: (json['atr'] as num?)?.toDouble(),
      confluenceScore: (json['confluenceScore'] as num?)?.toDouble(),
    );
  }
}

class BacktestTrade {
  final String type;
  final double entryPrice;
  final int entryTime;
  final double exitPrice;
  final int exitTime;
  final double profit;
  final double returnPercent;
  final double capitalAfter;
  final bool isOpen;

  BacktestTrade({
    required this.type,
    required this.entryPrice,
    required this.entryTime,
    required this.exitPrice,
    required this.exitTime,
    required this.profit,
    required this.returnPercent,
    required this.capitalAfter,
    this.isOpen = false,
  });

  factory BacktestTrade.fromJson(Map<String, dynamic> json) {
    return BacktestTrade(
      type: json['type'] ?? 'LONG',
      entryPrice: (json['entryPrice'] as num?)?.toDouble() ?? 0.0,
      entryTime: json['entryTime'] ?? 0,
      exitPrice: (json['exitPrice'] as num?)?.toDouble() ?? 0.0,
      exitTime: json['exitTime'] ?? 0,
      profit: (json['profit'] as num?)?.toDouble() ?? 0.0,
      returnPercent: (json['returnPercent'] as num?)?.toDouble() ?? 0.0,
      capitalAfter: (json['capitalAfter'] as num?)?.toDouble() ?? 0.0,
      isOpen: json['isOpen'] ?? false,
    );
  }
}

class BacktestSummary {
  final double startingCapital;
  final double endingCapital;
  final double netProfit;
  final double strategyReturn;
  final double buyAndHoldReturn;
  final int totalTrades;
  final double winRate;

  BacktestSummary({
    required this.startingCapital,
    required this.endingCapital,
    required this.netProfit,
    required this.strategyReturn,
    required this.buyAndHoldReturn,
    required this.totalTrades,
    required this.winRate,
  });

  factory BacktestSummary.fromJson(Map<String, dynamic> json) {
    return BacktestSummary(
      startingCapital: (json['startingCapital'] as num?)?.toDouble() ?? 0.0,
      endingCapital: (json['endingCapital'] as num?)?.toDouble() ?? 0.0,
      netProfit: (json['netProfit'] as num?)?.toDouble() ?? 0.0,
      strategyReturn: (json['strategyReturn'] as num?)?.toDouble() ?? 0.0,
      buyAndHoldReturn: (json['buyAndHoldReturn'] as num?)?.toDouble() ?? 0.0,
      totalTrades: json['totalTrades'] ?? 0,
      winRate: (json['winRate'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class DivergenceInfo {
  final String type;
  final String msg;
  final int index;

  DivergenceInfo({
    required this.type,
    required this.msg,
    required this.index,
  });

  factory DivergenceInfo.fromJson(Map<String, dynamic> json) {
    return DivergenceInfo(
      type: json['type'] ?? '',
      msg: json['msg'] ?? '',
      index: json['index'] ?? 0,
    );
  }
}

class HistoryResponse {
  final bool success;
  final String symbol;
  final String name;
  final String interval;
  final int rsiPeriod;
  final double avgRsi;
  final double rsiStdDev;
  final double latestAtr;
  final double latestAtrPercent;
  final List<DivergenceInfo> divergences;
  final List<BacktestTrade> trades;
  final BacktestSummary backtestSummary;
  final List<HistoryDataPoint> dataPoints;

  HistoryResponse({
    required this.success,
    required this.symbol,
    required this.name,
    required this.interval,
    required this.rsiPeriod,
    required this.avgRsi,
    required this.rsiStdDev,
    required this.latestAtr,
    required this.latestAtrPercent,
    required this.divergences,
    required this.trades,
    required this.backtestSummary,
    required this.dataPoints,
  });

  factory HistoryResponse.fromJson(Map<String, dynamic> json) {
    var stats = json['stats'] ?? {};
    var backtest = json['backtest'] ?? {};
    var tradesList = backtest['trades'] as List? ?? [];
    var dataList = json['dataPoints'] as List? ?? [];
    var divList = json['divergences'] as List? ?? [];

    return HistoryResponse(
      success: json['success'] ?? false,
      symbol: json['symbol'] ?? '',
      name: json['name'] ?? '',
      interval: json['interval'] ?? '',
      rsiPeriod: json['rsiPeriod'] ?? 14,
      avgRsi: (stats['avgRsi'] as num?)?.toDouble() ?? 0.0,
      rsiStdDev: (stats['rsiStdDev'] as num?)?.toDouble() ?? 0.0,
      latestAtr: (stats['latestAtr'] as num?)?.toDouble() ?? 0.0,
      latestAtrPercent: (stats['latestAtrPercent'] as num?)?.toDouble() ?? 0.0,
      divergences: divList.map((i) => DivergenceInfo.fromJson(i)).toList(),
      trades: tradesList.map((i) => BacktestTrade.fromJson(i)).toList(),
      backtestSummary: BacktestSummary.fromJson(backtest['summary'] ?? {}),
      dataPoints: dataList.map((i) => HistoryDataPoint.fromJson(i)).toList(),
    );
  }
}
