part of 'home_bloc.dart';

abstract class HomeState extends Equatable {
  const HomeState();
}

class HomeInitial extends HomeState {
  @override
  List<Object> get props => [];
}

class HomeInProgress extends HomeState {
  final List<Recipe> recipes;

  HomeInProgress({
    required this.recipes,
  });

  @override
  List<Object?> get props => [recipes];
}

class HomeSuccess extends HomeState {
  final List<Recipe> recipes;

  HomeSuccess({required this.recipes});

  @override
  List<Object?> get props => [recipes];
}

class HomeFailure extends HomeState {
  @override
  List<Object?> get props => [];
}
