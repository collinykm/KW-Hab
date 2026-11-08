import 'package:flutter/foundation.dart' show immutable;

/// How a support person prefers to be reached.
enum ContactMethod {
  phone,
  email;

  static ContactMethod? tryParse(Object? name) {
    for (final m in values) {
      if (m.name == name) return m;
    }
    return null;
  }
}

/// A support person (staff member, family member, caregiver) entered during
/// onboarding. Used for safety alerts and anything else that should reach a
/// person who helps the user.
///
/// Private: this never goes into the Facebook page (Facebook's scripts can
/// read anything there). Use it from Dart only.
@immutable
class SupportContact {
  const SupportContact({
    required this.id,
    this.name = '',
    this.phone = '',
    this.email = '',
    this.preferredMethod,
  });

  /// Stable identifier so the UI can edit/remove a specific entry.
  final String id;
  final String name;
  final String phone;
  final String email;

  /// How this person wants to be contacted (the onboarding radio buttons), or
  /// null if not chosen.
  final ContactMethod? preferredMethod;

  bool get isEmpty => name.trim().isEmpty && phone.trim().isEmpty && email.trim().isEmpty;
  bool get hasPhone => phone.trim().isNotEmpty;
  bool get hasEmail => email.trim().isNotEmpty;

  bool canUse(ContactMethod m) => switch (m) {
        ContactMethod.phone => hasPhone,
        ContactMethod.email => hasEmail,
      };

  /// The method to actually use: [preferredMethod] if its details were
  /// entered, otherwise whichever details exist (phone first). Null if this
  /// person can't be reached.
  ContactMethod? get contactMethod {
    final preferred = preferredMethod;
    if (preferred != null && canUse(preferred)) return preferred;
    for (final m in ContactMethod.values) {
      if (canUse(m)) return m;
    }
    return null;
  }

  /// Phone number or email for [method].
  String addressFor(ContactMethod method) => switch (method) {
        ContactMethod.phone => phone.trim(),
        ContactMethod.email => email.trim(),
      };

  SupportContact copyWith({
    String? name,
    String? phone,
    String? email,
    ContactMethod? preferredMethod,
  }) =>
      SupportContact(
        id: id,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        preferredMethod: preferredMethod ?? this.preferredMethod,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'email': email,
        'preferredMethod': preferredMethod?.name,
      };

  /// Returns null for entries that aren't a JSON object.
  static SupportContact? fromJson(Object? json) {
    if (json is! Map) return null;
    String str(Object? v) => v is String ? v : '';
    // Early builds saved a list ("preferredMethods"); take its first entry.
    final legacy = json['preferredMethods'];
    return SupportContact(
      id: str(json['id']).isEmpty ? newId() : str(json['id']),
      name: str(json['name']),
      phone: str(json['phone']),
      email: str(json['email']),
      preferredMethod: ContactMethod.tryParse(json['preferredMethod']) ??
          (legacy is List && legacy.isNotEmpty ? ContactMethod.tryParse(legacy.first) : null),
    );
  }

  static int _counter = 0;
  static String newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${(_counter++).toRadixString(36)}';

  @override
  bool operator ==(Object other) =>
      other is SupportContact &&
      other.id == id &&
      other.name == name &&
      other.phone == phone &&
      other.email == email &&
      other.preferredMethod == preferredMethod;

  @override
  int get hashCode => Object.hash(id, name, phone, email, preferredMethod);
}
