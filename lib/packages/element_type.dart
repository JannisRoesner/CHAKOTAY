/// Elementtyp eines Ablaufschritts (CHAPEL: `ElementTypeDto`, Tabelle
/// `element_types`). Das Manifest enthält nur den Schlüssel (`kind`); Name
/// und Farbe kommen von `GET /api/element-types` und werden beim Download
/// mit dem Paket gespeichert, damit sie offline verfügbar sind.
library;

/// Schlüssel der beiden CHAPEL-Grundtypen.
const String songSlotKind = 'songSlot';
const String liturgyKind = 'liturgy';

/// Darstellungston – abgeleitet aus der CHAPEL-Farbe des Typs.
enum ElementTone {
  /// CHAPEL `primary` (Akzentfarbe, z. B. Lied).
  accent,

  /// CHAPEL `secondary` (Liturgiefarbe).
  liturgy,

  /// Alle übrigen Farben.
  neutral,
}

class ElementType {
  const ElementType({
    required this.key,
    required this.label,
    required this.color,
    this.fixed = false,
  });

  final String key;
  final String label;

  /// CHAPEL-Farbname (`primary`, `secondary`, `neutral`, `info`, …).
  final String color;

  /// `true` = Track steht fest in der Vorlage (wie Liturgie).
  final bool fixed;

  ElementTone get tone => switch (color) {
    'primary' => ElementTone.accent,
    'secondary' => ElementTone.liturgy,
    _ => ElementTone.neutral,
  };

  /// Toleranter Parser; liefert `null` bei unbrauchbaren Einträgen.
  static ElementType? tryParse(Object? json) {
    if (json is! Map) return null;
    final key = json['key'];
    final label = json['label'];
    if (key is! String || key.isEmpty || label is! String || label.isEmpty) {
      return null;
    }
    final color = json['color'];
    return ElementType(
      key: key,
      label: label,
      color: color is String ? color : 'neutral',
      fixed: json['fixed'] == true,
    );
  }

  Map<String, Object?> toJson() => {
    'key': key,
    'label': label,
    'color': color,
    'fixed': fixed,
  };
}

/// Vorgaben von CHAPEL (`BUILTIN_ELEMENT_TYPES`).
const Map<String, ElementType> builtinElementTypes = {
  songSlotKind: ElementType(key: songSlotKind, label: 'Lied', color: 'primary'),
  liturgyKind: ElementType(
    key: liturgyKind,
    label: 'Liturgie',
    color: 'secondary',
    fixed: true,
  ),
  'voluntary': ElementType(
    key: 'voluntary',
    label: 'Ein-/Ausgang',
    color: 'neutral',
  ),
  'communion': ElementType(
    key: 'communion',
    label: 'Abendmahl-Musik',
    color: 'neutral',
  ),
};

/// Typ zum Schlüssel – wie CHAPEL `resolveElementType`: Unbekanntes
/// verhält sich wie ein Lied.
ElementType resolveElementType(Map<String, ElementType> known, String key) =>
    known[key] ??
    builtinElementTypes[key] ??
    known[songSlotKind] ??
    builtinElementTypes[songSlotKind]!;
