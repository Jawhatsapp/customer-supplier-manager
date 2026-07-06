// lib/models/store_model.dart

// هذا النموذج يمثل البيانات القادمة من جدول stores الموحد الجديد
class StoreModel {
  final int id;
  final String ownerId;
  final String storeType; // سيكون إما 'retailer' أو 'supplier'
  final String storeName;
  final String? address;
  final String? logoUrl;
  final String? bannerUrl;
  final DateTime createdAt;

  StoreModel({
    required this.id,
    required this.ownerId,
    required this.storeType,
    required this.storeName,
    this.address,
    this.logoUrl,
    this.bannerUrl,
    required this.createdAt,
  });

  // دالة Factory لتحويل بيانات الـ JSON القادمة من Supabase إلى كائن StoreModel
  factory StoreModel.fromMap(Map<String, dynamic> map) {
    return StoreModel(
      id: map['id'] as int,
      ownerId: map['owner_id'] as String,
      storeType: map['store_type'] as String,
      storeName: map['store_name'] as String,
      address: map['address'] as String?,
      logoUrl: map['logo_url'] as String?,
      bannerUrl: map['banner_url'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}