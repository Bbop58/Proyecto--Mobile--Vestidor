class VoiceReport {
  final String question;
  final String interpretation;
  final String spokenSummary;
  final List<String> columns;
  final List<Map<String, dynamic>> rows;

  const VoiceReport({
    required this.question,
    required this.interpretation,
    required this.spokenSummary,
    required this.columns,
    required this.rows,
  });

  factory VoiceReport.fromJson(Map<String, dynamic> json) {
    return VoiceReport(
      question: json['pregunta']?.toString() ?? '',
      interpretation: json['interpretacion']?.toString() ?? '',
      spokenSummary: json['resumen_hablado']?.toString() ?? '',
      columns: (json['columnas'] as List? ?? const [])
          .map((x) => x.toString())
          .toList(),
      rows: (json['filas'] as List? ?? const [])
          .map((x) => Map<String, dynamic>.from(x as Map))
          .toList(),
    );
  }
}
