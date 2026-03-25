class ApiProvider {
  final int? id;
  final String name;
  final String baseUrl;
  final String apiKey;
  final bool enabled;
  final String type; // 'perenual', 'trefle'

  ApiProvider({
    this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    this.enabled = true,
    this.type = 'perenual',
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'base_url': baseUrl,
      'api_key': apiKey,
      'enabled': enabled ? 1 : 0,
      'type': type,
    };
  }

  factory ApiProvider.fromMap(Map<String, dynamic> map) {
    return ApiProvider(
      id: map['id'] as int?,
      name: map['name'] as String,
      baseUrl: map['base_url'] as String,
      apiKey: map['api_key'] as String,
      enabled: (map['enabled'] as int? ?? 1) == 1,
      type: map['type'] as String? ?? 'perenual',
    );
  }

  ApiProvider copyWith({
    int? id,
    String? name,
    String? baseUrl,
    String? apiKey,
    bool? enabled,
    String? type,
  }) {
    return ApiProvider(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      enabled: enabled ?? this.enabled,
      type: type ?? this.type,
    );
  }
}
