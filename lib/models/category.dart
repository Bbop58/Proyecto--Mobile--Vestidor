class Category {
  final String id;
  final String nombre;
  final String? descripcion;
  final String slug;
  final bool activo;

  Category({
    required this.id,
    required this.nombre,
    this.descripcion,
    required this.slug,
    required this.activo,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    final nombre = json['nombre']?.toString() ?? '';
    return Category(
      id: json['id']?.toString() ?? '',
      nombre: nombre,
      descripcion: json['descripcion']?.toString(),
      slug: json['slug']?.toString() ??
          nombre.toLowerCase().replaceAll(RegExp(r'\s+'), '-'),
      activo: json['activa'] == true || json['activo'] == true || (json['activa'] == null && json['activo'] == null),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nombre': nombre,
      'descripcion': descripcion,
      'slug': slug,
      'activo': activo,
    };
  }
}
