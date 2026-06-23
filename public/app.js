(() => {
  const supportsWebAuthn = 'PublicKeyCredential' in window;

  const elements = createElementsMap();
  const showToast = createToaster(document.getElementById('toast-region'));
  const status = createStatusManager(elements.statuses, showToast);
  const session = createSessionManager(elements.session);
  const state = {
    emailLoginChallenge: null,
  };

  const api = createApi();
  const webAuthn = createWebAuthnHelpers();

  const userFlow = createUserFlow({ api, session, status, state });
  const emailVerificationFlow = createEmailVerificationFlow({
    api,
    session,
    status,
    inputs: elements.inputs,
    emailsList: elements.emailsList,
  });
  const emailsFlow = createEmailsFlow({
    api,
    session,
    status,
    emailsList: elements.emailsList,
  });
  const emailLoginFlow = createEmailLoginFlow({
    api,
    session,
    status,
    inputs: elements.inputs,
    state,
  });
  const passkeyFlow = createPasskeyFlow({
    api,
    session,
    status,
    webAuthn,
    supportsWebAuthn,
  });
  const profileImageFlow = createProfileImageFlow({
    api,
    session,
    status,
    inputs: elements.inputs,
    preview: elements.profileImagePreview,
    currentProfile: elements.currentProfile,
  });
  const eventsFlow = createEventsFlow({ api, session, status });
  const logoutFlow = createLogoutFlow({ session, status, state, profileImageFlow });

  init();

  function init() {
    const {
      create,
      sendEmail,
      confirmEmail,
      loadEmails,
      addPasskey,
      login,
      startEmailLogin,
      completeEmailLogin,
      uploadProfileImage,
      logout,
      wineStyles,
      wineVarieties,
      wineRegionTypes,
      wineRegions,
      eventsList,
      eventCreate,
      eventGet,
      eventUpdate,
      questionCreate,
      questionUpdate,
      answerCreate,
      answerUpdate,
      responseCreate,
      responseUpdate,
    } = elements.buttons;

    bindAsync(create, userFlow);
    bindAsync(sendEmail, emailVerificationFlow.send);
    bindAsync(confirmEmail, emailVerificationFlow.confirm);
    bindAsync(loadEmails, emailsFlow);
    bindAsync(addPasskey, passkeyFlow.add);
    bindAsync(login, passkeyFlow.login);
    bindAsync(startEmailLogin, emailLoginFlow.start);
    bindAsync(completeEmailLogin, emailLoginFlow.complete);
    bindAsync(uploadProfileImage, profileImageFlow.uploadAndRegister);
    elements.inputs.profileImageFile.addEventListener('change', profileImageFlow.previewSelectedFile);
    logout.addEventListener('click', logoutFlow);

    bindAsync(wineStyles, eventsFlow.loadWineStyles);
    bindAsync(wineVarieties, eventsFlow.loadWineVarieties);
    bindAsync(wineRegionTypes, eventsFlow.loadWineRegionTypes);
    bindAsync(wineRegions, eventsFlow.loadWineRegions);
    bindAsync(eventsList, eventsFlow.listEvents);
    document.getElementById('event-add')?.addEventListener('click', () => eventsFlow.openEventDialog());
    bindAsync(eventCreate, eventsFlow.createEvent);
    bindAsync(eventGet, eventsFlow.getEvent);
    bindAsync(eventUpdate, eventsFlow.updateEvent);
    bindAsync(questionCreate, eventsFlow.createQuestion);
    bindAsync(questionUpdate, eventsFlow.updateQuestion);
    bindAsync(answerCreate, eventsFlow.createCorrectAnswer);
    bindAsync(answerUpdate, eventsFlow.updateCorrectAnswer);
    bindAsync(responseCreate, eventsFlow.createResponse);
    bindAsync(responseUpdate, eventsFlow.updateMyResponse);

    if (!supportsWebAuthn) {
      addPasskey.disabled = true;
      login.disabled = true;
      status.set('passkey', 'このブラウザーは WebAuthn をサポートしていません。', { error: true });
      status.set('login', 'このブラウザーは WebAuthn をサポートしていません。', { error: true });
    }

    setupTabs(document.querySelector('[role="tablist"]'), id => {
      if (id === 'events') eventsFlow.maybeAutoLoadEvents();
    });
    session.render();
  }

  // ARIA タブパターン: タブで対応するパネルを表示し、他を隠す。
  function setupTabs(tablist, onActivate) {
    if (!tablist) return;
    const tabs = Array.from(tablist.querySelectorAll('[role="tab"]'));
    if (tabs.length === 0) return;

    function activate(tab, { focus = false, updateHash = true } = {}) {
      for (const other of tabs) {
        const selected = other === tab;
        other.setAttribute('aria-selected', selected ? 'true' : 'false');
        other.tabIndex = selected ? 0 : -1;
        const panel = document.getElementById(other.getAttribute('aria-controls'));
        if (panel) panel.hidden = !selected;
      }
      if (focus) tab.focus();
      const activeId = tab.getAttribute('aria-controls');
      if (updateHash && activeId && location.hash !== `#${activeId}`) {
        history.replaceState(null, '', `#${activeId}`);
      }
      if (typeof onActivate === 'function') onActivate(activeId);
    }

    tablist.addEventListener('click', event => {
      const tab = event.target.closest('[role="tab"]');
      if (tab) activate(tab);
    });

    tablist.addEventListener('keydown', event => {
      const index = tabs.indexOf(document.activeElement);
      if (index === -1) return;
      let next = null;
      switch (event.key) {
        case 'ArrowRight':
        case 'ArrowDown': next = tabs[(index + 1) % tabs.length]; break;
        case 'ArrowLeft':
        case 'ArrowUp': next = tabs[(index - 1 + tabs.length) % tabs.length]; break;
        case 'Home': next = tabs[0]; break;
        case 'End': next = tabs[tabs.length - 1]; break;
        default: return;
      }
      event.preventDefault();
      activate(next, { focus: true });
    });

    // ブラウザの戻る/進むに追従。
    window.addEventListener('popstate', () => {
      const tab = tabFromHash();
      if (tab) activate(tab, { updateHash: false });
    });

    function tabFromHash() {
      const id = location.hash.slice(1);
      return id ? tabs.find(tab => tab.getAttribute('aria-controls') === id) ?? null : null;
    }

    // 初期表示: URL hash を優先、無ければ既定の選択タブ。
    const initial = tabFromHash() ?? tabs.find(tab => tab.getAttribute('aria-selected') === 'true') ?? tabs[0];
    activate(initial, { updateHash: false });
  }

  function createUserFlow({ api, session, status, state }) {
    return async function handleCreateUser() {
      status.set('create', 'ユーザー作成中...');
      status.clear('emailStart', 'emailConfirm', 'emails', 'passkey', 'login', 'emailLogin', 'logout');
      try {
        const payload = await api.createUser();
        session.apply(payload);
        session.updateEmails([]);
        renderEmailsList(elements.emailsList, []);
        state.emailLoginChallenge = null;
        status.set('create', 'ユーザーを作成しトークンを取得しました。');
      } catch (error) {
        console.error(error);
        status.set('create', error.message || 'ユーザー作成に失敗しました。', { error: true });
      }
    };
  }

  function createEmailVerificationFlow({ api, session, status, inputs, emailsList }) {
    const emailInput = inputs.email;
    const codeInput = inputs.code;

    return {
      async send() {
        const { token } = session.data;
        const email = emailInput.value.trim();
        if (!validate('emailStart', [
          { predicate: () => !!token, message: '先にユーザーを作成またはログインしてください。' },
          { predicate: () => email.length > 0, message: 'メールアドレスを入力してください。' },
        ])) {
          return;
        }

        status.set('emailStart', '確認メール送信中...');
        status.clear('emailConfirm', 'logout');
        try {
          await api.sendVerificationEmail({ email, token });
          status.set('emailStart', '確認メールを送信しました。');
        } catch (error) {
          console.error(error);
          status.set('emailStart', error.message || '確認メールの送信に失敗しました。', { error: true });
        }
      },

      async confirm() {
        const { token } = session.data;
        const email = emailInput.value.trim();
        const code = codeInput.value.trim();
        if (!validate('emailConfirm', [
          { predicate: () => !!token, message: '先にユーザーを作成またはログインしてください。' },
          { predicate: () => email.length > 0, message: 'メールアドレスを入力してください。' },
          { predicate: () => code.length > 0, message: '確認コードを入力してください。' },
        ])) {
          return;
        }

        status.set('emailConfirm', '確認コード送信中...');
        status.clear('logout');
        try {
          await api.confirmEmailAddress({ email, code, token });
          const emails = await api.fetchEmailsFromMe(token);
          session.updateEmails(emails);
          renderEmailsList(emailsList, emails);
          codeInput.value = '';
          status.set('emailConfirm', 'メールアドレスを認証しました。');
        } catch (error) {
          console.error(error);
          status.set('emailConfirm', error.message || 'メールアドレスの確認に失敗しました。', { error: true });
        }
      },
    };
  }

  function createEmailLoginFlow({ api, session, status, inputs, state }) {
    const emailInput = inputs.emailLoginEmail;
    const codeInput = inputs.emailLoginCode;

    return {
      async start() {
        const email = emailInput.value.trim();
        if (!validate('emailLogin', [
          { predicate: () => email.length > 0, message: 'メールアドレスを入力してください。' },
        ])) {
          return;
        }

        status.set('emailLogin', 'ログインコード送信中...');
        status.clear('logout', 'login');
        try {
          state.emailLoginChallenge = await api.sendEmailLoginChallenge(email);
          codeInput.value = '';
          status.set('emailLogin', '確認コードを送信しました。メールをご確認ください。');
        } catch (error) {
          console.error(error);
          status.set('emailLogin', error.message || 'ログインコードの送信に失敗しました。', { error: true });
        }
      },

      async complete() {
        const email = emailInput.value.trim();
        const otp = codeInput.value.trim();

        if (!validate('emailLogin', [
          { predicate: () => email.length > 0, message: 'メールアドレスを入力してください。' },
          { predicate: () => otp.length > 0, message: '確認コードを入力してください。' },
          { predicate: () => !!state.emailLoginChallenge, message: '先にログインコードを送信してください。' },
        ])) {
          return;
        }

        status.set('emailLogin', 'ログイン処理中...');
        status.clear('logout', 'login');
        try {
          const tokens = await api.exchangeEmailCodeForToken({
            email,
            otp,
            challenge: state.emailLoginChallenge,
          });
          state.emailLoginChallenge = null;
          session.apply(tokens);
          await refreshSessionEmails(tokens.token);
          codeInput.value = '';
          status.set('emailLogin', 'メールアドレスでログインしました。');
          status.clear('login');
        } catch (error) {
          console.error(error);
          status.set('emailLogin', error.message || 'メールでのログインに失敗しました。', { error: true });
        }
      },
    };
  }

  function createPasskeyFlow({ api, session, status, webAuthn, supportsWebAuthn }) {
    return {
      async add() {
        const { token, userID } = session.data;
        if (!validate('passkey', [
          { predicate: () => !!token, message: '先にユーザーを作成またはログインしてください。' },
          { predicate: () => !!userID, message: 'ユーザーIDを取得できませんでした。' },
          { predicate: () => supportsWebAuthn, message: 'このブラウザーは WebAuthn をサポートしていません。' },
        ])) {
          return;
        }

        status.set('passkey', 'チャレンジ取得中...');
        status.clear('logout');
        try {
          const challenge = await api.fetchChallenge({ token });
          const options = webAuthn.buildRegistrationOptions({
            challenge,
            userID,
            email: session.data.emails[0]?.email,
          });
          const credential = await navigator.credentials.create({ publicKey: options });
          if (!credential) {
            throw new Error('認証器がキャンセルされました。');
          }

          const payload = webAuthn.serializeRegistrationCredential(credential);
          await api.registerPasskey({ challenge, payload, token });
          status.set('passkey', 'Passkey を登録しました。');
        } catch (error) {
          console.error(error);
          status.set('passkey', error.message || 'Passkey登録に失敗しました。', { error: true });
        }
      },

      async login() {
        if (!validate('login', [
          { predicate: () => supportsWebAuthn, message: 'このブラウザーは WebAuthn をサポートしていません。' },
        ])) {
          return;
        }

        status.set('login', 'チャレンジ取得中...');
        status.clear('logout', 'emailLogin');
        try {
          const challenge = await api.fetchChallenge();
          const options = webAuthn.buildAuthenticationOptions(challenge);
          const credential = await navigator.credentials.get({ publicKey: options });
          if (!credential) {
            throw new Error('認証器がキャンセルされました。');
          }

          const payload = webAuthn.serializeAuthenticationCredential(credential, challenge);
          const tokens = await api.requestPasskeyToken(payload);
          session.apply(tokens);
          await refreshSessionEmails(tokens.token);
          status.set('login', 'Passkeyでログインしました。新しいトークンを取得しました。');
        } catch (error) {
          console.error(error);
          status.set('login', error.message || 'ログインに失敗しました。', { error: true });
        }
      },
    };
  }

  function createProfileImageFlow({ api, session, status, inputs, preview, currentProfile }) {
    let previewURL = null;
    let currentImageURL = null;

    function setPreview(file) {
      if (previewURL) {
        URL.revokeObjectURL(previewURL);
        previewURL = null;
      }
      if (!file) {
        preview.hidden = true;
        preview.removeAttribute('src');
        return;
      }
      previewURL = URL.createObjectURL(file);
      preview.src = previewURL;
      preview.hidden = false;
    }

    function setCurrentProfile({ profile, file }) {
      if (currentImageURL) {
        URL.revokeObjectURL(currentImageURL);
      }
      currentImageURL = URL.createObjectURL(file);
      currentProfile.image.src = profile.imageURL || currentImageURL;
      currentProfile.name.textContent = `名前: ${profile.name}`;
      currentProfile.imageURL.textContent = `画像URL: ${profile.imageURL || ''}`;
      currentProfile.container.hidden = false;
    }

    function resetDisplay() {
      if (previewURL) {
        URL.revokeObjectURL(previewURL);
        previewURL = null;
      }
      if (currentImageURL) {
        URL.revokeObjectURL(currentImageURL);
        currentImageURL = null;
      }
      preview.hidden = true;
      preview.removeAttribute('src');
      currentProfile.image.removeAttribute('src');
      currentProfile.name.textContent = '';
      currentProfile.imageURL.textContent = '';
      currentProfile.container.hidden = true;
    }

    return {
      previewSelectedFile() {
        setPreview(inputs.profileImageFile.files?.[0] ?? null);
      },

      resetDisplay,

      async uploadAndRegister() {
        const { token } = session.data;
        const name = inputs.profileName.value.trim();
        const file = inputs.profileImageFile.files?.[0] ?? null;

        if (!validate('profileImage', [
          { predicate: () => !!token, message: '先にユーザーを作成またはログインしてください。' },
          { predicate: () => name.length > 0, message: 'プロフィール名を入力してください。' },
          { predicate: () => name.length <= 100, message: 'プロフィール名は100文字以内で入力してください。' },
          { predicate: () => !!file, message: '画像ファイルを選択してください。' },
        ])) {
          return;
        }

        status.set('profileImage', 'アップロードURL取得中...');
        status.clear('logout');
        try {
          const upload = await api.createImageUploadURL(token);
          status.set('profileImage', '画像アップロード中...');
          await api.uploadImageFile({ uploadURL: upload.uploadURL, file });

          status.set('profileImage', '画像登録中...');
          const image = await api.createImage({ imageID: upload.imageID, token });

          status.set('profileImage', 'プロフィール登録中...');
          const profile = await api.createUserProfile({
            name,
            imageID: image.id,
            token,
          });

          session.updateProfile(profile);
          setCurrentProfile({ profile, file });
          status.set('profileImage', 'プロフィール画像を登録しました。');
        } catch (error) {
          console.error(error);
          status.set('profileImage', error.message || 'プロフィール画像の登録に失敗しました。', { error: true });
        }
      },
    };
  }

  function createLogoutFlow({ session, status, state, profileImageFlow }) {
    return function handleLogout() {
      session.reset();
      state.emailLoginChallenge = null;
      profileImageFlow.resetDisplay();
      renderEmailsList(elements.emailsList, []);
      status.set('logout', 'ログアウトしました。');
      status.clear('create', 'emailStart', 'emailConfirm', 'emails', 'passkey', 'login', 'emailLogin', 'profileImage');
    };
  }

  function createEmailsFlow({ api, session, status, emailsList }) {
    return async function handleLoadEmails() {
      const { token } = session.data;
      if (!validate('emails', [
        { predicate: () => !!token, message: '先にユーザーを作成またはログインしてください。' },
      ])) {
        return;
      }

      status.set('emails', 'メールアドレス取得中...');
      status.clear('logout');
      try {
        const emails = await api.fetchEmailsFromMe(token);
        session.updateEmails(emails);
        renderEmailsList(emailsList, emails);
        status.set('emails', emails.length > 0 ? 'メールアドレスを取得しました。' : '登録済みメールアドレスはありません。');
      } catch (error) {
        console.error(error);
        status.set('emails', error.message || 'メールアドレスの取得に失敗しました。', { error: true });
      }
    };
  }

  function createEventsFlow({ api, session, status }) {
    const val = id => document.getElementById(id)?.value ?? '';
    const setVal = (id, value) => {
      const el = document.getElementById(id);
      if (el) el.value = value;
    };
    const resultEl = id => document.getElementById(id);

    // multiple select で選択中の（空でない）値の配列を返す。
    const selectedValues = id => {
      const el = document.getElementById(id);
      if (!el) return [];
      return Array.from(el.selectedOptions).map(option => option.value).filter(value => value.length > 0);
    };

    // wine 参照データから select の option を再構築する（既存の選択は可能な範囲で維持）。
    function populateSelect(id, items, { placeholder } = {}) {
      const el = document.getElementById(id);
      if (!el) return;
      const multiple = el.multiple;
      const previous = multiple
        ? Array.from(el.selectedOptions).map(option => option.value)
        : el.value;
      el.replaceChildren();
      if (placeholder !== undefined) {
        const option = document.createElement('option');
        option.value = '';
        option.textContent = placeholder;
        el.appendChild(option);
      }
      for (const item of Array.isArray(items) ? items : []) {
        if (!item?.id) continue;
        const option = document.createElement('option');
        option.value = item.id;
        option.textContent = item.name ? `${item.name} (${item.id})` : item.id;
        el.appendChild(option);
      }
      if (multiple && Array.isArray(previous)) {
        for (const option of el.options) {
          if (previous.includes(option.value)) option.selected = true;
        }
      } else if (!multiple && typeof previous === 'string') {
        el.value = previous;
      }
    }

    function requireToken(statusKey) {
      const { token } = session.data;
      if (!token) {
        status.set(statusKey, '先にユーザーを作成またはログインしてください。', { error: true });
        return null;
      }
      return token;
    }

    function buildEventBody() {
      const body = {
        title: val('event-title').trim(),
        body: val('event-body').trim(),
        venueName: val('event-venue-name').trim(),
        visibility: val('event-visibility'),
      };
      assignIfPresent(body, 'imageID', val('event-image-id').trim());

      const venueAddress = {
        addressLine1: val('event-address-line1').trim(),
        countryCode: val('event-country-code').trim(),
      };
      assignIfPresent(venueAddress, 'addressLine2', val('event-address-line2').trim());
      assignIfPresent(venueAddress, 'locality', val('event-locality').trim());
      assignIfPresent(venueAddress, 'administrativeArea', val('event-administrative-area').trim());
      assignIfPresent(venueAddress, 'postalCode', val('event-postal-code').trim());
      body.venueAddress = venueAddress;

      const latitude = readNumber(val('event-latitude'));
      const longitude = readNumber(val('event-longitude'));
      if (latitude !== null && longitude !== null) {
        body.venueCoordinate = { latitude, longitude };
      }

      body.eventPeriod = {
        startsAt: referenceSecondsFromInput(val('event-period-start')),
        endsAt: referenceSecondsFromInput(val('event-period-end')),
      };

      const registrationStart = referenceSecondsFromInput(val('event-registration-start'));
      const registrationEnd = referenceSecondsFromInput(val('event-registration-end'));
      if (registrationStart !== null && registrationEnd !== null) {
        body.registrationPeriod = { startsAt: registrationStart, endsAt: registrationEnd };
      }

      assignIfPresent(body, 'answersPublishedAt', referenceSecondsFromInput(val('event-answer-published-at')));
      const capacity = readNumber(val('event-capacity'));
      assignIfPresent(body, 'capacity', capacity === null ? null : Math.round(capacity));

      const feeAmount = readNumber(val('event-fee-amount'));
      const feeCurrency = val('event-fee-currency').trim();
      if (feeAmount !== null && feeCurrency) {
        body.entryFee = { minorAmount: Math.round(feeAmount), currencyCode: feeCurrency };
      }

      return body;
    }

    function validateEventBody(statusKey, body) {
      return validate(statusKey, [
        { predicate: () => body.title.length > 0, message: 'タイトルを入力してください。' },
        { predicate: () => body.body.length > 0, message: '本文を入力してください。' },
        { predicate: () => body.venueName.length > 0, message: '会場名を入力してください。' },
        { predicate: () => body.venueAddress.addressLine1.length > 0, message: '住所1を入力してください。' },
        { predicate: () => body.venueAddress.countryCode.length > 0, message: '国コードを入力してください。' },
        { predicate: () => body.eventPeriod.startsAt !== null, message: '開催開始日時を入力してください。' },
        { predicate: () => body.eventPeriod.endsAt !== null, message: '開催終了日時を入力してください。' },
      ]);
    }

    function buildAnswerLikeBody(prefix, { withNote = false } = {}) {
      const body = { wineVarietyIDs: selectedValues(`${prefix}-variety-ids`) };
      assignIfPresent(body, 'wineStyleID', val(`${prefix}-wine-style-id`).trim());
      assignIfPresent(body, 'wineRegionID', val(`${prefix}-wine-region-id`).trim());
      assignIfPresent(body, 'vintage', readNumber(val(`${prefix}-vintage`)));
      assignIfPresent(body, 'alcoholByVolume', readNumber(val(`${prefix}-abv`)));
      if (withNote) {
        assignIfPresent(body, 'note', val(`${prefix}-note`).trim());
      }
      return body;
    }

    // 取得済みの参照データをキャッシュし、品種→スタイル名や地域→タイプ名の解決に使う。
    const wineCache = { styles: [], varieties: [], region_types: [], regions: [] };

    const WINE_LABELS = { styles: 'スタイル', varieties: '品種', region_types: '地域タイプ', regions: '地域' };

    function nameFor(kind, id) {
      if (!id) return null;
      const item = (wineCache[kind] || []).find(entry => entry?.id === id);
      return item?.name ?? null;
    }

    function shortId(id) {
      return typeof id === 'string' && id.length > 10 ? `${id.slice(0, 8)}…` : (id ?? '');
    }

    async function copyText(text, button) {
      try {
        await navigator.clipboard.writeText(text);
      } catch {
        const area = document.createElement('textarea');
        area.value = text;
        area.style.position = 'fixed';
        area.style.opacity = '0';
        document.body.appendChild(area);
        area.select();
        try { document.execCommand('copy'); } catch { /* noop */ }
        area.remove();
      }
      const previous = button.textContent;
      button.textContent = 'コピー済み ✓';
      button.classList.add('is-copied');
      setTimeout(() => {
        button.textContent = previous;
        button.classList.remove('is-copied');
      }, 1500);
    }

    // ID + コピーボタンの塊（テーブルセルでもツリー行でも使う）。
    function buildIdControl(id) {
      const wrap = document.createElement('span');
      wrap.className = 'cell-id';
      const code = document.createElement('code');
      code.textContent = id ?? '—';
      wrap.appendChild(code);
      if (id) {
        const button = document.createElement('button');
        button.type = 'button';
        button.className = 'copy-btn';
        button.textContent = 'コピー';
        button.setAttribute('aria-label', `ID ${id} をコピー`);
        button.addEventListener('click', () => copyText(id, button));
        wrap.appendChild(button);
      }
      return wrap;
    }

    function renderIdCell(td, id) {
      td.appendChild(buildIdControl(id));
    }

    function renderRefCell(td, id, kind) {
      if (!id) { td.textContent = '—'; return; }
      const name = nameFor(kind, id);
      if (name) {
        td.textContent = name;
      } else {
        td.textContent = shortId(id);
        td.title = id; // フル ID をツールチップで補完
      }
    }

    function renderChips(td, ids, kind) {
      td.className = 'cell-chips';
      const list = Array.isArray(ids) ? ids : [];
      if (list.length === 0) { td.textContent = '—'; return; }
      for (const id of list) {
        const chip = document.createElement('span');
        chip.className = 'chip';
        const name = nameFor(kind, id);
        chip.textContent = name ?? shortId(id);
        if (!name) chip.title = id;
        td.appendChild(chip);
      }
    }

    function columnsFor(kind) {
      const nameCol = { label: '名前', render: (td, i) => { td.className = 'cell-name'; td.textContent = i?.name ?? '—'; } };
      const codeCol = {
        label: 'コード',
        render: (td, i) => {
          if (i?.code) {
            const code = document.createElement('code');
            code.className = 'code-chip';
            code.textContent = i.code;
            td.appendChild(code);
          } else {
            td.textContent = '—';
          }
        },
      };
      const idCol = { label: 'ID', render: (td, i) => renderIdCell(td, i?.id) };

      switch (kind) {
        case 'styles':
        case 'region_types':
          return [nameCol, codeCol, idCol];
        case 'varieties':
          return [nameCol, { label: 'スタイル', render: (td, i) => renderChips(td, i?.wineStyleIDs, 'styles') }, idCol];
        case 'regions':
          return [
            nameCol,
            { label: 'タイプ', render: (td, i) => renderRefCell(td, i?.wineRegionTypeID, 'region_types') },
            { label: '親地域', render: (td, i) => renderRefCell(td, i?.parentRegionID, 'regions') },
            idCol,
          ];
        default:
          return [nameCol, idCol];
      }
    }

    // 地域行（名前 + タイプ + ID）の中身を組み立てる。
    function appendRegionRow(row, item) {
      const name = document.createElement('span');
      name.className = 'tree-name';
      name.textContent = item?.name ?? '—';
      row.appendChild(name);

      const typeID = item?.wineRegionTypeID;
      if (typeID) {
        const chip = document.createElement('span');
        chip.className = 'chip';
        const typeName = nameFor('region_types', typeID);
        chip.textContent = typeName ?? shortId(typeID);
        if (!typeName) chip.title = typeID;
        row.appendChild(chip);
      }

      row.appendChild(buildIdControl(item?.id));
    }

    // parentRegionID から木構造を組み、親子関係をツリーで表示する。
    function renderRegionTree(container, items) {
      const byId = new Map(items.map(region => [region.id, region]));
      const childrenOf = new Map();
      const roots = [];
      for (const region of items) {
        const parentID = region.parentRegionID;
        if (parentID && byId.has(parentID) && parentID !== region.id) {
          if (!childrenOf.has(parentID)) childrenOf.set(parentID, []);
          childrenOf.get(parentID).push(region);
        } else {
          roots.push(region);
        }
      }
      const byName = (a, b) => (a.name ?? '').localeCompare(b.name ?? '', 'ja');
      roots.sort(byName);
      for (const list of childrenOf.values()) list.sort(byName);

      const tree = document.createElement('div');
      tree.className = 'tree';
      tree.setAttribute('role', 'tree');

      function renderNode(item, visited) {
        const kids = visited.has(item.id) ? [] : (childrenOf.get(item.id) ?? []);
        const next = new Set(visited).add(item.id);

        if (kids.length > 0) {
          const details = document.createElement('details');
          details.open = true;
          const summary = document.createElement('summary');
          summary.className = 'tree-row';
          const caret = document.createElement('span');
          caret.className = 'tw';
          caret.setAttribute('aria-hidden', 'true');
          caret.textContent = '▸';
          summary.appendChild(caret);
          appendRegionRow(summary, item);
          const count = document.createElement('span');
          count.className = 'tree-count';
          count.textContent = `${kids.length}`;
          count.title = `子地域 ${kids.length} 件`;
          summary.appendChild(count);
          details.appendChild(summary);

          const childWrap = document.createElement('div');
          childWrap.className = 'tree-children';
          for (const kid of kids) childWrap.appendChild(renderNode(kid, next));
          details.appendChild(childWrap);
          return details;
        }

        const row = document.createElement('div');
        row.className = 'tree-row tree-leaf';
        const spacer = document.createElement('span');
        spacer.className = 'tw tw--leaf';
        spacer.setAttribute('aria-hidden', 'true');
        row.appendChild(spacer);
        appendRegionRow(row, item);
        return row;
      }

      for (const node of roots) tree.appendChild(renderNode(node, new Set()));
      container.appendChild(tree);
    }

    // wine 参照データを JSON ではなく見やすく表示する。
    function renderWine(container, data, kind) {
      if (!container) return;
      container.replaceChildren();
      const items = Array.isArray(data) ? data : [];

      const summary = document.createElement('p');
      summary.className = 'wine-summary';
      summary.textContent = `${WINE_LABELS[kind] ?? ''} ${items.length} 件`;
      container.appendChild(summary);

      if (items.length === 0) {
        const empty = document.createElement('p');
        empty.className = 'wine-empty';
        empty.textContent = 'データがありません。';
        container.appendChild(empty);
        return;
      }

      // 地域は親子関係をツリーで、それ以外はテーブルで表示。
      if (kind === 'regions') {
        renderRegionTree(container, items);
        return;
      }

      const columns = columnsFor(kind);
      const table = document.createElement('table');
      table.className = 'wine-table';

      const thead = document.createElement('thead');
      const headRow = document.createElement('tr');
      for (const col of columns) {
        const th = document.createElement('th');
        th.scope = 'col';
        th.textContent = col.label;
        headRow.appendChild(th);
      }
      thead.appendChild(headRow);
      table.appendChild(thead);

      const tbody = document.createElement('tbody');
      for (const item of items) {
        const row = document.createElement('tr');
        for (const col of columns) {
          const td = document.createElement('td');
          col.render(td, item);
          row.appendChild(td);
        }
        tbody.appendChild(row);
      }
      table.appendChild(tbody);
      container.appendChild(table);
    }

    async function loadWine({ path, message, label, populate, kind }) {
      const token = requireToken('wine');
      if (!token) return;
      status.set('wine', `${label}を取得中...`);
      try {
        const data = await api.listWine({ path, token, message });
        wineCache[kind] = Array.isArray(data) ? data : [];
        renderWine(resultEl('wine-result'), data, kind);
        if (populate) populate(data);
        status.set('wine', `${label}を取得しました。`);
      } catch (error) {
        console.error(error);
        status.set('wine', error.message || message, { error: true });
      }
    }

    // ---- イベント表示ヘルパ（JSON ではなく読みやすいカードで表示） ----
    const VISIBILITY_LABELS = { public: '公開', unlisted: '限定公開', private: '非公開' };

    function formatDateTime(seconds) {
      if (typeof seconds !== 'number' || Number.isNaN(seconds)) return null;
      const date = new Date(APPLE_REFERENCE_DATE_MS + seconds * 1000);
      const pad = n => String(n).padStart(2, '0');
      return `${date.getFullYear()}/${pad(date.getMonth() + 1)}/${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}`;
    }

    // datetime-local 入力用の文字列（ローカル時刻）に変換。fillEventForm で使用。
    function inputFromReferenceSeconds(seconds) {
      if (typeof seconds !== 'number' || Number.isNaN(seconds)) return '';
      const date = new Date(APPLE_REFERENCE_DATE_MS + seconds * 1000);
      const pad = n => String(n).padStart(2, '0');
      return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
    }

    function formatPeriod(period) {
      if (!period) return null;
      const start = formatDateTime(period.startsAt);
      const end = formatDateTime(period.endsAt);
      if (!start && !end) return null;
      return `${start ?? '?'} 〜 ${end ?? '?'}`;
    }

    function formatAddress(address) {
      if (!address) return null;
      const parts = [
        address.postalCode ? `〒${address.postalCode}` : null,
        address.administrativeArea,
        address.locality,
        address.addressLine1,
        address.addressLine2,
        address.countryCode,
      ].filter(Boolean);
      return parts.length ? parts.join(' ') : null;
    }

    function formatMoney(money) {
      if (!money || money.minorAmount === undefined || !money.currencyCode) return null;
      return `${money.minorAmount.toLocaleString('ja-JP')} ${money.currencyCode}（最小単位）`;
    }

    function appendMetaRow(dl, label, value) {
      if (value === null || value === undefined || value === '') return;
      const dt = document.createElement('dt');
      dt.textContent = label;
      const dd = document.createElement('dd');
      dd.textContent = value;
      dl.append(dt, dd);
    }

    // 1 件のイベントを読みやすいカードにする。withEdit=true で「編集」ボタンを表示。
    function buildEventCard(event, { withEdit = false } = {}) {
      const card = document.createElement('article');
      card.className = 'event-card';

      const head = document.createElement('div');
      head.className = 'event-card__head';
      const title = document.createElement('h4');
      title.className = 'event-card__title';
      title.textContent = event?.title ?? '(無題)';
      head.appendChild(title);
      const vis = document.createElement('span');
      const visKey = event?.visibility;
      vis.className = `vis-badge vis-${visKey ?? 'private'}`;
      vis.textContent = VISIBILITY_LABELS[visKey] ?? visKey ?? '—';
      head.appendChild(vis);
      card.appendChild(head);

      if (event?.body) {
        const body = document.createElement('p');
        body.className = 'event-card__body';
        body.textContent = event.body;
        card.appendChild(body);
      }

      const dl = document.createElement('dl');
      dl.className = 'event-meta';
      appendMetaRow(dl, '開催', formatPeriod(event?.eventPeriod));
      const venue = [event?.venueName, formatAddress(event?.venueAddress)].filter(Boolean).join(' / ');
      appendMetaRow(dl, '会場', venue || null);
      appendMetaRow(dl, '受付', formatPeriod(event?.registrationPeriod));
      appendMetaRow(dl, '定員', event?.capacity != null ? `${event.capacity} 名` : null);
      appendMetaRow(dl, '参加費', formatMoney(event?.entryFee));
      appendMetaRow(dl, '正解公開', formatDateTime(event?.answersPublishedAt));
      appendMetaRow(dl, '作成', formatDateTime(event?.createdAt));
      if (dl.childElementCount > 0) card.appendChild(dl);

      const foot = document.createElement('div');
      foot.className = 'event-card__foot';
      foot.appendChild(buildIdControl(event?.id));
      if (withEdit) {
        const actions = document.createElement('div');
        actions.className = 'event-card__actions';

        const join = document.createElement('button');
        join.type = 'button';
        join.textContent = '参加登録';

        const edit = document.createElement('button');
        edit.type = 'button';
        edit.className = 'btn-ghost';
        edit.textContent = '編集';
        edit.addEventListener('click', () => openEventDialog(event));

        actions.append(join, edit);
        foot.appendChild(actions);
        card.appendChild(foot);

        const joinStatus = document.createElement('p');
        joinStatus.className = 'join-status';
        joinStatus.setAttribute('role', 'status');
        join.addEventListener('click', () => registerForEvent(event?.id, join, joinStatus));
        card.appendChild(joinStatus);
        return card;
      }
      card.appendChild(foot);
      return card;
    }

    // イベントセル内の「参加登録」。当該イベントIDで登録し、セル内に結果を表示。
    async function registerForEvent(eventID, button, statusEl) {
      const token = session.data.token;
      const setLine = (text, error = false) => {
        if (!statusEl) return;
        statusEl.textContent = text;
        statusEl.classList.toggle('is-error', error);
      };
      if (!token) {
        setLine('先にユーザーを作成またはログインしてください。', true);
        status.set('participant', '先にユーザーを作成またはログインしてください。', { error: true });
        return;
      }
      button.disabled = true;
      setLine('参加登録中...');
      try {
        const participant = await api.registerParticipant({ eventID, token });
        setLine(participant?.status ? `参加登録しました（${participant.status}）` : '参加登録しました');
        status.set('participant', '参加登録しました。');
      } catch (error) {
        console.error(error);
        setLine(error.message || '参加登録に失敗しました。', true);
        status.set('participant', error.message || '参加登録に失敗しました。', { error: true });
      } finally {
        button.disabled = false;
      }
    }

    function renderEvents(container, data) {
      if (!container) return;
      container.replaceChildren();
      const events = Array.isArray(data) ? data : [];
      if (events.length === 0) {
        const empty = document.createElement('p');
        empty.className = 'wine-empty';
        empty.textContent = 'イベントがありません。「+ 追加」から作成できます。';
        container.appendChild(empty);
        return;
      }
      for (const event of events) container.appendChild(buildEventCard(event, { withEdit: true }));
    }

    function renderEventDetail(container, event) {
      if (!container) return;
      container.replaceChildren();
      if (event) container.appendChild(buildEventCard(event));
    }

    function clearEventForm() {
      for (const id of [
        'event-title', 'event-body', 'event-image-id', 'event-venue-name',
        'event-address-line1', 'event-address-line2', 'event-locality',
        'event-administrative-area', 'event-postal-code', 'event-country-code',
        'event-latitude', 'event-longitude', 'event-period-start', 'event-period-end',
        'event-registration-start', 'event-registration-end', 'event-answer-published-at',
        'event-capacity', 'event-fee-amount', 'event-fee-currency', 'event-id',
      ]) setVal(id, '');
      setVal('event-visibility', 'private');
      resultEl('event-result')?.replaceChildren();
    }

    function fillEventForm(event) {
      const address = event?.venueAddress ?? {};
      const coordinate = event?.venueCoordinate ?? {};
      setVal('event-title', event?.title ?? '');
      setVal('event-body', event?.body ?? '');
      setVal('event-image-id', event?.imageID ?? '');
      setVal('event-venue-name', event?.venueName ?? '');
      setVal('event-address-line1', address.addressLine1 ?? '');
      setVal('event-address-line2', address.addressLine2 ?? '');
      setVal('event-locality', address.locality ?? '');
      setVal('event-administrative-area', address.administrativeArea ?? '');
      setVal('event-postal-code', address.postalCode ?? '');
      setVal('event-country-code', address.countryCode ?? '');
      setVal('event-latitude', coordinate.latitude ?? '');
      setVal('event-longitude', coordinate.longitude ?? '');
      setVal('event-period-start', inputFromReferenceSeconds(event?.eventPeriod?.startsAt));
      setVal('event-period-end', inputFromReferenceSeconds(event?.eventPeriod?.endsAt));
      setVal('event-registration-start', inputFromReferenceSeconds(event?.registrationPeriod?.startsAt));
      setVal('event-registration-end', inputFromReferenceSeconds(event?.registrationPeriod?.endsAt));
      setVal('event-answer-published-at', inputFromReferenceSeconds(event?.answersPublishedAt));
      setVal('event-capacity', event?.capacity ?? '');
      setVal('event-fee-amount', event?.entryFee?.minorAmount ?? '');
      setVal('event-fee-currency', event?.entryFee?.currencyCode ?? '');
      setVal('event-visibility', event?.visibility ?? 'private');
      setVal('event-id', event?.id ?? '');
    }

    function setDialogTitle(text) {
      const el = document.getElementById('event-dialog-title');
      if (el) el.textContent = text;
    }

    function closeEventDialog() {
      document.getElementById('event-dialog')?.close();
    }

    // event を渡すと編集モード、未指定なら新規作成モードでダイアログを開く。
    function openEventDialog(event) {
      status.clear('eventCreate', 'eventDetail');
      if (event) {
        fillEventForm(event);
        setDialogTitle('イベントを編集');
      } else {
        clearEventForm();
        setDialogTitle('イベント作成');
      }
      document.getElementById('event-dialog')?.showModal();
    }

    let eventsLoaded = false;
    async function refreshEvents() {
      const token = requireToken('eventsList');
      if (!token) return;
      status.set('eventsList', 'イベント一覧取得中...');
      try {
        const events = await api.listEvents(token);
        renderEvents(resultEl('events-list-result'), events);
        eventsLoaded = true;
        status.set('eventsList', `イベントを ${Array.isArray(events) ? events.length : 0} 件取得しました。`);
      } catch (error) {
        console.error(error);
        status.set('eventsList', error.message || 'イベント一覧の取得に失敗しました。', { error: true });
      }
    }

    return {
      listEvents: refreshEvents,

      openEventDialog,

      // イベントタブを開いたときに、未取得かつログイン済みなら自動で一覧を読み込む。
      maybeAutoLoadEvents() {
        if (!eventsLoaded && session.data.token) refreshEvents();
      },

      async createEvent() {
        const token = requireToken('eventCreate');
        if (!token) return;
        const body = buildEventBody();
        if (!validateEventBody('eventCreate', body)) return;

        status.set('eventCreate', 'イベント作成中...');
        try {
          const event = await api.createEvent({ body, token });
          status.set('eventCreate', 'イベントを作成しました。');
          closeEventDialog();
          await refreshEvents();
        } catch (error) {
          console.error(error);
          status.set('eventCreate', error.message || 'イベント作成に失敗しました。', { error: true });
        }
      },

      async getEvent() {
        const token = requireToken('eventDetail');
        if (!token) return;
        const eventID = val('event-id').trim();
        if (!validate('eventDetail', [
          { predicate: () => eventID.length > 0, message: 'イベントIDを入力してください。' },
        ])) return;

        status.set('eventDetail', 'イベント取得中...');
        try {
          const event = await api.getEvent({ eventID, token });
          fillEventForm(event);
          renderEventDetail(resultEl('event-result'), event);
          status.set('eventDetail', '最新の内容を取得しました。');
        } catch (error) {
          console.error(error);
          status.set('eventDetail', error.message || 'イベント取得に失敗しました。', { error: true });
        }
      },

      async updateEvent() {
        const token = requireToken('eventDetail');
        if (!token) return;
        const eventID = val('event-id').trim();
        const body = buildEventBody();
        if (!validate('eventDetail', [
          { predicate: () => eventID.length > 0, message: 'イベントIDを入力してください。' },
        ])) return;
        if (!validateEventBody('eventDetail', body)) return;

        status.set('eventDetail', 'イベント更新中...');
        try {
          const event = await api.updateEvent({ eventID, body, token });
          renderEventDetail(resultEl('event-result'), event);
          status.set('eventDetail', 'イベントを更新しました。');
          closeEventDialog();
          await refreshEvents();
        } catch (error) {
          console.error(error);
          status.set('eventDetail', error.message || 'イベント更新に失敗しました。', { error: true });
        }
      },

      async createQuestion() {
        const token = requireToken('question');
        if (!token) return;
        const eventID = val('question-event-id').trim();
        const questionNumber = readNumber(val('question-number'));
        if (!validate('question', [
          { predicate: () => eventID.length > 0, message: 'イベントIDを入力してください。' },
          { predicate: () => questionNumber !== null && questionNumber > 0, message: '問題番号は1以上で入力してください。' },
        ])) return;

        const body = { questionNumber };
        assignIfPresent(body, 'imageID', val('question-image-id').trim());
        assignIfPresent(body, 'note', val('question-note').trim());

        status.set('question', '問題作成中...');
        try {
          const question = await api.createQuestion({ eventID, body, token });
          renderResult(resultEl('question-result'), question);
          if (question?.id) {
            setVal('question-id', question.id);
          }
          status.set('question', '問題を作成しました。');
        } catch (error) {
          console.error(error);
          status.set('question', error.message || '問題作成に失敗しました。', { error: true });
        }
      },

      async updateQuestion() {
        const token = requireToken('question');
        if (!token) return;
        const eventID = val('question-event-id').trim();
        const questionID = val('question-id').trim();
        const questionNumber = readNumber(val('question-number'));
        if (!validate('question', [
          { predicate: () => eventID.length > 0, message: 'イベントIDを入力してください。' },
          { predicate: () => questionID.length > 0, message: '問題IDを入力してください。' },
          { predicate: () => questionNumber !== null && questionNumber > 0, message: '問題番号は1以上で入力してください。' },
        ])) return;

        const body = { questionNumber };
        assignIfPresent(body, 'imageID', val('question-image-id').trim());
        assignIfPresent(body, 'note', val('question-note').trim());

        status.set('question', '問題更新中...');
        try {
          const question = await api.updateQuestion({ eventID, questionID, body, token });
          renderResult(resultEl('question-result'), question);
          status.set('question', '問題を更新しました。');
        } catch (error) {
          console.error(error);
          status.set('question', error.message || '問題更新に失敗しました。', { error: true });
        }
      },

      async createCorrectAnswer() {
        const token = requireToken('answer');
        if (!token) return;
        const eventID = val('answer-event-id').trim();
        const questionID = val('answer-question-id').trim();
        const body = buildAnswerLikeBody('answer');
        if (!validate('answer', [
          { predicate: () => eventID.length > 0, message: 'イベントIDを入力してください。' },
          { predicate: () => questionID.length > 0, message: '問題IDを入力してください。' },
          { predicate: () => body.wineVarietyIDs.length > 0, message: '品種IDを1つ以上入力してください。' },
        ])) return;

        status.set('answer', '正解作成中...');
        try {
          const answer = await api.createCorrectAnswer({ eventID, questionID, body, token });
          renderResult(resultEl('answer-result'), answer);
          status.set('answer', '正解を作成しました。');
        } catch (error) {
          console.error(error);
          status.set('answer', error.message || '正解作成に失敗しました。', { error: true });
        }
      },

      async updateCorrectAnswer() {
        const token = requireToken('answer');
        if (!token) return;
        const eventID = val('answer-event-id').trim();
        const questionID = val('answer-question-id').trim();
        const body = buildAnswerLikeBody('answer');
        if (!validate('answer', [
          { predicate: () => eventID.length > 0, message: 'イベントIDを入力してください。' },
          { predicate: () => questionID.length > 0, message: '問題IDを入力してください。' },
          { predicate: () => body.wineVarietyIDs.length > 0, message: '品種IDを1つ以上入力してください。' },
        ])) return;

        status.set('answer', '正解更新中...');
        try {
          const answer = await api.updateCorrectAnswer({ eventID, questionID, body, token });
          renderResult(resultEl('answer-result'), answer);
          status.set('answer', '正解を更新しました。');
        } catch (error) {
          console.error(error);
          status.set('answer', error.message || '正解更新に失敗しました。', { error: true });
        }
      },

      async createResponse() {
        const token = requireToken('response');
        if (!token) return;
        const eventID = val('response-event-id').trim();
        const questionID = val('response-question-id').trim();
        const body = buildAnswerLikeBody('response', { withNote: true });
        if (!validate('response', [
          { predicate: () => eventID.length > 0, message: 'イベントIDを入力してください。' },
          { predicate: () => questionID.length > 0, message: '問題IDを入力してください。' },
          { predicate: () => body.wineVarietyIDs.length > 0, message: '品種IDを1つ以上入力してください。' },
        ])) return;

        status.set('response', '回答作成中...');
        try {
          const response = await api.createResponse({ eventID, questionID, body, token });
          renderResult(resultEl('response-result'), response);
          status.set('response', '回答を作成しました。');
        } catch (error) {
          console.error(error);
          status.set('response', error.message || '回答作成に失敗しました。', { error: true });
        }
      },

      async updateMyResponse() {
        const token = requireToken('response');
        if (!token) return;
        const eventID = val('response-event-id').trim();
        const questionID = val('response-question-id').trim();
        const body = buildAnswerLikeBody('response', { withNote: true });
        if (!validate('response', [
          { predicate: () => eventID.length > 0, message: 'イベントIDを入力してください。' },
          { predicate: () => questionID.length > 0, message: '問題IDを入力してください。' },
          { predicate: () => body.wineVarietyIDs.length > 0, message: '品種IDを1つ以上入力してください。' },
        ])) return;

        status.set('response', '回答更新中...');
        try {
          const response = await api.updateMyResponse({ eventID, questionID, body, token });
          renderResult(resultEl('response-result'), response);
          status.set('response', '回答を更新しました。');
        } catch (error) {
          console.error(error);
          status.set('response', error.message || '回答更新に失敗しました。', { error: true });
        }
      },

      loadWineStyles() {
        return loadWine({ path: '/wine/styles', message: 'スタイルの取得に失敗しました。', label: 'スタイル', kind: 'styles' });
      },
      loadWineVarieties() {
        return loadWine({
          path: '/wine/varieties',
          message: '品種の取得に失敗しました。',
          label: '品種',
          kind: 'varieties',
          populate: data => {
            populateSelect('answer-variety-ids', data);
            populateSelect('response-variety-ids', data);
          },
        });
      },
      loadWineRegionTypes() {
        return loadWine({ path: '/wine/region_types', message: '地域タイプの取得に失敗しました。', label: '地域タイプ', kind: 'region_types' });
      },
      loadWineRegions() {
        return loadWine({
          path: '/wine/regions',
          message: '地域の取得に失敗しました。',
          label: '地域',
          kind: 'regions',
          populate: data => {
            populateSelect('answer-wine-region-id', data, { placeholder: '（未選択）' });
            populateSelect('response-wine-region-id', data, { placeholder: '（未選択）' });
          },
        });
      },
    };
  }

  async function refreshSessionEmails(token) {
    if (!token) {
      return;
    }
    try {
      const emails = await api.fetchEmailsFromMe(token);
      session.updateEmails(emails);
      renderEmailsList(elements.emailsList, emails);
    } catch (error) {
      console.error(error);
    }
  }

  function renderEmailsList(list, emails) {
    list.replaceChildren();
    for (const item of emails) {
      const email = (typeof item === 'string' ? item : item?.email)?.trim();
      if (!email) continue;
      const createdAt = typeof item?.createdAt === 'number'
        ? ` (${formatReferenceDate(item.createdAt)})`
        : '';
      const listItem = document.createElement('li');
      listItem.textContent = `${email}${createdAt}`;
      list.appendChild(listItem);
    }
  }

  function bindAsync(button, action) {
    button.addEventListener('click', () => runWithButtonDisabled(button, action));
  }

  function validate(statusKey, checks) {
    for (const { predicate, message } of checks) {
      if (!predicate()) {
        status.set(statusKey, message, { error: true });
        return false;
      }
    }
    return true;
  }

  async function runWithButtonDisabled(button, action) {
    button.disabled = true;
    try {
      await action();
    } finally {
      button.disabled = false;
    }
  }

  // 右下に積層表示するトースト通知。popover="manual" で top layer に乗せる。
  function createToaster(region) {
    function dismissIfEmpty() {
      if (region && region.children.length === 0 && region.matches(':popover-open')) {
        try { region.hidePopover(); } catch (_) { /* noop */ }
      }
    }
    return function showToast(message, { error = false } = {}) {
      if (!region || !message) return;
      if (!region.matches(':popover-open')) {
        try { region.showPopover(); } catch (_) { region.style.display = 'flex'; }
      }
      const toast = document.createElement('div');
      toast.className = error ? 'toast toast--error' : 'toast toast--success';
      toast.setAttribute('role', error ? 'alert' : 'status');

      const text = document.createElement('span');
      text.textContent = message;

      const close = document.createElement('button');
      close.type = 'button';
      close.className = 'toast__close';
      close.setAttribute('aria-label', '閉じる');
      close.textContent = '×';

      const remove = () => {
        clearTimeout(timer);
        toast.remove();
        dismissIfEmpty();
      };
      close.addEventListener('click', remove);

      toast.append(text, close);
      region.appendChild(toast);
      const timer = setTimeout(remove, error ? 6000 : 3500);
    };
  }

  function createElementsMap() {
    return {
      buttons: {
        create: document.getElementById('create-user'),
        sendEmail: document.getElementById('send-email'),
        confirmEmail: document.getElementById('confirm-email'),
        loadEmails: document.getElementById('load-emails'),
        addPasskey: document.getElementById('add-passkey'),
        login: document.getElementById('login'),
        startEmailLogin: document.getElementById('start-email-login'),
        completeEmailLogin: document.getElementById('complete-email-login'),
        uploadProfileImage: document.getElementById('upload-profile-image'),
        logout: document.getElementById('logout'),
        wineStyles: document.getElementById('wine-styles'),
        wineVarieties: document.getElementById('wine-varieties'),
        wineRegionTypes: document.getElementById('wine-region-types'),
        wineRegions: document.getElementById('wine-regions'),
        eventsList: document.getElementById('events-list'),
        eventCreate: document.getElementById('event-create'),
        eventGet: document.getElementById('event-get'),
        eventUpdate: document.getElementById('event-update'),
        questionCreate: document.getElementById('question-create'),
        questionUpdate: document.getElementById('question-update'),
        answerCreate: document.getElementById('answer-create'),
        answerUpdate: document.getElementById('answer-update'),
        responseCreate: document.getElementById('response-create'),
        responseUpdate: document.getElementById('response-update'),
      },
      statuses: {
        create: document.getElementById('create-status'),
        emailStart: document.getElementById('email-start-status'),
        emailConfirm: document.getElementById('email-confirm-status'),
        emails: document.getElementById('emails-status'),
        passkey: document.getElementById('passkey-status'),
        login: document.getElementById('login-status'),
        emailLogin: document.getElementById('email-login-status'),
        profileImage: document.getElementById('profile-image-status'),
        logout: document.getElementById('logout-status'),
        wine: document.getElementById('wine-status'),
        eventsList: document.getElementById('events-list-status'),
        eventCreate: document.getElementById('event-create-status'),
        eventDetail: document.getElementById('event-detail-status'),
        question: document.getElementById('question-status'),
        answer: document.getElementById('answer-status'),
        response: document.getElementById('response-status'),
      },
      inputs: {
        email: document.getElementById('email-input'),
        code: document.getElementById('email-code'),
        emailLoginEmail: document.getElementById('email-login-input'),
        emailLoginCode: document.getElementById('email-login-code'),
        profileName: document.getElementById('profile-name-input'),
        profileImageFile: document.getElementById('profile-image-file'),
      },
      profileImagePreview: document.getElementById('profile-image-preview'),
      currentProfile: {
        container: document.getElementById('current-profile'),
        image: document.getElementById('current-profile-image'),
        name: document.getElementById('current-profile-name'),
        imageURL: document.getElementById('current-profile-image-url'),
      },
      emailsList: document.getElementById('emails-list'),
      session: {
        output: document.getElementById('session-output'),
        badge: document.getElementById('session-badge'),
        userID: document.getElementById('session-user-id'),
        token: document.getElementById('session-token'),
        emails: document.getElementById('session-emails'),
        profile: document.getElementById('session-profile'),
      },
    };
  }

  function createStatusManager(statusElements, showToast) {
    // 「...」で終わる進行中メッセージはトースト表示しない（完了とエラーのみ通知）。
    const isProgress = message => /\.\.\.$/.test(message ?? '');
    return {
      set(key, message, { error = false } = {}) {
        const element = statusElements[key];
        if (element) {
          element.textContent = message;
          element.classList.toggle('status--error', !!error);
        }
        if (showToast && (error || !isProgress(message))) {
          showToast(message, { error });
        }
      },
      clear(...keys) {
        keys.forEach(key => {
          const element = statusElements[key];
          if (element) {
            element.textContent = '';
            element.classList.remove('status--error');
          }
        });
      },
    };
  }

  function createSessionManager(panel) {
    const data = {
      userID: null,
      token: null,
      tokenExpiresAt: null,
      refreshToken: null,
      refreshTokenExpiresAt: null,
      emails: [],
      profile: null,
    };

    function render() {
      const loggedIn = !!data.userID;
      panel.badge.dataset.state = loggedIn ? 'in' : 'out';
      panel.badge.textContent = loggedIn ? '● ログイン中' : '● 未ログイン';
      panel.userID.textContent = data.userID ?? '—';
      panel.token.textContent = data.token ? 'あり' : 'なし';
      panel.emails.textContent = String(data.emails.length);
      panel.profile.textContent = data.profile?.name ?? '—';
      panel.output.textContent = loggedIn
        ? JSON.stringify(data, null, 2)
        : 'セッションがありません。';
    }

    function formatReferenceDate(value) {
      if (typeof value !== 'number' || Number.isNaN(value)) {
        return null;
      }
      return new Date(APPLE_REFERENCE_DATE_MS + value * 1000).toISOString();
    }

    return {
      data,
      apply(payload) {
        const userID = payload?.userID ?? payload?.id ?? null;
        data.userID = userID;
        data.token = payload?.token ?? null;
        data.tokenExpiresAt = formatReferenceDate(payload?.tokenExpiredDate);
        data.refreshToken = payload?.refreshToken ?? null;
        data.refreshTokenExpiresAt = formatReferenceDate(payload?.refreshTokenExpiredDate);
        render();
      },
      updateEmails(emails) {
        data.emails = Array.isArray(emails) ? emails : [];
        render();
      },
      updateProfile(profile) {
        data.profile = profile ?? null;
        render();
      },
      reset() {
        data.userID = null;
        data.token = null;
        data.tokenExpiresAt = null;
        data.refreshToken = null;
        data.refreshTokenExpiresAt = null;
        data.emails = [];
        data.profile = null;
        render();
      },
      render,
    };
  }

  function formatReferenceDate(value) {
    if (typeof value !== 'number' || Number.isNaN(value)) {
      return null;
    }
    return new Date(APPLE_REFERENCE_DATE_MS + value * 1000).toISOString();
  }

  const APPLE_REFERENCE_DATE_MS = Date.UTC(2001, 0, 1);

  // datetime-local の入力値を Apple 基準日(2001-01-01 UTC)起点の秒に変換する。
  function referenceSecondsFromInput(localValue) {
    const trimmed = (localValue ?? '').trim();
    if (!trimmed) {
      return null;
    }
    const ms = Date.parse(trimmed);
    if (Number.isNaN(ms)) {
      return null;
    }
    return (ms - APPLE_REFERENCE_DATE_MS) / 1000;
  }

  // 値が空でないときだけ target に格納する。
  function assignIfPresent(target, key, value) {
    if (value === null || value === undefined) {
      return;
    }
    if (typeof value === 'string' && value.trim() === '') {
      return;
    }
    if (typeof value === 'number' && Number.isNaN(value)) {
      return;
    }
    target[key] = value;
  }

  function renderResult(element, data) {
    if (!element) return;
    element.textContent = typeof data === 'string' ? data : JSON.stringify(data, null, 2);
  }

  function readNumber(value) {
    const trimmed = (value ?? '').trim();
    if (!trimmed) {
      return null;
    }
    const parsed = Number(trimmed);
    return Number.isNaN(parsed) ? null : parsed;
  }

  function createApi() {
    return {
      async createUser() {
        const response = await post('/user', { message: 'ユーザー作成に失敗しました。' });
        return response.json();
      },

      async sendVerificationEmail({ email, token }) {
        const url = new URL('/email/verify/start', window.location.origin);
        url.searchParams.set('email', email);
        await post(url, {
          headers: { Authorization: `Bearer ${token}` },
          message: '確認メールの送信に失敗しました。',
        });
      },

      async confirmEmailAddress({ email, code, token }) {
        await post('/email/verify', {
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${token}`,
          },
          body: JSON.stringify({ email, otp: code }),
          message: 'メールアドレスの確認に失敗しました。',
        });
      },

      async fetchChallenge({ token } = {}) {
        const headers = token ? { Authorization: `Bearer ${token}` } : {};
        const response = await post('/challenge', {
          headers,
          message: 'チャレンジ取得に失敗しました。',
        });
        return readChallengeResponse(response);
      },

      async registerPasskey({ challenge, payload, token }) {
        await post('/passkey', {
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${token}`,
          },
          body: JSON.stringify({ ...payload, challenge }),
          message: 'Passkey登録に失敗しました。',
        });
      },

      async requestPasskeyToken(payload) {
        return postJSON('/token/passkey', payload, {
          message: 'ログインに失敗しました。',
        });
      },

      async fetchCurrentUser(token) {
        const response = await get('/me', {
          headers: { Authorization: `Bearer ${token}` },
          message: 'ユーザー情報の取得に失敗しました。',
        });
        return response.json();
      },

      async fetchEmailsFromMe(token) {
        const response = await get('/me', {
          headers: { Authorization: `Bearer ${token}` },
          message: 'メールアドレスの取得に失敗しました。',
        });
        const me = await response.json();
        return Array.isArray(me?.emails) ? me.emails : [];
      },

      async sendEmailLoginChallenge(email) {
        const url = new URL('/token/email/start', window.location.origin);
        url.searchParams.set('email', email);
        const response = await post(url, {
          message: 'ログインコードの送信に失敗しました。',
        });
        return readChallengeResponse(response);
      },

      async exchangeEmailCodeForToken(payload) {
        return postJSON('/token/email', payload, {
          message: 'メールでのログインに失敗しました。',
        });
      },

      async createImageUploadURL(token) {
        const response = await post('/images/upload_url', {
          headers: { Authorization: `Bearer ${token}` },
          message: '画像アップロードURLの取得に失敗しました。',
        });
        return response.json();
      },

      async uploadImageFile({ uploadURL, file }) {
        const body = new FormData();
        body.append('file', file);
        await post(uploadURL, {
          body,
          message: '画像アップロードに失敗しました。',
        });
      },

      async createImage({ imageID, token }) {
        return postJSON('/images', { imageID }, {
          headers: { Authorization: `Bearer ${token}` },
          message: '画像登録に失敗しました。',
        });
      },

      async createUserProfile({ name, imageID, token }) {
        return postJSON('/me', { name, imageID }, {
          headers: { Authorization: `Bearer ${token}` },
          message: 'プロフィール登録に失敗しました。',
        });
      },

      async listEvents(token) {
        const response = await get('/events', {
          headers: { Authorization: `Bearer ${token}` },
          message: 'イベント一覧の取得に失敗しました。',
        });
        return response.json();
      },

      async createEvent({ body, token }) {
        return postJSON('/events', body, {
          headers: { Authorization: `Bearer ${token}` },
          message: 'イベント作成に失敗しました。',
        });
      },

      async getEvent({ eventID, token }) {
        const response = await get(`/events/${encodeURIComponent(eventID)}`, {
          headers: { Authorization: `Bearer ${token}` },
          message: 'イベント取得に失敗しました。',
        });
        return response.json();
      },

      async updateEvent({ eventID, body, token }) {
        return putJSON(`/events/${encodeURIComponent(eventID)}`, body, {
          headers: { Authorization: `Bearer ${token}` },
          message: 'イベント更新に失敗しました。',
        });
      },

      async registerParticipant({ eventID, token }) {
        const response = await post(`/events/${encodeURIComponent(eventID)}/participants`, {
          headers: { Authorization: `Bearer ${token}` },
          message: '参加登録に失敗しました。',
        });
        return response.json();
      },

      async createQuestion({ eventID, body, token }) {
        return postJSON(`/events/${encodeURIComponent(eventID)}/questions`, body, {
          headers: { Authorization: `Bearer ${token}` },
          message: '問題作成に失敗しました。',
        });
      },

      async updateQuestion({ eventID, questionID, body, token }) {
        return putJSON(
          `/events/${encodeURIComponent(eventID)}/questions/${encodeURIComponent(questionID)}`,
          body,
          {
            headers: { Authorization: `Bearer ${token}` },
            message: '問題更新に失敗しました。',
          }
        );
      },

      async createCorrectAnswer({ eventID, questionID, body, token }) {
        return postJSON(
          `/events/${encodeURIComponent(eventID)}/questions/${encodeURIComponent(questionID)}/correct_answer`,
          body,
          {
            headers: { Authorization: `Bearer ${token}` },
            message: '正解作成に失敗しました。',
          }
        );
      },

      async updateCorrectAnswer({ eventID, questionID, body, token }) {
        return putJSON(
          `/events/${encodeURIComponent(eventID)}/questions/${encodeURIComponent(questionID)}/correct_answer`,
          body,
          {
            headers: { Authorization: `Bearer ${token}` },
            message: '正解更新に失敗しました。',
          }
        );
      },

      async createResponse({ eventID, questionID, body, token }) {
        return postJSON(
          `/events/${encodeURIComponent(eventID)}/questions/${encodeURIComponent(questionID)}/responses`,
          body,
          {
            headers: { Authorization: `Bearer ${token}` },
            message: '回答作成に失敗しました。',
          }
        );
      },

      async updateMyResponse({ eventID, questionID, body, token }) {
        return putJSON(
          `/events/${encodeURIComponent(eventID)}/questions/${encodeURIComponent(questionID)}/responses/me`,
          body,
          {
            headers: { Authorization: `Bearer ${token}` },
            message: '回答更新に失敗しました。',
          }
        );
      },

      async listWine({ path, token, message }) {
        const response = await get(path, {
          headers: { Authorization: `Bearer ${token}` },
          message,
        });
        return response.json();
      },
    };
  }

  function createWebAuthnHelpers() {
    const encoder = new TextEncoder();
    return {
      buildRegistrationOptions({ challenge, userID, email }) {
        const label = (email ?? '').trim() || userID;
        return {
          challenge: base64ToUint8Array(challenge),
          rp: { name: document.title || 'BlindLog', id: window.location.hostname },
          user: {
            id: encoder.encode(userID),
            name: label,
            displayName: label,
          },
          pubKeyCredParams: [
            { type: 'public-key', alg: -7 },
            { type: 'public-key', alg: -257 },
          ],
          authenticatorSelection: { userVerification: 'preferred' },
          timeout: 60000,
          attestation: 'none',
        };
      },

      buildAuthenticationOptions(challenge) {
        return {
          challenge: base64ToUint8Array(challenge),
          rpId: window.location.hostname,
          timeout: 60000,
          userVerification: 'preferred',
        };
      },

      serializeRegistrationCredential(credential) {
        const { response } = credential;
        return {
          id: credential.id,
          rawId: arrayBufferToBase64Url(credential.rawId),
          type: credential.type,
          response: {
            clientDataJSON: arrayBufferToBase64Url(response.clientDataJSON),
            attestationObject: arrayBufferToBase64Url(response.attestationObject),
          },
        };
      },

      serializeAuthenticationCredential(credential, challenge) {
        const { response } = credential;
        const payload = {
          id: credential.id,
          rawId: arrayBufferToBase64Url(credential.rawId),
          type: credential.type,
          response: {
            clientDataJSON: arrayBufferToBase64Url(response.clientDataJSON),
            authenticatorData: arrayBufferToBase64Url(response.authenticatorData),
            signature: arrayBufferToBase64Url(response.signature),
          },
          challenge,
        };
        if (response.userHandle) {
          payload.response.userHandle = arrayBufferToBase64Url(response.userHandle);
        }
        if (credential.authenticatorAttachment) {
          payload.authenticatorAttachment = credential.authenticatorAttachment;
        }
        return payload;
      },
    };
  }

  function normalizeBase64(input) {
    const base = input.replace(/-/g, '+').replace(/_/g, '/').replace(/\s+/g, '');
    const mod = base.length % 4;
    if (mod === 2) return base + '==';
    if (mod === 3) return base + '=';
    if (mod === 1) return base + '===';
    return base;
  }

  function base64ToUint8Array(base64) {
    const normalized = normalizeBase64(base64);
    const binary = atob(normalized);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i += 1) {
      bytes[i] = binary.charCodeAt(i);
    }
    return bytes;
  }

  function arrayBufferToBase64Url(buffer) {
    const bytes = new Uint8Array(buffer);
    let binary = '';
    for (let i = 0; i < bytes.length; i += 1) {
      binary += String.fromCharCode(bytes[i]);
    }
    const base64 = btoa(binary);
    return base64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
  }

  async function post(resource, { headers = {}, body, message }) {
    const init = {
      method: 'POST',
      headers,
    };
    if (body !== undefined) {
      init.body = body;
    }
    return ensureOk(fetch(resource, init), message);
  }

  async function postJSON(resource, payload, { headers = {}, message }) {
    const response = await post(resource, {
      headers: {
        'Content-Type': 'application/json',
        ...headers,
      },
      body: JSON.stringify(payload),
      message,
    });
    return response.json();
  }

  async function putJSON(resource, payload, { headers = {}, message }) {
    const response = await ensureOk(
      fetch(resource, {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
          ...headers,
        },
        body: JSON.stringify(payload),
      }),
      message
    );
    return response.json();
  }

  async function get(resource, { headers = {}, message }) {
    return ensureOk(
      fetch(resource, {
        method: 'GET',
        headers,
      }),
      message
    );
  }

  async function ensureOk(responsePromise, defaultMessage) {
    const response = await responsePromise;
    if (response.ok) {
      return response;
    }
    const detail = (await response.text()).trim();
    throw new Error(detail ? `${defaultMessage}: ${detail}` : defaultMessage);
  }

  async function readChallengeResponse(response) {
    const text = (await response.text()).trim();
    try {
      const parsed = JSON.parse(text);
      if (typeof parsed === 'string') return parsed;
      if (typeof parsed?.challenge === 'string') return parsed.challenge;
      if (typeof parsed?.value === 'string') return parsed.value;
      if (Array.isArray(parsed?.data)) {
        return arrayBufferToBase64Url(Uint8Array.from(parsed.data).buffer);
      }
    } catch {
      const unquoted = text.replace(/^"|"$/g, '');
      if (unquoted) return unquoted;
    }
    throw new Error('Unexpected challenge response format.');
  }
})();
