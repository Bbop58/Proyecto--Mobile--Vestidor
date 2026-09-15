class Branch {
  final String id;
  final String nombre;
  final String direccion;
  final String? telefono;
  final String? ciudad;
  final bool activa;

  Branch({
    required this.id,
    required this.nombre,
    required this.direccion,
    this.telefono,
    this.ciudad,
    required this.activa,
  });

  factory Branch.fromJson(Map<String, dynamic> json) {
    return Branch(
      id: json['id'] ?? '',
      nombre: json['nombre'] ?? '',
      direccion: json['direccion'] ?? '',
      telefono: json['telefono'],
      ciudad: json['ciudad'],
      activa: json['activa'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nombre': nombre,
      'direccion': direccion,
      'telefono': telefono,
      'ciudad': ciudad,
      'activa': activa,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Branch && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
