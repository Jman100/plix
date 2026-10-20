class PlexPin {
  final int id;
  final String code;
  final String? product;
  final String? qr;
  final String clientIdentifier;
  final int expiresIn;
  final String? authToken;

  PlexPin({
    required this.id,
    required this.code,
    this.product,
    this.qr,
    required this.clientIdentifier,
    required this.expiresIn,
    this.authToken,
  });

  bool get isLinked => authToken != null && authToken!.isNotEmpty;

  factory PlexPin.fromJson(Map<String, dynamic> json) {
    return PlexPin(
      id: json['id'] as int? ?? 0,
      code: json['code'] as String? ?? '',
      product: json['product'] as String?,
      qr: json['qr'] as String?,
      clientIdentifier: json['clientIdentifier'] as String? ?? '',
      expiresIn: json['expiresIn'] as int? ?? 900,
      authToken: json['authToken'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'code': code,
      'product': product,
      'qr': qr,
      'clientIdentifier': clientIdentifier,
      'expiresIn': expiresIn,
      'authToken': authToken,
    };
  }
}
