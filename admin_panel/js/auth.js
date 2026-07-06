import { supabase } from './supabase-client.js';

// --- التحقق من وجود جلسة نشطة ودور المسؤول ---
async function checkAuth() {
  const { data: { session } } = await supabase.auth.getSession();
  const isLoginPage = window.location.pathname.endsWith('/') || window.location.pathname.endsWith('index.html');

  if (!session) {
    if (!isLoginPage) window.location.replace('/');
    return null;
  }

  const user = session.user;
  const { data: profile, error } = await supabase
    .from('profiles')
    .select('role')
    .eq('id', user.id)
    .single();

  if (error || !profile || profile.role !== 'admin') {
    await supabase.auth.signOut();
    if (!isLoginPage) window.location.replace('/');
    return null;
  }

  if (isLoginPage) window.location.replace('/dashboard.html');
  return user; // إرجاع بيانات مستخدم المسؤول
}

// --- التعامل مع نموذج تسجيل الدخول ---
const loginForm = document.getElementById('login-form');
if (loginForm) {
  const loginButton = document.getElementById('login-button');
  const errorMessage = document.getElementById('error-message');

  loginForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const email = document.getElementById('email').value;
    const password = document.getElementById('password').value;

    loginButton.disabled = true;
    loginButton.setAttribute('aria-busy', 'true'); // For Pico loading
    errorMessage.style.display = 'none';

    try {
      const { data, error } = await supabase.auth.signInWithPassword({ email, password });
      if (error) throw error;

      // تحقق من الدور بعد الدخول
      const user = data.user;
      const { data: profile, error: profileError } = await supabase
        .from('profiles')
        .select('role')
        .eq('id', user.id)
        .single();
      if (profileError) throw profileError;

      if (profile && profile.role === 'admin') {
        window.location.replace('/dashboard.html'); // نجح وانتقل
      } else {
        await supabase.auth.signOut();
        throw new Error('ليس لديك صلاحيات المسؤول.');
      }

    } catch (error) {
      errorMessage.textContent = `خطأ: ${error.message}`;
      errorMessage.style.display = 'block';
      loginButton.disabled = false;
      loginButton.setAttribute('aria-busy', 'false');
    }
    // لا حاجة لـ finally هنا لأننا نترك الزر معطلاً عند النجاح (للانتقال)
  });
}

// --- دالة تسجيل الخروج ---
async function logout() {
    try {
         await supabase.auth.signOut();
         window.location.replace('/');
    } catch (error) {
         console.error("Logout error:", error);
         alert("حدث خطأ أثناء تسجيل الخروج.");
    }
}

// --- جعل الدوال قابلة للاستدعاء عالميًا ---
window.checkAuth = checkAuth;
window.logout = logout;

// قم باستدعاء checkAuth في بداية الصفحات الأخرى للتحقق
// مثال في dashboard.js:
// document.addEventListener('DOMContentLoaded', async () => {
//     const adminUser = await checkAuth();
//     if (adminUser) {
//         // ابدأ تحميل بيانات اللوحة
//     }
// });