// lib/models/product.dart
class Product {
  final int id;
  final String productName;
  final String product_description;
  final double price;
  final String? imageUrl;
  final int stock;
  final int storeId; // ✅ تمت الإضافة هنا
  final int? categoryId;

  Product({
    required this.id,
    required this.productName,
    required this.product_description,
    required this.price,
    this.imageUrl,
    required this.stock,
    required this.storeId, // ✅ تمت الإضافة هنا
    this.categoryId,
  });

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'],
      productName: map['product_name'],
      product_description: map['product_description'],
      price: double.parse(map['price'].toString()),
      imageUrl: map['image_url'],
      stock: map['stock'] ?? 0,
      storeId: map['store_id'], // ✅ تمت الإضافة هنا
      categoryId: map['category_id'] as int?,
    );
  }
}
