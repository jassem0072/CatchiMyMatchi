import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Country with name and flag emoji.
class _Country {
  final String name;
  final String flag;
  const _Country(this.name, this.flag);
}

const _countries = [
  _Country('Afghanistan', '🇦🇫'),
  _Country('Albania', '🇦🇱'),
  _Country('Algeria', '🇩🇿'),
  _Country('Andorra', '🇦🇩'),
  _Country('Angola', '🇦🇴'),
  _Country('Antigua and Barbuda', '🇦🇬'),
  _Country('Argentina', '🇦🇷'),
  _Country('Armenia', '🇦🇲'),
  _Country('Australia', '🇦🇺'),
  _Country('Austria', '🇦🇹'),
  _Country('Azerbaijan', '🇦🇿'),
  _Country('Bahamas', '🇧🇸'),
  _Country('Bahrain', '🇧🇭'),
  _Country('Bangladesh', '🇧🇩'),
  _Country('Barbados', '🇧🇧'),
  _Country('Belarus', '🇧🇾'),
  _Country('Belgium', '🇧🇪'),
  _Country('Belize', '🇧🇿'),
  _Country('Benin', '🇧🇯'),
  _Country('Bhutan', '🇧🇹'),
  _Country('Bolivia', '🇧🇴'),
  _Country('Bosnia and Herzegovina', '🇧🇦'),
  _Country('Botswana', '🇧🇼'),
  _Country('Brazil', '🇧🇷'),
  _Country('Brunei', '🇧🇳'),
  _Country('Bulgaria', '🇧🇬'),
  _Country('Burkina Faso', '🇧🇫'),
  _Country('Burundi', '🇧🇮'),
  _Country('Cabo Verde', '🇨🇻'),
  _Country('Cambodia', '🇰🇭'),
  _Country('Cameroon', '🇨🇲'),
  _Country('Canada', '🇨🇦'),
  _Country('Central African Republic', '🇨🇫'),
  _Country('Chad', '🇹🇩'),
  _Country('Chile', '🇨🇱'),
  _Country('China', '🇨🇳'),
  _Country('Colombia', '🇨🇴'),
  _Country('Comoros', '🇰🇲'),
  _Country('Congo', '🇨🇬'),
  _Country('Costa Rica', '🇨🇷'),
  _Country('Croatia', '🇭🇷'),
  _Country('Cuba', '🇨🇺'),
  _Country('Cyprus', '🇨🇾'),
  _Country('Czech Republic', '🇨🇿'),
  _Country('Denmark', '🇩🇰'),
  _Country('Djibouti', '🇩🇯'),
  _Country('Dominica', '🇩🇲'),
  _Country('Dominican Republic', '🇩🇴'),
  _Country('DR Congo', '🇨🇩'),
  _Country('Ecuador', '🇪🇨'),
  _Country('Egypt', '🇪🇬'),
  _Country('El Salvador', '🇸🇻'),
  _Country('Equatorial Guinea', '🇬🇶'),
  _Country('Eritrea', '🇪🇷'),
  _Country('Estonia', '🇪🇪'),
  _Country('Eswatini', '🇸🇿'),
  _Country('Ethiopia', '🇪🇹'),
  _Country('Fiji', '🇫🇯'),
  _Country('Finland', '🇫🇮'),
  _Country('France', '🇫🇷'),
  _Country('Gabon', '🇬🇦'),
  _Country('Gambia', '🇬🇲'),
  _Country('Georgia', '🇬🇪'),
  _Country('Germany', '🇩🇪'),
  _Country('Ghana', '🇬🇭'),
  _Country('Greece', '🇬🇷'),
  _Country('Grenada', '🇬🇩'),
  _Country('Guatemala', '🇬🇹'),
  _Country('Guinea', '🇬🇳'),
  _Country('Guinea-Bissau', '🇬🇼'),
  _Country('Guyana', '🇬🇾'),
  _Country('Haiti', '🇭🇹'),
  _Country('Honduras', '🇭🇳'),
  _Country('Hungary', '🇭🇺'),
  _Country('Iceland', '🇮🇸'),
  _Country('India', '🇮🇳'),
  _Country('Indonesia', '🇮🇩'),
  _Country('Iran', '🇮🇷'),
  _Country('Iraq', '🇮🇶'),
  _Country('Ireland', '🇮🇪'),
  _Country('Israel', '🇮🇱'),
  _Country('Italy', '🇮🇹'),
  _Country('Ivory Coast', '🇨🇮'),
  _Country('Jamaica', '🇯🇲'),
  _Country('Japan', '🇯🇵'),
  _Country('Jordan', '🇯🇴'),
  _Country('Kazakhstan', '🇰🇿'),
  _Country('Kenya', '🇰🇪'),
  _Country('Kiribati', '🇰🇮'),
  _Country('Kosovo', '🇽🇰'),
  _Country('Kuwait', '🇰🇼'),
  _Country('Kyrgyzstan', '🇰🇬'),
  _Country('Laos', '🇱🇦'),
  _Country('Latvia', '🇱🇻'),
  _Country('Lebanon', '🇱🇧'),
  _Country('Lesotho', '🇱🇸'),
  _Country('Liberia', '🇱🇷'),
  _Country('Libya', '🇱🇾'),
  _Country('Liechtenstein', '🇱🇮'),
  _Country('Lithuania', '🇱🇹'),
  _Country('Luxembourg', '🇱🇺'),
  _Country('Madagascar', '🇲🇬'),
  _Country('Malawi', '🇲🇼'),
  _Country('Malaysia', '🇲🇾'),
  _Country('Maldives', '🇲🇻'),
  _Country('Mali', '🇲🇱'),
  _Country('Malta', '🇲🇹'),
  _Country('Marshall Islands', '🇲🇭'),
  _Country('Mauritania', '🇲🇷'),
  _Country('Mauritius', '🇲🇺'),
  _Country('Mexico', '🇲🇽'),
  _Country('Micronesia', '🇫🇲'),
  _Country('Moldova', '🇲🇩'),
  _Country('Monaco', '🇲🇨'),
  _Country('Mongolia', '🇲🇳'),
  _Country('Montenegro', '🇲🇪'),
  _Country('Morocco', '🇲🇦'),
  _Country('Mozambique', '🇲🇿'),
  _Country('Myanmar', '🇲🇲'),
  _Country('Namibia', '🇳🇦'),
  _Country('Nauru', '🇳🇷'),
  _Country('Nepal', '🇳🇵'),
  _Country('Netherlands', '🇳🇱'),
  _Country('New Zealand', '🇳🇿'),
  _Country('Nicaragua', '🇳🇮'),
  _Country('Niger', '🇳🇪'),
  _Country('Nigeria', '🇳🇬'),
  _Country('North Korea', '🇰🇵'),
  _Country('North Macedonia', '🇲🇰'),
  _Country('Norway', '🇳🇴'),
  _Country('Oman', '🇴🇲'),
  _Country('Pakistan', '🇵🇰'),
  _Country('Palau', '🇵🇼'),
  _Country('Palestine', '🇵🇸'),
  _Country('Panama', '🇵🇦'),
  _Country('Papua New Guinea', '🇵🇬'),
  _Country('Paraguay', '🇵🇾'),
  _Country('Peru', '🇵🇪'),
  _Country('Philippines', '🇵🇭'),
  _Country('Poland', '🇵🇱'),
  _Country('Portugal', '🇵🇹'),
  _Country('Qatar', '🇶🇦'),
  _Country('Romania', '🇷🇴'),
  _Country('Russia', '🇷🇺'),
  _Country('Rwanda', '🇷🇼'),
  _Country('Saint Kitts and Nevis', '🇰🇳'),
  _Country('Saint Lucia', '🇱🇨'),
  _Country('Saint Vincent', '🇻🇨'),
  _Country('Samoa', '🇼🇸'),
  _Country('San Marino', '🇸🇲'),
  _Country('Sao Tome and Principe', '🇸🇹'),
  _Country('Saudi Arabia', '🇸🇦'),
  _Country('Senegal', '🇸🇳'),
  _Country('Serbia', '🇷🇸'),
  _Country('Seychelles', '🇸🇨'),
  _Country('Sierra Leone', '🇸🇱'),
  _Country('Singapore', '🇸🇬'),
  _Country('Slovakia', '🇸🇰'),
  _Country('Slovenia', '🇸🇮'),
  _Country('Solomon Islands', '🇸🇧'),
  _Country('Somalia', '🇸🇴'),
  _Country('South Africa', '🇿🇦'),
  _Country('South Korea', '🇰🇷'),
  _Country('South Sudan', '🇸🇸'),
  _Country('Spain', '🇪🇸'),
  _Country('Sri Lanka', '🇱🇰'),
  _Country('Sudan', '🇸🇩'),
  _Country('Suriname', '🇸🇷'),
  _Country('Sweden', '🇸🇪'),
  _Country('Switzerland', '🇨🇭'),
  _Country('Syria', '🇸🇾'),
  _Country('Tajikistan', '🇹🇯'),
  _Country('Tanzania', '🇹🇿'),
  _Country('Thailand', '🇹🇭'),
  _Country('Timor-Leste', '🇹🇱'),
  _Country('Togo', '🇹🇬'),
  _Country('Tonga', '🇹🇴'),
  _Country('Trinidad and Tobago', '🇹🇹'),
  _Country('Tunisia', '🇹🇳'),
  _Country('Turkey', '🇹🇷'),
  _Country('Turkmenistan', '🇹🇲'),
  _Country('Tuvalu', '🇹🇻'),
  _Country('Uganda', '🇺🇬'),
  _Country('Ukraine', '🇺🇦'),
  _Country('United Arab Emirates', '🇦🇪'),
  _Country('United Kingdom', '🇬🇧'),
  _Country('United States', '🇺🇸'),
  _Country('Uruguay', '🇺🇾'),
  _Country('Uzbekistan', '🇺🇿'),
  _Country('Vanuatu', '🇻🇺'),
  _Country('Vatican City', '🇻🇦'),
  _Country('Venezuela', '🇻🇪'),
  _Country('Vietnam', '🇻🇳'),
  _Country('Yemen', '🇾🇪'),
  _Country('Zambia', '🇿🇲'),
  _Country('Zimbabwe', '🇿🇼'),
];

/// Convert a 2-letter ISO country code to its flag emoji.
String _isoToFlag(String code) {
  final upper = code.toUpperCase();
  if (upper.length != 2) return '';
  final a = upper.codeUnitAt(0) - 0x41 + 0x1F1E6;
  final b = upper.codeUnitAt(1) - 0x41 + 0x1F1E6;
  return String.fromCharCodes([a, b]);
}

/// Common name/abbreviation to ISO 2-letter code mapping.
const _nameToIso = <String, String>{
  'england': 'GB', 'scotland': 'GB', 'wales': 'GB',
  'usa': 'US', 'united states': 'US', 'korea republic': 'KR',
  'south korea': 'KR', 'north korea': 'KP', 'ivory coast': 'CI',
  "cote d'ivoire": 'CI', 'czech republic': 'CZ', 'czechia': 'CZ',
  'dr congo': 'CD', 'congo': 'CG', 'uae': 'AE',
  'bosnia': 'BA', 'bosnia and herzegovina': 'BA',
  'trinidad and tobago': 'TT', 'antigua and barbuda': 'AG',
  'saint kitts and nevis': 'KN', 'saint lucia': 'LC',
  'saint vincent and the grenadines': 'VC', 'sao tome and principe': 'ST',
  'cape verde': 'CV', 'east timor': 'TL', 'timor-leste': 'TL',
  'eswatini': 'SZ', 'swaziland': 'SZ',
};

/// Lookup flag for a country name, abbreviation, or ISO code.
String flagForCountry(String name) {
  final lower = name.trim().toLowerCase();
  if (lower.isEmpty) return '';

  // Exact match (case-insensitive) against known countries
  for (final c in _countries) {
    if (c.name.toLowerCase() == lower) return c.flag;
  }

  // Check common name/abbreviation mapping
  final iso = _nameToIso[lower];
  if (iso != null) return _isoToFlag(iso);

  // If input is a 2-letter code, convert directly to flag emoji
  if (lower.length == 2 && RegExp(r'^[a-z]{2}$').hasMatch(lower)) {
    return _isoToFlag(lower);
  }

  // Partial/contains match
  for (final c in _countries) {
    if (c.name.toLowerCase().contains(lower) || lower.contains(c.name.toLowerCase())) {
      return c.flag;
    }
  }
  return '🏳️';
}

/// Shows a searchable bottom-sheet country picker.
/// Returns the selected country name or null if cancelled.
Future<String?> showCountryPicker(BuildContext context, {String? current}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CountryPickerSheet(current: current),
  );
}

class _CountryPickerSheet extends StatefulWidget {
  const _CountryPickerSheet({this.current});
  final String? current;

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  final _searchCtrl = TextEditingController();
  List<_Country> _filtered = _countries;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearch);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearch() {
    final q = _searchCtrl.text.toLowerCase().trim();
    setState(() {
      if (q.isEmpty) {
        _filtered = _countries;
      } else {
        _filtered = _countries.where((c) => c.name.toLowerCase().contains(q)).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Container(
      height: mq.size.height * 0.7,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Select Country',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search country...',
                prefixIcon: const Icon(Icons.search, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: _filtered.length,
              itemBuilder: (ctx, i) {
                final c = _filtered[i];
                final selected = c.name == widget.current;
                return ListTile(
                  leading: Text(c.flag, style: const TextStyle(fontSize: 24)),
                  title: Text(
                    c.name,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w900 : FontWeight.w500,
                      color: selected ? AppColors.primary : null,
                    ),
                  ),
                  trailing: selected ? const Icon(Icons.check_circle, color: AppColors.primary, size: 20) : null,
                  onTap: () => Navigator.of(ctx).pop(c.name),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
