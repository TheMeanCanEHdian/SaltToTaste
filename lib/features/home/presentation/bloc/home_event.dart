part of 'home_bloc.dart';

abstract class HomeEvent extends Equatable {
  const HomeEvent();
}

class HomeFetchRecipes extends HomeEvent {
  @override
  List<Object?> get props => [];
}
