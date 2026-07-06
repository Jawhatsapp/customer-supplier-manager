// lib/utils/helpers.dart
import 'package:supabase_flutter/supabase_flutter.dart';

Future<int?> fetchStoreIdAutomatically() async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return null;

  final profile = await Supabase.instance.client
      .from('profiles')
      .select('role')
      .eq('id', user.id)
      .maybeSingle();

  final role = profile?['role'];

  if (role == 'retailer') {
    final retailerStore = await Supabase.instance.client
        .from('retailer_stores')
        .select('id')
        .eq('retailer_id', user.id)
        .maybeSingle();

    return retailerStore?['id'];
  } else if (role == 'supplier') {
    final supplierStore = await Supabase.instance.client
        .from('supplier_stores')
        .select('id')
        .eq('supplier_id', user.id)
        .maybeSingle();

    return supplierStore?['id'];
  }

  return null;
}
