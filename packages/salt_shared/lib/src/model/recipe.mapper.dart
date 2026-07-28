// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'recipe.dart';

class MeasureMapper extends EnumMapper<Measure> {
  MeasureMapper._();

  static MeasureMapper? _instance;
  static MeasureMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = MeasureMapper._());
    }
    return _instance!;
  }

  static Measure fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  Measure decode(dynamic value) {
    switch (value) {
      case r'volume':
        return Measure.volume;
      case r'weight':
        return Measure.weight;
      case r'count':
        return Measure.count;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(Measure self) {
    switch (self) {
      case Measure.volume:
        return r'volume';
      case Measure.weight:
        return r'weight';
      case Measure.count:
        return r'count';
    }
  }
}

extension MeasureMapperExtension on Measure {
  String toValue() {
    MeasureMapper.ensureInitialized();
    return MapperContainer.globals.toValue<Measure>(this) as String;
  }
}

class AmountMapper extends ClassMapperBase<Amount> {
  AmountMapper._();

  static AmountMapper? _instance;
  static AmountMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = AmountMapper._());
      MeasureMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'Amount';

  static Measure _$measure(Amount v) => v.measure;
  static const Field<Amount, Measure> _f$measure = Field('measure', _$measure);
  static String _$quantity(Amount v) => v.quantity;
  static const Field<Amount, String> _f$quantity = Field(
    'quantity',
    _$quantity,
  );
  static String? _$unit(Amount v) => v.unit;
  static const Field<Amount, String> _f$unit = Field('unit', _$unit, opt: true);
  static bool _$approximate(Amount v) => v.approximate;
  static const Field<Amount, bool> _f$approximate = Field(
    'approximate',
    _$approximate,
    opt: true,
    def: false,
  );
  static bool _$primary(Amount v) => v.primary;
  static const Field<Amount, bool> _f$primary = Field(
    'primary',
    _$primary,
    opt: true,
    def: false,
  );

  @override
  final MappableFields<Amount> fields = const {
    #measure: _f$measure,
    #quantity: _f$quantity,
    #unit: _f$unit,
    #approximate: _f$approximate,
    #primary: _f$primary,
  };

  static Amount _instantiate(DecodingData data) {
    return Amount(
      measure: data.dec(_f$measure),
      quantity: data.dec(_f$quantity),
      unit: data.dec(_f$unit),
      approximate: data.dec(_f$approximate),
      primary: data.dec(_f$primary),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static Amount fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<Amount>(map);
  }

  static Amount fromJson(String json) {
    return ensureInitialized().decodeJson<Amount>(json);
  }
}

mixin AmountMappable {
  String toJson() {
    return AmountMapper.ensureInitialized().encodeJson<Amount>(this as Amount);
  }

  Map<String, dynamic> toMap() {
    return AmountMapper.ensureInitialized().encodeMap<Amount>(this as Amount);
  }

  AmountCopyWith<Amount, Amount, Amount> get copyWith =>
      _AmountCopyWithImpl<Amount, Amount>(this as Amount, $identity, $identity);
  @override
  String toString() {
    return AmountMapper.ensureInitialized().stringifyValue(this as Amount);
  }

  @override
  bool operator ==(Object other) {
    return AmountMapper.ensureInitialized().equalsValue(this as Amount, other);
  }

  @override
  int get hashCode {
    return AmountMapper.ensureInitialized().hashValue(this as Amount);
  }
}

extension AmountValueCopy<$R, $Out> on ObjectCopyWith<$R, Amount, $Out> {
  AmountCopyWith<$R, Amount, $Out> get $asAmount =>
      $base.as((v, t, t2) => _AmountCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class AmountCopyWith<$R, $In extends Amount, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    Measure? measure,
    String? quantity,
    String? unit,
    bool? approximate,
    bool? primary,
  });
  AmountCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _AmountCopyWithImpl<$R, $Out> extends ClassCopyWithBase<$R, Amount, $Out>
    implements AmountCopyWith<$R, Amount, $Out> {
  _AmountCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<Amount> $mapper = AmountMapper.ensureInitialized();
  @override
  $R call({
    Measure? measure,
    String? quantity,
    Object? unit = $none,
    bool? approximate,
    bool? primary,
  }) => $apply(
    FieldCopyWithData({
      if (measure != null) #measure: measure,
      if (quantity != null) #quantity: quantity,
      if (unit != $none) #unit: unit,
      if (approximate != null) #approximate: approximate,
      if (primary != null) #primary: primary,
    }),
  );
  @override
  Amount $make(CopyWithData data) => Amount(
    measure: data.get(#measure, or: $value.measure),
    quantity: data.get(#quantity, or: $value.quantity),
    unit: data.get(#unit, or: $value.unit),
    approximate: data.get(#approximate, or: $value.approximate),
    primary: data.get(#primary, or: $value.primary),
  );

  @override
  AmountCopyWith<$R2, Amount, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _AmountCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class IngredientLineMapper extends ClassMapperBase<IngredientLine> {
  IngredientLineMapper._();

  static IngredientLineMapper? _instance;
  static IngredientLineMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = IngredientLineMapper._());
      AmountMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'IngredientLine';

  static String _$raw(IngredientLine v) => v.raw;
  static const Field<IngredientLine, String> _f$raw = Field('raw', _$raw);
  static List<Amount> _$amounts(IngredientLine v) => v.amounts;
  static const Field<IngredientLine, List<Amount>> _f$amounts = Field(
    'amounts',
    _$amounts,
    opt: true,
    def: const [],
  );
  static String? _$item(IngredientLine v) => v.item;
  static const Field<IngredientLine, String> _f$item = Field(
    'item',
    _$item,
    opt: true,
  );
  static String? _$prep(IngredientLine v) => v.prep;
  static const Field<IngredientLine, String> _f$prep = Field(
    'prep',
    _$prep,
    opt: true,
  );

  @override
  final MappableFields<IngredientLine> fields = const {
    #raw: _f$raw,
    #amounts: _f$amounts,
    #item: _f$item,
    #prep: _f$prep,
  };

  static IngredientLine _instantiate(DecodingData data) {
    return IngredientLine(
      raw: data.dec(_f$raw),
      amounts: data.dec(_f$amounts),
      item: data.dec(_f$item),
      prep: data.dec(_f$prep),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static IngredientLine fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<IngredientLine>(map);
  }

  static IngredientLine fromJson(String json) {
    return ensureInitialized().decodeJson<IngredientLine>(json);
  }
}

mixin IngredientLineMappable {
  String toJson() {
    return IngredientLineMapper.ensureInitialized().encodeJson<IngredientLine>(
      this as IngredientLine,
    );
  }

  Map<String, dynamic> toMap() {
    return IngredientLineMapper.ensureInitialized().encodeMap<IngredientLine>(
      this as IngredientLine,
    );
  }

  IngredientLineCopyWith<IngredientLine, IngredientLine, IngredientLine>
  get copyWith => _IngredientLineCopyWithImpl<IngredientLine, IngredientLine>(
    this as IngredientLine,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return IngredientLineMapper.ensureInitialized().stringifyValue(
      this as IngredientLine,
    );
  }

  @override
  bool operator ==(Object other) {
    return IngredientLineMapper.ensureInitialized().equalsValue(
      this as IngredientLine,
      other,
    );
  }

  @override
  int get hashCode {
    return IngredientLineMapper.ensureInitialized().hashValue(
      this as IngredientLine,
    );
  }
}

extension IngredientLineValueCopy<$R, $Out>
    on ObjectCopyWith<$R, IngredientLine, $Out> {
  IngredientLineCopyWith<$R, IngredientLine, $Out> get $asIngredientLine =>
      $base.as((v, t, t2) => _IngredientLineCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class IngredientLineCopyWith<$R, $In extends IngredientLine, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, Amount, AmountCopyWith<$R, Amount, Amount>> get amounts;
  $R call({String? raw, List<Amount>? amounts, String? item, String? prep});
  IngredientLineCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _IngredientLineCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, IngredientLine, $Out>
    implements IngredientLineCopyWith<$R, IngredientLine, $Out> {
  _IngredientLineCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<IngredientLine> $mapper =
      IngredientLineMapper.ensureInitialized();
  @override
  ListCopyWith<$R, Amount, AmountCopyWith<$R, Amount, Amount>> get amounts =>
      ListCopyWith(
        $value.amounts,
        (v, t) => v.copyWith.$chain(t),
        (v) => call(amounts: v),
      );
  @override
  $R call({
    String? raw,
    List<Amount>? amounts,
    Object? item = $none,
    Object? prep = $none,
  }) => $apply(
    FieldCopyWithData({
      if (raw != null) #raw: raw,
      if (amounts != null) #amounts: amounts,
      if (item != $none) #item: item,
      if (prep != $none) #prep: prep,
    }),
  );
  @override
  IngredientLine $make(CopyWithData data) => IngredientLine(
    raw: data.get(#raw, or: $value.raw),
    amounts: data.get(#amounts, or: $value.amounts),
    item: data.get(#item, or: $value.item),
    prep: data.get(#prep, or: $value.prep),
  );

  @override
  IngredientLineCopyWith<$R2, IngredientLine, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _IngredientLineCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class IngredientGroupMapper extends ClassMapperBase<IngredientGroup> {
  IngredientGroupMapper._();

  static IngredientGroupMapper? _instance;
  static IngredientGroupMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = IngredientGroupMapper._());
      IngredientLineMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'IngredientGroup';

  static String? _$group(IngredientGroup v) => v.group;
  static const Field<IngredientGroup, String> _f$group = Field(
    'group',
    _$group,
    opt: true,
  );
  static List<IngredientLine> _$items(IngredientGroup v) => v.items;
  static const Field<IngredientGroup, List<IngredientLine>> _f$items = Field(
    'items',
    _$items,
    opt: true,
    def: const [],
  );

  @override
  final MappableFields<IngredientGroup> fields = const {
    #group: _f$group,
    #items: _f$items,
  };

  static IngredientGroup _instantiate(DecodingData data) {
    return IngredientGroup(
      group: data.dec(_f$group),
      items: data.dec(_f$items),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static IngredientGroup fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<IngredientGroup>(map);
  }

  static IngredientGroup fromJson(String json) {
    return ensureInitialized().decodeJson<IngredientGroup>(json);
  }
}

mixin IngredientGroupMappable {
  String toJson() {
    return IngredientGroupMapper.ensureInitialized()
        .encodeJson<IngredientGroup>(this as IngredientGroup);
  }

  Map<String, dynamic> toMap() {
    return IngredientGroupMapper.ensureInitialized().encodeMap<IngredientGroup>(
      this as IngredientGroup,
    );
  }

  IngredientGroupCopyWith<IngredientGroup, IngredientGroup, IngredientGroup>
  get copyWith =>
      _IngredientGroupCopyWithImpl<IngredientGroup, IngredientGroup>(
        this as IngredientGroup,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return IngredientGroupMapper.ensureInitialized().stringifyValue(
      this as IngredientGroup,
    );
  }

  @override
  bool operator ==(Object other) {
    return IngredientGroupMapper.ensureInitialized().equalsValue(
      this as IngredientGroup,
      other,
    );
  }

  @override
  int get hashCode {
    return IngredientGroupMapper.ensureInitialized().hashValue(
      this as IngredientGroup,
    );
  }
}

extension IngredientGroupValueCopy<$R, $Out>
    on ObjectCopyWith<$R, IngredientGroup, $Out> {
  IngredientGroupCopyWith<$R, IngredientGroup, $Out> get $asIngredientGroup =>
      $base.as((v, t, t2) => _IngredientGroupCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class IngredientGroupCopyWith<$R, $In extends IngredientGroup, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<
    $R,
    IngredientLine,
    IngredientLineCopyWith<$R, IngredientLine, IngredientLine>
  >
  get items;
  $R call({String? group, List<IngredientLine>? items});
  IngredientGroupCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _IngredientGroupCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, IngredientGroup, $Out>
    implements IngredientGroupCopyWith<$R, IngredientGroup, $Out> {
  _IngredientGroupCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<IngredientGroup> $mapper =
      IngredientGroupMapper.ensureInitialized();
  @override
  ListCopyWith<
    $R,
    IngredientLine,
    IngredientLineCopyWith<$R, IngredientLine, IngredientLine>
  >
  get items => ListCopyWith(
    $value.items,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(items: v),
  );
  @override
  $R call({Object? group = $none, List<IngredientLine>? items}) => $apply(
    FieldCopyWithData({
      if (group != $none) #group: group,
      if (items != null) #items: items,
    }),
  );
  @override
  IngredientGroup $make(CopyWithData data) => IngredientGroup(
    group: data.get(#group, or: $value.group),
    items: data.get(#items, or: $value.items),
  );

  @override
  IngredientGroupCopyWith<$R2, IngredientGroup, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _IngredientGroupCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class RecipeStepMapper extends ClassMapperBase<RecipeStep> {
  RecipeStepMapper._();

  static RecipeStepMapper? _instance;
  static RecipeStepMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RecipeStepMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'RecipeStep';

  static int _$number(RecipeStep v) => v.number;
  static const Field<RecipeStep, int> _f$number = Field('number', _$number);
  static String? _$label(RecipeStep v) => v.label;
  static const Field<RecipeStep, String> _f$label = Field(
    'label',
    _$label,
    opt: true,
  );
  static String _$text(RecipeStep v) => v.text;
  static const Field<RecipeStep, String> _f$text = Field('text', _$text);

  @override
  final MappableFields<RecipeStep> fields = const {
    #number: _f$number,
    #label: _f$label,
    #text: _f$text,
  };

  static RecipeStep _instantiate(DecodingData data) {
    return RecipeStep(
      number: data.dec(_f$number),
      label: data.dec(_f$label),
      text: data.dec(_f$text),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static RecipeStep fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RecipeStep>(map);
  }

  static RecipeStep fromJson(String json) {
    return ensureInitialized().decodeJson<RecipeStep>(json);
  }
}

mixin RecipeStepMappable {
  String toJson() {
    return RecipeStepMapper.ensureInitialized().encodeJson<RecipeStep>(
      this as RecipeStep,
    );
  }

  Map<String, dynamic> toMap() {
    return RecipeStepMapper.ensureInitialized().encodeMap<RecipeStep>(
      this as RecipeStep,
    );
  }

  RecipeStepCopyWith<RecipeStep, RecipeStep, RecipeStep> get copyWith =>
      _RecipeStepCopyWithImpl<RecipeStep, RecipeStep>(
        this as RecipeStep,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return RecipeStepMapper.ensureInitialized().stringifyValue(
      this as RecipeStep,
    );
  }

  @override
  bool operator ==(Object other) {
    return RecipeStepMapper.ensureInitialized().equalsValue(
      this as RecipeStep,
      other,
    );
  }

  @override
  int get hashCode {
    return RecipeStepMapper.ensureInitialized().hashValue(this as RecipeStep);
  }
}

extension RecipeStepValueCopy<$R, $Out>
    on ObjectCopyWith<$R, RecipeStep, $Out> {
  RecipeStepCopyWith<$R, RecipeStep, $Out> get $asRecipeStep =>
      $base.as((v, t, t2) => _RecipeStepCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class RecipeStepCopyWith<$R, $In extends RecipeStep, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({int? number, String? label, String? text});
  RecipeStepCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _RecipeStepCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, RecipeStep, $Out>
    implements RecipeStepCopyWith<$R, RecipeStep, $Out> {
  _RecipeStepCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<RecipeStep> $mapper =
      RecipeStepMapper.ensureInitialized();
  @override
  $R call({int? number, Object? label = $none, String? text}) => $apply(
    FieldCopyWithData({
      if (number != null) #number: number,
      if (label != $none) #label: label,
      if (text != null) #text: text,
    }),
  );
  @override
  RecipeStep $make(CopyWithData data) => RecipeStep(
    number: data.get(#number, or: $value.number),
    label: data.get(#label, or: $value.label),
    text: data.get(#text, or: $value.text),
  );

  @override
  RecipeStepCopyWith<$R2, RecipeStep, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _RecipeStepCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class SubsectionMapper extends ClassMapperBase<Subsection> {
  SubsectionMapper._();

  static SubsectionMapper? _instance;
  static SubsectionMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = SubsectionMapper._());
      IngredientGroupMapper.ensureInitialized();
      RecipeStepMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'Subsection';

  static String? _$title(Subsection v) => v.title;
  static const Field<Subsection, String> _f$title = Field(
    'title',
    _$title,
    opt: true,
  );
  static String? _$kind(Subsection v) => v.kind;
  static const Field<Subsection, String> _f$kind = Field(
    'kind',
    _$kind,
    opt: true,
  );
  static String? _$body(Subsection v) => v.body;
  static const Field<Subsection, String> _f$body = Field(
    'body',
    _$body,
    opt: true,
  );
  static String? _$servings(Subsection v) => v.servings;
  static const Field<Subsection, String> _f$servings = Field(
    'servings',
    _$servings,
    opt: true,
  );
  static String? _$prepNotes(Subsection v) => v.prepNotes;
  static const Field<Subsection, String> _f$prepNotes = Field(
    'prepNotes',
    _$prepNotes,
    key: r'prep_notes',
    opt: true,
  );
  static List<IngredientGroup>? _$ingredients(Subsection v) => v.ingredients;
  static const Field<Subsection, List<IngredientGroup>> _f$ingredients = Field(
    'ingredients',
    _$ingredients,
    opt: true,
  );
  static List<RecipeStep>? _$steps(Subsection v) => v.steps;
  static const Field<Subsection, List<RecipeStep>> _f$steps = Field(
    'steps',
    _$steps,
    opt: true,
  );

  @override
  final MappableFields<Subsection> fields = const {
    #title: _f$title,
    #kind: _f$kind,
    #body: _f$body,
    #servings: _f$servings,
    #prepNotes: _f$prepNotes,
    #ingredients: _f$ingredients,
    #steps: _f$steps,
  };

  static Subsection _instantiate(DecodingData data) {
    return Subsection(
      title: data.dec(_f$title),
      kind: data.dec(_f$kind),
      body: data.dec(_f$body),
      servings: data.dec(_f$servings),
      prepNotes: data.dec(_f$prepNotes),
      ingredients: data.dec(_f$ingredients),
      steps: data.dec(_f$steps),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static Subsection fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<Subsection>(map);
  }

  static Subsection fromJson(String json) {
    return ensureInitialized().decodeJson<Subsection>(json);
  }
}

mixin SubsectionMappable {
  String toJson() {
    return SubsectionMapper.ensureInitialized().encodeJson<Subsection>(
      this as Subsection,
    );
  }

  Map<String, dynamic> toMap() {
    return SubsectionMapper.ensureInitialized().encodeMap<Subsection>(
      this as Subsection,
    );
  }

  SubsectionCopyWith<Subsection, Subsection, Subsection> get copyWith =>
      _SubsectionCopyWithImpl<Subsection, Subsection>(
        this as Subsection,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return SubsectionMapper.ensureInitialized().stringifyValue(
      this as Subsection,
    );
  }

  @override
  bool operator ==(Object other) {
    return SubsectionMapper.ensureInitialized().equalsValue(
      this as Subsection,
      other,
    );
  }

  @override
  int get hashCode {
    return SubsectionMapper.ensureInitialized().hashValue(this as Subsection);
  }
}

extension SubsectionValueCopy<$R, $Out>
    on ObjectCopyWith<$R, Subsection, $Out> {
  SubsectionCopyWith<$R, Subsection, $Out> get $asSubsection =>
      $base.as((v, t, t2) => _SubsectionCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class SubsectionCopyWith<$R, $In extends Subsection, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<
    $R,
    IngredientGroup,
    IngredientGroupCopyWith<$R, IngredientGroup, IngredientGroup>
  >?
  get ingredients;
  ListCopyWith<$R, RecipeStep, RecipeStepCopyWith<$R, RecipeStep, RecipeStep>>?
  get steps;
  $R call({
    String? title,
    String? kind,
    String? body,
    String? servings,
    String? prepNotes,
    List<IngredientGroup>? ingredients,
    List<RecipeStep>? steps,
  });
  SubsectionCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _SubsectionCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, Subsection, $Out>
    implements SubsectionCopyWith<$R, Subsection, $Out> {
  _SubsectionCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<Subsection> $mapper =
      SubsectionMapper.ensureInitialized();
  @override
  ListCopyWith<
    $R,
    IngredientGroup,
    IngredientGroupCopyWith<$R, IngredientGroup, IngredientGroup>
  >?
  get ingredients => $value.ingredients != null
      ? ListCopyWith(
          $value.ingredients!,
          (v, t) => v.copyWith.$chain(t),
          (v) => call(ingredients: v),
        )
      : null;
  @override
  ListCopyWith<$R, RecipeStep, RecipeStepCopyWith<$R, RecipeStep, RecipeStep>>?
  get steps => $value.steps != null
      ? ListCopyWith(
          $value.steps!,
          (v, t) => v.copyWith.$chain(t),
          (v) => call(steps: v),
        )
      : null;
  @override
  $R call({
    Object? title = $none,
    Object? kind = $none,
    Object? body = $none,
    Object? servings = $none,
    Object? prepNotes = $none,
    Object? ingredients = $none,
    Object? steps = $none,
  }) => $apply(
    FieldCopyWithData({
      if (title != $none) #title: title,
      if (kind != $none) #kind: kind,
      if (body != $none) #body: body,
      if (servings != $none) #servings: servings,
      if (prepNotes != $none) #prepNotes: prepNotes,
      if (ingredients != $none) #ingredients: ingredients,
      if (steps != $none) #steps: steps,
    }),
  );
  @override
  Subsection $make(CopyWithData data) => Subsection(
    title: data.get(#title, or: $value.title),
    kind: data.get(#kind, or: $value.kind),
    body: data.get(#body, or: $value.body),
    servings: data.get(#servings, or: $value.servings),
    prepNotes: data.get(#prepNotes, or: $value.prepNotes),
    ingredients: data.get(#ingredients, or: $value.ingredients),
    steps: data.get(#steps, or: $value.steps),
  );

  @override
  SubsectionCopyWith<$R2, Subsection, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _SubsectionCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class TechniqueStepMapper extends ClassMapperBase<TechniqueStep> {
  TechniqueStepMapper._();

  static TechniqueStepMapper? _instance;
  static TechniqueStepMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TechniqueStepMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'TechniqueStep';

  static int _$number(TechniqueStep v) => v.number;
  static const Field<TechniqueStep, int> _f$number = Field('number', _$number);
  static String? _$image(TechniqueStep v) => v.image;
  static const Field<TechniqueStep, String> _f$image = Field(
    'image',
    _$image,
    opt: true,
  );
  static String _$caption(TechniqueStep v) => v.caption;
  static const Field<TechniqueStep, String> _f$caption = Field(
    'caption',
    _$caption,
  );

  @override
  final MappableFields<TechniqueStep> fields = const {
    #number: _f$number,
    #image: _f$image,
    #caption: _f$caption,
  };

  static TechniqueStep _instantiate(DecodingData data) {
    return TechniqueStep(
      number: data.dec(_f$number),
      image: data.dec(_f$image),
      caption: data.dec(_f$caption),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static TechniqueStep fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<TechniqueStep>(map);
  }

  static TechniqueStep fromJson(String json) {
    return ensureInitialized().decodeJson<TechniqueStep>(json);
  }
}

mixin TechniqueStepMappable {
  String toJson() {
    return TechniqueStepMapper.ensureInitialized().encodeJson<TechniqueStep>(
      this as TechniqueStep,
    );
  }

  Map<String, dynamic> toMap() {
    return TechniqueStepMapper.ensureInitialized().encodeMap<TechniqueStep>(
      this as TechniqueStep,
    );
  }

  TechniqueStepCopyWith<TechniqueStep, TechniqueStep, TechniqueStep>
  get copyWith => _TechniqueStepCopyWithImpl<TechniqueStep, TechniqueStep>(
    this as TechniqueStep,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return TechniqueStepMapper.ensureInitialized().stringifyValue(
      this as TechniqueStep,
    );
  }

  @override
  bool operator ==(Object other) {
    return TechniqueStepMapper.ensureInitialized().equalsValue(
      this as TechniqueStep,
      other,
    );
  }

  @override
  int get hashCode {
    return TechniqueStepMapper.ensureInitialized().hashValue(
      this as TechniqueStep,
    );
  }
}

extension TechniqueStepValueCopy<$R, $Out>
    on ObjectCopyWith<$R, TechniqueStep, $Out> {
  TechniqueStepCopyWith<$R, TechniqueStep, $Out> get $asTechniqueStep =>
      $base.as((v, t, t2) => _TechniqueStepCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class TechniqueStepCopyWith<$R, $In extends TechniqueStep, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({int? number, String? image, String? caption});
  TechniqueStepCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _TechniqueStepCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, TechniqueStep, $Out>
    implements TechniqueStepCopyWith<$R, TechniqueStep, $Out> {
  _TechniqueStepCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<TechniqueStep> $mapper =
      TechniqueStepMapper.ensureInitialized();
  @override
  $R call({int? number, Object? image = $none, String? caption}) => $apply(
    FieldCopyWithData({
      if (number != null) #number: number,
      if (image != $none) #image: image,
      if (caption != null) #caption: caption,
    }),
  );
  @override
  TechniqueStep $make(CopyWithData data) => TechniqueStep(
    number: data.get(#number, or: $value.number),
    image: data.get(#image, or: $value.image),
    caption: data.get(#caption, or: $value.caption),
  );

  @override
  TechniqueStepCopyWith<$R2, TechniqueStep, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _TechniqueStepCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class TechniqueMapper extends ClassMapperBase<Technique> {
  TechniqueMapper._();

  static TechniqueMapper? _instance;
  static TechniqueMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TechniqueMapper._());
      TechniqueStepMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'Technique';

  static String? _$heading(Technique v) => v.heading;
  static const Field<Technique, String> _f$heading = Field(
    'heading',
    _$heading,
    opt: true,
  );
  static String? _$description(Technique v) => v.description;
  static const Field<Technique, String> _f$description = Field(
    'description',
    _$description,
    opt: true,
  );
  static List<TechniqueStep> _$steps(Technique v) => v.steps;
  static const Field<Technique, List<TechniqueStep>> _f$steps = Field(
    'steps',
    _$steps,
    opt: true,
    def: const [],
  );

  @override
  final MappableFields<Technique> fields = const {
    #heading: _f$heading,
    #description: _f$description,
    #steps: _f$steps,
  };

  static Technique _instantiate(DecodingData data) {
    return Technique(
      heading: data.dec(_f$heading),
      description: data.dec(_f$description),
      steps: data.dec(_f$steps),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static Technique fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<Technique>(map);
  }

  static Technique fromJson(String json) {
    return ensureInitialized().decodeJson<Technique>(json);
  }
}

mixin TechniqueMappable {
  String toJson() {
    return TechniqueMapper.ensureInitialized().encodeJson<Technique>(
      this as Technique,
    );
  }

  Map<String, dynamic> toMap() {
    return TechniqueMapper.ensureInitialized().encodeMap<Technique>(
      this as Technique,
    );
  }

  TechniqueCopyWith<Technique, Technique, Technique> get copyWith =>
      _TechniqueCopyWithImpl<Technique, Technique>(
        this as Technique,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return TechniqueMapper.ensureInitialized().stringifyValue(
      this as Technique,
    );
  }

  @override
  bool operator ==(Object other) {
    return TechniqueMapper.ensureInitialized().equalsValue(
      this as Technique,
      other,
    );
  }

  @override
  int get hashCode {
    return TechniqueMapper.ensureInitialized().hashValue(this as Technique);
  }
}

extension TechniqueValueCopy<$R, $Out> on ObjectCopyWith<$R, Technique, $Out> {
  TechniqueCopyWith<$R, Technique, $Out> get $asTechnique =>
      $base.as((v, t, t2) => _TechniqueCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class TechniqueCopyWith<$R, $In extends Technique, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<
    $R,
    TechniqueStep,
    TechniqueStepCopyWith<$R, TechniqueStep, TechniqueStep>
  >
  get steps;
  $R call({String? heading, String? description, List<TechniqueStep>? steps});
  TechniqueCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _TechniqueCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, Technique, $Out>
    implements TechniqueCopyWith<$R, Technique, $Out> {
  _TechniqueCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<Technique> $mapper =
      TechniqueMapper.ensureInitialized();
  @override
  ListCopyWith<
    $R,
    TechniqueStep,
    TechniqueStepCopyWith<$R, TechniqueStep, TechniqueStep>
  >
  get steps => ListCopyWith(
    $value.steps,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(steps: v),
  );
  @override
  $R call({
    Object? heading = $none,
    Object? description = $none,
    List<TechniqueStep>? steps,
  }) => $apply(
    FieldCopyWithData({
      if (heading != $none) #heading: heading,
      if (description != $none) #description: description,
      if (steps != null) #steps: steps,
    }),
  );
  @override
  Technique $make(CopyWithData data) => Technique(
    heading: data.get(#heading, or: $value.heading),
    description: data.get(#description, or: $value.description),
    steps: data.get(#steps, or: $value.steps),
  );

  @override
  TechniqueCopyWith<$R2, Technique, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _TechniqueCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class RecipeSourceMapper extends ClassMapperBase<RecipeSource> {
  RecipeSourceMapper._();

  static RecipeSourceMapper? _instance;
  static RecipeSourceMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RecipeSourceMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'RecipeSource';

  static String _$name(RecipeSource v) => v.name;
  static const Field<RecipeSource, String> _f$name = Field('name', _$name);
  static String _$type(RecipeSource v) => v.type;
  static const Field<RecipeSource, String> _f$type = Field('type', _$type);
  static String? _$publisher(RecipeSource v) => v.publisher;
  static const Field<RecipeSource, String> _f$publisher = Field(
    'publisher',
    _$publisher,
    opt: true,
  );
  static String? _$isbn(RecipeSource v) => v.isbn;
  static const Field<RecipeSource, String> _f$isbn = Field(
    'isbn',
    _$isbn,
    opt: true,
  );
  static String? _$sourceFile(RecipeSource v) => v.sourceFile;
  static const Field<RecipeSource, String> _f$sourceFile = Field(
    'sourceFile',
    _$sourceFile,
    key: r'source_file',
    opt: true,
  );
  static String? _$chapter(RecipeSource v) => v.chapter;
  static const Field<RecipeSource, String> _f$chapter = Field(
    'chapter',
    _$chapter,
    opt: true,
  );
  static String? _$sectionId(RecipeSource v) => v.sectionId;
  static const Field<RecipeSource, String> _f$sectionId = Field(
    'sectionId',
    _$sectionId,
    key: r'section_id',
    opt: true,
  );
  static int? _$pageStart(RecipeSource v) => v.pageStart;
  static const Field<RecipeSource, int> _f$pageStart = Field(
    'pageStart',
    _$pageStart,
    key: r'page_start',
    opt: true,
  );
  static int? _$pageEnd(RecipeSource v) => v.pageEnd;
  static const Field<RecipeSource, int> _f$pageEnd = Field(
    'pageEnd',
    _$pageEnd,
    key: r'page_end',
    opt: true,
  );
  static String? _$url(RecipeSource v) => v.url;
  static const Field<RecipeSource, String> _f$url = Field(
    'url',
    _$url,
    opt: true,
  );

  @override
  final MappableFields<RecipeSource> fields = const {
    #name: _f$name,
    #type: _f$type,
    #publisher: _f$publisher,
    #isbn: _f$isbn,
    #sourceFile: _f$sourceFile,
    #chapter: _f$chapter,
    #sectionId: _f$sectionId,
    #pageStart: _f$pageStart,
    #pageEnd: _f$pageEnd,
    #url: _f$url,
  };

  static RecipeSource _instantiate(DecodingData data) {
    return RecipeSource(
      name: data.dec(_f$name),
      type: data.dec(_f$type),
      publisher: data.dec(_f$publisher),
      isbn: data.dec(_f$isbn),
      sourceFile: data.dec(_f$sourceFile),
      chapter: data.dec(_f$chapter),
      sectionId: data.dec(_f$sectionId),
      pageStart: data.dec(_f$pageStart),
      pageEnd: data.dec(_f$pageEnd),
      url: data.dec(_f$url),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static RecipeSource fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RecipeSource>(map);
  }

  static RecipeSource fromJson(String json) {
    return ensureInitialized().decodeJson<RecipeSource>(json);
  }
}

mixin RecipeSourceMappable {
  String toJson() {
    return RecipeSourceMapper.ensureInitialized().encodeJson<RecipeSource>(
      this as RecipeSource,
    );
  }

  Map<String, dynamic> toMap() {
    return RecipeSourceMapper.ensureInitialized().encodeMap<RecipeSource>(
      this as RecipeSource,
    );
  }

  RecipeSourceCopyWith<RecipeSource, RecipeSource, RecipeSource> get copyWith =>
      _RecipeSourceCopyWithImpl<RecipeSource, RecipeSource>(
        this as RecipeSource,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return RecipeSourceMapper.ensureInitialized().stringifyValue(
      this as RecipeSource,
    );
  }

  @override
  bool operator ==(Object other) {
    return RecipeSourceMapper.ensureInitialized().equalsValue(
      this as RecipeSource,
      other,
    );
  }

  @override
  int get hashCode {
    return RecipeSourceMapper.ensureInitialized().hashValue(
      this as RecipeSource,
    );
  }
}

extension RecipeSourceValueCopy<$R, $Out>
    on ObjectCopyWith<$R, RecipeSource, $Out> {
  RecipeSourceCopyWith<$R, RecipeSource, $Out> get $asRecipeSource =>
      $base.as((v, t, t2) => _RecipeSourceCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class RecipeSourceCopyWith<$R, $In extends RecipeSource, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? name,
    String? type,
    String? publisher,
    String? isbn,
    String? sourceFile,
    String? chapter,
    String? sectionId,
    int? pageStart,
    int? pageEnd,
    String? url,
  });
  RecipeSourceCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _RecipeSourceCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, RecipeSource, $Out>
    implements RecipeSourceCopyWith<$R, RecipeSource, $Out> {
  _RecipeSourceCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<RecipeSource> $mapper =
      RecipeSourceMapper.ensureInitialized();
  @override
  $R call({
    String? name,
    String? type,
    Object? publisher = $none,
    Object? isbn = $none,
    Object? sourceFile = $none,
    Object? chapter = $none,
    Object? sectionId = $none,
    Object? pageStart = $none,
    Object? pageEnd = $none,
    Object? url = $none,
  }) => $apply(
    FieldCopyWithData({
      if (name != null) #name: name,
      if (type != null) #type: type,
      if (publisher != $none) #publisher: publisher,
      if (isbn != $none) #isbn: isbn,
      if (sourceFile != $none) #sourceFile: sourceFile,
      if (chapter != $none) #chapter: chapter,
      if (sectionId != $none) #sectionId: sectionId,
      if (pageStart != $none) #pageStart: pageStart,
      if (pageEnd != $none) #pageEnd: pageEnd,
      if (url != $none) #url: url,
    }),
  );
  @override
  RecipeSource $make(CopyWithData data) => RecipeSource(
    name: data.get(#name, or: $value.name),
    type: data.get(#type, or: $value.type),
    publisher: data.get(#publisher, or: $value.publisher),
    isbn: data.get(#isbn, or: $value.isbn),
    sourceFile: data.get(#sourceFile, or: $value.sourceFile),
    chapter: data.get(#chapter, or: $value.chapter),
    sectionId: data.get(#sectionId, or: $value.sectionId),
    pageStart: data.get(#pageStart, or: $value.pageStart),
    pageEnd: data.get(#pageEnd, or: $value.pageEnd),
    url: data.get(#url, or: $value.url),
  );

  @override
  RecipeSourceCopyWith<$R2, RecipeSource, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _RecipeSourceCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class ServesMapper extends ClassMapperBase<Serves> {
  ServesMapper._();

  static ServesMapper? _instance;
  static ServesMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ServesMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'Serves';

  static int _$min(Serves v) => v.min;
  static const Field<Serves, int> _f$min = Field('min', _$min);
  static int _$max(Serves v) => v.max;
  static const Field<Serves, int> _f$max = Field('max', _$max);

  @override
  final MappableFields<Serves> fields = const {#min: _f$min, #max: _f$max};

  static Serves _instantiate(DecodingData data) {
    return Serves(min: data.dec(_f$min), max: data.dec(_f$max));
  }

  @override
  final Function instantiate = _instantiate;

  static Serves fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<Serves>(map);
  }

  static Serves fromJson(String json) {
    return ensureInitialized().decodeJson<Serves>(json);
  }
}

mixin ServesMappable {
  String toJson() {
    return ServesMapper.ensureInitialized().encodeJson<Serves>(this as Serves);
  }

  Map<String, dynamic> toMap() {
    return ServesMapper.ensureInitialized().encodeMap<Serves>(this as Serves);
  }

  ServesCopyWith<Serves, Serves, Serves> get copyWith =>
      _ServesCopyWithImpl<Serves, Serves>(this as Serves, $identity, $identity);
  @override
  String toString() {
    return ServesMapper.ensureInitialized().stringifyValue(this as Serves);
  }

  @override
  bool operator ==(Object other) {
    return ServesMapper.ensureInitialized().equalsValue(this as Serves, other);
  }

  @override
  int get hashCode {
    return ServesMapper.ensureInitialized().hashValue(this as Serves);
  }
}

extension ServesValueCopy<$R, $Out> on ObjectCopyWith<$R, Serves, $Out> {
  ServesCopyWith<$R, Serves, $Out> get $asServes =>
      $base.as((v, t, t2) => _ServesCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ServesCopyWith<$R, $In extends Serves, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({int? min, int? max});
  ServesCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _ServesCopyWithImpl<$R, $Out> extends ClassCopyWithBase<$R, Serves, $Out>
    implements ServesCopyWith<$R, Serves, $Out> {
  _ServesCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<Serves> $mapper = ServesMapper.ensureInitialized();
  @override
  $R call({int? min, int? max}) => $apply(
    FieldCopyWithData({if (min != null) #min: min, if (max != null) #max: max}),
  );
  @override
  Serves $make(CopyWithData data) => Serves(
    min: data.get(#min, or: $value.min),
    max: data.get(#max, or: $value.max),
  );

  @override
  ServesCopyWith<$R2, Serves, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _ServesCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class RecipeTimesMapper extends ClassMapperBase<RecipeTimes> {
  RecipeTimesMapper._();

  static RecipeTimesMapper? _instance;
  static RecipeTimesMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RecipeTimesMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'RecipeTimes';

  static int? _$prep(RecipeTimes v) => v.prep;
  static const Field<RecipeTimes, int> _f$prep = Field(
    'prep',
    _$prep,
    opt: true,
  );
  static int? _$cook(RecipeTimes v) => v.cook;
  static const Field<RecipeTimes, int> _f$cook = Field(
    'cook',
    _$cook,
    opt: true,
  );
  static int? _$total(RecipeTimes v) => v.total;
  static const Field<RecipeTimes, int> _f$total = Field(
    'total',
    _$total,
    opt: true,
  );

  @override
  final MappableFields<RecipeTimes> fields = const {
    #prep: _f$prep,
    #cook: _f$cook,
    #total: _f$total,
  };

  static RecipeTimes _instantiate(DecodingData data) {
    return RecipeTimes(
      prep: data.dec(_f$prep),
      cook: data.dec(_f$cook),
      total: data.dec(_f$total),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static RecipeTimes fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RecipeTimes>(map);
  }

  static RecipeTimes fromJson(String json) {
    return ensureInitialized().decodeJson<RecipeTimes>(json);
  }
}

mixin RecipeTimesMappable {
  String toJson() {
    return RecipeTimesMapper.ensureInitialized().encodeJson<RecipeTimes>(
      this as RecipeTimes,
    );
  }

  Map<String, dynamic> toMap() {
    return RecipeTimesMapper.ensureInitialized().encodeMap<RecipeTimes>(
      this as RecipeTimes,
    );
  }

  RecipeTimesCopyWith<RecipeTimes, RecipeTimes, RecipeTimes> get copyWith =>
      _RecipeTimesCopyWithImpl<RecipeTimes, RecipeTimes>(
        this as RecipeTimes,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return RecipeTimesMapper.ensureInitialized().stringifyValue(
      this as RecipeTimes,
    );
  }

  @override
  bool operator ==(Object other) {
    return RecipeTimesMapper.ensureInitialized().equalsValue(
      this as RecipeTimes,
      other,
    );
  }

  @override
  int get hashCode {
    return RecipeTimesMapper.ensureInitialized().hashValue(this as RecipeTimes);
  }
}

extension RecipeTimesValueCopy<$R, $Out>
    on ObjectCopyWith<$R, RecipeTimes, $Out> {
  RecipeTimesCopyWith<$R, RecipeTimes, $Out> get $asRecipeTimes =>
      $base.as((v, t, t2) => _RecipeTimesCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class RecipeTimesCopyWith<$R, $In extends RecipeTimes, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({int? prep, int? cook, int? total});
  RecipeTimesCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _RecipeTimesCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, RecipeTimes, $Out>
    implements RecipeTimesCopyWith<$R, RecipeTimes, $Out> {
  _RecipeTimesCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<RecipeTimes> $mapper =
      RecipeTimesMapper.ensureInitialized();
  @override
  $R call({
    Object? prep = $none,
    Object? cook = $none,
    Object? total = $none,
  }) => $apply(
    FieldCopyWithData({
      if (prep != $none) #prep: prep,
      if (cook != $none) #cook: cook,
      if (total != $none) #total: total,
    }),
  );
  @override
  RecipeTimes $make(CopyWithData data) => RecipeTimes(
    prep: data.get(#prep, or: $value.prep),
    cook: data.get(#cook, or: $value.cook),
    total: data.get(#total, or: $value.total),
  );

  @override
  RecipeTimesCopyWith<$R2, RecipeTimes, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _RecipeTimesCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class RecipeImagesMapper extends ClassMapperBase<RecipeImages> {
  RecipeImagesMapper._();

  static RecipeImagesMapper? _instance;
  static RecipeImagesMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RecipeImagesMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'RecipeImages';

  static String? _$hero(RecipeImages v) => v.hero;
  static const Field<RecipeImages, String> _f$hero = Field(
    'hero',
    _$hero,
    opt: true,
  );
  static List<String> _$gallery(RecipeImages v) => v.gallery;
  static const Field<RecipeImages, List<String>> _f$gallery = Field(
    'gallery',
    _$gallery,
    opt: true,
    def: const [],
  );
  static String? _$credit(RecipeImages v) => v.credit;
  static const Field<RecipeImages, String> _f$credit = Field(
    'credit',
    _$credit,
    opt: true,
  );

  @override
  final MappableFields<RecipeImages> fields = const {
    #hero: _f$hero,
    #gallery: _f$gallery,
    #credit: _f$credit,
  };

  static RecipeImages _instantiate(DecodingData data) {
    return RecipeImages(
      hero: data.dec(_f$hero),
      gallery: data.dec(_f$gallery),
      credit: data.dec(_f$credit),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static RecipeImages fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RecipeImages>(map);
  }

  static RecipeImages fromJson(String json) {
    return ensureInitialized().decodeJson<RecipeImages>(json);
  }
}

mixin RecipeImagesMappable {
  String toJson() {
    return RecipeImagesMapper.ensureInitialized().encodeJson<RecipeImages>(
      this as RecipeImages,
    );
  }

  Map<String, dynamic> toMap() {
    return RecipeImagesMapper.ensureInitialized().encodeMap<RecipeImages>(
      this as RecipeImages,
    );
  }

  RecipeImagesCopyWith<RecipeImages, RecipeImages, RecipeImages> get copyWith =>
      _RecipeImagesCopyWithImpl<RecipeImages, RecipeImages>(
        this as RecipeImages,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return RecipeImagesMapper.ensureInitialized().stringifyValue(
      this as RecipeImages,
    );
  }

  @override
  bool operator ==(Object other) {
    return RecipeImagesMapper.ensureInitialized().equalsValue(
      this as RecipeImages,
      other,
    );
  }

  @override
  int get hashCode {
    return RecipeImagesMapper.ensureInitialized().hashValue(
      this as RecipeImages,
    );
  }
}

extension RecipeImagesValueCopy<$R, $Out>
    on ObjectCopyWith<$R, RecipeImages, $Out> {
  RecipeImagesCopyWith<$R, RecipeImages, $Out> get $asRecipeImages =>
      $base.as((v, t, t2) => _RecipeImagesCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class RecipeImagesCopyWith<$R, $In extends RecipeImages, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get gallery;
  $R call({String? hero, List<String>? gallery, String? credit});
  RecipeImagesCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _RecipeImagesCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, RecipeImages, $Out>
    implements RecipeImagesCopyWith<$R, RecipeImages, $Out> {
  _RecipeImagesCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<RecipeImages> $mapper =
      RecipeImagesMapper.ensureInitialized();
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get gallery =>
      ListCopyWith(
        $value.gallery,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(gallery: v),
      );
  @override
  $R call({
    Object? hero = $none,
    List<String>? gallery,
    Object? credit = $none,
  }) => $apply(
    FieldCopyWithData({
      if (hero != $none) #hero: hero,
      if (gallery != null) #gallery: gallery,
      if (credit != $none) #credit: credit,
    }),
  );
  @override
  RecipeImages $make(CopyWithData data) => RecipeImages(
    hero: data.get(#hero, or: $value.hero),
    gallery: data.get(#gallery, or: $value.gallery),
    credit: data.get(#credit, or: $value.credit),
  );

  @override
  RecipeImagesCopyWith<$R2, RecipeImages, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _RecipeImagesCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class ExtractionMapper extends ClassMapperBase<Extraction> {
  ExtractionMapper._();

  static ExtractionMapper? _instance;
  static ExtractionMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ExtractionMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'Extraction';

  static String? _$extractor(Extraction v) => v.extractor;
  static const Field<Extraction, String> _f$extractor = Field(
    'extractor',
    _$extractor,
    opt: true,
  );
  static String? _$extractorVersion(Extraction v) => v.extractorVersion;
  static const Field<Extraction, String> _f$extractorVersion = Field(
    'extractorVersion',
    _$extractorVersion,
    key: r'extractor_version',
    opt: true,
  );
  static String? _$extractedAt(Extraction v) => v.extractedAt;
  static const Field<Extraction, String> _f$extractedAt = Field(
    'extractedAt',
    _$extractedAt,
    key: r'extracted_at',
    opt: true,
  );
  static List<String> _$warnings(Extraction v) => v.warnings;
  static const Field<Extraction, List<String>> _f$warnings = Field(
    'warnings',
    _$warnings,
    opt: true,
    def: const [],
  );

  @override
  final MappableFields<Extraction> fields = const {
    #extractor: _f$extractor,
    #extractorVersion: _f$extractorVersion,
    #extractedAt: _f$extractedAt,
    #warnings: _f$warnings,
  };

  static Extraction _instantiate(DecodingData data) {
    return Extraction(
      extractor: data.dec(_f$extractor),
      extractorVersion: data.dec(_f$extractorVersion),
      extractedAt: data.dec(_f$extractedAt),
      warnings: data.dec(_f$warnings),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static Extraction fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<Extraction>(map);
  }

  static Extraction fromJson(String json) {
    return ensureInitialized().decodeJson<Extraction>(json);
  }
}

mixin ExtractionMappable {
  String toJson() {
    return ExtractionMapper.ensureInitialized().encodeJson<Extraction>(
      this as Extraction,
    );
  }

  Map<String, dynamic> toMap() {
    return ExtractionMapper.ensureInitialized().encodeMap<Extraction>(
      this as Extraction,
    );
  }

  ExtractionCopyWith<Extraction, Extraction, Extraction> get copyWith =>
      _ExtractionCopyWithImpl<Extraction, Extraction>(
        this as Extraction,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return ExtractionMapper.ensureInitialized().stringifyValue(
      this as Extraction,
    );
  }

  @override
  bool operator ==(Object other) {
    return ExtractionMapper.ensureInitialized().equalsValue(
      this as Extraction,
      other,
    );
  }

  @override
  int get hashCode {
    return ExtractionMapper.ensureInitialized().hashValue(this as Extraction);
  }
}

extension ExtractionValueCopy<$R, $Out>
    on ObjectCopyWith<$R, Extraction, $Out> {
  ExtractionCopyWith<$R, Extraction, $Out> get $asExtraction =>
      $base.as((v, t, t2) => _ExtractionCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ExtractionCopyWith<$R, $In extends Extraction, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get warnings;
  $R call({
    String? extractor,
    String? extractorVersion,
    String? extractedAt,
    List<String>? warnings,
  });
  ExtractionCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _ExtractionCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, Extraction, $Out>
    implements ExtractionCopyWith<$R, Extraction, $Out> {
  _ExtractionCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<Extraction> $mapper =
      ExtractionMapper.ensureInitialized();
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get warnings =>
      ListCopyWith(
        $value.warnings,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(warnings: v),
      );
  @override
  $R call({
    Object? extractor = $none,
    Object? extractorVersion = $none,
    Object? extractedAt = $none,
    List<String>? warnings,
  }) => $apply(
    FieldCopyWithData({
      if (extractor != $none) #extractor: extractor,
      if (extractorVersion != $none) #extractorVersion: extractorVersion,
      if (extractedAt != $none) #extractedAt: extractedAt,
      if (warnings != null) #warnings: warnings,
    }),
  );
  @override
  Extraction $make(CopyWithData data) => Extraction(
    extractor: data.get(#extractor, or: $value.extractor),
    extractorVersion: data.get(#extractorVersion, or: $value.extractorVersion),
    extractedAt: data.get(#extractedAt, or: $value.extractedAt),
    warnings: data.get(#warnings, or: $value.warnings),
  );

  @override
  ExtractionCopyWith<$R2, Extraction, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ExtractionCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class RecipeMapper extends ClassMapperBase<Recipe> {
  RecipeMapper._();

  static RecipeMapper? _instance;
  static RecipeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RecipeMapper._());
      RecipeSourceMapper.ensureInitialized();
      ServesMapper.ensureInitialized();
      RecipeTimesMapper.ensureInitialized();
      IngredientGroupMapper.ensureInitialized();
      RecipeStepMapper.ensureInitialized();
      SubsectionMapper.ensureInitialized();
      TechniqueMapper.ensureInitialized();
      RecipeImagesMapper.ensureInitialized();
      ExtractionMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'Recipe';

  static int _$schemaVersion(Recipe v) => v.schemaVersion;
  static const Field<Recipe, int> _f$schemaVersion = Field(
    'schemaVersion',
    _$schemaVersion,
    key: r'schema_version',
    opt: true,
    def: 2,
  );
  static String _$id(Recipe v) => v.id;
  static const Field<Recipe, String> _f$id = Field('id', _$id);
  static String _$title(Recipe v) => v.title;
  static const Field<Recipe, String> _f$title = Field('title', _$title);
  static String _$slug(Recipe v) => v.slug;
  static const Field<Recipe, String> _f$slug = Field('slug', _$slug);
  static RecipeSource _$source(Recipe v) => v.source;
  static const Field<Recipe, RecipeSource> _f$source = Field(
    'source',
    _$source,
  );
  static String? _$servings(Recipe v) => v.servings;
  static const Field<Recipe, String> _f$servings = Field(
    'servings',
    _$servings,
    opt: true,
  );
  static Serves? _$serves(Recipe v) => v.serves;
  static const Field<Recipe, Serves> _f$serves = Field(
    'serves',
    _$serves,
    opt: true,
  );
  static RecipeTimes _$times(Recipe v) => v.times;
  static const Field<Recipe, RecipeTimes> _f$times = Field(
    'times',
    _$times,
    opt: true,
    def: const RecipeTimes(),
  );
  static String? _$category(Recipe v) => v.category;
  static const Field<Recipe, String> _f$category = Field(
    'category',
    _$category,
    opt: true,
  );
  static List<String> _$tags(Recipe v) => v.tags;
  static const Field<Recipe, List<String>> _f$tags = Field(
    'tags',
    _$tags,
    opt: true,
    def: const [],
  );
  static String? _$background(Recipe v) => v.background;
  static const Field<Recipe, String> _f$background = Field(
    'background',
    _$background,
    opt: true,
  );
  static String? _$prepNotes(Recipe v) => v.prepNotes;
  static const Field<Recipe, String> _f$prepNotes = Field(
    'prepNotes',
    _$prepNotes,
    key: r'prep_notes',
    opt: true,
  );
  static List<IngredientGroup> _$ingredients(Recipe v) => v.ingredients;
  static const Field<Recipe, List<IngredientGroup>> _f$ingredients = Field(
    'ingredients',
    _$ingredients,
    opt: true,
    def: const [],
  );
  static List<RecipeStep> _$steps(Recipe v) => v.steps;
  static const Field<Recipe, List<RecipeStep>> _f$steps = Field(
    'steps',
    _$steps,
    opt: true,
    def: const [],
  );
  static List<Subsection> _$subsections(Recipe v) => v.subsections;
  static const Field<Recipe, List<Subsection>> _f$subsections = Field(
    'subsections',
    _$subsections,
    opt: true,
    def: const [],
  );
  static List<Technique> _$techniques(Recipe v) => v.techniques;
  static const Field<Recipe, List<Technique>> _f$techniques = Field(
    'techniques',
    _$techniques,
    opt: true,
    def: const [],
  );
  static RecipeImages _$images(Recipe v) => v.images;
  static const Field<Recipe, RecipeImages> _f$images = Field(
    'images',
    _$images,
    opt: true,
    def: const RecipeImages(),
  );
  static String? _$notes(Recipe v) => v.notes;
  static const Field<Recipe, String> _f$notes = Field(
    'notes',
    _$notes,
    opt: true,
  );
  static Extraction? _$extraction(Recipe v) => v.extraction;
  static const Field<Recipe, Extraction> _f$extraction = Field(
    'extraction',
    _$extraction,
    opt: true,
  );

  @override
  final MappableFields<Recipe> fields = const {
    #schemaVersion: _f$schemaVersion,
    #id: _f$id,
    #title: _f$title,
    #slug: _f$slug,
    #source: _f$source,
    #servings: _f$servings,
    #serves: _f$serves,
    #times: _f$times,
    #category: _f$category,
    #tags: _f$tags,
    #background: _f$background,
    #prepNotes: _f$prepNotes,
    #ingredients: _f$ingredients,
    #steps: _f$steps,
    #subsections: _f$subsections,
    #techniques: _f$techniques,
    #images: _f$images,
    #notes: _f$notes,
    #extraction: _f$extraction,
  };

  static Recipe _instantiate(DecodingData data) {
    return Recipe(
      schemaVersion: data.dec(_f$schemaVersion),
      id: data.dec(_f$id),
      title: data.dec(_f$title),
      slug: data.dec(_f$slug),
      source: data.dec(_f$source),
      servings: data.dec(_f$servings),
      serves: data.dec(_f$serves),
      times: data.dec(_f$times),
      category: data.dec(_f$category),
      tags: data.dec(_f$tags),
      background: data.dec(_f$background),
      prepNotes: data.dec(_f$prepNotes),
      ingredients: data.dec(_f$ingredients),
      steps: data.dec(_f$steps),
      subsections: data.dec(_f$subsections),
      techniques: data.dec(_f$techniques),
      images: data.dec(_f$images),
      notes: data.dec(_f$notes),
      extraction: data.dec(_f$extraction),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static Recipe fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<Recipe>(map);
  }

  static Recipe fromJson(String json) {
    return ensureInitialized().decodeJson<Recipe>(json);
  }
}

mixin RecipeMappable {
  String toJson() {
    return RecipeMapper.ensureInitialized().encodeJson<Recipe>(this as Recipe);
  }

  Map<String, dynamic> toMap() {
    return RecipeMapper.ensureInitialized().encodeMap<Recipe>(this as Recipe);
  }

  RecipeCopyWith<Recipe, Recipe, Recipe> get copyWith =>
      _RecipeCopyWithImpl<Recipe, Recipe>(this as Recipe, $identity, $identity);
  @override
  String toString() {
    return RecipeMapper.ensureInitialized().stringifyValue(this as Recipe);
  }

  @override
  bool operator ==(Object other) {
    return RecipeMapper.ensureInitialized().equalsValue(this as Recipe, other);
  }

  @override
  int get hashCode {
    return RecipeMapper.ensureInitialized().hashValue(this as Recipe);
  }
}

extension RecipeValueCopy<$R, $Out> on ObjectCopyWith<$R, Recipe, $Out> {
  RecipeCopyWith<$R, Recipe, $Out> get $asRecipe =>
      $base.as((v, t, t2) => _RecipeCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class RecipeCopyWith<$R, $In extends Recipe, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  RecipeSourceCopyWith<$R, RecipeSource, RecipeSource> get source;
  ServesCopyWith<$R, Serves, Serves>? get serves;
  RecipeTimesCopyWith<$R, RecipeTimes, RecipeTimes> get times;
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get tags;
  ListCopyWith<
    $R,
    IngredientGroup,
    IngredientGroupCopyWith<$R, IngredientGroup, IngredientGroup>
  >
  get ingredients;
  ListCopyWith<$R, RecipeStep, RecipeStepCopyWith<$R, RecipeStep, RecipeStep>>
  get steps;
  ListCopyWith<$R, Subsection, SubsectionCopyWith<$R, Subsection, Subsection>>
  get subsections;
  ListCopyWith<$R, Technique, TechniqueCopyWith<$R, Technique, Technique>>
  get techniques;
  RecipeImagesCopyWith<$R, RecipeImages, RecipeImages> get images;
  ExtractionCopyWith<$R, Extraction, Extraction>? get extraction;
  $R call({
    int? schemaVersion,
    String? id,
    String? title,
    String? slug,
    RecipeSource? source,
    String? servings,
    Serves? serves,
    RecipeTimes? times,
    String? category,
    List<String>? tags,
    String? background,
    String? prepNotes,
    List<IngredientGroup>? ingredients,
    List<RecipeStep>? steps,
    List<Subsection>? subsections,
    List<Technique>? techniques,
    RecipeImages? images,
    String? notes,
    Extraction? extraction,
  });
  RecipeCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _RecipeCopyWithImpl<$R, $Out> extends ClassCopyWithBase<$R, Recipe, $Out>
    implements RecipeCopyWith<$R, Recipe, $Out> {
  _RecipeCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<Recipe> $mapper = RecipeMapper.ensureInitialized();
  @override
  RecipeSourceCopyWith<$R, RecipeSource, RecipeSource> get source =>
      $value.source.copyWith.$chain((v) => call(source: v));
  @override
  ServesCopyWith<$R, Serves, Serves>? get serves =>
      $value.serves?.copyWith.$chain((v) => call(serves: v));
  @override
  RecipeTimesCopyWith<$R, RecipeTimes, RecipeTimes> get times =>
      $value.times.copyWith.$chain((v) => call(times: v));
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get tags =>
      ListCopyWith(
        $value.tags,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(tags: v),
      );
  @override
  ListCopyWith<
    $R,
    IngredientGroup,
    IngredientGroupCopyWith<$R, IngredientGroup, IngredientGroup>
  >
  get ingredients => ListCopyWith(
    $value.ingredients,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(ingredients: v),
  );
  @override
  ListCopyWith<$R, RecipeStep, RecipeStepCopyWith<$R, RecipeStep, RecipeStep>>
  get steps => ListCopyWith(
    $value.steps,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(steps: v),
  );
  @override
  ListCopyWith<$R, Subsection, SubsectionCopyWith<$R, Subsection, Subsection>>
  get subsections => ListCopyWith(
    $value.subsections,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(subsections: v),
  );
  @override
  ListCopyWith<$R, Technique, TechniqueCopyWith<$R, Technique, Technique>>
  get techniques => ListCopyWith(
    $value.techniques,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(techniques: v),
  );
  @override
  RecipeImagesCopyWith<$R, RecipeImages, RecipeImages> get images =>
      $value.images.copyWith.$chain((v) => call(images: v));
  @override
  ExtractionCopyWith<$R, Extraction, Extraction>? get extraction =>
      $value.extraction?.copyWith.$chain((v) => call(extraction: v));
  @override
  $R call({
    int? schemaVersion,
    String? id,
    String? title,
    String? slug,
    RecipeSource? source,
    Object? servings = $none,
    Object? serves = $none,
    RecipeTimes? times,
    Object? category = $none,
    List<String>? tags,
    Object? background = $none,
    Object? prepNotes = $none,
    List<IngredientGroup>? ingredients,
    List<RecipeStep>? steps,
    List<Subsection>? subsections,
    List<Technique>? techniques,
    RecipeImages? images,
    Object? notes = $none,
    Object? extraction = $none,
  }) => $apply(
    FieldCopyWithData({
      if (schemaVersion != null) #schemaVersion: schemaVersion,
      if (id != null) #id: id,
      if (title != null) #title: title,
      if (slug != null) #slug: slug,
      if (source != null) #source: source,
      if (servings != $none) #servings: servings,
      if (serves != $none) #serves: serves,
      if (times != null) #times: times,
      if (category != $none) #category: category,
      if (tags != null) #tags: tags,
      if (background != $none) #background: background,
      if (prepNotes != $none) #prepNotes: prepNotes,
      if (ingredients != null) #ingredients: ingredients,
      if (steps != null) #steps: steps,
      if (subsections != null) #subsections: subsections,
      if (techniques != null) #techniques: techniques,
      if (images != null) #images: images,
      if (notes != $none) #notes: notes,
      if (extraction != $none) #extraction: extraction,
    }),
  );
  @override
  Recipe $make(CopyWithData data) => Recipe(
    schemaVersion: data.get(#schemaVersion, or: $value.schemaVersion),
    id: data.get(#id, or: $value.id),
    title: data.get(#title, or: $value.title),
    slug: data.get(#slug, or: $value.slug),
    source: data.get(#source, or: $value.source),
    servings: data.get(#servings, or: $value.servings),
    serves: data.get(#serves, or: $value.serves),
    times: data.get(#times, or: $value.times),
    category: data.get(#category, or: $value.category),
    tags: data.get(#tags, or: $value.tags),
    background: data.get(#background, or: $value.background),
    prepNotes: data.get(#prepNotes, or: $value.prepNotes),
    ingredients: data.get(#ingredients, or: $value.ingredients),
    steps: data.get(#steps, or: $value.steps),
    subsections: data.get(#subsections, or: $value.subsections),
    techniques: data.get(#techniques, or: $value.techniques),
    images: data.get(#images, or: $value.images),
    notes: data.get(#notes, or: $value.notes),
    extraction: data.get(#extraction, or: $value.extraction),
  );

  @override
  RecipeCopyWith<$R2, Recipe, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _RecipeCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

