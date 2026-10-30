import 'package:flutter/material.dart';

class TenantModel {
  final String id;
  final String nombre;
  final String razonSocial;
  final String nitRut;
  final String slug;
  final String? logoUrl;
  final String? colorPrimario;
  final String? colorSecundario;
  final String? eslogan;
  final String? telefono;
  final String? emailContacto;
  final bool activo;
  final String planCodigo;
  final String planNombre;

  TenantModel({
    required this.id,
    required this.nombre,
    required this.razonSocial,
    required this.nitRut,
    required this.slug,
    this.logoUrl,
    this.colorPrimario = '#4f46e5',
    this.colorSecundario = '#818cf8',
    this.eslogan,
    this.telefono,
    this.emailContacto,
    this.activo = true,
    this.planCodigo = 'BASICO',
    this.planNombre = 'Plan Básico',
  });

  factory TenantModel.fromJson(Map<String, dynamic> json) {
    return TenantModel(
      id: json['id']?.toString() ?? '',
      nombre: json['nombre']?.toString() ?? 'Empresa',
      razonSocial: json['razon_social']?.toString() ?? '',
      nitRut: json['nit_rut']?.toString() ?? '',
      slug: json['slug']?.toString() ?? '',
      logoUrl: json['logo_url']?.toString(),
      colorPrimario: json['color_primario']?.toString() ?? '#4f46e5',
      colorSecundario: json['color_secundario']?.toString() ?? '#818cf8',
      eslogan: json['eslogan']?.toString(),
      telefono: json['telefono']?.toString(),
      emailContacto: json['email_contacto']?.toString(),
      activo: json['activo'] as bool? ?? true,
      planCodigo: json['plan_codigo']?.toString() ?? 'BASICO',
      planNombre: json['plan_nombre']?.toString() ?? 'Plan Básico',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nombre': nombre,
      'razon_social': razonSocial,
      'nit_rut': nitRut,
      'slug': slug,
      'logo_url': logoUrl,
      'color_primario': colorPrimario,
      'color_secundario': colorSecundario,
      'eslogan': eslogan,
      'telefono': telefono,
      'email_contacto': emailContacto,
      'activo': activo,
      'plan_codigo': planCodigo,
      'plan_nombre': planNombre,
    };
  }

  Color get parsedPrimaryColor {
    return _parseHexColor(colorPrimario, const Color(0xFF4F46E5));
  }

  Color get parsedSecondaryColor {
    return _parseHexColor(colorSecundario, const Color(0xFF818CF8));
  }

  static Color _parseHexColor(String? hexString, Color defaultColor) {
    if (hexString == null || hexString.isEmpty) return defaultColor;
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    try {
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (_) {
      return defaultColor;
    }
  }
}

