import 'dart:math';

/// 午餐吃什麼's three kinds of lunch, with the same dishes as on iOS.
enum LunchCategory {
  noodles('麵', '🍜', '麵食、湯麵、乾麵', [
    '義大利麵',
    '牛肉麵',
    '拉麵',
    '烏龍麵',
    '炸醬麵',
    '麻醬麵',
    '鍋燒意麵',
    '陽春麵',
    '涼麵',
    '擔仔麵',
    '米粉湯',
    '越南河粉',
  ]),
  rice('飯', '🍚', '便當、丼飯、燴飯', [
    '滷肉飯',
    '雞腿便當',
    '排骨飯',
    '咖哩飯',
    '炒飯',
    '丼飯',
    '燴飯',
    '雞肉飯',
    '石鍋拌飯',
    '自助餐',
    '壽司',
    '海南雞飯',
  ]),
  other('其他', '🥪', '早午餐、輕食、點心', [
    '早午餐',
    '蛋餅',
    '三明治',
    '漢堡',
    '潛艇堡',
    '貝果',
    '蔥抓餅',
    '水餃',
    '鍋貼',
    '沙拉',
    '披薩',
    '墨西哥捲餅',
  ]);

  const LunchCategory(this.title, this.emoji, this.detail, this.dishes);
  final String title, emoji, detail;
  final List<String> dishes;

  /// What the wheel shows while it spins over the categories.
  String get face => '$emoji $title';
}

/// Where to look for a shop. The centre is fixed, as on iOS, so nothing
/// asks for the student's location; the map app does the searching.
enum LunchArea {
  campus('宜大周邊', '國立宜蘭大學', 24.7461, 121.7475),
  station('宜蘭火車站', '宜蘭火車站', 24.7547, 121.7586);

  const LunchArea(this.title, this.landmark, this.latitude, this.longitude);
  final String title;

  /// Added to the web search, which has no centre of its own.
  final String landmark;
  final double latitude, longitude;

  /// A map app's search for [dish] around the centre.
  Uri mapSearch(String dish) =>
      Uri.parse('geo:$latitude,$longitude?q=${Uri.encodeQueryComponent(dish)}');

  /// The same search on Google Maps' site, for phones without a map app.
  Uri webSearch(String dish) => Uri.https('www.google.com', '/maps/search/', {
    'api': '1',
    'query': '$dish $landmark',
  });
}

/// Picks one of [options], never [previous] while there is anything else,
/// so 重抽 always changes the answer.
T? pickLunch<T>(List<T> options, {T? avoiding, Random? random}) {
  final rest = [
    for (final o in options)
      if (o != avoiding) o,
  ];
  final from = rest.isEmpty ? options : rest;
  if (from.isEmpty) return null;
  return from[(random ?? Random()).nextInt(from.length)];
}

/// The wheel slows down as it settles, one gap a frame.
const lunchShuffleDelays = [50, 55, 60, 70, 80, 95, 115, 140, 170, 210];
