const app = document.getElementById('app');

function ownerNotice(message) {
  if (typeof window.toast === 'function') window.toast(message);
}

function courseById(id) {
  return window.medadCourses?.find(course => String(course.id) === String(id));
}

async function loadSections(courseId) {
  const { data, error } = await window.medad.client
    .from('course_sections')
    .select('id,title,description,sort_order,lectures(id,title,description,summary,duration_seconds,completion_required_percent,is_published,sort_order,video_sources(video_id),lecture_resources(id,title,resource_type,storage_path,external_url))')
    .eq('course_id', courseId)
    .order('sort_order');
  if (error) throw error;
  return data || [];
}

function youtubeVideoId(value) {
  const text = value.trim();
  if (/^[A-Za-z0-9_-]{11}$/.test(text)) return text;
  return text.match(/(?:youtu\.be\/|youtube\.com\/(?:watch\?v=|embed\/|live\/|shorts\/))([A-Za-z0-9_-]{11})/)?.[1] || null;
}

function showForm(title, fields, submitLabel, onSubmit) {
  const overlay = document.getElementById('overlay');
  overlay.innerHTML = `<div class="modal-backdrop"><form class="modal" id="ownerForm"><h2>${title}</h2>${fields}<div id="ownerFormError" style="font-size:10px;color:#b13e2d" role="status"></div><div class="modal-actions"><button class="primary" type="submit">${submitLabel}</button><button class="secondary" type="button" id="ownerFormCancel">إلغاء</button></div></form></div>`;
  overlay.querySelector('#ownerFormCancel').onclick = () => { overlay.innerHTML = ''; };
  overlay.querySelector('#ownerForm').onsubmit = async event => {
    event.preventDefault();
    const form = event.currentTarget;
    const button = form.querySelector('[type="submit"]');
    const errorNode = form.querySelector('#ownerFormError');
    button.disabled = true;
    errorNode.textContent = 'جارٍ الحفظ...';
    try {
      await onSubmit(new FormData(form));
      overlay.innerHTML = '';
      ownerNotice('تم الحفظ بنجاح.');
    } catch (error) {
      errorNode.textContent = error.message || 'تعذر الحفظ.';
      button.disabled = false;
    }
  };
}

async function renderCourseManager(courseId) {
  const course = courseById(courseId);
  if (!course) return ownerNotice('لم يتم العثور على الكورس.');
  let sections;
  try {
    sections = await loadSections(course.id);
  } catch (error) {
    ownerNotice(error.message || 'تعذر تحميل الوحدات.');
    return;
  }
  const [{ data: quizzes, error: quizError }, { data: assignments, error: assignmentError }] = await Promise.all([
    window.medad.client.from('quizzes').select('id,title,max_attempts,is_published').eq('course_id', course.id).order('created_at'),
    window.medad.client.from('assignments').select('id,title,due_at,max_score,is_published').eq('course_id', course.id).order('created_at')
  ]);
  if (quizError || assignmentError) return ownerNotice(quizError?.message || assignmentError?.message || 'تعذر تحميل الاختبارات والواجبات.');

  app.innerHTML = `
    <section class="fade-in">
      <button class="text-btn" id="backToOwnerDashboard">← لوحة المدرس</button>
      <div class="dashboard-head"><div><div class="eyebrow">إدارة المحتوى</div><h1>${course.title}</h1><p>${course.subject} · ${course.grade || ''}</p></div><div><button class="secondary" id="addQuiz">＋ اختبار</button> <button class="secondary" id="addAssignment">＋ واجب</button> <button class="primary" id="addSection">＋ إضافة وحدة</button></div></div>
      <div class="panel">
        <h2>الوحدات والمحاضرات <span style="color:var(--muted);font-size:10px;font-weight:400">${sections.length} وحدة</span></h2>
        ${sections.length ? sections.map(section => `
          <section style="border-top:1px solid var(--line);padding:14px 0">
            <div style="display:flex;justify-content:space-between;align-items:center;gap:12px"><strong>${section.title}</strong><button class="secondary" data-add-lecture="${section.id}">＋ محاضرة</button></div>
            <div style="font-size:10px;color:var(--muted);margin-top:8px">${section.lectures?.length ? section.lectures.map(lecture => `<div style="padding:7px 0;border-top:1px solid #eef1ed;display:flex;justify-content:space-between;gap:10px"><span>${lecture.title}</span><span>${lecture.is_published ? 'منشورة' : 'مسودة'}　${lecture.video_sources?.length ? '· فيديو مرتبط' : '· دون فيديو'}</span><button class="text-btn" data-add-resource="${lecture.id}">＋ ملف</button></div>`).join('') : '<div style="padding:8px 0;color:var(--muted)">لا توجد محاضرات بعد.</div>'}</div>
          </section>`).join('') : '<p style="font-size:11px;color:var(--muted)">ابدأ بإضافة الوحدة الأولى إلى الكورس.</p>'}
      </div>
      <div class="panel dashboard-lower"><h2>الاختبارات</h2>${quizzes?.length ? quizzes.map(quiz => `<div class="notice"><i class="notice-mark" style="background:var(--green)"></i><div>${quiz.title}<small>${quiz.max_attempts} محاولات · ${quiz.is_published?'منشور':'مسودة'}</small></div><button class="text-btn" data-toggle-quiz="${quiz.id}" data-published="${quiz.is_published}">${quiz.is_published?'إخفاء':'نشر'}</button></div>`).join('') : '<p style="font-size:10px;color:var(--muted)">لا توجد اختبارات لهذا الكورس.</p>'}</div>
      <div class="panel dashboard-lower"><h2>الواجبات</h2>${assignments?.length ? assignments.map(assignment => `<div class="notice"><i class="notice-mark" style="background:var(--yellow)"></i><div>${assignment.title}<small>آخر موعد: ${assignment.due_at?new Date(assignment.due_at).toLocaleDateString('ar-EG'):'غير محدد'} · ${assignment.is_published?'منشور':'مسودة'}</small></div><button class="text-btn" data-toggle-assignment="${assignment.id}" data-published="${assignment.is_published}">${assignment.is_published?'إخفاء':'نشر'}</button></div>`).join('') : '<p style="font-size:10px;color:var(--muted)">لا توجد واجبات لهذا الكورس.</p>'}</div>
    </section>`;

  document.getElementById('backToOwnerDashboard').onclick = () => {
    document.querySelector('#mainNav [data-role="teacher"]')?.click();
  };
  document.querySelectorAll('[data-toggle-quiz]').forEach(button => {
    button.onclick = async () => {
      const { error } = await window.medad.client.from('quizzes').update({ is_published: button.dataset.published !== 'true' }).eq('id', button.dataset.toggleQuiz);
      if (error) return ownerNotice(error.message || 'تعذر تحديث حالة الاختبار.');
      await renderCourseManager(course.id);
    };
  });
  document.querySelectorAll('[data-toggle-assignment]').forEach(button => {
    button.onclick = async () => {
      const { error } = await window.medad.client.from('assignments').update({ is_published: button.dataset.published !== 'true' }).eq('id', button.dataset.toggleAssignment);
      if (error) return ownerNotice(error.message || 'تعذر تحديث حالة الواجب.');
      await renderCourseManager(course.id);
    };
  });
  document.getElementById('addSection').onclick = () => showForm('إضافة وحدة', '<label>اسم الوحدة</label><input name="title" required maxlength="180" placeholder="مثال: الحملة الفرنسية"><label>نبذة عن الوحدة</label><textarea name="description" maxlength="2000"></textarea>', 'حفظ الوحدة', async values => {
    const { error } = await window.medad.client.from('course_sections').insert({
      course_id: course.id,
      title: String(values.get('title')).trim(),
      description: String(values.get('description') || '').trim(),
      sort_order: sections.length
    });
    if (error) throw error;
    course.sections = undefined;
    await renderCourseManager(course.id);
  });
  document.getElementById('addQuiz').onclick = () => showForm('إنشاء اختبار اختيار من متعدد', '<label>عنوان الاختبار</label><input name="title" required maxlength="180"><label>عدد المحاولات</label><input name="attempts" type="number" min="1" value="1" required><label>مدة الاختبار بالدقائق (اختياري)</label><input name="duration" type="number" min="1"><label>السؤال الأول</label><textarea name="question" required maxlength="3000"></textarea><label>الخيار الأول</label><input name="choice1" required><label>الخيار الثاني</label><input name="choice2" required><label>الخيار الثالث</label><input name="choice3" required><label>الخيار الرابع</label><input name="choice4" required><label>رقم الإجابة الصحيحة</label><select name="correct"><option value="0">الخيار الأول</option><option value="1">الخيار الثاني</option><option value="2">الخيار الثالث</option><option value="3">الخيار الرابع</option></select><label>درجة السؤال</label><input name="points" type="number" min="0" step="0.5" value="1" required>', 'حفظ الاختبار كمسودة', async values => {
    const { data: quiz, error } = await window.medad.client.from('quizzes').insert({
      course_id: course.id,
      title: String(values.get('title')).trim(),
      max_attempts: Number(values.get('attempts')),
      duration_minutes: values.get('duration') ? Number(values.get('duration')) : null,
      is_published: false
    }).select('id').single();
    if (error) throw error;
    const { data: question, error: questionError } = await window.medad.client.from('quiz_questions').insert({
      quiz_id: quiz.id,
      prompt: String(values.get('question')).trim(),
      question_type: 'multiple_choice',
      points: Number(values.get('points')),
      sort_order: 0
    }).select('id').single();
    if (questionError) throw new Error(`تم حفظ الاختبار لكن تعذرت إضافة السؤال: ${questionError.message}`);
    const { data: choices, error: choicesError } = await window.medad.client.from('quiz_choices').insert([1,2,3,4].map((number,index)=>({
      question_id: question.id,
      choice_text: String(values.get(`choice${number}`)).trim(),
      sort_order: index
    }))).select('id');
    if (choicesError) throw new Error(`تم حفظ السؤال لكن تعذرت إضافة الاختيارات: ${choicesError.message}`);
    const { error: answerError } = await window.medad.client.from('quiz_answer_keys').insert({
      question_id: question.id,
      correct_choice_id: choices[Number(values.get('correct'))].id
    });
    if (answerError) throw new Error(`تم حفظ الاختيارات لكن تعذر حفظ الإجابة الصحيحة: ${answerError.message}`);
    await renderCourseManager(course.id);
  });
  document.getElementById('addAssignment').onclick = () => showForm('إنشاء واجب', '<label>عنوان الواجب</label><input name="title" required maxlength="180"><label>التعليمات</label><textarea name="instructions" required maxlength="5000"></textarea><label>موعد التسليم</label><input name="dueAt" type="datetime-local"><label>الدرجة النهائية</label><input name="maxScore" type="number" min="0" value="100" required>', 'حفظ الواجب كمسودة', async values => {
    const dueAt = values.get('dueAt');
    const { error } = await window.medad.client.from('assignments').insert({
      course_id: course.id,
      title: String(values.get('title')).trim(),
      instructions: String(values.get('instructions')).trim(),
      due_at: dueAt ? new Date(dueAt).toISOString() : null,
      max_score: Number(values.get('maxScore')),
      is_published: false
    });
    if (error) throw error;
    await renderCourseManager(course.id);
  });

  document.querySelectorAll('[data-add-lecture]').forEach(button => {
    button.onclick = () => {
      const section = sections.find(item => item.id === button.dataset.addLecture);
      showForm('إضافة محاضرة', '<label>عنوان المحاضرة</label><input name="title" required maxlength="180"><label>وصف</label><textarea name="description" maxlength="3000"></textarea><label>ملخص الدرس</label><textarea name="summary" maxlength="6000"></textarea><label>رابط فيديو YouTube</label><input name="youtube" type="url" placeholder="https://youtu.be/VIDEO_ID"><label>مدة المحاضرة بالثواني</label><input name="duration" type="number" min="1" required><label>نسبة الإكمال المطلوبة</label><input name="completion" type="number" min="1" max="100" value="90" required><label><input name="speed" type="checkbox" checked> السماح بتغيير سرعة التشغيل</label><label><input name="published" type="checkbox"> نشر المحاضرة</label>', 'حفظ المحاضرة', async values => {
        const source = String(values.get('youtube') || '').trim();
        const videoId = source ? youtubeVideoId(source) : null;
        if (source && !videoId) throw new Error('رابط YouTube أو معرّف الفيديو غير صالح.');
        const { data: lecture, error } = await window.medad.client.from('lectures').insert({
          section_id: section.id,
          title: String(values.get('title')).trim(),
          description: String(values.get('description') || '').trim(),
          summary: String(values.get('summary') || '').trim(),
          duration_seconds: Number(values.get('duration')),
          completion_required_percent: Number(values.get('completion')),
          is_published: values.get('published') === 'on',
          sort_order: section.lectures?.length || 0
        }).select('id').single();
        if (error) throw error;
        if (videoId) {
          const { error: sourceError } = await window.medad.client.from('video_sources').insert({
            lecture_id: lecture.id,
            video_id: videoId,
            playback_speed_enabled: values.get('speed') === 'on'
          });
          if (sourceError) throw new Error(`حُفظت المحاضرة لكن تعذر حفظ رابط الفيديو: ${sourceError.message}`);
        }
        course.sections = undefined;
        await renderCourseManager(course.id);
      });
    };
  });

  document.querySelectorAll('[data-add-resource]').forEach(button => {
    button.onclick = () => showForm('إضافة ملف للمحاضرة', '<label>عنوان المورد</label><input name="title" required maxlength="180"><label>نوع المورد</label><select name="type"><option value="pdf">ملف PDF</option><option value="summary">ملخص</option><option value="link">رابط خارجي</option></select><label>ملف PDF (اختياري)</label><input name="file" type="file" accept="application/pdf"><label>رابط خارجي (اختياري)</label><input name="url" type="url"><label><input name="downloadable" type="checkbox" checked> السماح بالتنزيل</label><label><input name="afterCompletion" type="checkbox"> إتاحته بعد إكمال المحاضرة</label>', 'حفظ المورد', async values => {
        const lectureId = button.dataset.addResource;
        const file = values.get('file');
        const externalUrl = String(values.get('url') || '').trim();
        if ((!file || !file.size) && !externalUrl) throw new Error('اختر ملفًا أو أدخل رابطًا.');
        let storagePath = null;
        if (file?.size) {
          if (file.type !== 'application/pdf') throw new Error('الملفات المسموح بها حاليًا PDF فقط.');
          if (file.size > 20 * 1024 * 1024) throw new Error('الحد الأقصى لحجم الملف 20 ميغابايت.');
          const safeName = file.name.replace(/[^\w.-]/g, '_');
          storagePath = `${course.id}/${lectureId}/${crypto.randomUUID()}-${safeName}`;
          const { error: uploadError } = await window.medad.client.storage.from('course-resources').upload(storagePath, file, { contentType: 'application/pdf', upsert: false });
          if (uploadError) throw uploadError;
        }
        const { error } = await window.medad.client.from('lecture_resources').insert({
          lecture_id: lectureId,
          title: String(values.get('title')).trim(),
          resource_type: String(values.get('type')),
          storage_path: storagePath,
          external_url: externalUrl || null,
          downloadable: values.get('downloadable') === 'on',
          available_after_completion: values.get('afterCompletion') === 'on'
        });
        if (error) throw error;
        course.sections = undefined;
        await renderCourseManager(course.id);
      });
    };
  });
}

async function renderSubscriptionRequests() {
  const { data: requests, error } = await window.medad.client
    .from('subscriptions')
    .select('id,student_id,course_id,created_at,profiles(display_name,email),courses(title,price_minor,currency)')
    .eq('status', 'pending')
    .order('created_at', { ascending: true });
  if (error) return ownerNotice(error.message || 'تعذر تحميل طلبات الاشتراك.');

  app.innerHTML = `<section class="fade-in"><button class="text-btn" id="backToOwnerDashboard">← لوحة المدرس</button><div class="dashboard-head"><div><div class="eyebrow">مراجعة يدوية</div><h1>طلبات الاشتراك</h1><p>فعّل الطلب بعد التأكد من الدفع خارج المنصة.</p></div></div><div class="panel"><table class="dashboard-table"><thead><tr><th>الطالب</th><th>الكورس</th><th>القيمة</th><th>تاريخ الطلب</th><th>الإجراء</th></tr></thead><tbody>${requests?.length ? requests.map(request => `<tr><td>${request.profiles?.display_name || request.profiles?.email || request.student_id}</td><td>${request.courses?.title || 'كورس محذوف'}</td><td>${((request.courses?.price_minor || 0) / 100).toFixed(2)} ${request.courses?.currency || 'EGP'}</td><td>${new Date(request.created_at).toLocaleDateString('ar-EG')}</td><td><button class="primary" data-activate-subscription="${request.id}" data-student-id="${request.student_id}" data-course-id="${request.course_id}">تفعيل بعد تأكيد الدفع</button></td></tr>`).join('') : '<tr><td colspan="5">لا توجد طلبات معلقة.</td></tr>'}</tbody></table></div></section>`;

  document.getElementById('backToOwnerDashboard').onclick = () => document.querySelector('#mainNav [data-role="teacher"]')?.click();
  document.querySelectorAll('[data-activate-subscription]').forEach(button => {
    button.onclick = async () => {
      if (window.medad?.profile?.role !== 'owner') return ownerNotice('هذه العملية متاحة لمالك المنصة فقط.');
      button.disabled = true;
      const { error: updateError } = await window.medad.client
        .from('subscriptions')
        .update({ status: 'active', starts_at: new Date().toISOString() })
        .eq('id', button.dataset.activateSubscription)
        .eq('status', 'pending');
      if (updateError) {
        button.disabled = false;
        return ownerNotice(updateError.message || 'تعذر تفعيل الاشتراك.');
      }
      const { error: enrollmentError } = await window.medad.client.from('enrollments').upsert({
        student_id: button.dataset.studentId,
        course_id: button.dataset.courseId,
        subscription_id: button.dataset.activateSubscription,
        status: 'active'
      }, { onConflict: 'student_id,course_id' });
      if (enrollmentError) return ownerNotice('تم تفعيل الاشتراك لكن تعذر تحديث سجل الالتحاق: ' + enrollmentError.message);
      await window.medad.client.from('notifications').insert({
        student_id: button.dataset.studentId,
        title: 'تم تفعيل اشتراكك',
        body: 'أصبح الكورس متاحًا في لوحة تعلمك.',
        notification_type: 'subscription'
      });
      ownerNotice('تم تفعيل اشتراك الطالب وإشعاره.');
      await renderSubscriptionRequests();
    };
  });
}

window.openCourseManager = courseId => {
  if (window.medad?.profile?.role !== 'owner') return ownerNotice('هذه العملية متاحة لمالك المنصة فقط.');
  return renderCourseManager(courseId);
};

const ownerDashboardObserver = new MutationObserver(() => {
  if (window.medad?.profile?.role !== 'owner' || !document.querySelector('.dashboard-head h1')?.textContent.includes('لوحة مستر إياد')) return;
  const dashboardHead = document.querySelector('.dashboard-head');
  if (dashboardHead && !dashboardHead.querySelector('[data-open-subscriptions]')) {
    dashboardHead.insertAdjacentHTML('beforeend', '<button class="secondary" data-open-subscriptions>طلبات الاشتراك</button>');
  }
  if (dashboardHead && !dashboardHead.querySelector('[data-send-announcement]')) {
    dashboardHead.insertAdjacentHTML('beforeend', '<button class="secondary" data-send-announcement>إشعار للطلاب</button>');
  }
  const table = document.querySelector('.dashboard-lower .dashboard-table');
  if (!table) return;
  const header = table.tHead?.rows[0];
  if (header && !header.querySelector('[data-manage-header]')) header.insertAdjacentHTML('beforeend', '<th data-manage-header>إدارة المحتوى</th>');
  [...table.tBodies[0]?.rows || []].forEach((row, index) => {
    if (row.querySelector('[data-manage-course]')) return;
    const course = window.medadCourses?.[index];
    if (course) row.insertAdjacentHTML('beforeend', `<td><button class="text-btn" data-manage-course="${course.id}">الوحدات والمحاضرات ←</button></td>`);
  });
});
ownerDashboardObserver.observe(app, { childList: true, subtree: true });

document.addEventListener('click', event => {
  const announcementButton = event.target.closest('[data-send-announcement]');
  if (announcementButton) {
    event.preventDefault();
    event.stopImmediatePropagation();
    if (window.medad?.profile?.role !== 'owner') return ownerNotice('هذه العملية متاحة لمالك المنصة فقط.');
    showForm('إرسال إشعار للطلاب', '<label>عنوان الإشعار</label><input name="title" required maxlength="180"><label>نص الإشعار</label><textarea name="body" required maxlength="3000"></textarea>', 'إرسال', async values => {
      const { error } = await window.medad.client.from('notifications').insert({
        student_id: null,
        title: String(values.get('title')).trim(),
        body: String(values.get('body')).trim(),
        notification_type: 'announcement'
      });
      if (error) throw error;
    });
    return;
  }

  const subscriptionButton = event.target.closest('[data-open-subscriptions]');
  if (subscriptionButton) {
    event.preventDefault();
    event.stopImmediatePropagation();
    if (window.medad?.profile?.role === 'owner') renderSubscriptionRequests();
    return;
  }

  const button = event.target.closest('[data-manage-course]');
  if (!button) return;
  event.preventDefault();
  event.stopImmediatePropagation();
  window.openCourseManager(button.dataset.manageCourse);
}, true);