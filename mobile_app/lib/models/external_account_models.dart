  // lib/data/models/external_account_models.dart
  import 'package:flutter/foundation.dart';

  // نموذج لتمثيل حساب خارجي
  class ExternalAccount {
    final int id;
    final int storeId;
    final String firstName;
    final String? lastName;
    final String? phone;
    final String? address;
    final String accountType;
    final String? details;
    final DateTime createdAt;
    final String? createdBy; // UUID of the user who created it
    final bool isActive;

    ExternalAccount({
      required this.id,
      required this.storeId,
      required this.firstName,
      this.lastName,
      this.phone,
      this.address,
      required this.accountType,
      this.details,
      required this.createdAt,
      this.createdBy,
      required this.isActive,
    });

    factory ExternalAccount.fromJson(Map<String, dynamic> json) {
      return ExternalAccount(
        id: json['id'] as int,
        storeId: json['store_id'] as int,
        firstName: json['first_name'] as String,
        lastName: json['last_name'] as String?,
        phone: json['phone'] as String?,
        address: json['address'] as String?,
        accountType: json['account_type'] as String,
        details: json['details'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        createdBy: json['created_by'] as String?,
        isActive: json['is_active'] as bool,
      );
    }

    String get fullName => '$firstName ${lastName ?? ''}'.trim();
  }

  // نموذج لتمثيل معاملة حساب خارجي
  class ExternalAccountTransaction {
    final int id;
    final int externalAccountId;
    final int storeId;
    final String type; // 'له' or 'عليه'
    final double amount;
    final String? description;
    final DateTime transactionDate;
    final DateTime createdAt;
    final String? createdBy;

    ExternalAccountTransaction({
      required this.id,
      required this.externalAccountId,
      required this.storeId,
      required this.type,
      required this.amount,
      this.description,
      required this.transactionDate,
      required this.createdAt,
      this.createdBy,
    });

    factory ExternalAccountTransaction.fromJson(Map<String, dynamic> json) {
      return ExternalAccountTransaction(
        id: json['id'] as int,
        externalAccountId: json['external_account_id'] as int,
        storeId: json['store_id'] as int,
        type: json['type'] as String,
        // Supabase might return amount as String or num, handle both
        amount: double.tryParse(json['amount']?.toString() ?? '0') ?? 0.0,
        description: json['description'] as String?,
        transactionDate: DateTime.parse(json['transaction_date'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
        createdBy: json['created_by'] as String?,
      );
    }
  }

  // نموذج موحد لعرض ملخص في التقرير (إما مستخدم مسجل أو حساب خارجي)
  // يمكن استخدام abstract class أو interface إذا أردت المزيد من التجريد
  class AccountSummaryItem {
    final bool isExternal; // للتمييز بين النوعين
    final String id; // userId للمستخدم المسجل, externalAccountId.toString() للخارجي
    final String name;
    late final double totalCredit;
    late final double totalDebit;
    final DateTime? lastTransactionDate; // تاريخ آخر عملية (يمكن حسابه)

    double get balance => totalCredit - totalDebit;

    AccountSummaryItem({
      required this.isExternal,
      required this.id,
      required this.name,
      required this.totalCredit,
      required this.totalDebit,
      this.lastTransactionDate,
    });
  }