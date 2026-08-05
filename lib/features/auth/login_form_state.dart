import 'package:flutter/foundation.dart';

/// Transient state of the login form.
///
/// Deliberately does not hold the typed credentials — those live in the
/// screen's `TextEditingController`s, so a rebuild of this state never
/// round-trips the user's password through provider state.
@immutable
class LoginFormState {
  const LoginFormState({this.busy = false, this.error});

  /// True while a homeserver check or login request is in flight.
  final bool busy;

  /// User-facing failure message, already translated from the SDK's exception.
  final String? error;

  LoginFormState copyWith({bool? busy, String? error, bool clearError = false}) =>
      LoginFormState(
        busy: busy ?? this.busy,
        error: clearError ? null : (error ?? this.error),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LoginFormState && busy == other.busy && error == other.error;

  @override
  int get hashCode => Object.hash(busy, error);
}
