// lib/models/store_payment_method_model.dart

class StorePaymentMethod {
  final int id;
  final int storeId;
  final String storeType;
  final String? ownerId; // يمكن أن يكون null إذا تم حذفه
  final String institutionName;
  final String accountName;
  final String accountNumber;
  final String? details;
  bool isActive; // نجعلها قابلة للتعديل لتحديث الواجهة فوراً
  final DateTime createdAt;

  StorePaymentMethod({
    required this.id,
    required this.storeId,
    required this.storeType,
    this.ownerId,
    required this.institutionName,
    required this.accountName,
    required this.accountNumber,
    this.details,
    required this.isActive,
    required this.createdAt,
  });

  factory StorePaymentMethod.fromJson(Map<String, dynamic> json) {
    return StorePaymentMethod(
      id: json['id'] as int,
      storeId: json['store_id'] as int,
      storeType: json['store_type'] as String,
      ownerId: json['owner_id'] as String?,
      institutionName: json['institution_name'] as String,
      accountName: json['account_name'] as String,
      accountNumber: json['account_number'] as String,
      details: json['details'] as String?,
      isActive: json['is_active'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  // لتحويل الكائن إلى Map عند الإرسال لقاعدة البيانات (اختياري)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'store_id': storeId,
      'store_type': storeType,
      'owner_id': ownerId,
      'institution_name': institutionName,
      'account_name': accountName,
      'account_number': accountNumber,
      'details': details,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
    };
  }
}