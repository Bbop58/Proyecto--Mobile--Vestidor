/// Modelo de usuario que refleja el schema del backend
class User {
  final String accessScope;
  final bool isPlatformAdmin;
  bool get canUseMobile => accessScope=='COMPANY' && !isPlatformAdmin;
  final bool serviceRestricted;
  final Map<String,bool> subscriptionCapabilities;
  final List<String> permissions;
  bool hasPermission(String code) => permissions.contains(code);
  bool get canViewVoiceReports => canUseMobile && !serviceRestricted &&
      hasPermission('ventas.reports') && subscriptionCapabilities['reportes_ia'] == true;
  final String id;
  final String? tenantId;
  final String email;
  final String fullName;
  final bool isActive;
  final bool isVerified;
  final String createdAt;

  User({
    required this.id,
    this.accessScope='COMPANY',
    this.isPlatformAdmin=false,
    this.serviceRestricted=false,
    this.subscriptionCapabilities=const {},
    this.permissions=const [],
    this.tenantId,
    required this.email,
    required this.fullName,
    required this.isActive,
    this.isVerified = false,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id']?.toString() ?? '',
      accessScope:json['access_scope']?.toString() ?? 'COMPANY',
      isPlatformAdmin:json['is_platform_admin']==true,
      serviceRestricted:json['service_restricted']==true,
      subscriptionCapabilities:Map<String,dynamic>.from(json['subscription_capabilities'] as Map? ?? {}).map((k,v)=>MapEntry(k,v==true)),
      permissions: (json['permissions'] is List)
          ? List<String>.unmodifiable((json['permissions'] as List).whereType<String>())
          : const [],
      tenantId: json['tenant_id']?.toString(),
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
      'access_scope':accessScope,
      'is_platform_admin':isPlatformAdmin,
      'service_restricted':serviceRestricted,
      'subscription_capabilities':subscriptionCapabilities,
      'permissions':permissions,
      'tenant_id': tenantId,
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
      accessScope:accessScope,
      isPlatformAdmin:isPlatformAdmin,
      serviceRestricted:serviceRestricted,
      subscriptionCapabilities:subscriptionCapabilities,
      permissions:permissions,
      tenantId: tenantId,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      isActive: isActive ?? this.isActive,
      isVerified: isVerified ?? this.isVerified,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
