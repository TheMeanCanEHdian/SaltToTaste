/// The nutrient set the app reports — the old app's ~30-nutrient panel,
/// keyed by the same names the legacy UI used, mapped to USDA FDC nutrient
/// numbers, with current FDA Daily Values for the %DV column.
library;

/// One reported nutrient: identity, FDC mapping, unit, and Daily Value.
class NutrientDef {
  /// Builds a definition from its parts.
  const NutrientDef({
    required this.key,
    required this.label,
    required this.fdcNumbers,
    required this.unit,
    this.dailyValue,
  });

  /// Stable key (matches the old app's nutrient dictionary keys).
  final String key;

  /// Human label for the FDA panel.
  final String label;

  /// FDC nutrient `number`s that carry this value, in preference order —
  /// Foundation and SR Legacy foods occasionally publish under different
  /// numbers (e.g. Atwater energy variants).
  final List<String> fdcNumbers;

  /// Reporting unit (`g`, `mg`, `µg`, `kcal`) — FDC amounts for the mapped
  /// numbers are already in this unit.
  final String unit;

  /// FDA Daily Value in [unit] for adults, or null when no %DV is defined
  /// (total sugars, trans fat, mono/poly).
  final double? dailyValue;
}

/// Every reported nutrient in panel order.
const List<NutrientDef> nutrientDefs = [
  NutrientDef(
    key: 'energy',
    label: 'Calories',
    // 208 = Energy kcal (SR Legacy); 957/958 are the Atwater variants some
    // Foundation foods publish instead.
    fdcNumbers: ['208', '957', '958'],
    unit: 'kcal',
    dailyValue: 2000,
  ),
  NutrientDef(
    key: 'fat',
    label: 'Total Fat',
    fdcNumbers: ['204', '298'],
    unit: 'g',
    dailyValue: 78,
  ),
  NutrientDef(
    key: 'saturated',
    label: 'Saturated Fat',
    fdcNumbers: ['606'],
    unit: 'g',
    dailyValue: 20,
  ),
  NutrientDef(
    key: 'trans',
    label: 'Trans Fat',
    fdcNumbers: ['605'],
    unit: 'g',
  ),
  NutrientDef(
    key: 'monounsaturated',
    label: 'Monounsaturated Fat',
    fdcNumbers: ['645'],
    unit: 'g',
  ),
  NutrientDef(
    key: 'polyunsaturated',
    label: 'Polyunsaturated Fat',
    fdcNumbers: ['646'],
    unit: 'g',
  ),
  NutrientDef(
    key: 'cholesterol',
    label: 'Cholesterol',
    fdcNumbers: ['601'],
    unit: 'mg',
    dailyValue: 300,
  ),
  NutrientDef(
    key: 'sodium',
    label: 'Sodium',
    fdcNumbers: ['307'],
    unit: 'mg',
    dailyValue: 2300,
  ),
  NutrientDef(
    key: 'carbs',
    label: 'Total Carbohydrate',
    fdcNumbers: ['205'],
    unit: 'g',
    dailyValue: 275,
  ),
  NutrientDef(
    key: 'fiber',
    label: 'Dietary Fiber',
    fdcNumbers: ['291'],
    unit: 'g',
    dailyValue: 28,
  ),
  NutrientDef(
    key: 'sugars',
    label: 'Total Sugars',
    fdcNumbers: ['269'],
    unit: 'g',
  ),
  NutrientDef(
    key: 'sugars_added',
    label: 'Added Sugars',
    fdcNumbers: ['539'],
    unit: 'g',
    dailyValue: 50,
  ),
  NutrientDef(
    key: 'protein',
    label: 'Protein',
    fdcNumbers: ['203'],
    unit: 'g',
    dailyValue: 50,
  ),
  NutrientDef(
    key: 'vitamin_d',
    label: 'Vitamin D',
    fdcNumbers: ['328'],
    unit: 'µg',
    dailyValue: 20,
  ),
  NutrientDef(
    key: 'calcium',
    label: 'Calcium',
    fdcNumbers: ['301'],
    unit: 'mg',
    dailyValue: 1300,
  ),
  NutrientDef(
    key: 'iron',
    label: 'Iron',
    fdcNumbers: ['303'],
    unit: 'mg',
    dailyValue: 18,
  ),
  NutrientDef(
    key: 'potassium',
    label: 'Potassium',
    fdcNumbers: ['306'],
    unit: 'mg',
    dailyValue: 4700,
  ),
  NutrientDef(
    key: 'vitamin_a',
    label: 'Vitamin A',
    fdcNumbers: ['320'],
    unit: 'µg',
    dailyValue: 900,
  ),
  NutrientDef(
    key: 'vitamin_c',
    label: 'Vitamin C',
    fdcNumbers: ['401'],
    unit: 'mg',
    dailyValue: 90,
  ),
  NutrientDef(
    key: 'vitamin_e',
    label: 'Vitamin E',
    fdcNumbers: ['323'],
    unit: 'mg',
    dailyValue: 15,
  ),
  NutrientDef(
    key: 'vitamin_k',
    label: 'Vitamin K',
    fdcNumbers: ['430'],
    unit: 'µg',
    dailyValue: 120,
  ),
  NutrientDef(
    key: 'thiamin_b1',
    label: 'Thiamin (B1)',
    fdcNumbers: ['404'],
    unit: 'mg',
    dailyValue: 1.2,
  ),
  NutrientDef(
    key: 'riboflavin_b2',
    label: 'Riboflavin (B2)',
    fdcNumbers: ['405'],
    unit: 'mg',
    dailyValue: 1.3,
  ),
  NutrientDef(
    key: 'niacin_b3',
    label: 'Niacin (B3)',
    fdcNumbers: ['406'],
    unit: 'mg',
    dailyValue: 16,
  ),
  NutrientDef(
    key: 'vitamin_b6',
    label: 'Vitamin B6',
    fdcNumbers: ['415'],
    unit: 'mg',
    dailyValue: 1.7,
  ),
  NutrientDef(
    key: 'folate_equivalent',
    label: 'Folate (DFE)',
    fdcNumbers: ['435'],
    unit: 'µg',
    dailyValue: 400,
  ),
  NutrientDef(
    key: 'folate_food',
    label: 'Folate (food)',
    fdcNumbers: ['432'],
    unit: 'µg',
  ),
  NutrientDef(
    key: 'vitamin_b12',
    label: 'Vitamin B12',
    fdcNumbers: ['418'],
    unit: 'µg',
    dailyValue: 2.4,
  ),
  NutrientDef(
    key: 'magnesium',
    label: 'Magnesium',
    fdcNumbers: ['304'],
    unit: 'mg',
    dailyValue: 420,
  ),
  NutrientDef(
    key: 'phosphorus',
    label: 'Phosphorus',
    fdcNumbers: ['305'],
    unit: 'mg',
    dailyValue: 1250,
  ),
];

/// Nutrient defs by every FDC number they map from.
final Map<String, NutrientDef> nutrientByFdcNumber = {
  for (final def in nutrientDefs)
    for (final number in def.fdcNumbers) number: def,
};
