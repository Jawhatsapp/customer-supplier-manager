// lib/providers/auth_provider.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// --- نموذج UserProfile المحدث (يبقى كما هو) ---
class UserProfile {
  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final String role;
  final String? phone;
  final String? address;
  final String? avatarUrl;
  final bool isApproved;
  final String? approvedBy;
  final DateTime? approvedAt;
  final String? rejectionReason;
  final DateTime? emailConfirmedAt;

  UserProfile({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.role,
    this.phone,
    this.address,
    this.avatarUrl,
    required this.isApproved,
    this.approvedBy,
    this.approvedAt,
    this.rejectionReason,
    this.emailConfirmedAt,
  });

  factory UserProfile.fromMap(Map<String, dynamic> map, User? authUser) {
    return UserProfile(
      id: map['id'] ?? '',
      firstName: map['first_name'] ?? '',
      lastName: map['last_name'] ?? '',
      email: map['email'] ?? authUser?.email ?? '',
      role: map['role'] ?? 'client',
      phone: map['phone'] as String?,
      address: map['address'] as String?,
      avatarUrl: map['avatar_url'] as String?,
      isApproved: map['is_approved'] as bool? ?? false,
      approvedBy: map['approved_by'] as String?,
      approvedAt: map['approved_at'] == null ? null : DateTime.tryParse(map['approved_at'].toString()),
      emailConfirmedAt: authUser?.emailConfirmedAt == null ? null : DateTime.tryParse(authUser!.emailConfirmedAt!),
    );
  }

  String get fullName => '$firstName $lastName'.trim();

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserProfile &&
        other.id == id &&
        other.firstName == firstName &&
        other.lastName == lastName &&
        other.email == email &&
        other.role == role &&
        other.phone == phone &&
        other.address == address &&
        other.avatarUrl == avatarUrl &&
        other.isApproved == isApproved &&
        other.approvedBy == approvedBy &&
        other.approvedAt == approvedAt &&
        other.rejectionReason == rejectionReason &&
        other.emailConfirmedAt == emailConfirmedAt;
  }

  @override
  int get hashCode {
    return Object.hash(
        id, firstName, lastName, email, role, phone, address, avatarUrl,
        isApproved, approvedBy, approvedAt, rejectionReason, emailConfirmedAt);
  }
}

// --- مزود المصادقة الرئيسي ---
class AuthProvider with ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;
  StreamSubscription<AuthState>? _authStateSubscription;

  User? _currentUser;
  UserProfile? _userProfile;
  int? _storeId;

  bool _isInitialized = false;
  bool _isLoadingUser = true;
  String? _errorMessage;
  String? _infoMessage;

  // --- Getters ---
  User? get currentUser => _currentUser;
  UserProfile? get userProfile => _userProfile;
  int? get storeId => _storeId;
  bool get isLoading => !_isInitialized || _isLoadingUser;
  String? get errorMessage => _errorMessage;
  String? get infoMessage => _infoMessage;
  bool get isLoggedIn => _currentUser != null;
  String? get userRole => _userProfile?.role;
  bool get isUserApproved => _userProfile?.isApproved ?? false;
  bool get isEmailConfirmed => _userProfile?.emailConfirmedAt != null;
  bool get isInitialized => _isInitialized;

  AuthProvider() {
    print("AuthProvider: Constructor called. Initializing...");
    _initialize();
  }

  Future<void> _initialize() {
    // ... (هذه الدالة تبقى كما هي، لا تحتاج لتعديل)
    if (_isInitialized) return Future.value();
    print("AuthProvider: Initializing...");
    _isLoadingUser = true;
    _isInitialized = false;

    try {
      final initialSession = _supabase.auth.currentSession;
      _currentUser = initialSession?.user;
      print("AuthProvider: Initial Session Check - User: ${_currentUser?.id}, Email Confirmed: ${_currentUser?.emailConfirmedAt != null}");
      if (_currentUser != null) {
        // We will await this fetch
        return _fetchUserProfileAndStore(_currentUser!.id, _currentUser).whenComplete(() {
          _finishInitialization();
        });
      }
    } catch (e) {
      print("AuthProvider: Error during initial session check - $e");
      _errorMessage = "خطأ عند التحقق من الجلسة: $e";
    }

    _finishInitialization();
    return Future.value();
  }

  void _finishInitialization() {
    _isInitialized = true;
    _isLoadingUser = false;
    notifyListeners();
    print("AuthProvider: Initialization complete. Initial User: ${_currentUser?.id}, Approved: ${isUserApproved}, Confirmed: ${isEmailConfirmed}");
    _listenToAuthChanges();
  }

  void _listenToAuthChanges() {
    _authStateSubscription = _supabase.auth.onAuthStateChange.listen(
          (data) async {
        final AuthChangeEvent event = data.event;
        final Session? session = data.session;
        final newUser = session?.user;
        print(">>>> AuthProvider: onAuthStateChange - Event: ${event.name}, New User ID: ${newUser?.id}, Email Confirmed: ${newUser?.emailConfirmedAt != null}");

        if (_currentUser?.id != newUser?.id || event == AuthChangeEvent.userUpdated || event == AuthChangeEvent.passwordRecovery || event == AuthChangeEvent.signedIn) {
          print(">>>> AuthProvider: State Change Triggered. Current User ID: ${_currentUser?.id}, New User ID: ${newUser?.id}");
          bool needsNotifyStart = !_isLoadingUser;
          _isLoadingUser = true;

          User? userToProcess = newUser;
          bool userChanged = _currentUser?.id != userToProcess?.id;

          if (userChanged) {
            _currentUser = userToProcess;
            _userProfile = null; _storeId = null; _errorMessage = null; _infoMessage = null;
            print(">>>> AuthProvider: User ID changed. State reset.");
            needsNotifyStart = true;
          } else if (event == AuthChangeEvent.userUpdated && userToProcess != null) {
            _currentUser = userToProcess;
            print(">>>> AuthProvider: User updated event. Current user reference updated.");
          }

          if (needsNotifyStart) {
            print(">>>> AuthProvider: Notifying UI (Start Loading)");
            notifyListeners();
          }

          if (_currentUser != null) {
            print(">>>> AuthProvider: Calling _fetchUserProfileAndStore for User ID: ${_currentUser!.id}");
            await _fetchUserProfileAndStore(_currentUser!.id, _currentUser);
            print(">>>> AuthProvider: _fetchUserProfileAndStore completed.");
            if (event == AuthChangeEvent.passwordRecovery) {
              print("AuthProvider: Password recovery event handled.");
              _infoMessage = 'إذا طلبت إعادة تعيين، تم إرسال الرابط لبريدك.';
            }
            if (event == AuthChangeEvent.userUpdated) {
              print("AuthProvider: User update processed, profile refreshed. Confirmed: ${isEmailConfirmed}");
            }
          } else {
            _userProfile = null; _storeId = null; _errorMessage = null; _infoMessage = null;
            print(">>>> AuthProvider: User is null (Signed Out). State reset.");
          }

          _isLoadingUser = false;
          print(">>>> AuthProvider: Notifying UI (End Loading). Final State: isLoggedIn=${_currentUser != null}, isEmailConfirmed=${isEmailConfirmed}, isUserApproved=${isUserApproved}, profile=${_userProfile?.id}, error=${_errorMessage}");
          notifyListeners();
        } else if (event == AuthChangeEvent.tokenRefreshed) {
          print("AuthProvider: Token refreshed. No state change needed.");
        }
        else {
          print(">>>> AuthProvider: Event ${event.name} did not trigger major state change.");
        }
      },
      onError: (error) {
        print(">>>> AuthProvider: ERROR in auth stream: $error");
        _isLoadingUser = false;
        _errorMessage = "خطأ في متابعة حالة المصادقة: $error";
        _currentUser = null; _userProfile = null; _storeId = null;
        notifyListeners();
      },
    );
  }


  // --- تم تعديل هذه الدالة ---
  Future<void> _fetchUserProfileAndStore(String userId, User? authUser) async {
    print(">>>> _fetchUserProfileAndStore: START for User ID: $userId");
    bool needsNotify = false;
    String? previousError = _errorMessage;
    _errorMessage = null;

    try {
      final profileResponse = await _supabase
          .from('profiles')
          .select('*')
          .eq('id', userId)
          .single();

      final fetchedProfile = UserProfile.fromMap(profileResponse, authUser);
      print(">>>> _fetchUserProfileAndStore: Profile fetched - Role: ${fetchedProfile.role}, Approved: ${fetchedProfile.isApproved}, Confirmed: ${fetchedProfile.emailConfirmedAt != null}");

      if (_userProfile != fetchedProfile) {
        _userProfile = fetchedProfile;
        needsNotify = true;
      }

      int? fetchedStoreId;
      // *** التعديل الرئيسي هنا ***
      if (['retailer', 'supplier'].contains(_userProfile?.role)) {
        // الآن نبحث في جدول 'stores' الموحد فقط
        final storeResponse = await _supabase
            .from('stores') // <-- اسم الجدول الموحد
            .select('id')
            .eq('owner_id', userId) // <-- الحقل الموحد للمالك
            .maybeSingle(); // قد لا يكون للمستخدم متجر بعد

        fetchedStoreId = storeResponse?['id'] as int?;
        print(">>>> _fetchUserProfileAndStore: Store ID fetched: $fetchedStoreId from 'stores' table.");
      } else {
        fetchedStoreId = null;
      }
      // *** نهاية التعديل الرئيسي ***

      if (_storeId != fetchedStoreId) {
        _storeId = fetchedStoreId;
        needsNotify = true;
      }

      if (previousError != null) {
        needsNotify = true;
      }
      print(">>>> _fetchUserProfileAndStore: SUCCESS.");

    } on PostgrestException catch (e) {
      print(">>>> _fetchUserProfileAndStore: Postgrest ERROR - Code: ${e.code}, Message: ${e.message}");
      if (e.code == 'PGRST116') {
        _errorMessage = 'لم يتم العثور على ملفك الشخصي أو المتجر المرتبط.';
        print("AuthProvider: Profile/Store not found (PGRST116).");
      } else {
        _errorMessage = 'خطأ جلب البيانات (${e.code}): ${e.message}';
      }
      _userProfile = null;
      _storeId = null;
      needsNotify = true;

    } catch (e) {
      print(">>>> _fetchUserProfileAndStore: Generic ERROR - $e");
      _errorMessage = 'خطأ غير متوقع أثناء جلب البيانات: $e';
      _userProfile = null;
      _storeId = null;
      needsNotify = true;
    } finally {
      if (needsNotify) {
        print(">>>> _fetchUserProfileAndStore: FINISHED. Notifying listeners.");
        notifyListeners();
      } else {
        print(">>>> _fetchUserProfileAndStore: FINISHED. No changes, no notification needed.");
      }
    }
  }

  // --- دوال تسجيل الدخول وإنشاء الحساب (تبقى كما هي) ---
  Future<bool> signIn(String email, String password) async {
    // ... (الكود كما هو)
    _errorMessage = null;
    _infoMessage = null;

    try {
      print("AuthProvider: Attempting signIn for $email");
      await _supabase.auth.signInWithPassword(
        email: email.trim(),
        password: password.trim(),
      );
      print("AuthProvider: Sign in successful (Auth level) for $email.");
      return true;

    } on AuthException catch (e) {
      print("AuthProvider: Sign in AuthException - Code: ${e.statusCode}, Message: ${e.message}");
      if (e.message.toLowerCase().contains('email not confirmed')) {
        _errorMessage = 'يرجى تأكيد بريدك الإلكتروني أولاً. تحقق من صندوق الوارد.';
      } else if (e.message.contains('Invalid login credentials')) {
        _errorMessage = 'بيانات الدخول غير صحيحة.';
      } else {
        _errorMessage = "خطأ في المصادقة: ${e.message}";
      }
      notifyListeners();
      return false;

    } catch (e) {
      print("AuthProvider: Sign in general error - $e");
      _errorMessage = 'حدث خطأ غير متوقع أثناء تسجيل الدخول: $e';
      notifyListeners();
      return false;
    }
  }

  Future<String?> signUp({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String phone,
    required String address,
    required String role,
  }) async {
    // ... (الكود كما هو)
    _errorMessage = null;
    _infoMessage = null;
    String? resultMessage;

    try {
      print("AuthProvider: Attempting Supabase signUp for $email with role $role");
      final response = await _supabase.auth.signUp(
        email: email.trim(),
        password: password.trim(),
        data: {
          'firstName': firstName.trim(),
          'lastName': lastName.trim(),
          'phone': phone.trim().isEmpty ? null : phone.trim(),
          'address': address.trim().isEmpty ? null : address.trim(),
          'role': role,
        },
      );

      final createdUser = response.user;
      if (createdUser == null) {
        throw AuthException('Signup failed: User object is null after Supabase response.');
      }
      bool emailConfirmationNeeded = createdUser.emailConfirmedAt == null;
      bool needsApproval = (role == 'retailer' || role == 'supplier');

      if (needsApproval) {
        resultMessage = emailConfirmationNeeded
            ? 'تم إنشاء الحساب! يرجى تأكيد بريدك الإلكتروني أولاً، ثم سيتم مراجعة حسابك.'
            : 'تم إنشاء الحساب بنجاح! حسابك قيد المراجعة الآن.';
      } else {
        resultMessage = emailConfirmationNeeded
            ? 'تم إنشاء الحساب بنجاح! يرجى تأكيد بريدك الإلكتروني للمتابعة.'
            : 'تم إنشاء الحساب بنجاح!';
      }

      _infoMessage = resultMessage;
      notifyListeners();
      return resultMessage;

    } on AuthException catch (e) {
      print("AuthProvider: !! AuthException in signUp: ${e.message}");
      if (e.message.contains('User already registered')) {
        resultMessage = 'هذا البريد الإلكتروني مسجل بالفعل.';
      } else if (e.message.contains('Password should be at least 6 characters')) {
        resultMessage = 'يجب أن تتكون كلمة المرور من 6 أحرف على الأقل.';
      } else {
        resultMessage = "خطأ في المصادقة: ${e.message}";
      }
      _errorMessage = resultMessage;
      notifyListeners();
      return resultMessage;

    } catch (e) {
      print("AuthProvider: !! Generic Exception in signUp: $e");
      resultMessage = 'حدث خطأ غير متوقع أثناء عملية التسجيل: $e';
      _errorMessage = resultMessage;
      notifyListeners();
      return resultMessage;
    }
  }

  Future<void> signOut() async {
    // ... (الكود كما هو)
    print("AuthProvider: Signing out...");
    _infoMessage = null; _errorMessage = null;
    await _supabase.auth.signOut();
  }

  Future<void> refreshUserProfile() async {
    // ... (الكود كما هو)
    if (_currentUser == null) {
      print("AuthProvider: Cannot refresh profile, user not logged in.");
      return;
    }
    print("AuthProvider: Refreshing user profile explicitly for User ID: ${_currentUser!.id}");
    _isLoadingUser = true;
    notifyListeners(); // Notify UI that loading has started
    await _fetchUserProfileAndStore(_currentUser!.id, _currentUser);
    _isLoadingUser = false;
    notifyListeners(); // Notify UI that loading has finished and data is (potentially) updated
    print("AuthProvider: refreshUserProfile finished. Final State -> Approved: ${isUserApproved}, Confirmed: ${isEmailConfirmed}");
  }

  String getArabicRoleName(String? role) {
    // ... (الكود كما هو)
    switch (role) {
      case 'client': return 'عميل';
      case 'retailer': return 'تاجر تجزئة';
      case 'supplier': return 'مورد';
      case 'admin': return 'مسؤول';
      default: return role ?? 'غير معروف';
    }
  }

  @override
  void dispose() {
    // ... (الكود كما هو)
    print("AuthProvider: Disposing...");
    _authStateSubscription?.cancel();
    super.dispose();
  }

  void clearErrorMessage() {
    // ... (الكود كما هو)
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }

  void clearInfoMessage() {
    // ... (الكود كما هو)
    if (_infoMessage != null) {
      _infoMessage = null;
      notifyListeners();
    }
  }
}