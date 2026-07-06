// lib/data/repositories/store_repository.dart

import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/store_model.dart';

class StoreRepository {
  final SupabaseClient _supabaseClient;

  StoreRepository({SupabaseClient? client})
      : _supabaseClient = client ?? Supabase.instance.client;

  Future<List<StoreModel>> getStores({
    required String storeType,
    String? searchTerm,
    String? excludeOwnerId,
  }) async {
    // ... (الكود كما هو من الرد السابق)
    try {
      var query = _supabaseClient
          .from('stores')
          .select<List<Map<String, dynamic>>>('*')
          .eq('store_type', storeType);

      if (excludeOwnerId != null) {
        query = query.neq('owner_id', excludeOwnerId);
      }

      if (searchTerm != null && searchTerm.trim().isNotEmpty) {
        final searchPattern = '%${searchTerm.trim()}%';
        query = query.or('store_name.ilike.$searchPattern,address.ilike.$searchPattern');
      }

      final data = await query;
      return data.map((map) => StoreModel.fromMap(map)).toList();

    } catch (e) {
      print("Error in StoreRepository.getStores: $e");
      throw Exception('فشل في جلب بيانات المتاجر.');
    }
  }

  Future<StoreModel> getStoreById(int storeId) async {
    // ... (الكود كما هو من الرد السابق)
    try {
      final data = await _supabaseClient
          .from('stores')
          .select<Map<String, dynamic>>('*')
          .eq('id', storeId)
          .single();

      return StoreModel.fromMap(data);

    } on PostgrestException catch (e) {
      print("Error in StoreRepository.getStoreById (Postgrest): ${e.message}");
      if (e.code == 'PGRST116') {
        throw Exception('المتجر المطلوب غير موجود.');
      }
      throw Exception('خطأ في قاعدة البيانات: ${e.message}');
    }
    catch (e) {
      print("Error in StoreRepository.getStoreById: $e");
      throw Exception('فشل في جلب بيانات المتجر.');
    }
  }

  // --- دالة جديدة لرفع الصور ---
  Future<String> uploadStoreImage({
    required File file,
    required int storeId,
    required String imageType, // 'logo' or 'banner'
    required String bucketName, // 'store-logos' or 'store-banners'
  }) async {
    try {
      final fileExtension = p.extension(file.path);
      final fileName = '$imageType$fileExtension'; // e.g., logo.png or banner.jpg
      final filePath = '$storeId/$fileName';

      await _supabaseClient.storage.from(bucketName).upload(
        filePath,
        file,
        fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
      );

      // Add timestamp for cache busting
      final publicUrl = _supabaseClient.storage.from(bucketName).getPublicUrl(filePath);
      return '$publicUrl?t=${DateTime.now().millisecondsSinceEpoch}';

    } catch (e) {
      print("Error uploading $imageType to bucket $bucketName: $e");
      throw Exception('فشل في رفع صورة الـ$imageType.');
    }
  }

  // --- دالة جديدة لتحديث بيانات المتجر ---
  Future<void> updateStoreDetails({
    required int storeId,
    required Map<String, dynamic> updates,
  }) async {
    try {
      await _supabaseClient
          .from('stores') // <-- اسم الجدول الجديد
          .update(updates)
          .eq('id', storeId);
    } catch (e) {
      print("Error in StoreRepository.updateStoreDetails: $e");
      throw Exception('فشل في تحديث بيانات المتجر.');
    }
  }
}