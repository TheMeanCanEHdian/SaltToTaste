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

