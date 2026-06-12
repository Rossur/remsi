import 'dart:math';

class OptimizationResult {
  final int rsiPeriod;
  final int overbought;
  final int oversold;
  final double netProfit;
  final double strategyReturn;
  final double winRate;
  final int totalTrades;
  final double robustnessScore;

  OptimizationResult({
    required this.rsiPeriod,
    required this.overbought,
    required this.oversold,
    required this.netProfit,
    required this.strategyReturn,
    required this.winRate,
    required this.totalTrades,
    required this.robustnessScore,
  });
}

class IndicatorCalculator {
  // Wilder's RSI calculation in Dart
  static List<double?> calculateWildersRSI(List<double> closes, int period) {
    if (closes.length <= period) {
      return List<double?>.filled(closes.length, null);
    }

    final List<double?> rsiHistory = List<double?>.filled(closes.length, null);
    final List<double> changes = [];
    for (int i = 1; i < closes.length; i++) {
      changes.add(closes[i] - closes[i - 1]);
    }

    final List<double> gains = changes.map((val) => val > 0 ? val : 0.0).toList();
    final List<double> losses = changes.map((val) => val < 0 ? -val : 0.0).toList();

    double avgGain = gains.sublist(0, period).reduce((a, b) => a + b) / period;
    double avgLoss = losses.sublist(0, period).reduce((a, b) => a + b) / period;

    if (avgLoss == 0) {
      rsiHistory[period] = 100.0;
    } else {
      double rs = avgGain / avgLoss;
      rsiHistory[period] = 100.0 - (100.0 / (1.0 + rs));
    }

    for (int i = period; i < changes.length; i++) {
      avgGain = (avgGain * (period - 1) + gains[i]) / period;
      avgLoss = (avgLoss * (period - 1) + losses[i]) / period;

      if (avgLoss == 0) {
        rsiHistory[i + 1] = 100.0;
      } else {
        double rs = avgGain / avgLoss;
        rsiHistory[i + 1] = 100.0 - (100.0 / (1.0 + rs));
      }
    }

    return rsiHistory;
  }
  
  // EMA calculation in Dart
  static List<double?> calculateEMA(List<double> closes, int period) {
    final List<double?> ema = List<double?>.filled(closes.length, null);
    if (closes.length < period) return ema;

    final double multiplier = 2.0 / (period + 1);
    double sum = 0.0;
    for (int i = 0; i < period; i++) {
      sum += closes[i];
    }
    double currentEma = sum / period;
    ema[period - 1] = currentEma;

    for (int i = period; i < closes.length; i++) {
      currentEma = (closes[i] - currentEma) * multiplier + currentEma;
      ema[i] = currentEma;
    }

    return ema;
  }

  // MACD calculation in Dart
  static Map<String, List<double?>> calculateMACD(List<double> closes) {
    final ema12 = calculateEMA(closes, 12);
    final ema26 = calculateEMA(closes, 26);

    final List<double?> macdLine = List<double?>.filled(closes.length, null);
    for (int i = 0; i < closes.length; i++) {
      if (ema12[i] != null && ema26[i] != null) {
        macdLine[i] = ema12[i]! - ema26[i]!;
      }
    }

    final macdSignal = calculateEMAForNullableList(macdLine, 9);
    final List<double?> macdHist = List<double?>.filled(closes.length, null);
    for (int i = 0; i < closes.length; i++) {
      if (macdLine[i] != null && macdSignal[i] != null) {
        macdHist[i] = macdLine[i]! - macdSignal[i]!;
      }
    }

    return {
      'macdLine': macdLine,
      'macdSignal': macdSignal,
      'macdHist': macdHist,
    };
  }

  static List<double?> calculateEMAForNullableList(List<double?> arr, int period) {
    final List<double?> ema = List<double?>.filled(arr.length, null);
    int firstValidIndex = 0;
    while (firstValidIndex < arr.length && arr[firstValidIndex] == null) {
      firstValidIndex++;
    }

    if (arr.length - firstValidIndex < period) return ema;

    final double multiplier = 2.0 / (period + 1);
    double sum = 0.0;
    for (int i = 0; i < period; i++) {
      sum += arr[firstValidIndex + i]!;
    }
    double currentEma = sum / period;
    ema[firstValidIndex + period - 1] = currentEma;

    for (int i = firstValidIndex + period; i < arr.length; i++) {
      if (arr[i] != null) {
        currentEma = (arr[i]! - currentEma) * multiplier + currentEma;
        ema[i] = currentEma;
      }
    }

    return ema;
  }

  // Bollinger Bands
  static Map<String, List<double?>> calculateBollingerBands(List<double> closes, int period, double numStdDev) {
    final List<double?> middleBand = List<double?>.filled(closes.length, null);
    final List<double?> upperBand = List<double?>.filled(closes.length, null);
    final List<double?> lowerBand = List<double?>.filled(closes.length, null);

    if (closes.length < period) {
      return {'middleBand': middleBand, 'upperBand': upperBand, 'lowerBand': lowerBand};
    }

    for (int i = period - 1; i < closes.length; i++) {
      final slice = closes.sublist(i - period + 1, i + 1);
      final sum = slice.reduce((a, b) => a + b);
      final mean = sum / period;
      middleBand[i] = mean;

      final variance = slice.map((x) => pow(x - mean, 2)).reduce((a, b) => a + b) / period;
      final stdDev = sqrt(variance);

      upperBand[i] = mean + numStdDev * stdDev;
      lowerBand[i] = mean - numStdDev * stdDev;
    }

    return {'middleBand': middleBand, 'upperBand': upperBand, 'lowerBand': lowerBand};
  }
}

class Backtester {
  static double runBacktest(
    List<double> closes,
    List<double?> rsi,
    List<double?> ema,
    List<double?> bbUpper,
    List<double?> bbLower,
    List<double?> macdHist,
    int overbought,
    int oversold,
    {double startingCapital = 10000.0}
  ) {
    double capital = startingCapital;
    Map<String, dynamic>? position;
    
    for (int i = 0; i < closes.length; i++) {
      final double closeVal = closes[i];
      final double? rsiVal = rsi[i];
      final double? bbLowerVal = bbLower[i];
      final double? bbUpperVal = bbUpper[i];
      final double? macdHistVal = macdHist[i];
      final double? emaVal = ema[i];

      String rsiSignal = 'HOLD';
      if (rsiVal != null) {
        if (rsiVal <= oversold) rsiSignal = 'BUY';
        else if (rsiVal >= overbought) rsiSignal = 'SELL';
      }

      String bbSignal = 'HOLD';
      if (bbLowerVal != null && bbUpperVal != null) {
        if (closeVal <= bbLowerVal) bbSignal = 'BUY';
        else if (closeVal >= bbUpperVal) bbSignal = 'SELL';
      }

      String emaSignal = 'HOLD';
      if (emaVal != null) {
        if (closeVal > emaVal) emaSignal = 'BUY';
        else if (closeVal < emaVal) emaSignal = 'SELL';
      }

      bool isOversold = (rsiSignal == 'BUY' || bbSignal == 'BUY');
      bool isOverbought = (rsiSignal == 'SELL' || bbSignal == 'SELL');

      String signal = 'HOLD';
      if (isOversold && emaSignal == 'BUY') {
        signal = 'BUY';
      } else if (isOverbought || (position != null && emaSignal == 'SELL')) {
        signal = 'SELL';
      }

      if (position == null) {
        if (signal == 'BUY') {
          double shares = capital / closeVal;
          position = {
            'entryPrice': closeVal,
            'shares': shares,
          };
        }
      } else {
        if (signal == 'SELL') {
          double entryPrice = position['entryPrice'];
          double shares = position['shares'];
          double grossReturn = closeVal * shares;
          capital = grossReturn;
          position = null;
        }
      }
    }

    if (position != null) {
      double entryPrice = position['entryPrice'];
      double shares = position['shares'];
      double grossReturn = closes.last * shares;
      capital = grossReturn;
    }

    return ((capital - startingCapital) / startingCapital) * 100.0;
  }
}

class OptimizerEngine {
  static List<OptimizationResult> runOptimization({
    required List<double> closes,
    required bool expandedMode,
  }) {
    if (closes.length < 30) return [];

    // 1. Calculate static indicators
    final ema = IndicatorCalculator.calculateEMA(closes, 9);
    final macd = IndicatorCalculator.calculateMACD(closes);
    final macdHist = macd['macdHist']!;
    final bb = IndicatorCalculator.calculateBollingerBands(closes, 20, 2);
    final bbUpper = bb['upperBand']!;
    final bbLower = bb['lowerBand']!;

    // 2. Define search space
    final List<int> rsiPeriods = [];
    final List<int> overboughts = [];
    final List<int> oversolds = [];

    if (expandedMode) {
      // Expanded Robustness Scan (Wider search range, step 2/3)
      for (int p = 7; p <= 25; p += 2) rsiPeriods.add(p);
      for (int ob = 60; ob <= 80; ob += 3) overboughts.add(ob);
      for (int os = 15; os <= 40; os += 3) oversolds.add(os);
    } else {
      // Fast Scan (Constrained, step 2)
      for (int p = 10; p <= 18; p += 2) rsiPeriods.add(p);
      for (int ob = 65; ob <= 75; ob += 2) overboughts.add(ob);
      for (int os = 25; os <= 35; os += 2) oversolds.add(os);
    }

    // Cache computed RSI arrays
    final Map<int, List<double?>> rsiCache = {};
    for (final p in rsiPeriods) {
      rsiCache[p] = IndicatorCalculator.calculateWildersRSI(closes, p);
    }

    final List<OptimizationResult> candidates = [];

    // 3. Grid search
    for (final period in rsiPeriods) {
      final rsi = rsiCache[period]!;
      for (final ob in overboughts) {
        for (final os in oversolds) {
          final eval = evaluatePerformance(closes, rsi, ema, bbUpper, bbLower, macdHist, ob, os);
          
          // Calculate robustness (neighbor return average)
          double neighborSum = 0.0;
          int neighborCount = 0;
          
          final List<int> pNeighbors = [period - 1, period, period + 1];
          final List<int> obNeighbors = [ob - 5, ob, ob + 5];
          final List<int> osNeighbors = [os - 5, os, os + 5];
          
          for (final np in pNeighbors) {
            // Compute neighbor RSI if not in cache
            if (!rsiCache.containsKey(np)) {
              rsiCache[np] = IndicatorCalculator.calculateWildersRSI(closes, np);
            }
            final nRsi = rsiCache[np]!;
            for (final nob in obNeighbors) {
              for (final nos in osNeighbors) {
                if (nob > nos) {
                  final nReturn = Backtester.runBacktest(closes, nRsi, ema, bbUpper, bbLower, macdHist, nob, nos);
                  neighborSum += nReturn;
                  neighborCount++;
                }
              }
            }
          }
          final double robustness = neighborCount > 0 ? (neighborSum / neighborCount) : eval.strategyReturn;

          candidates.add(OptimizationResult(
            rsiPeriod: period,
            overbought: ob,
            oversold: os,
            netProfit: eval.netProfit,
            strategyReturn: eval.strategyReturn,
            winRate: eval.winRate,
            totalTrades: eval.totalTrades,
            robustnessScore: robustness,
          ));
        }
      }
    }

    // Sort options
    if (expandedMode) {
      // Sort by robustness score to favor neighborhoods of stable returns
      candidates.sort((a, b) => b.robustnessScore.compareTo(a.robustnessScore));
    } else {
      // Sort directly by strategy performance
      candidates.sort((a, b) => b.strategyReturn.compareTo(a.strategyReturn));
    }

    return candidates;
  }

  static PerformanceEval evaluatePerformance(
    List<double> closes,
    List<double?> rsi,
    List<double?> ema,
    List<double?> bbUpper,
    List<double?> bbLower,
    List<double?> macdHist,
    int overbought,
    int oversold,
  ) {
    double capital = 10000.0;
    Map<String, dynamic>? position;
    int totalTrades = 0;
    int winningTrades = 0;

    for (int i = 0; i < closes.length; i++) {
      final double closeVal = closes[i];
      final double? rsiVal = rsi[i];
      final double? bbLowerVal = bbLower[i];
      final double? bbUpperVal = bbUpper[i];
      final double? macdHistVal = macdHist[i];
      final double? emaVal = ema[i];

      String rsiSignal = 'HOLD';
      if (rsiVal != null) {
        if (rsiVal <= oversold) rsiSignal = 'BUY';
        else if (rsiVal >= overbought) rsiSignal = 'SELL';
      }

      String bbSignal = 'HOLD';
      if (bbLowerVal != null && bbUpperVal != null) {
        if (closeVal <= bbLowerVal) bbSignal = 'BUY';
        else if (closeVal >= bbUpperVal) bbSignal = 'SELL';
      }

      String emaSignal = 'HOLD';
      if (emaVal != null) {
        if (closeVal > emaVal) emaSignal = 'BUY';
        else if (closeVal < emaVal) emaSignal = 'SELL';
      }

      bool isOversold = (rsiSignal == 'BUY' || bbSignal == 'BUY');
      bool isOverbought = (rsiSignal == 'SELL' || bbSignal == 'SELL');

      String signal = 'HOLD';
      if (isOversold && emaSignal == 'BUY') {
        signal = 'BUY';
      } else if (isOverbought || (position != null && emaSignal == 'SELL')) {
        signal = 'SELL';
      }

      if (position == null) {
        if (signal == 'BUY') {
          double shares = capital / closeVal;
          position = {
            'entryPrice': closeVal,
            'shares': shares,
          };
        }
      } else {
        if (signal == 'SELL') {
          double entryPrice = position['entryPrice'];
          double shares = position['shares'];
          double grossReturn = closeVal * shares;
          double profit = grossReturn - (shares * entryPrice);
          capital = grossReturn;
          totalTrades++;
          if (profit > 0) winningTrades++;
          position = null;
        }
      }
    }

    if (position != null) {
      double entryPrice = position['entryPrice'];
      double shares = position['shares'];
      double grossReturn = closes.last * shares;
      double profit = grossReturn - (shares * entryPrice);
      capital = grossReturn;
      totalTrades++;
      if (profit > 0) winningTrades++;
    }

    double strategyReturn = ((capital - 10000.0) / 10000.0) * 100.0;
    double winRate = totalTrades > 0 ? (winningTrades / totalTrades) * 100.0 : 0.0;

    return PerformanceEval(
      netProfit: capital - 10000.0,
      strategyReturn: strategyReturn,
      winRate: winRate,
      totalTrades: totalTrades,
    );
  }
}

class PerformanceEval {
  final double netProfit;
  final double strategyReturn;
  final double winRate;
  final int totalTrades;

  PerformanceEval({
    required this.netProfit,
    required this.strategyReturn,
    required this.winRate,
    required this.totalTrades,
  });
}
