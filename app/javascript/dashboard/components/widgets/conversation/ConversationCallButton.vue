<script setup>
import { computed, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import {
  getVoiceCallProvider,
  VOICE_CALL_PROVIDERS,
} from 'dashboard/helper/inbox';
import {
  VOICE_CALL_DIRECTION,
  VOICE_CALL_OUTBOUND_INIT_STATUS,
} from 'dashboard/components-next/message/constants';
import { useWhatsappCallSession } from 'dashboard/composables/useWhatsappCallSession';
import { useCallsStore } from 'dashboard/stores/calls';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { useAlert } from 'dashboard/composables';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  inbox: {
    type: Object,
    default: () => ({}),
  },
  chat: {
    type: Object,
    default: () => ({}),
  },
});

const { t } = useI18n();
const route = useRoute();
const store = useStore();
const callsStore = useCallsStore();
const whatsappCallSession = useWhatsappCallSession();
const contactsUiFlags = useMapGetter('contacts/getUIFlags');
const { isCloudFeatureEnabled } = useAccount();
const soorEnabledInboxId = ref(null);

watch(
  [() => props.inbox?.id, () => route.params.accountId],
  async ([inboxId, accountId]) => {
    soorEnabledInboxId.value = null;
    if (
      !inboxId ||
      !accountId ||
      props.inbox?.channel_type !== 'Channel::Whatsapp'
    )
      return;

    try {
      const { data } = await window.axios.get(
        `/api/v1/accounts/${accountId}/soor_whatsapp_calls`
      );
      soorEnabledInboxId.value = data.inbox_id;
    } catch (_) {
      // Keep calling hidden when this inbox is not configured or accessible.
    }
  },
  { immediate: true }
);

const voiceCallProvider = computed(() => getVoiceCallProvider(props.inbox));
const isVoiceCallInbox = computed(
  () =>
    voiceCallProvider.value !== null &&
    isCloudFeatureEnabled(FEATURE_FLAGS.CHANNEL_VOICE)
);
const isSoorWhatsappInbox = computed(
  () =>
    props.inbox?.channel_type === 'Channel::Whatsapp' &&
    props.inbox?.provider === 'whatsapp_cloud' &&
    Number(props.inbox?.id) === Number(soorEnabledInboxId.value)
);
const isWhatsappVoiceInbox = computed(
  () => voiceCallProvider.value === VOICE_CALL_PROVIDERS.WHATSAPP
);

const isCallButtonDisabled = computed(() => {
  if (callsStore.hasActiveCall || callsStore.hasIncomingCall) return true;
  if (isWhatsappVoiceInbox.value) {
    return whatsappCallSession.isInitiating.value;
  }
  return contactsUiFlags.value?.isInitiatingCall || false;
});

const isCallButtonLoading = computed(() =>
  isWhatsappVoiceInbox.value
    ? whatsappCallSession.isInitiating.value
    : !!contactsUiFlags.value?.isInitiatingCall
);

const callButtonTooltip = computed(() =>
  isWhatsappVoiceInbox.value || isSoorWhatsappInbox.value
    ? t('CONVERSATION.HEADER.WHATSAPP_CALL')
    : t('CONVERSATION.HEADER.VOICE_CALL')
);

const startWhatsappCall = async () => {
  if (whatsappCallSession.isInitiating.value) return;
  try {
    const response = await whatsappCallSession.initiateOutboundCall({
      conversationId: props.chat.id,
    });

    // Composable returns LOCKED when init is already in flight or a call is
    // active; soft no-op so a parallel click doesn't trigger a banner.
    if (response?.status === VOICE_CALL_OUTBOUND_INIT_STATUS.LOCKED) return;
    // Permission template path returns no call id — show banner, no widget yet.
    if (!response?.id) {
      const status = response?.status;
      const messageKey =
        status === VOICE_CALL_OUTBOUND_INIT_STATUS.PERMISSION_PENDING
          ? 'CONVERSATION.HEADER.WHATSAPP_CALL_PERMISSION_PENDING'
          : 'CONVERSATION.HEADER.WHATSAPP_CALL_PERMISSION_REQUESTED';
      useAlert(t(messageKey));
      return;
    }

    // Stay non-active until Meta delivers the connect webhook (sdp_answer);
    // flipping to active here would start the duration timer before pickup.
    callsStore.addCall({
      callSid: response.call_id,
      callId: response.id,
      conversationId: props.chat.id,
      inboxId: props.inbox?.id,
      callDirection: VOICE_CALL_DIRECTION.OUTBOUND,
      provider: VOICE_CALL_PROVIDERS.WHATSAPP,
    });
  } catch (error) {
    useAlert(error?.message || t('CONVERSATION.HEADER.WHATSAPP_CALL_FAILED'));
  }
};

const startTwilioCall = async () => {
  if (contactsUiFlags.value?.isInitiatingCall) return;
  try {
    const response = await store.dispatch('contacts/initiateCall', {
      contactId: props.chat?.meta?.sender?.id,
      inboxId: props.inbox?.id,
      conversationId: props.chat.id,
    });

    callsStore.addCall({
      callSid: response?.call_sid,
      conversationId: response?.conversation_id ?? props.chat.id,
      inboxId: props.inbox?.id,
      callDirection: VOICE_CALL_DIRECTION.OUTBOUND,
    });
  } catch (error) {
    useAlert(error?.message || t('CONVERSATION.HEADER.VOICE_CALL_FAILED'));
  }
};

const startCall = () => {
  if (isSoorWhatsappInbox.value) {
    window.dispatchEvent(
      new CustomEvent('soor-whatsapp-call-start', {
        detail: { conversationId: props.chat.id },
      })
    );
    return;
  }
  if (isWhatsappVoiceInbox.value) {
    startWhatsappCall();
    return;
  }
  startTwilioCall();
};
</script>

<template>
  <NextButton
    v-if="isVoiceCallInbox || isSoorWhatsappInbox"
    v-tooltip.bottom="callButtonTooltip"
    sm
    ghost
    slate
    icon="i-lucide-phone"
    :is-loading="isCallButtonLoading"
    :disabled="isCallButtonDisabled"
    @click="startCall"
  />
  <template v-else />
</template>
