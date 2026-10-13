<script setup>
import { onMounted, ref } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import ReportHeader from './components/ReportHeader.vue';

const route = useRoute();
const { t } = useI18n();
const today = new Date();
const monthAgo = new Date(today);
monthAgo.setDate(today.getDate() - 29);
const dateValue = value =>
  `${value.getFullYear()}-${String(value.getMonth() + 1).padStart(2, '0')}-${String(value.getDate()).padStart(2, '0')}`;

const filters = ref({
  from: dateValue(monthAgo),
  to: dateValue(today),
  direction: '',
  agent_id: '',
  status: '',
  source: '',
});
const sources = [
  'instagram',
  'tiktok',
  'google',
  'referral',
  'existing_customer',
  'website',
  'other',
  'not_asked',
];
const report = ref(null);
const loading = ref(false);
const error = ref('');
const page = ref(1);

const sourceLabel = source =>
  source ? t(`SOOR_CALLS.SOURCES.${source.toUpperCase()}`) : t('SOOR_CALL_REPORTS.UNRECORDED');
const statusLabel = status => t(`SOOR_CALL_REPORTS.${status.toUpperCase()}`);
const time = value => value ? new Date(value).toLocaleString() : '—';
const duration = seconds => {
  if (seconds === null || seconds === undefined) return '—';
  const minutes = Math.floor(seconds / 60);
  return `${minutes}:${String(seconds % 60).padStart(2, '0')}`;
};

const fetchReport = async () => {
  loading.value = true;
  error.value = '';
  try {
    const { data } = await window.axios.get(
      `/api/v1/accounts/${route.params.accountId}/soor_whatsapp_calls/performance`,
      { params: { ...filters.value, page: page.value } }
    );
    report.value = data;
  } catch (requestError) {
    error.value = requestError.response?.data?.error || t('SOOR_CALL_REPORTS.LOAD_ERROR');
  } finally {
    loading.value = false;
  }
};
const applyFilters = () => {
  page.value = 1;
  fetchReport();
};
const changePage = next => {
  page.value = next;
  fetchReport();
};

onMounted(fetchReport);
</script>

<template>
  <div class="flex flex-col gap-5 pb-8">
    <ReportHeader
      :header-title="t('SOOR_CALL_REPORTS.TITLE')"
      :header-description="t('SOOR_CALL_REPORTS.DESCRIPTION')"
    />

    <form class="grid grid-cols-2 gap-3 rounded-xl border border-n-weak bg-n-surface-1 p-4 md:grid-cols-4" @submit.prevent="applyFilters">
      <label class="flex flex-col gap-1 text-sm text-n-slate-11">
        {{ t('SOOR_CALL_REPORTS.FROM') }}
        <input v-model="filters.from" type="date" required class="rounded-md border border-n-weak bg-n-surface-1 p-2 text-n-slate-12" />
      </label>
      <label class="flex flex-col gap-1 text-sm text-n-slate-11">
        {{ t('SOOR_CALL_REPORTS.TO') }}
        <input v-model="filters.to" type="date" required class="rounded-md border border-n-weak bg-n-surface-1 p-2 text-n-slate-12" />
      </label>
      <label class="flex flex-col gap-1 text-sm text-n-slate-11">
        {{ t('SOOR_CALL_REPORTS.DIRECTION') }}
        <select v-model="filters.direction" class="rounded-md border border-n-weak bg-n-surface-1 p-2 text-n-slate-12">
          <option value="">{{ t('SOOR_CALL_REPORTS.ALL') }}</option>
          <option value="inbound">{{ t('SOOR_CALL_REPORTS.INBOUND') }}</option>
          <option value="outbound">{{ t('SOOR_CALL_REPORTS.OUTBOUND') }}</option>
        </select>
      </label>
      <label class="flex flex-col gap-1 text-sm text-n-slate-11">
        {{ t('SOOR_CALL_REPORTS.AGENT') }}
        <select v-model="filters.agent_id" class="rounded-md border border-n-weak bg-n-surface-1 p-2 text-n-slate-12">
          <option value="">{{ t('SOOR_CALL_REPORTS.ALL') }}</option>
          <option v-for="agent in report?.filter_agents || []" :key="agent.id" :value="agent.id">{{ agent.name }}</option>
        </select>
      </label>
      <label class="flex flex-col gap-1 text-sm text-n-slate-11">
        {{ t('SOOR_CALL_REPORTS.STATUS') }}
        <select v-model="filters.status" class="rounded-md border border-n-weak bg-n-surface-1 p-2 text-n-slate-12">
          <option value="">{{ t('SOOR_CALL_REPORTS.ALL') }}</option>
          <option value="answered">{{ t('SOOR_CALL_REPORTS.ANSWERED') }}</option>
          <option value="missed">{{ t('SOOR_CALL_REPORTS.MISSED') }}</option>
          <option value="unanswered">{{ t('SOOR_CALL_REPORTS.UNANSWERED') }}</option>
          <option value="ongoing">{{ t('SOOR_CALL_REPORTS.ONGOING') }}</option>
        </select>
      </label>
      <label class="flex flex-col gap-1 text-sm text-n-slate-11">
        {{ t('SOOR_CALL_REPORTS.SOURCE') }}
        <select v-model="filters.source" class="rounded-md border border-n-weak bg-n-surface-1 p-2 text-n-slate-12">
          <option value="">{{ t('SOOR_CALL_REPORTS.ALL') }}</option>
          <option v-for="source in sources" :key="source" :value="source">{{ sourceLabel(source) }}</option>
          <option value="unrecorded">{{ t('SOOR_CALL_REPORTS.UNRECORDED') }}</option>
        </select>
      </label>
      <div class="col-span-2 flex items-end">
        <button type="submit" :disabled="loading" class="rounded-md bg-n-brand px-4 py-2 text-white disabled:opacity-50">
          {{ t('SOOR_CALL_REPORTS.APPLY') }}
        </button>
      </div>
    </form>

    <p v-if="error" role="alert" class="rounded-md bg-ruby-2 p-3 text-ruby-9">{{ error }}</p>
    <template v-if="report">
      <div class="grid grid-cols-2 gap-3 lg:grid-cols-5">
        <div v-for="metric in [
          { label: 'TOTAL', value: report.metrics.total },
          { label: 'ANSWERED', value: report.metrics.answered },
          { label: 'MISSED', value: report.metrics.missed },
          { label: 'ANSWER_RATE', value: `${report.metrics.answer_rate}%` },
          { label: 'AVERAGE_DURATION', value: duration(report.metrics.average_duration_seconds) },
        ]" :key="metric.label" class="rounded-xl border border-n-weak bg-n-surface-1 p-4">
          <p class="text-sm text-n-slate-11">{{ t(`SOOR_CALL_REPORTS.${metric.label}`) }}</p>
          <p class="mt-2 text-2xl font-semibold text-n-slate-12">{{ metric.value }}</p>
        </div>
      </div>
      <p class="text-sm text-n-slate-11">
        {{ t('SOOR_CALL_REPORTS.AVERAGE_PICKUP') }}: {{ duration(report.metrics.average_pickup_seconds) }}
      </p>

      <div class="grid gap-4 lg:grid-cols-2">
        <section class="rounded-xl border border-n-weak bg-n-surface-1 p-4">
          <h2 class="mb-3 font-semibold text-n-slate-12">{{ t('SOOR_CALL_REPORTS.SOURCES_TITLE') }}</h2>
          <div v-for="(count, source) in report.sources" :key="source" class="flex justify-between border-t border-n-weak py-2 text-sm text-n-slate-12">
            <span>{{ sourceLabel(source === 'null' ? null : source) }}</span><span>{{ count }}</span>
          </div>
        </section>
        <section class="rounded-xl border border-n-weak bg-n-surface-1 p-4">
          <h2 class="mb-3 font-semibold text-n-slate-12">{{ t('SOOR_CALL_REPORTS.AGENTS_TITLE') }}</h2>
          <div v-for="agent in report.agents" :key="agent.id" class="flex justify-between border-t border-n-weak py-2 text-sm text-n-slate-12">
            <span>{{ agent.name }}</span><span>{{ agent.answered }} / {{ agent.calls }} {{ t('SOOR_CALL_REPORTS.ANSWERED').toLowerCase() }}</span>
          </div>
        </section>
      </div>

      <section class="overflow-x-auto rounded-xl border border-n-weak bg-n-surface-1">
        <h2 class="p-4 font-semibold text-n-slate-12">{{ t('SOOR_CALL_REPORTS.RECENT_TITLE') }}</h2>
        <table class="w-full min-w-[900px] text-left text-sm">
          <thead class="border-y border-n-weak bg-n-surface-2 text-n-slate-11">
            <tr>
              <th v-for="column in ['DATE', 'CUSTOMER', 'DIRECTION', 'STATUS', 'AGENT', 'DURATION', 'SOURCE', 'OUTCOME', 'CONVERSATION']" :key="column" class="px-3 py-2 font-medium">{{ t(`SOOR_CALL_REPORTS.${column}`) }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="call in report.records" :key="call.id" class="border-b border-n-weak text-n-slate-12">
              <td class="px-3 py-3 whitespace-nowrap">{{ time(call.started_at) }}</td>
              <td class="px-3 py-3">{{ call.phone_number || '—' }}</td>
              <td class="px-3 py-3">{{ t(`SOOR_CALL_REPORTS.${call.direction.toUpperCase()}`) }}</td>
              <td class="px-3 py-3">{{ statusLabel(call.status) }}</td>
              <td class="px-3 py-3">{{ call.agent || '—' }}</td>
              <td class="px-3 py-3">{{ duration(call.duration_seconds) }}</td>
              <td class="px-3 py-3">{{ sourceLabel(call.source) }}</td>
              <td class="max-w-48 truncate px-3 py-3" :title="call.outcome">{{ call.outcome || '—' }}</td>
              <td class="px-3 py-3">
                <router-link v-if="call.conversation_display_id" :to="`/app/accounts/${route.params.accountId}/conversations/${call.conversation_display_id}`" class="text-n-brand underline">
                  {{ t('SOOR_CALL_REPORTS.OPEN_CHAT') }}
                </router-link>
                <span v-else>—</span>
              </td>
            </tr>
          </tbody>
        </table>
        <p v-if="!report.records.length" class="p-4 text-sm text-n-slate-11">{{ t('SOOR_CALL_REPORTS.EMPTY') }}</p>
      </section>
      <div v-if="report.meta.pages > 1" class="flex items-center justify-end gap-3 text-sm text-n-slate-11">
        <button :disabled="page <= 1 || loading" @click="changePage(page - 1)">{{ t('SOOR_CALL_REPORTS.PREVIOUS') }}</button>
        <span>{{ t('SOOR_CALL_REPORTS.PAGE', { page, pages: report.meta.pages }) }}</span>
        <button :disabled="page >= report.meta.pages || loading" @click="changePage(page + 1)">{{ t('SOOR_CALL_REPORTS.NEXT') }}</button>
      </div>
    </template>
  </div>
</template>
