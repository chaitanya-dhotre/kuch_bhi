/// Username rules shared by Register, Google onboarding and Edit Profile
/// (dead-code audit §3.2): one pattern, one validator, one wording.
library;
final _usernamePattern = RegExp(r'^[a-zA-Z0-9_]+$');

String? validateUsername(String? v) {
  if (v == null || v.trim().isEmpty) return 'Enter a username';
  if (v.trim().length < 3) return 'At least 3 characters';
  if (!_usernamePattern.hasMatch(v.trim())) {
    return 'Letters, numbers and underscores only';
  }
  return null;
}
