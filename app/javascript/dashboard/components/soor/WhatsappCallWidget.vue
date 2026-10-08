<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';

const route = useRoute();
const { t } = useI18n();
const calls = ref([]);
const activeId = ref(null);
const error = ref('');
const busy = ref(false);
const enabled = ref(true);
const completedCall = ref(null);
const outcome = ref('');
let peer;
let microphone;
const remoteAudio = ref(null);
let pollTimer;

const url = () =>
  `/api/v1/accounts/${route.params.accountId}/soor_whatsapp_calls`;
const activeCall = computed(() =>
  calls.value.find(call => call.id === activeId.value)
);
const incoming = computed(() =>
  calls.value.find(
    call =>
      call.direction === 'inbound' &&
      call.status === 'ringing' &&
      new Date(call.ring_expires_at).getTime() > Date.now()
  )
);

const releaseAudio = () => {
  microphone?.getTracks().forEach(track => track.stop());
  peer?.close();
  if (remoteAudio.value) remoteAudio.value.srcObject = null;
  microphone = null;
  peer = null;
  activeId.value = null;
};

const gatherIce = connection =>
  new Promise(resolve => {
    if (connection.iceGatheringState === 'complete') {
      resolve();
      return;
    }
    const timeout = setTimeout(resolve, 10000);
    connection.addEventListener('icegatheringstatechange', () => {
      if (connection.iceGatheringState === 'complete') {
        clearTimeout(timeout);
        resolve();
      }
    });
  });

const prepareAudio = async () => {
  microphone = await navigator.mediaDevices.getUserMedia({ audio: true });
  peer = new RTCPeerConnection({
    iceServers: [{ urls: 'stun:stun.l.google.com:19302' }],
  });
  microphone.getTracks().forEach(track => peer.addTrack(track, microphone));
  peer.ontrack = event => {
    if (remoteAudio.value) {
      remoteAudio.value.srcObject = event.streams[0];
      remoteAudio.value.play().catch(() => {
        error.value = t('SOOR_CALLS.AUDIO_BLOCKED');
      });
    }
  };
};

const refresh = async () => {
  if (!enabled.value || !route.params.accountId) return;
  try {
    const { data } = await window.axios.get(url());
    calls.value = data.calls;
    const call = activeCall.value;
    if (
      call?.direction === 'outbound' &&
      call.sdp_answer &&
      peer?.remoteDescription === null
    ) {
      await peer.setRemoteDescription({ type: 'answer', sdp: call.sdp_answer });
    }
    if (call?.status === 'ended') {
      completedCall.value = call;
      releaseAudio();
    }
  } catch (requestError) {
    if ([403, 404].includes(requestError.response?.status))
      enabled.value = false;
  }
};

const start = async event => {
  if (busy.value || activeId.value) return;
  busy.value = true;
  error.value = '';
  completedCall.value = null;
  try {
    await prepareAudio();
    const offer = await peer.createOffer();
    await peer.setLocalDescription(offer);
    await gatherIce(peer);
    const { data } = await window.axios.post(`${url()}/initiate`, {
      conversation_id: event.detail.conversationId,
      sdp_offer: peer.localDescription.sdp,
    });
    activeId.value = data.id;
    await refresh();
  } catch (requestError) {
    error.value =
      requestError.response?.data?.error ||
      requestError.message ||
      t('SOOR_CALLS.START_FAILED');
    releaseAudio();
  } finally {
    busy.value = false;
  }
};

const answer = async call => {
  if (busy.value || activeId.value) return;
  busy.value = true;
  error.value = '';
  try {
    await prepareAudio();
    await peer.setRemoteDescription({ type: 'offer', sdp: call.sdp_offer });
    const answerDescription = await peer.createAnswer();
    await peer.setLocalDescription(answerDescription);
    await gatherIce(peer);
    await window.axios.post(`${url()}/${encodeURIComponent(call.id)}/accept`, {
      sdp_answer: peer.localDescription.sdp,
    });
    activeId.value = call.id;
    await refresh();
  } catch (requestError) {
    error.value =
      requestError.response?.data?.error ||
      requestError.message ||
      t('SOOR_CALLS.ANSWER_FAILED');
    releaseAudio();
  } finally {
    busy.value = false;
  }
};

const end = async (call, action = 'terminate') => {
  try {
    await window.axios.post(
      `${url()}/${encodeURIComponent(call.id)}/${action}`
    );
    completedCall.value = call;
    releaseAudio();
    await refresh();
  } catch (requestError) {
    error.value =
      requestError.response?.data?.error || t('SOOR_CALLS.END_FAILED');
  }
};

const saveOutcome = async () => {
  const displayId = completedCall.value?.conversation_display_id;
  if (!displayId || !outcome.value.trim()) return;
  busy.value = true;
  try {
    await window.axios.post(
      `/api/v1/accounts/${route.params.accountId}/conversations/${displayId}/messages`,
      {
        content: `WhatsApp call outcome: ${outcome.value.trim()}`,
        private: true,
      }
    );
    completedCall.value = null;
    outcome.value = '';
    error.value = '';
  } catch (requestError) {
    error.value =
      requestError.response?.data?.error || t('SOOR_CALLS.NOTE_FAILED');
  } finally {
    busy.value = false;
  }
};

onMounted(() => {
  window.addEventListener('soor-whatsapp-call-start', start);
  refresh();
  pollTimer = setInterval(refresh, 2500);
});
onUnmounted(() => {
  window.removeEventListener('soor-whatsapp-call-start', start);
  clearInterval(pollTimer);
  releaseAudio();
});
</script>

<template>
  <aside
    v-if="enabled && (incoming || activeCall || completedCall || error || busy)"
    class="fixed bottom-6 right-6 z-50 w-80 rounded-xl border border-n-weak bg-n-surface-1 p-4 shadow-xl"
  >
    <audio ref="remoteAudio" autoplay playsinline class="hidden" />
    <p class="font-medium text-n-slate-12">{{ t('SOOR_CALLS.TITLE') }}</p>
    <p v-if="incoming && !activeCall" class="mt-2 text-n-slate-11">
      {{
        t('SOOR_CALLS.INCOMING_FROM', {
          caller: incoming.caller || t('SOOR_CALLS.UNKNOWN_CUSTOMER'),
        })
      }}
    </p>
    <p v-if="activeCall" class="mt-2 text-n-slate-11">
      {{
        t(
          activeCall.status === 'active'
            ? 'SOOR_CALLS.CONNECTED'
            : 'SOOR_CALLS.RINGING'
        )
      }}
    </p>
    <p v-if="error" class="mt-2 text-sm text-ruby-9">{{ error }}</p>
    <div class="mt-3 flex gap-2">
      <button
        v-if="incoming && !activeCall"
        type="button"
        :disabled="busy"
        class="rounded-md bg-n-brand px-3 py-2 text-white"
        @click="answer(incoming)"
      >
        {{ t('SOOR_CALLS.ANSWER') }}
      </button>
      <button
        v-if="incoming && !activeCall"
        type="button"
        :disabled="busy"
        class="rounded-md border border-n-weak px-3 py-2"
        @click="end(incoming, 'reject')"
      >
        {{ t('SOOR_CALLS.DECLINE') }}
      </button>
      <button
        v-if="activeCall"
        type="button"
        class="rounded-md bg-ruby-9 px-3 py-2 text-white"
        @click="end(activeCall)"
      >
        {{ t('SOOR_CALLS.END') }}
      </button>
      <button
        v-if="error && !activeCall && !incoming"
        type="button"
        @click="error = ''"
      >
        {{ t('SOOR_CALLS.DISMISS') }}
      </button>
    </div>
    <div v-if="completedCall && !activeCall" class="mt-3">
      <label
        v-if="completedCall.conversation_display_id"
        class="block text-sm text-n-slate-11"
      >
        {{ t('SOOR_CALLS.OUTCOME_LABEL') }}
        <textarea
          v-model="outcome"
          class="mt-1 w-full rounded-md border border-n-weak bg-n-surface-1 p-2 text-n-slate-12"
          rows="2"
          :placeholder="t('SOOR_CALLS.OUTCOME_PLACEHOLDER')"
        />
      </label>
      <p v-else class="text-sm text-n-slate-11">
        {{ t('SOOR_CALLS.NO_CONVERSATION') }}
      </p>
      <button
        v-if="completedCall.conversation_display_id"
        type="button"
        :disabled="busy || !outcome.trim()"
        class="mt-2 rounded-md bg-n-brand px-3 py-2 text-white"
        @click="saveOutcome"
      >
        {{ t('SOOR_CALLS.SAVE_OUTCOME') }}
      </button>
      <button
        type="button"
        class="ml-2 text-sm text-n-slate-11"
        @click="completedCall = null"
      >
        {{ t('SOOR_CALLS.CLOSE') }}
      </button>
    </div>
  </aside>
</template>
