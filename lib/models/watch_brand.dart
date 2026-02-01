/// Watch brand for auctions: id + display name. Source: Firestore watchBrands collection or default list.

class WatchBrand {
  final String id;
  final String name;
  final int order;

  const WatchBrand({
    required this.id,
    required this.name,
    this.order = 0,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'order': order,
      };

  static WatchBrand fromMap(Map<String, dynamic> m) => WatchBrand(
        id: m['id'] as String? ?? '',
        name: m['name'] as String? ?? m['id'] as String? ?? '',
        order: (m['order'] as num?)?.toInt() ?? 0,
      );
}

/// Default watch brands (flat list, no tiers). Used when Firestore watchBrands is empty.
/// Includes "Other" as selectable option. 50+ luxury watch brands.
const List<WatchBrand> defaultWatchBrands = [
  WatchBrand(id: 'rolex', name: 'Rolex', order: 1),
  WatchBrand(id: 'patek_philippe', name: 'Patek Philippe', order: 2),
  WatchBrand(id: 'audemars_piguet', name: 'Audemars Piguet', order: 3),
  WatchBrand(id: 'omega', name: 'Omega', order: 4),
  WatchBrand(id: 'cartier', name: 'Cartier', order: 5),
  WatchBrand(id: 'tag_heuer', name: 'Tag Heuer', order: 6),
  WatchBrand(id: 'breitling', name: 'Breitling', order: 7),
  WatchBrand(id: 'iwc', name: 'IWC Schaffhausen', order: 8),
  WatchBrand(id: 'panerai', name: 'Panerai', order: 9),
  WatchBrand(id: 'jaeger_lecoutre', name: 'Jaeger-LeCoultre', order: 10),
  WatchBrand(id: 'vacheron_constantin', name: 'Vacheron Constantin', order: 11),
  WatchBrand(id: 'tudor', name: 'Tudor', order: 12),
  WatchBrand(id: 'hublot', name: 'Hublot', order: 13),
  WatchBrand(id: 'richard_mille', name: 'Richard Mille', order: 14),
  WatchBrand(id: 'a_lange_sohne', name: 'A. Lange & Söhne', order: 15),
  WatchBrand(id: 'blancpain', name: 'Blancpain', order: 16),
  WatchBrand(id: 'breguet', name: 'Breguet', order: 17),
  WatchBrand(id: 'chopard', name: 'Chopard', order: 18),
  WatchBrand(id: 'girard_perregaux', name: 'Girard-Perregaux', order: 19),
  WatchBrand(id: 'piaget', name: 'Piaget', order: 20),
  WatchBrand(id: 'zenith', name: 'Zenith', order: 21),
  WatchBrand(id: 'bulgari', name: 'Bulgari', order: 22),
  WatchBrand(id: 'hermes', name: 'Hermès', order: 23),
  WatchBrand(id: 'louis_vuitton', name: 'Louis Vuitton', order: 24),
  WatchBrand(id: 'chanel', name: 'Chanel', order: 25),
  WatchBrand(id: 'montblanc', name: 'Montblanc', order: 26),
  WatchBrand(id: 'grand_seiko', name: 'Grand Seiko', order: 27),
  WatchBrand(id: 'seiko', name: 'Seiko', order: 28),
  WatchBrand(id: 'citizen', name: 'Citizen', order: 29),
  WatchBrand(id: 'casio', name: 'Casio', order: 30),
  WatchBrand(id: 'tissot', name: 'Tissot', order: 31),
  WatchBrand(id: 'longines', name: 'Longines', order: 32),
  WatchBrand(id: 'rado', name: 'Rado', order: 33),
  WatchBrand(id: 'mido', name: 'Mido', order: 34),
  WatchBrand(id: 'hamilton', name: 'Hamilton', order: 35),
  WatchBrand(id: 'oris', name: 'Oris', order: 36),
  WatchBrand(id: 'nomos', name: 'Nomos Glashütte', order: 37),
  WatchBrand(id: 'glashutte_original', name: 'Glashütte Original', order: 38),
  WatchBrand(id: 'baume_mercier', name: 'Baume & Mercier', order: 39),
  WatchBrand(id: 'bell_ross', name: 'Bell & Ross', order: 40),
  WatchBrand(id: 'bremont', name: 'Bremont', order: 41),
  WatchBrand(id: 'maurice_lacroix', name: 'Maurice Lacroix', order: 42),
  WatchBrand(id: 'frederique_constant', name: 'Frederique Constant', order: 43),
  WatchBrand(id: 'jaquet_droz', name: 'Jaquet Droz', order: 44),
  WatchBrand(id: 'ulysse_nardin', name: 'Ulysse Nardin', order: 45),
  WatchBrand(id: 'certina', name: 'Certina', order: 46),
  WatchBrand(id: 'sinn', name: 'Sinn', order: 47),
  WatchBrand(id: 'junghans', name: 'Junghans', order: 48),
  WatchBrand(id: 'glycine', name: 'Glycine', order: 49),
  WatchBrand(id: 'doxa', name: 'Doxa', order: 50),
  WatchBrand(id: 'gucci', name: 'Gucci', order: 51),
  WatchBrand(id: 'van_cleef_arpels', name: 'Van Cleef & Arpels', order: 52),
  WatchBrand(id: 'ebel', name: 'Ebel', order: 53),
  WatchBrand(id: 'corum', name: 'Corum', order: 54),
  WatchBrand(id: 'other', name: 'Other', order: 999),
];

/// Resolve display name from auction data: prefer brand (legacy), else look up brandId in default list.
String effectiveBrandDisplay(Map<String, dynamic> data) {
  final brand = data['brand'] as String?;
  if (brand != null && brand.trim().isNotEmpty) return brand.trim();
  final brandId = data['brandId'] as String?;
  if (brandId == null || brandId.isEmpty) return '—';
  for (final b in defaultWatchBrands) {
    if (b.id == brandId) return b.name;
  }
  return brandId;
}
