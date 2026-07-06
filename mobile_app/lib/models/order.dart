// lib/models/order.dart
class OrderModel {
  final int id;
  final int storeId;
  final String paymentType;
  final bool isApproved;
  final DateTime createdAt;
  final String status;
  final String? clientEmail; // من جدول profiles المرتبط

  OrderModel({
    required this.id,
    required this.storeId,
    required this.paymentType,
    required this.isApproved,
    required this.createdAt,
    required this.status,
    this.clientEmail,
  });

  factory OrderModel.fromMap(Map<String, dynamic> map) {
    return OrderModel(
      id: map['id'],
      storeId: map['store_id'],
      paymentType: map['payment_type'],
      isApproved: map['is_approved'],
      createdAt: DateTime.parse(map['created_at']),
      status: map['status'] ?? '',
      clientEmail: map['profiles'] != null ? map['profiles']['email'] : null,
    );
  }
}
