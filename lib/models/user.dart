/// Modelo de usuario que refleja el schema del backend
class User {
  final String id;
  final String email;
  final String fullName;
  final bool isActive;
  final bool isVerified;
  final String createdAt;

  User({
    required this.id,
    required this.email,
    required this.fullName,
    required this.isActive,
    this.isVerified = false,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      fullName: json['full_name']?.toString() ?? '',
      isActive: json['is_active'] as bool? ?? true,
      isVerified: json['is_verified'] as bool? ?? false,
      createdAt: json['created_at']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'full_name': fullName,
      'is_active': isActive,
      'is_verified': isVerified,
      'created_at': createdAt,
    };
  }

  User copyWith({
    String? id,
    String? email,
    String? fullName,
    bool? isActive,
    bool? isVerified,
    String? createdAt,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      isActive: isActive ?? this.isActive,
      isVerified: isVerified ?? this.isVerified,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

