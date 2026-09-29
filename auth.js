import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import './owner-tools.js';

const roleSelect = document.getElementById('roleSelect');
const loginButton = document.getElementById('loginBtn');
let client = null;
let currentUser = null;
let currentProfile = null;

function toast(message) {
  if (typeof window.toast === 'function') window.toast(message);
  else window.alert(message);
}

function applySession(user, profile) {
  currentUser = user;
  currentProfile = profile;
  const isOwner = profile?.role === 'owner';
  roleSelect.value = isOwner ? 'teacher' : 'student';
  document.querySelectorAll('#mainNav [data-role="teacher"]').forEach(button => {
    button.hidden = !isOwner;
  });
  loginButton.textContent = user ? 'تسجيل الخروج' : 'تسجيل الدخول';
  const displayName = profile?.display_name || user?.email?.split('@')[0] || 'طالب';
  document.getElementById('userAvatar').textContent = displayName.slice(0, 2);
  window.medad = { client, user, profile };
  if (user && profile && !localStorage.getItem(`medad-welcome-${user.id}`)) {
    localStorage.setItem(`medad-welcome-${user.id}`, '1');
    if (typeof window.notifyFirstVisit === 'function') window.notifyFirstVisit();
  }
}

async function refreshSession(user, shouldRedirect = false) {
  if (!user) {
    applySession(null, null);
    window.medadClearStudentData?.();
    await window.medadLoadCourses?.(client, false);
    return;
  }

  const { data, error } = await client
    .from('profiles')
    .select('id, display_name, avatar_url, phone, guardian_phone, grade, role')
    .eq('id', user.id)
    .maybeSingle();

  if (error) {
    toast('تعذر تحميل ملف الحساب. تأكد من تطبيق migration في Supabase.');
    applySession(user, null);
    return;
  }

  applySession(user, data);
  await window.medadLoadCourses?.(client, data?.role === 'owner');
  if (data?.role !== 'owner') {
    await window.medadLoadStudentDashboard?.(client, user);
  }
  if (shouldRedirect) window.medadNavigate?.(data?.role === 'owner' ? 'teacher' : 'student');
}

function closeAuthDialog() {
  document.getElementById('authOverlay')?.remove();
}

function openAuthDialog(mode = 'login') {
  closeAuthDialog();
  const overlay = document.createElement('div');
  overlay.id = 'authOverlay';
  overlay.className = 'modal-backdrop';
  overlay.innerHTML = `
    <form class="modal" id="authForm">
      <h2>${mode === 'signup' ? 'إنشاء حساب طالب' : 'تسجيل الدخول'}</h2>
      <p>${mode === 'signup' ? 'أول حساب يُنشأ يصبح حساب المدير والمدرس، وبعده تُنشأ حسابات الطلاب من هنا.' : 'استخدم بريدك وكلمة مرورك، وسنفتح لك لوحتك تلقائيًا حسب دورك.'}</p>
      ${mode === 'signup' ? '<label>اسم الطالب</label><input name="displayName" required autocomplete="name" maxlength="100" placeholder="الاسم بالكامل"><label>رقم الهاتف</label><input name="phone" type="tel" required autocomplete="tel" maxlength="30" placeholder="رقم الطالب"><label>رقم ولي الأمر</label><input name="guardianPhone" type="tel" required autocomplete="tel" maxlength="30" placeholder="رقم ولي الأمر"><label>الصف الدراسي</label><input name="grade" required maxlength="100" placeholder="مثل: الصف الثالث الإعدادي">' : ''}
      <label>البريد الإلكتروني</label><input name="email" type="email" required autocomplete="email" placeholder="name@example.com">
      <label>كلمة المرور</label><input name="password" type="password" required minlength="8" autocomplete="${mode === 'signup' ? 'new-password' : 'current-password'}" placeholder="8 أحرف على الأقل">
      <div id="authError" role="status" style="color:#b13e2d;font-size:10px;margin-top:8px"></div>
      <div class="modal-actions">
        <button class="primary" type="submit">${mode === 'signup' ? 'إنشاء الحساب' : 'دخول'}</button>
        <button class="secondary" type="button" id="closeAuth">إغلاق</button>
      </div>
      <button type="button" data-auth-mode="${mode === 'signup' ? 'login' : 'signup'}" style="border:0;background:none;color:#24664e;padding:12px 0 0;font:inherit;font-size:10px">
        ${mode === 'signup' ? 'لديك حساب؟ سجّل الدخول' : 'طالب جديد؟ أنشئ حسابًا'}
      </button>
      ${mode === 'login' ? '<a href="/student-signup.html" style="display:block;color:#24664e;font-size:10px;padding-top:8px">فتح صفحة إنشاء حساب الطالب</a>' : ''}
    </form>`;
  document.body.append(overlay);

  overlay.querySelector('#closeAuth').addEventListener('click', closeAuthDialog);
  overlay.addEventListener('click', event => {
    if (event.target === overlay) closeAuthDialog();
  });
  overlay.querySelector('[data-auth-mode]').addEventListener('click', event => {
    event.preventDefault();
    openAuthDialog(event.currentTarget.dataset.authMode);
  });
  overlay.querySelector('#authForm').addEventListener('submit', async event => {
    event.preventDefault();
    const form = event.currentTarget;
    const submit = form.querySelector('[type="submit"]');
    const values = new FormData(form);
    submit.disabled = true;
    overlay.querySelector('#authError').textContent = '';

    try {
      const credentials = {
        email: String(values.get('email')).trim().toLowerCase(),
        password: values.get('password')
      };
      if (mode === 'signup') {
        const { data, error } = await client.auth.signUp({
          ...credentials,
          options: {
            data: {
              display_name: String(values.get('displayName')).trim(),
              phone: String(values.get('phone')).trim(),
              guardian_phone: String(values.get('guardianPhone')).trim(),
              grade: String(values.get('grade')).trim()
            },
            emailRedirectTo: window.location.origin
          }
        });
        if (error) throw error;
        if (!data.session) {
          overlay.querySelector('#authError').textContent = 'تم إنشاء الحساب. افحص بريدك لتأكيده ثم سجّل الدخول.';
          return;
        }
        closeAuthDialog();
        await refreshSession(data.user, true);
        toast('تم إنشاء الحساب. أهلاً بك في منصة المؤرخ الصغير.');
      } else {
        const { data, error } = await client.auth.signInWithPassword(credentials);
        if (error) throw error;
        closeAuthDialog();
        await refreshSession(data.user, true);
        toast('تم تسجيل الدخول بنجاح.');
      }
    } catch (error) {
      overlay.querySelector('#authError').textContent = error.message || 'تعذر إتمام العملية.';
    } finally {
      submit.disabled = false;
    }
  });
}

document.addEventListener('click', async event => {
  const subscriptionButton = event.target.closest('[data-subscribe-course]');
  if (subscriptionButton) {
    event.preventDefault();
    event.stopImmediatePropagation();
    if (!currentUser) {
      toast('سجّل الدخول لطلب الاشتراك.');
      if (client) openAuthDialog();
      return;
    }
    if (currentProfile?.role === 'owner') {
      toast('هذا الإجراء مخصص لحساب الطالب.');
      return;
    }
    subscriptionButton.disabled = true;
    const { data, error } = await client.rpc('request_course_subscription', {
      p_course_id: subscriptionButton.dataset.subscribeCourse
    });
    subscriptionButton.disabled = false;
    if (error) {
      toast(error.message || 'تعذر إنشاء طلب الاشتراك.');
      return;
    }
    if (data?.status === 'active') {
      toast('تم تفعيل اشتراكك. يمكنك متابعة التعلم الآن.');
      await refreshSession(currentUser);
    } else {
      subscriptionButton.textContent = 'بانتظار تأكيد الدفع';
      subscriptionButton.disabled = true;
      toast('تم تسجيل طلب الاشتراك، ويُفعّل بعد تأكيد الدفع.');
    }
    return;
  }

  const loginClick = event.target.closest('#loginBtn');
  if (loginClick) {
    event.preventDefault();
    event.stopImmediatePropagation();
    if (!client) {
      toast('خدمة الحسابات غير مهيأة بعد. أكمل إعداد Supabase ومتغيرات Vercel أولًا.');
      return;
    }
    if (currentUser) {
      const { error } = await client.auth.signOut();
      if (error) toast('تعذر تسجيل الخروج.');
      else toast('تم تسجيل الخروج.');
      return;
    }
    openAuthDialog();
    return;
  }

  const adminEntry = event.target.closest('[data-admin-entry]');
  if (adminEntry) {
    event.preventDefault();
    if (!client) {
      toast('خدمة الحسابات غير مهيأة بعد. أكمل إعداد Supabase ومتغيرات Vercel أولًا.');
    } else if (!currentUser) {
      openAuthDialog();
    } else if (currentProfile?.role === 'owner') {
      window.medadNavigate?.('teacher');
    } else {
      toast('رابط admin متاح لمدير المنصة فقط.');
    }
    return;
  }

  const roleButton = event.target.closest('#mainNav [data-role]');
  if (roleButton) {
    const needsOwner = roleButton.dataset.role === 'teacher';
    if (!currentUser || (needsOwner && currentProfile?.role !== 'owner')) {
      event.preventDefault();
      event.stopImmediatePropagation();
      toast(needsOwner ? 'هذه اللوحة متاحة لحساب مالك المنصة فقط.' : 'سجّل الدخول لعرض لوحة الطالب.');
      if (!currentUser && client) openAuthDialog();
      return;
    }
  }

  if (event.target.closest('[data-course], [data-open-course]') && !currentUser) {
    event.preventDefault();
    event.stopImmediatePropagation();
    toast('سجّل الدخول لمتابعة الدرس.');
    if (client) openAuthDialog();
  }
}, true);

try {
  const response = await fetch('/api/config', { cache: 'no-store' });
  if (!response.ok) throw new Error('Supabase is not configured');
  const config = await response.json();
  client = createClient(config.supabaseUrl, config.anonKey, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
  });
  const { data, error } = await client.auth.getSession();
  if (error) throw error;
  await refreshSession(data.session?.user || null);
  if (new URLSearchParams(window.location.search).has('admin')) {
    if (!currentUser) openAuthDialog();
    else if (currentProfile?.role === 'owner') window.medadNavigate?.('teacher');
    else toast('رابط admin متاح لمدير المنصة فقط.');
  }
  client.auth.onAuthStateChange((_event, session) => {
    window.setTimeout(() => refreshSession(session?.user || null), 0);
  });
} catch {
  applySession(null, null);
}