// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'dto.dart';

class PagedMapper extends ClassMapperBase<Paged> {
  PagedMapper._();

  static PagedMapper? _instance;
  static PagedMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = PagedMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'Paged';
  @override
  Function get typeFactory =>
      <T>(f) => f<Paged<T>>();

  static List<dynamic> _$items(Paged v) => v.items;
  static dynamic _arg$items<T>(f) => f<List<T>>();
  static const Field<Paged, List<dynamic>> _f$items = Field(
    'items',
    _$items,
    arg: _arg$items,
  );
  static int _$total(Paged v) => v.total;
  static const Field<Paged, int> _f$total = Field('total', _$total);
  static int _$page(Paged v) => v.page;
  static const Field<Paged, int> _f$page = Field('page', _$page);
  static int _$limit(Paged v) => v.limit;
  static const Field<Paged, int> _f$limit = Field('limit', _$limit);

  @override
  final MappableFields<Paged> fields = const {
    #items: _f$items,
    #total: _f$total,
    #page: _f$page,
    #limit: _f$limit,
  };

  static Paged<T> _instantiate<T>(DecodingData data) {
    return Paged(
      items: data.dec(_f$items),
      total: data.dec(_f$total),
      page: data.dec(_f$page),
      limit: data.dec(_f$limit),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static Paged<T> fromMap<T>(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<Paged<T>>(map);
  }

  static Paged<T> fromJson<T>(String json) {
    return ensureInitialized().decodeJson<Paged<T>>(json);
  }
}

mixin PagedMappable<T> {
  String toJson() {
    return PagedMapper.ensureInitialized().encodeJson<Paged<T>>(
      this as Paged<T>,
    );
  }

  Map<String, dynamic> toMap() {
    return PagedMapper.ensureInitialized().encodeMap<Paged<T>>(
      this as Paged<T>,
    );
  }

  PagedCopyWith<Paged<T>, Paged<T>, Paged<T>, T> get copyWith =>
      _PagedCopyWithImpl<Paged<T>, Paged<T>, T>(
        this as Paged<T>,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return PagedMapper.ensureInitialized().stringifyValue(this as Paged<T>);
  }

  @override
  bool operator ==(Object other) {
    return PagedMapper.ensureInitialized().equalsValue(this as Paged<T>, other);
  }

  @override
  int get hashCode {
    return PagedMapper.ensureInitialized().hashValue(this as Paged<T>);
  }
}

extension PagedValueCopy<$R, $Out, T> on ObjectCopyWith<$R, Paged<T>, $Out> {
  PagedCopyWith<$R, Paged<T>, $Out, T> get $asPaged =>
      $base.as((v, t, t2) => _PagedCopyWithImpl<$R, $Out, T>(v, t, t2));
}

abstract class PagedCopyWith<$R, $In extends Paged<T>, $Out, T>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, T, ObjectCopyWith<$R, T, T>?> get items;
  $R call({List<T>? items, int? total, int? page, int? limit});
  PagedCopyWith<$R2, $In, $Out2, T> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _PagedCopyWithImpl<$R, $Out, T>
    extends ClassCopyWithBase<$R, Paged<T>, $Out>
    implements PagedCopyWith<$R, Paged<T>, $Out, T> {
  _PagedCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<Paged> $mapper = PagedMapper.ensureInitialized();
  @override
  ListCopyWith<$R, T, ObjectCopyWith<$R, T, T>?> get items => ListCopyWith(
    $value.items,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(items: v),
  );
  @override
  $R call({List<T>? items, int? total, int? page, int? limit}) => $apply(
    FieldCopyWithData({
      if (items != null) #items: items,
      if (total != null) #total: total,
      if (page != null) #page: page,
      if (limit != null) #limit: limit,
    }),
  );
  @override
  Paged<T> $make(CopyWithData data) => Paged(
    items: data.get(#items, or: $value.items),
    total: data.get(#total, or: $value.total),
    page: data.get(#page, or: $value.page),
    limit: data.get(#limit, or: $value.limit),
  );

  @override
  PagedCopyWith<$R2, Paged<T>, $Out2, T> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _PagedCopyWithImpl<$R2, $Out2, T>($value, $cast, t);
}

class RecipeCardMapper extends ClassMapperBase<RecipeCard> {
  RecipeCardMapper._();

  static RecipeCardMapper? _instance;
  static RecipeCardMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RecipeCardMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'RecipeCard';

  static String _$id(RecipeCard v) => v.id;
  static const Field<RecipeCard, String> _f$id = Field('id', _$id);
  static String _$slug(RecipeCard v) => v.slug;
  static const Field<RecipeCard, String> _f$slug = Field('slug', _$slug);
  static String _$title(RecipeCard v) => v.title;
  static const Field<RecipeCard, String> _f$title = Field('title', _$title);
  static String? _$category(RecipeCard v) => v.category;
  static const Field<RecipeCard, String> _f$category = Field(
    'category',
    _$category,
    opt: true,
  );
  static String? _$heroImage(RecipeCard v) => v.heroImage;
  static const Field<RecipeCard, String> _f$heroImage = Field(
    'heroImage',
    _$heroImage,
    key: r'hero_image',
    opt: true,
  );
  static List<String> _$tags(RecipeCard v) => v.tags;
  static const Field<RecipeCard, List<String>> _f$tags = Field(
    'tags',
    _$tags,
    opt: true,
    def: const [],
  );
  static String? _$servingsText(RecipeCard v) => v.servingsText;
  static const Field<RecipeCard, String> _f$servingsText = Field(
    'servingsText',
    _$servingsText,
    key: r'servings_text',
    opt: true,
  );
  static int? _$totalMinutes(RecipeCard v) => v.totalMinutes;
  static const Field<RecipeCard, int> _f$totalMinutes = Field(
    'totalMinutes',
    _$totalMinutes,
    key: r'total_minutes',
    opt: true,
  );
  static double? _$caloriesPerServing(RecipeCard v) => v.caloriesPerServing;
  static const Field<RecipeCard, double> _f$caloriesPerServing = Field(
    'caloriesPerServing',
    _$caloriesPerServing,
    key: r'calories_per_serving',
    opt: true,
  );
  static bool _$favorite(RecipeCard v) => v.favorite;
  static const Field<RecipeCard, bool> _f$favorite = Field(
    'favorite',
    _$favorite,
    opt: true,
    def: false,
  );
  static int _$variationCount(RecipeCard v) => v.variationCount;
  static const Field<RecipeCard, int> _f$variationCount = Field(
    'variationCount',
    _$variationCount,
    key: r'variation_count',
    opt: true,
    def: 0,
  );

  @override
  final MappableFields<RecipeCard> fields = const {
    #id: _f$id,
    #slug: _f$slug,
    #title: _f$title,
    #category: _f$category,
    #heroImage: _f$heroImage,
    #tags: _f$tags,
    #servingsText: _f$servingsText,
    #totalMinutes: _f$totalMinutes,
    #caloriesPerServing: _f$caloriesPerServing,
    #favorite: _f$favorite,
    #variationCount: _f$variationCount,
  };

  static RecipeCard _instantiate(DecodingData data) {
    return RecipeCard(
      id: data.dec(_f$id),
      slug: data.dec(_f$slug),
      title: data.dec(_f$title),
      category: data.dec(_f$category),
      heroImage: data.dec(_f$heroImage),
      tags: data.dec(_f$tags),
      servingsText: data.dec(_f$servingsText),
      totalMinutes: data.dec(_f$totalMinutes),
      caloriesPerServing: data.dec(_f$caloriesPerServing),
      favorite: data.dec(_f$favorite),
      variationCount: data.dec(_f$variationCount),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static RecipeCard fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RecipeCard>(map);
  }

  static RecipeCard fromJson(String json) {
    return ensureInitialized().decodeJson<RecipeCard>(json);
  }
}

mixin RecipeCardMappable {
  String toJson() {
    return RecipeCardMapper.ensureInitialized().encodeJson<RecipeCard>(
      this as RecipeCard,
    );
  }

  Map<String, dynamic> toMap() {
    return RecipeCardMapper.ensureInitialized().encodeMap<RecipeCard>(
      this as RecipeCard,
    );
  }

  RecipeCardCopyWith<RecipeCard, RecipeCard, RecipeCard> get copyWith =>
      _RecipeCardCopyWithImpl<RecipeCard, RecipeCard>(
        this as RecipeCard,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return RecipeCardMapper.ensureInitialized().stringifyValue(
      this as RecipeCard,
    );
  }

  @override
  bool operator ==(Object other) {
    return RecipeCardMapper.ensureInitialized().equalsValue(
      this as RecipeCard,
      other,
    );
  }

  @override
  int get hashCode {
    return RecipeCardMapper.ensureInitialized().hashValue(this as RecipeCard);
  }
}

extension RecipeCardValueCopy<$R, $Out>
    on ObjectCopyWith<$R, RecipeCard, $Out> {
  RecipeCardCopyWith<$R, RecipeCard, $Out> get $asRecipeCard =>
      $base.as((v, t, t2) => _RecipeCardCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class RecipeCardCopyWith<$R, $In extends RecipeCard, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get tags;
  $R call({
    String? id,
    String? slug,
    String? title,
    String? category,
    String? heroImage,
    List<String>? tags,
    String? servingsText,
    int? totalMinutes,
    double? caloriesPerServing,
    bool? favorite,
    int? variationCount,
  });
  RecipeCardCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _RecipeCardCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, RecipeCard, $Out>
    implements RecipeCardCopyWith<$R, RecipeCard, $Out> {
  _RecipeCardCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<RecipeCard> $mapper =
      RecipeCardMapper.ensureInitialized();
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get tags =>
      ListCopyWith(
        $value.tags,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(tags: v),
      );
  @override
  $R call({
    String? id,
    String? slug,
    String? title,
    Object? category = $none,
    Object? heroImage = $none,
    List<String>? tags,
    Object? servingsText = $none,
    Object? totalMinutes = $none,
    Object? caloriesPerServing = $none,
    bool? favorite,
    int? variationCount,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (slug != null) #slug: slug,
      if (title != null) #title: title,
      if (category != $none) #category: category,
      if (heroImage != $none) #heroImage: heroImage,
      if (tags != null) #tags: tags,
      if (servingsText != $none) #servingsText: servingsText,
      if (totalMinutes != $none) #totalMinutes: totalMinutes,
      if (caloriesPerServing != $none) #caloriesPerServing: caloriesPerServing,
      if (favorite != null) #favorite: favorite,
      if (variationCount != null) #variationCount: variationCount,
    }),
  );
  @override
  RecipeCard $make(CopyWithData data) => RecipeCard(
    id: data.get(#id, or: $value.id),
    slug: data.get(#slug, or: $value.slug),
    title: data.get(#title, or: $value.title),
    category: data.get(#category, or: $value.category),
    heroImage: data.get(#heroImage, or: $value.heroImage),
    tags: data.get(#tags, or: $value.tags),
    servingsText: data.get(#servingsText, or: $value.servingsText),
    totalMinutes: data.get(#totalMinutes, or: $value.totalMinutes),
    caloriesPerServing: data.get(
      #caloriesPerServing,
      or: $value.caloriesPerServing,
    ),
    favorite: data.get(#favorite, or: $value.favorite),
    variationCount: data.get(#variationCount, or: $value.variationCount),
  );

  @override
  RecipeCardCopyWith<$R2, RecipeCard, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _RecipeCardCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class RecipeReviewReportMapper extends ClassMapperBase<RecipeReviewReport> {
  RecipeReviewReportMapper._();

  static RecipeReviewReportMapper? _instance;
  static RecipeReviewReportMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RecipeReviewReportMapper._());
      RecipeReviewCategoryMapper.ensureInitialized();
      RecipeReviewItemMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'RecipeReviewReport';

  static int _$total(RecipeReviewReport v) => v.total;
  static const Field<RecipeReviewReport, int> _f$total = Field(
    'total',
    _$total,
  );
  static List<RecipeReviewCategory> _$categories(RecipeReviewReport v) =>
      v.categories;
  static const Field<RecipeReviewReport, List<RecipeReviewCategory>>
  _f$categories = Field('categories', _$categories);
  static List<RecipeReviewItem> _$items(RecipeReviewReport v) => v.items;
  static const Field<RecipeReviewReport, List<RecipeReviewItem>> _f$items =
      Field('items', _$items);
  static int _$page(RecipeReviewReport v) => v.page;
  static const Field<RecipeReviewReport, int> _f$page = Field('page', _$page);
  static int _$limit(RecipeReviewReport v) => v.limit;
  static const Field<RecipeReviewReport, int> _f$limit = Field(
    'limit',
    _$limit,
  );

  @override
  final MappableFields<RecipeReviewReport> fields = const {
    #total: _f$total,
    #categories: _f$categories,
    #items: _f$items,
    #page: _f$page,
    #limit: _f$limit,
  };

  static RecipeReviewReport _instantiate(DecodingData data) {
    return RecipeReviewReport(
      total: data.dec(_f$total),
      categories: data.dec(_f$categories),
      items: data.dec(_f$items),
      page: data.dec(_f$page),
      limit: data.dec(_f$limit),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static RecipeReviewReport fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RecipeReviewReport>(map);
  }

  static RecipeReviewReport fromJson(String json) {
    return ensureInitialized().decodeJson<RecipeReviewReport>(json);
  }
}

mixin RecipeReviewReportMappable {
  String toJson() {
    return RecipeReviewReportMapper.ensureInitialized()
        .encodeJson<RecipeReviewReport>(this as RecipeReviewReport);
  }

  Map<String, dynamic> toMap() {
    return RecipeReviewReportMapper.ensureInitialized()
        .encodeMap<RecipeReviewReport>(this as RecipeReviewReport);
  }

  RecipeReviewReportCopyWith<
    RecipeReviewReport,
    RecipeReviewReport,
    RecipeReviewReport
  >
  get copyWith =>
      _RecipeReviewReportCopyWithImpl<RecipeReviewReport, RecipeReviewReport>(
        this as RecipeReviewReport,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return RecipeReviewReportMapper.ensureInitialized().stringifyValue(
      this as RecipeReviewReport,
    );
  }

  @override
  bool operator ==(Object other) {
    return RecipeReviewReportMapper.ensureInitialized().equalsValue(
      this as RecipeReviewReport,
      other,
    );
  }

  @override
  int get hashCode {
    return RecipeReviewReportMapper.ensureInitialized().hashValue(
      this as RecipeReviewReport,
    );
  }
}

extension RecipeReviewReportValueCopy<$R, $Out>
    on ObjectCopyWith<$R, RecipeReviewReport, $Out> {
  RecipeReviewReportCopyWith<$R, RecipeReviewReport, $Out>
  get $asRecipeReviewReport => $base.as(
    (v, t, t2) => _RecipeReviewReportCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class RecipeReviewReportCopyWith<
  $R,
  $In extends RecipeReviewReport,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<
    $R,
    RecipeReviewCategory,
    RecipeReviewCategoryCopyWith<$R, RecipeReviewCategory, RecipeReviewCategory>
  >
  get categories;
  ListCopyWith<
    $R,
    RecipeReviewItem,
    RecipeReviewItemCopyWith<$R, RecipeReviewItem, RecipeReviewItem>
  >
  get items;
  $R call({
    int? total,
    List<RecipeReviewCategory>? categories,
    List<RecipeReviewItem>? items,
    int? page,
    int? limit,
  });
  RecipeReviewReportCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _RecipeReviewReportCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, RecipeReviewReport, $Out>
    implements RecipeReviewReportCopyWith<$R, RecipeReviewReport, $Out> {
  _RecipeReviewReportCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<RecipeReviewReport> $mapper =
      RecipeReviewReportMapper.ensureInitialized();
  @override
  ListCopyWith<
    $R,
    RecipeReviewCategory,
    RecipeReviewCategoryCopyWith<$R, RecipeReviewCategory, RecipeReviewCategory>
  >
  get categories => ListCopyWith(
    $value.categories,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(categories: v),
  );
  @override
  ListCopyWith<
    $R,
    RecipeReviewItem,
    RecipeReviewItemCopyWith<$R, RecipeReviewItem, RecipeReviewItem>
  >
  get items => ListCopyWith(
    $value.items,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(items: v),
  );
  @override
  $R call({
    int? total,
    List<RecipeReviewCategory>? categories,
    List<RecipeReviewItem>? items,
    int? page,
    int? limit,
  }) => $apply(
    FieldCopyWithData({
      if (total != null) #total: total,
      if (categories != null) #categories: categories,
      if (items != null) #items: items,
      if (page != null) #page: page,
      if (limit != null) #limit: limit,
    }),
  );
  @override
  RecipeReviewReport $make(CopyWithData data) => RecipeReviewReport(
    total: data.get(#total, or: $value.total),
    categories: data.get(#categories, or: $value.categories),
    items: data.get(#items, or: $value.items),
    page: data.get(#page, or: $value.page),
    limit: data.get(#limit, or: $value.limit),
  );

  @override
  RecipeReviewReportCopyWith<$R2, RecipeReviewReport, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _RecipeReviewReportCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class RecipeReviewCategoryMapper extends ClassMapperBase<RecipeReviewCategory> {
  RecipeReviewCategoryMapper._();

  static RecipeReviewCategoryMapper? _instance;
  static RecipeReviewCategoryMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RecipeReviewCategoryMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'RecipeReviewCategory';

  static String _$id(RecipeReviewCategory v) => v.id;
  static const Field<RecipeReviewCategory, String> _f$id = Field('id', _$id);
  static String _$label(RecipeReviewCategory v) => v.label;
  static const Field<RecipeReviewCategory, String> _f$label = Field(
    'label',
    _$label,
  );
  static String _$description(RecipeReviewCategory v) => v.description;
  static const Field<RecipeReviewCategory, String> _f$description = Field(
    'description',
    _$description,
  );
  static int _$count(RecipeReviewCategory v) => v.count;
  static const Field<RecipeReviewCategory, int> _f$count = Field(
    'count',
    _$count,
  );

  @override
  final MappableFields<RecipeReviewCategory> fields = const {
    #id: _f$id,
    #label: _f$label,
    #description: _f$description,
    #count: _f$count,
  };

  static RecipeReviewCategory _instantiate(DecodingData data) {
    return RecipeReviewCategory(
      id: data.dec(_f$id),
      label: data.dec(_f$label),
      description: data.dec(_f$description),
      count: data.dec(_f$count),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static RecipeReviewCategory fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RecipeReviewCategory>(map);
  }

  static RecipeReviewCategory fromJson(String json) {
    return ensureInitialized().decodeJson<RecipeReviewCategory>(json);
  }
}

mixin RecipeReviewCategoryMappable {
  String toJson() {
    return RecipeReviewCategoryMapper.ensureInitialized()
        .encodeJson<RecipeReviewCategory>(this as RecipeReviewCategory);
  }

  Map<String, dynamic> toMap() {
    return RecipeReviewCategoryMapper.ensureInitialized()
        .encodeMap<RecipeReviewCategory>(this as RecipeReviewCategory);
  }

  RecipeReviewCategoryCopyWith<
    RecipeReviewCategory,
    RecipeReviewCategory,
    RecipeReviewCategory
  >
  get copyWith =>
      _RecipeReviewCategoryCopyWithImpl<
        RecipeReviewCategory,
        RecipeReviewCategory
      >(this as RecipeReviewCategory, $identity, $identity);
  @override
  String toString() {
    return RecipeReviewCategoryMapper.ensureInitialized().stringifyValue(
      this as RecipeReviewCategory,
    );
  }

  @override
  bool operator ==(Object other) {
    return RecipeReviewCategoryMapper.ensureInitialized().equalsValue(
      this as RecipeReviewCategory,
      other,
    );
  }

  @override
  int get hashCode {
    return RecipeReviewCategoryMapper.ensureInitialized().hashValue(
      this as RecipeReviewCategory,
    );
  }
}

extension RecipeReviewCategoryValueCopy<$R, $Out>
    on ObjectCopyWith<$R, RecipeReviewCategory, $Out> {
  RecipeReviewCategoryCopyWith<$R, RecipeReviewCategory, $Out>
  get $asRecipeReviewCategory => $base.as(
    (v, t, t2) => _RecipeReviewCategoryCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class RecipeReviewCategoryCopyWith<
  $R,
  $In extends RecipeReviewCategory,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? id, String? label, String? description, int? count});
  RecipeReviewCategoryCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _RecipeReviewCategoryCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, RecipeReviewCategory, $Out>
    implements RecipeReviewCategoryCopyWith<$R, RecipeReviewCategory, $Out> {
  _RecipeReviewCategoryCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<RecipeReviewCategory> $mapper =
      RecipeReviewCategoryMapper.ensureInitialized();
  @override
  $R call({String? id, String? label, String? description, int? count}) =>
      $apply(
        FieldCopyWithData({
          if (id != null) #id: id,
          if (label != null) #label: label,
          if (description != null) #description: description,
          if (count != null) #count: count,
        }),
      );
  @override
  RecipeReviewCategory $make(CopyWithData data) => RecipeReviewCategory(
    id: data.get(#id, or: $value.id),
    label: data.get(#label, or: $value.label),
    description: data.get(#description, or: $value.description),
    count: data.get(#count, or: $value.count),
  );

  @override
  RecipeReviewCategoryCopyWith<$R2, RecipeReviewCategory, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _RecipeReviewCategoryCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class RecipeReviewItemMapper extends ClassMapperBase<RecipeReviewItem> {
  RecipeReviewItemMapper._();

  static RecipeReviewItemMapper? _instance;
  static RecipeReviewItemMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RecipeReviewItemMapper._());
      RecipeReviewIssueMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'RecipeReviewItem';

  static String _$id(RecipeReviewItem v) => v.id;
  static const Field<RecipeReviewItem, String> _f$id = Field('id', _$id);
  static String _$slug(RecipeReviewItem v) => v.slug;
  static const Field<RecipeReviewItem, String> _f$slug = Field('slug', _$slug);
  static String _$title(RecipeReviewItem v) => v.title;
  static const Field<RecipeReviewItem, String> _f$title = Field(
    'title',
    _$title,
  );
  static String _$source(RecipeReviewItem v) => v.source;
  static const Field<RecipeReviewItem, String> _f$source = Field(
    'source',
    _$source,
  );
  static List<RecipeReviewIssue> _$issues(RecipeReviewItem v) => v.issues;
  static const Field<RecipeReviewItem, List<RecipeReviewIssue>> _f$issues =
      Field('issues', _$issues);

  @override
  final MappableFields<RecipeReviewItem> fields = const {
    #id: _f$id,
    #slug: _f$slug,
    #title: _f$title,
    #source: _f$source,
    #issues: _f$issues,
  };

  static RecipeReviewItem _instantiate(DecodingData data) {
    return RecipeReviewItem(
      id: data.dec(_f$id),
      slug: data.dec(_f$slug),
      title: data.dec(_f$title),
      source: data.dec(_f$source),
      issues: data.dec(_f$issues),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static RecipeReviewItem fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RecipeReviewItem>(map);
  }

  static RecipeReviewItem fromJson(String json) {
    return ensureInitialized().decodeJson<RecipeReviewItem>(json);
  }
}

mixin RecipeReviewItemMappable {
  String toJson() {
    return RecipeReviewItemMapper.ensureInitialized()
        .encodeJson<RecipeReviewItem>(this as RecipeReviewItem);
  }

  Map<String, dynamic> toMap() {
    return RecipeReviewItemMapper.ensureInitialized()
        .encodeMap<RecipeReviewItem>(this as RecipeReviewItem);
  }

  RecipeReviewItemCopyWith<RecipeReviewItem, RecipeReviewItem, RecipeReviewItem>
  get copyWith =>
      _RecipeReviewItemCopyWithImpl<RecipeReviewItem, RecipeReviewItem>(
        this as RecipeReviewItem,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return RecipeReviewItemMapper.ensureInitialized().stringifyValue(
      this as RecipeReviewItem,
    );
  }

  @override
  bool operator ==(Object other) {
    return RecipeReviewItemMapper.ensureInitialized().equalsValue(
      this as RecipeReviewItem,
      other,
    );
  }

  @override
  int get hashCode {
    return RecipeReviewItemMapper.ensureInitialized().hashValue(
      this as RecipeReviewItem,
    );
  }
}

extension RecipeReviewItemValueCopy<$R, $Out>
    on ObjectCopyWith<$R, RecipeReviewItem, $Out> {
  RecipeReviewItemCopyWith<$R, RecipeReviewItem, $Out>
  get $asRecipeReviewItem =>
      $base.as((v, t, t2) => _RecipeReviewItemCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class RecipeReviewItemCopyWith<$R, $In extends RecipeReviewItem, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<
    $R,
    RecipeReviewIssue,
    RecipeReviewIssueCopyWith<$R, RecipeReviewIssue, RecipeReviewIssue>
  >
  get issues;
  $R call({
    String? id,
    String? slug,
    String? title,
    String? source,
    List<RecipeReviewIssue>? issues,
  });
  RecipeReviewItemCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _RecipeReviewItemCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, RecipeReviewItem, $Out>
    implements RecipeReviewItemCopyWith<$R, RecipeReviewItem, $Out> {
  _RecipeReviewItemCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<RecipeReviewItem> $mapper =
      RecipeReviewItemMapper.ensureInitialized();
  @override
  ListCopyWith<
    $R,
    RecipeReviewIssue,
    RecipeReviewIssueCopyWith<$R, RecipeReviewIssue, RecipeReviewIssue>
  >
  get issues => ListCopyWith(
    $value.issues,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(issues: v),
  );
  @override
  $R call({
    String? id,
    String? slug,
    String? title,
    String? source,
    List<RecipeReviewIssue>? issues,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (slug != null) #slug: slug,
      if (title != null) #title: title,
      if (source != null) #source: source,
      if (issues != null) #issues: issues,
    }),
  );
  @override
  RecipeReviewItem $make(CopyWithData data) => RecipeReviewItem(
    id: data.get(#id, or: $value.id),
    slug: data.get(#slug, or: $value.slug),
    title: data.get(#title, or: $value.title),
    source: data.get(#source, or: $value.source),
    issues: data.get(#issues, or: $value.issues),
  );

  @override
  RecipeReviewItemCopyWith<$R2, RecipeReviewItem, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _RecipeReviewItemCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class RecipeReviewIssueMapper extends ClassMapperBase<RecipeReviewIssue> {
  RecipeReviewIssueMapper._();

  static RecipeReviewIssueMapper? _instance;
  static RecipeReviewIssueMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RecipeReviewIssueMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'RecipeReviewIssue';

  static String _$check(RecipeReviewIssue v) => v.check;
  static const Field<RecipeReviewIssue, String> _f$check = Field(
    'check',
    _$check,
  );
  static String _$label(RecipeReviewIssue v) => v.label;
  static const Field<RecipeReviewIssue, String> _f$label = Field(
    'label',
    _$label,
  );
  static String _$detail(RecipeReviewIssue v) => v.detail;
  static const Field<RecipeReviewIssue, String> _f$detail = Field(
    'detail',
    _$detail,
  );

  @override
  final MappableFields<RecipeReviewIssue> fields = const {
    #check: _f$check,
    #label: _f$label,
    #detail: _f$detail,
  };

  static RecipeReviewIssue _instantiate(DecodingData data) {
    return RecipeReviewIssue(
      check: data.dec(_f$check),
      label: data.dec(_f$label),
      detail: data.dec(_f$detail),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static RecipeReviewIssue fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RecipeReviewIssue>(map);
  }

  static RecipeReviewIssue fromJson(String json) {
    return ensureInitialized().decodeJson<RecipeReviewIssue>(json);
  }
}

mixin RecipeReviewIssueMappable {
  String toJson() {
    return RecipeReviewIssueMapper.ensureInitialized()
        .encodeJson<RecipeReviewIssue>(this as RecipeReviewIssue);
  }

  Map<String, dynamic> toMap() {
    return RecipeReviewIssueMapper.ensureInitialized()
        .encodeMap<RecipeReviewIssue>(this as RecipeReviewIssue);
  }

  RecipeReviewIssueCopyWith<
    RecipeReviewIssue,
    RecipeReviewIssue,
    RecipeReviewIssue
  >
  get copyWith =>
      _RecipeReviewIssueCopyWithImpl<RecipeReviewIssue, RecipeReviewIssue>(
        this as RecipeReviewIssue,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return RecipeReviewIssueMapper.ensureInitialized().stringifyValue(
      this as RecipeReviewIssue,
    );
  }

  @override
  bool operator ==(Object other) {
    return RecipeReviewIssueMapper.ensureInitialized().equalsValue(
      this as RecipeReviewIssue,
      other,
    );
  }

  @override
  int get hashCode {
    return RecipeReviewIssueMapper.ensureInitialized().hashValue(
      this as RecipeReviewIssue,
    );
  }
}

extension RecipeReviewIssueValueCopy<$R, $Out>
    on ObjectCopyWith<$R, RecipeReviewIssue, $Out> {
  RecipeReviewIssueCopyWith<$R, RecipeReviewIssue, $Out>
  get $asRecipeReviewIssue => $base.as(
    (v, t, t2) => _RecipeReviewIssueCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class RecipeReviewIssueCopyWith<
  $R,
  $In extends RecipeReviewIssue,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? check, String? label, String? detail});
  RecipeReviewIssueCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _RecipeReviewIssueCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, RecipeReviewIssue, $Out>
    implements RecipeReviewIssueCopyWith<$R, RecipeReviewIssue, $Out> {
  _RecipeReviewIssueCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<RecipeReviewIssue> $mapper =
      RecipeReviewIssueMapper.ensureInitialized();
  @override
  $R call({String? check, String? label, String? detail}) => $apply(
    FieldCopyWithData({
      if (check != null) #check: check,
      if (label != null) #label: label,
      if (detail != null) #detail: detail,
    }),
  );
  @override
  RecipeReviewIssue $make(CopyWithData data) => RecipeReviewIssue(
    check: data.get(#check, or: $value.check),
    label: data.get(#label, or: $value.label),
    detail: data.get(#detail, or: $value.detail),
  );

  @override
  RecipeReviewIssueCopyWith<$R2, RecipeReviewIssue, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _RecipeReviewIssueCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class LogEntryMapper extends ClassMapperBase<LogEntry> {
  LogEntryMapper._();

  static LogEntryMapper? _instance;
  static LogEntryMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = LogEntryMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'LogEntry';

  static String _$time(LogEntry v) => v.time;
  static const Field<LogEntry, String> _f$time = Field('time', _$time);
  static String _$level(LogEntry v) => v.level;
  static const Field<LogEntry, String> _f$level = Field('level', _$level);
  static String _$logger(LogEntry v) => v.logger;
  static const Field<LogEntry, String> _f$logger = Field('logger', _$logger);
  static String _$message(LogEntry v) => v.message;
  static const Field<LogEntry, String> _f$message = Field('message', _$message);
  static String? _$requestId(LogEntry v) => v.requestId;
  static const Field<LogEntry, String> _f$requestId = Field(
    'requestId',
    _$requestId,
    key: r'request_id',
    opt: true,
  );

  @override
  final MappableFields<LogEntry> fields = const {
    #time: _f$time,
    #level: _f$level,
    #logger: _f$logger,
    #message: _f$message,
    #requestId: _f$requestId,
  };

  static LogEntry _instantiate(DecodingData data) {
    return LogEntry(
      time: data.dec(_f$time),
      level: data.dec(_f$level),
      logger: data.dec(_f$logger),
      message: data.dec(_f$message),
      requestId: data.dec(_f$requestId),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static LogEntry fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<LogEntry>(map);
  }

  static LogEntry fromJson(String json) {
    return ensureInitialized().decodeJson<LogEntry>(json);
  }
}

mixin LogEntryMappable {
  String toJson() {
    return LogEntryMapper.ensureInitialized().encodeJson<LogEntry>(
      this as LogEntry,
    );
  }

  Map<String, dynamic> toMap() {
    return LogEntryMapper.ensureInitialized().encodeMap<LogEntry>(
      this as LogEntry,
    );
  }

  LogEntryCopyWith<LogEntry, LogEntry, LogEntry> get copyWith =>
      _LogEntryCopyWithImpl<LogEntry, LogEntry>(
        this as LogEntry,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return LogEntryMapper.ensureInitialized().stringifyValue(this as LogEntry);
  }

  @override
  bool operator ==(Object other) {
    return LogEntryMapper.ensureInitialized().equalsValue(
      this as LogEntry,
      other,
    );
  }

  @override
  int get hashCode {
    return LogEntryMapper.ensureInitialized().hashValue(this as LogEntry);
  }
}

extension LogEntryValueCopy<$R, $Out> on ObjectCopyWith<$R, LogEntry, $Out> {
  LogEntryCopyWith<$R, LogEntry, $Out> get $asLogEntry =>
      $base.as((v, t, t2) => _LogEntryCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class LogEntryCopyWith<$R, $In extends LogEntry, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? time,
    String? level,
    String? logger,
    String? message,
    String? requestId,
  });
  LogEntryCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _LogEntryCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, LogEntry, $Out>
    implements LogEntryCopyWith<$R, LogEntry, $Out> {
  _LogEntryCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<LogEntry> $mapper =
      LogEntryMapper.ensureInitialized();
  @override
  $R call({
    String? time,
    String? level,
    String? logger,
    String? message,
    Object? requestId = $none,
  }) => $apply(
    FieldCopyWithData({
      if (time != null) #time: time,
      if (level != null) #level: level,
      if (logger != null) #logger: logger,
      if (message != null) #message: message,
      if (requestId != $none) #requestId: requestId,
    }),
  );
  @override
  LogEntry $make(CopyWithData data) => LogEntry(
    time: data.get(#time, or: $value.time),
    level: data.get(#level, or: $value.level),
    logger: data.get(#logger, or: $value.logger),
    message: data.get(#message, or: $value.message),
    requestId: data.get(#requestId, or: $value.requestId),
  );

  @override
  LogEntryCopyWith<$R2, LogEntry, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _LogEntryCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class ApiErrorMapper extends ClassMapperBase<ApiError> {
  ApiErrorMapper._();

  static ApiErrorMapper? _instance;
  static ApiErrorMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ApiErrorMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'ApiError';

  static String _$code(ApiError v) => v.code;
  static const Field<ApiError, String> _f$code = Field('code', _$code);
  static String _$message(ApiError v) => v.message;
  static const Field<ApiError, String> _f$message = Field('message', _$message);
  static String? _$requestId(ApiError v) => v.requestId;
  static const Field<ApiError, String> _f$requestId = Field(
    'requestId',
    _$requestId,
    key: r'request_id',
    opt: true,
  );

  @override
  final MappableFields<ApiError> fields = const {
    #code: _f$code,
    #message: _f$message,
    #requestId: _f$requestId,
  };

  static ApiError _instantiate(DecodingData data) {
    return ApiError(
      code: data.dec(_f$code),
      message: data.dec(_f$message),
      requestId: data.dec(_f$requestId),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ApiError fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ApiError>(map);
  }

  static ApiError fromJson(String json) {
    return ensureInitialized().decodeJson<ApiError>(json);
  }
}

mixin ApiErrorMappable {
  String toJson() {
    return ApiErrorMapper.ensureInitialized().encodeJson<ApiError>(
      this as ApiError,
    );
  }

  Map<String, dynamic> toMap() {
    return ApiErrorMapper.ensureInitialized().encodeMap<ApiError>(
      this as ApiError,
    );
  }

  ApiErrorCopyWith<ApiError, ApiError, ApiError> get copyWith =>
      _ApiErrorCopyWithImpl<ApiError, ApiError>(
        this as ApiError,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return ApiErrorMapper.ensureInitialized().stringifyValue(this as ApiError);
  }

  @override
  bool operator ==(Object other) {
    return ApiErrorMapper.ensureInitialized().equalsValue(
      this as ApiError,
      other,
    );
  }

  @override
  int get hashCode {
    return ApiErrorMapper.ensureInitialized().hashValue(this as ApiError);
  }
}

extension ApiErrorValueCopy<$R, $Out> on ObjectCopyWith<$R, ApiError, $Out> {
  ApiErrorCopyWith<$R, ApiError, $Out> get $asApiError =>
      $base.as((v, t, t2) => _ApiErrorCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ApiErrorCopyWith<$R, $In extends ApiError, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? code, String? message, String? requestId});
  ApiErrorCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _ApiErrorCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ApiError, $Out>
    implements ApiErrorCopyWith<$R, ApiError, $Out> {
  _ApiErrorCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ApiError> $mapper =
      ApiErrorMapper.ensureInitialized();
  @override
  $R call({String? code, String? message, Object? requestId = $none}) => $apply(
    FieldCopyWithData({
      if (code != null) #code: code,
      if (message != null) #message: message,
      if (requestId != $none) #requestId: requestId,
    }),
  );
  @override
  ApiError $make(CopyWithData data) => ApiError(
    code: data.get(#code, or: $value.code),
    message: data.get(#message, or: $value.message),
    requestId: data.get(#requestId, or: $value.requestId),
  );

  @override
  ApiErrorCopyWith<$R2, ApiError, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ApiErrorCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

