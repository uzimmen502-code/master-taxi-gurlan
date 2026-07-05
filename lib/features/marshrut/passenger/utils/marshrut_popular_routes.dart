import '../models/marshrut_route_pair.dart';

/// Mashhur marshrut yo'nalishlari (statik ro'yxat, backend kerak emas).
class MarshrutPopularRoutes {
  MarshrutPopularRoutes._();

  static const List<MarshrutRoutePair> routes = [
    MarshrutRoutePair(from: 'Гурлан бозори', to: 'Урганч'),
    MarshrutRoutePair(from: 'Гурлан автовокзали', to: 'Хива'),
    MarshrutRoutePair(from: 'Обод МФЙ', to: 'Гурлан бозори'),
    MarshrutRoutePair(from: 'Гурлан бозори', to: 'Нукус'),
  ];
}
