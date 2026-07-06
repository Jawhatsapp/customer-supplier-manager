import { supabase } from './supabase-client.js';
import { checkAuth } from './auth.js'; // استيراد دالة التحقق

// عناصر الواجهة
const loadingIndicator = document.getElementById('loading-indicator');
const pendingErrorMessage = document.getElementById('pending-error-message');
const usersTable = document.getElementById('pending-users-table');
const tableBody = usersTable?.querySelector('tbody');
const noPendingUsersMessage = document.getElementById('no-pending-users-message');
const resetPasswordForm = document.getElementById('reset-password-form');
const resetEmailInput = document.getElementById('reset-email');
const resetPasswordButton = document.getElementById('reset-password-button');
const resetStatusMessage = document.getElementById('reset-status-message');

let currentAdmin = null; // سيتم تعيينه بواسطة checkAuth

// --- جلب المستخدمين المعلقين وملء الجدول ---
async function fetchAndDisplayPendingUsers() {
    if (!tableBody) { console.error("Table body not found!"); return; }

    loadingIndicator.style.display = 'block';
    pendingErrorMessage.style.display = 'none';
    usersTable.style.display = 'none';
    noPendingUsersMessage.style.display = 'none';
    tableBody.innerHTML = ''; // مسح القديم

    try {
        const { data: users, error } = await supabase
            .from('profiles')
            .select('id, first_name, last_name, email, role, created_at')
            .in('role', ['retailer', 'supplier'])
            .eq('is_approved', false)
            .order('created_at', { ascending: true });

        if (error) throw error;

        if (users.length === 0) {
            noPendingUsersMessage.style.display = 'block';
        } else {
            users.forEach(user => {
                const row = tableBody.insertRow();
                row.innerHTML = `
                    <td>${user.first_name || ''} ${user.last_name || ''}</td>
                    <td>${user.email}</td>
                    <td>${user.role === 'retailer' ? 'تاجر تجزئة' : 'مورد'}</td>
                    <td>${user.created_at ? new Date(user.created_at).toLocaleDateString('ar-EG') : '-'}</td>
                    <td>
                        <button class="action-btn approve-btn" data-user-id="${user.id}" title="موافقة">✔️</button>
                        <button class="action-btn reject-btn" data-user-id="${user.id}" title="رفض">❌</button>
                    </td>
                `;
            });
            usersTable.style.display = 'table';
            addTableButtonListeners();
        }

    } catch (error) {
        console.error("Error fetching pending users:", error);
        pendingErrorMessage.textContent = `خطأ في جلب المستخدمين: ${error.message}`;
        pendingErrorMessage.style.display = 'block';
    } finally {
        loadingIndicator.style.display = 'none';
    }
}

// --- إضافة مستمعين لأزرار الجدول ---
function addTableButtonListeners() {
    if (!tableBody) return;
    tableBody.querySelectorAll('.approve-btn').forEach(button => {
        button.addEventListener('click', () => updateUserApproval(button.dataset.userId, true, button));
    });
    tableBody.querySelectorAll('.reject-btn').forEach(button => {
        button.addEventListener('click', () => {
            const userId = button.dataset.userId;
            const reason = prompt(`ادخل سبب رفض المستخدم (اختياري) لـ ID: ${userId}`);
            if (reason !== null) { // استمر فقط إذا لم يضغط المستخدم Cancel
                updateUserApproval(userId, false, button, reason.trim());
            }
        });
    });
}

// --- دالة الموافقة أو الرفض ---
async function updateUserApproval(userId, approve, button, rejectionReason = null) {
    if (!currentAdmin || !userId || button.disabled) return;

    button.disabled = true;
    button.innerHTML = '<span aria-busy="true"></span>'; // مؤشر تحميل Pico

    try {
        const updateData = {
            is_approved: approve,
            approved_by: approve ? currentAdmin.id : null,
            approved_at: approve ? new Date().toISOString() : null,
            rejection_reason: !approve ? (rejectionReason || null) : null
        };

        const { error } = await supabase
            .from('profiles')
            .update(updateData)
            .eq('id', userId);

        if (error) throw error;

        // إرسال الإشعار
        await sendUserNotification(userId, approve, rejectionReason);

        alert(`تم ${approve ? 'الموافقة' : 'الرفض'} بنجاح!`);
        fetchAndDisplayPendingUsers(); // إعادة تحميل القائمة

    } catch (error) {
        console.error(`Error ${approve ? 'approving' : 'rejecting'} user ${userId}:`, error);
        alert(`فشل ${approve ? 'الموافقة' : 'الرفض'}: ${error.message}`);
        // إعادة الزر لحالته الأصلية عند الفشل
        button.disabled = false;
        button.innerHTML = approve ? '✔️' : '❌';
    }
    // لا حاجة لـ finally لإعادة الزر لأننا نعيد تحميل الجدول بالكامل
}

 // --- دالة إرسال الإشعار ---
 async function sendUserNotification(targetUserId, isApproved, reason = null) {
    try {
         const title = isApproved ? 'تمت الموافقة على حسابك!' : 'تم رفض طلب تسجيلك';
         let message = isApproved
            ? 'تهانينا! تم تفعيل حسابك كتاجر/مورد ويمكنك الآن تسجيل الدخول واستخدام جميع ميزات التطبيق.'
            : 'نأسف لإبلاغك بأنه تم رفض طلب تسجيلك كتاجر/مورد.';
        if (!isApproved && reason && reason.trim() !== '') {
            message += `\nالسبب: ${reason}`;
        }

         const { error } = await supabase
         .from('notifications') // تأكد من اسم الجدول الصحيح للإشعارات
         .insert({ user_id: targetUserId, title: title, message: message });

        if (error) throw error;
        console.log(`Notification sent to ${targetUserId}`);
    } catch (error) {
        console.error(`Error sending notification to ${targetUserId}:`, error);
    }
}

// --- التعامل مع نموذج إعادة تعيين كلمة المرور ---
if (resetPasswordForm) {
    resetPasswordForm.addEventListener('submit', async (e) => {
        e.preventDefault();
        const emailToReset = resetEmailInput.value.trim();
        if (!emailToReset) return;

        resetPasswordButton.disabled = true;
        resetPasswordButton.setAttribute('aria-busy', 'true');
        resetStatusMessage.textContent = '';
        resetStatusMessage.className = ''; // Reset class

        try {
             console.log(`Requesting password reset for: ${emailToReset}`);
             // استخدام الدالة المدمجة في Supabase لإرسال رابط إعادة التعيين
             // تأكد من أن إعدادات SMTP للبريد الإلكتروني مفعلة في مشروع Supabase
             const { error } = await supabase.auth.resetPasswordForEmail(emailToReset, {
                 // redirectTo: 'YOUR_APP_RESET_PASSWORD_URL' // مهم: رابط في تطبيق Flutter لتغيير كلمة السر
             });

            if (error) {
                 // أخطاء شائعة: User not found, Email rate limit exceeded
                 console.error('Supabase password reset error:', error);
                 throw new Error(error.message || 'فشل إرسال رابط إعادة التعيين.');
             }

            resetStatusMessage.textContent = 'تم إرسال رابط إعادة تعيين كلمة المرور إلى البريد الإلكتروني بنجاح.';
            resetStatusMessage.className = 'success-text';
            resetEmailInput.value = '';

        } catch (error) {
            console.error('Error processing password reset:', error);
            resetStatusMessage.textContent = `خطأ: ${error.message}`;
            resetStatusMessage.className = 'error-text';
        } finally {
            resetPasswordButton.disabled = false;
            resetPasswordButton.setAttribute('aria-busy', 'false');
        }
    });
}

// --- بدء التشغيل للوحة التحكم ---
document.addEventListener('DOMContentLoaded', async () => {
    currentAdmin = await checkAuth(); // التحقق من أن المستخدم مسؤول
    if (currentAdmin) {
        console.log("Admin authenticated, fetching pending users...");
        fetchAndDisplayPendingUsers(); // إذا كان مسؤولاً، اجلب المستخدمين المعلقين
    } else {
         console.log("Not an admin or not logged in.");
         // checkAuth ستقوم بإعادة التوجيه إذا لزم الأمر
    }
});