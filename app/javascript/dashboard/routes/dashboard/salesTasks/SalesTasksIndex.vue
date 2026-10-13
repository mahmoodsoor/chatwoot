<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

const { t } = useI18n();
const route = useRoute();
const store = useStore();
const accountId = computed(() => route.params.accountId);
const agents = useMapGetter('agents/getVerifiedAgents');
const tasks = ref([]);
const meta = ref({ page: 1, total: 0, pages: 0 });
const counts = ref({});
const view = ref('all');
const query = ref('');
const filters = reactive({
  stage: '',
  task_type: '',
  assignee_id: '',
  car: '',
  lead_source: '',
  call_outcome: '',
  sort: 'due_soonest',
});
const loading = ref(false);
const saving = ref(false);
const opening = ref(false);
const selected = ref(null);
const form = reactive({
  task_type: '',
  stage: '',
  assignee_id: '',
  due_at: '',
  outcome: '',
  lead_source: '',
  call_outcome: '',
  call_outcome_detail: '',
});
const callOutcomes = [
  'expensive',
  'other_company',
  'not_due',
  'end_of_month',
  'other',
  'no_available_quotes',
];
const insuranceCompanies = [
  'Al-Arabiya',
  'Al Hilal Life',
  'Al Rajhi Insurance',
  'Al Saqr Saudi Insurance',
  'Alhilal Takaful',
  'Allied Cooperative Insurance Group',
  'Amana Gulf Insurance',
  'Arab Insurance Group (Arig)',
  'Arabia Insurance',
  'Arabia Insurance International',
  'Bahrain Kuwait Insurance (GIG Bahrain)',
  'Bahrain National Insurance (bni)',
  'Bahrain National Life',
  'BKIC',
  'Cigna Life Insurance',
  'Gulf Insurance Group (GIG Gulf)',
  'GIG Gulf',
  'Gulf Union Insurance',
  'Hannover ReTakaful',
  'Hannover Rueck',
  'International Insurance',
  'International Islamic Insurance',
  'Iran Insurance',
  'KFH Takaful',
  'LIVA Insurance',
  'Life Insurance Corporation (International)',
  'Masheed Captive Insurance',
  'Medgulf Bahrain',
  'Medgulf Takaful',
  'MetLife Bahrain',
  'New India',
  'Orient Insurance',
  'Orient',
  'Saudi Allied Cooperative Insurance',
  'Saudi Arabian Insurance Company (Damana)',
  'DAMANA',
  'Saudi National Insurance',
  'SNIC Insurance',
  'SOOR',
  'Solidarity Bahrain',
  "T'azur",
  'Takaful International',
  'The New India Assurance',
  'Trust Re',
  'United Insurance',
  'Zurich Insurance',
  'Zurich International Life',
];
const leadSources = [
  'instagram',
  'tiktok',
  'google',
  'referral',
  'existing_customer',
  'website',
  'other',
  'not_asked',
];
const taskTypes = [
  'welcome_call',
  'follow_up',
  'documents',
  'quote',
  'renewal',
  'other',
];
const stages = [
  'new',
  'attempted',
  'contacted',
  'follow_up',
  'quote_sent',
  'won',
  'lost',
];
let searchTimer;
let latestRequest = 0;

const apiUrl = computed(
  () => `/api/v1/accounts/${accountId.value}/soor_sales_tasks`
);
const stageLabel = stage => t(`SOOR_SALES_TASKS.STAGE_LABELS.${stage}`);
const typeLabel = type => t(`SOOR_SALES_TASKS.TYPE_LABELS.${type}`);
const callOutcomeLabel = outcome =>
  outcome ? t(`SOOR_SALES_TASKS.CALL_OUTCOMES.${outcome.toUpperCase()}`) : '—';
const carLabel = task => {
  const car = task.vehicle || {};
  return (
    [car.make, car.model, car.year].filter(Boolean).join(' ') ||
    t('SOOR_SALES_TASKS.NO_CAR')
  );
};
const expiryLabel = task => {
  const expiry = task.vehicle?.registration_expiry;
  return expiry ? new Date(expiry).toLocaleDateString() : '';
};
const formatTime = value =>
  value
    ? new Intl.DateTimeFormat(undefined, {
        timeZone: 'Asia/Bahrain',
        hour: '2-digit',
        minute: '2-digit',
      }).format(new Date(value))
    : '';
const formatShortDate = value =>
  value
    ? new Intl.DateTimeFormat(undefined, {
        timeZone: 'Asia/Bahrain',
        day: 'numeric',
        month: 'short',
        year: 'numeric',
      }).format(new Date(value))
    : '—';
const stageClass = stage => {
  if (stage === 'won') return 'bg-n-teal-2 text-n-teal-11';
  if (stage === 'lost') return 'bg-n-ruby-2 text-n-ruby-11';
  if (stage === 'new') return 'bg-n-slate-3 text-n-slate-11';
  return 'bg-n-amber-2 text-n-amber-11';
};
const localDateTime = value => {
  if (!value) return '';
  const date = new Date(value);
  return new Date(date.getTime() - date.getTimezoneOffset() * 60000)
    .toISOString()
    .slice(0, 16);
};
const isOverdue = task =>
  task.due_at &&
  new Date(task.due_at) < new Date() &&
  !['won', 'lost'].includes(task.stage);
const openCount = computed(() =>
  Object.entries(counts.value).reduce(
    (sum, [stage, count]) =>
      ['won', 'lost'].includes(stage) ? sum : sum + count,
    0
  )
);
const hasActiveFilters = computed(() =>
  view.value !== 'all' ||
  query.value.trim() ||
  filters.stage ||
  filters.task_type ||
  filters.assignee_id ||
  filters.car ||
  filters.lead_source ||
  filters.call_outcome
);

async function load(page = 1) {
  const requestId = ++latestRequest;
  loading.value = true;
  try {
    const params = {
      page,
      q: query.value.trim() || undefined,
      stage: view.value === 'new' ? 'new' : filters.stage || undefined,
      task_type: filters.task_type || undefined,
      assignee_id: filters.assignee_id || undefined,
      car: filters.car || undefined,
      lead_source: filters.lead_source || undefined,
      call_outcome: filters.call_outcome || undefined,
      sort: filters.sort,
    };
    if (view.value === 'mine') params.mine = true;
    if (view.value === 'unassigned_filter') params.unassigned = true;
    if (view.value === 'overdue') params.overdue = true;
    const { data } = await window.axios.get(apiUrl.value, { params });
    if (requestId !== latestRequest) return;

    tasks.value = data.tasks;
    meta.value = data.meta;
    counts.value = data.counts;
  } catch {
    if (requestId === latestRequest) useAlert(t('SOOR_SALES_TASKS.LOAD_FAILED'));
  } finally {
    if (requestId === latestRequest) loading.value = false;
  }
}

function open(task) {
  selected.value = task;
  Object.assign(form, {
    task_type: task.task_type,
    stage: task.stage,
    assignee_id: task.assignee?.id || '',
    due_at: localDateTime(task.due_at),
    outcome: '',
    lead_source: task.lead_source || '',
    call_outcome: task.call_outcome || '',
    call_outcome_detail: task.call_outcome_detail || '',
  });
}

async function save() {
  if (!selected.value || saving.value) return;
  saving.value = true;
  try {
    const { data } = await window.axios.patch(
      `${apiUrl.value}/${selected.value.id}`,
      {
        task: {
          task_type: form.task_type,
          stage: form.stage,
          assignee_id: form.assignee_id || '',
          due_at: form.due_at ? new Date(form.due_at).toISOString() : '',
          outcome: form.outcome.trim(),
          lead_source: form.lead_source,
          call_outcome: form.call_outcome,
          call_outcome_detail: form.call_outcome_detail.trim(),
        },
      }
    );
    selected.value = data.task;
    form.outcome = '';
    useAlert(t('SOOR_SALES_TASKS.SAVED'));
    await load(meta.value.page);
  } catch (error) {
    useAlert(error.response?.data?.error || t('SOOR_SALES_TASKS.SAVE_FAILED'));
  } finally {
    saving.value = false;
  }
}

async function openChat() {
  if (!selected.value || opening.value) return;
  opening.value = true;
  try {
    const { data } = await window.axios.post(
      `${apiUrl.value}/${selected.value.id}/open_conversation`
    );
    window.location.assign(
      `/app/accounts/${accountId.value}/conversations/${data.conversation_id}`
    );
  } catch (error) {
    useAlert(error.response?.data?.error || t('SOOR_SALES_TASKS.SAVE_FAILED'));
    opening.value = false;
  }
}

watch(
  () => [
    view.value,
    query.value,
    filters.stage,
    filters.task_type,
    filters.assignee_id,
    filters.car,
    filters.lead_source,
    filters.call_outcome,
    filters.sort,
  ],
  () => {
    clearTimeout(searchTimer);
    searchTimer = setTimeout(() => load(), query.value ? 300 : 0);
  }
);
function resetFilters() {
  view.value = 'all';
  query.value = '';
  Object.assign(filters, {
    stage: '',
    task_type: '',
    assignee_id: '',
    car: '',
    lead_source: '',
    call_outcome: '',
    sort: 'due_soonest',
  });
}
function selectView(next) {
  if (next === 'new') filters.stage = '';
  if (['mine', 'unassigned_filter'].includes(next)) filters.assignee_id = '';
  view.value = next;
}
onMounted(() => {
  store.dispatch('agents/get');
  load();
});
</script>

<template>
  <div class="flex h-full min-w-0 flex-col bg-n-background">
    <header class="border-b border-n-weak bg-n-solid-1 px-6 py-4">
      <div class="flex flex-wrap items-center justify-between gap-4">
        <div>
          <h1 class="text-xl font-semibold text-n-slate-12">
            {{ t('SOOR_SALES_TASKS.TITLE') }}
          </h1>
          <p class="mt-0.5 text-xs text-n-slate-11">
            {{ t('SOOR_SALES_TASKS.SUBTITLE') }}
          </p>
        </div>
        <button
          class="rounded-lg border border-n-weak px-3 py-2 text-sm text-n-slate-12 hover:bg-n-alpha-2"
          type="button"
          @click="load(meta.page)"
        >
          {{ t('SOOR_SALES_TASKS.REFRESH') }}
        </button>
      </div>
      <div class="mt-4 flex flex-wrap items-center gap-x-6 gap-y-2 text-sm">
        <div class="flex items-baseline gap-2">
          <span class="font-semibold text-n-slate-12">{{ openCount }}</span>
          <span class="text-n-slate-11">{{ t('SOOR_SALES_TASKS.IN_PROGRESS') }}</span>
        </div>
        <div class="flex items-baseline gap-2">
          <span class="font-semibold text-n-slate-12">{{ counts.new || 0 }}</span>
          <span class="text-n-slate-11">{{ t('SOOR_SALES_TASKS.NEW') }}</span>
        </div>
        <div class="flex items-baseline gap-2">
          <span class="font-semibold text-n-teal-11">{{ counts.won || 0 }}</span>
          <span class="text-n-slate-11">{{ t('SOOR_SALES_TASKS.WON') }}</span>
        </div>
      </div>
    </header>

    <div
      class="flex flex-wrap items-center gap-2 border-b border-n-weak bg-n-solid-1 px-6 py-3"
    >
      <button
        v-for="filter in ['all', 'mine', 'unassigned_filter', 'overdue', 'new']"
        :key="filter"
        type="button"
        class="rounded-lg px-3 py-1.5 text-sm"
        :class="
          view === filter
            ? 'bg-n-brand text-white'
            : 'text-n-slate-11 hover:bg-n-alpha-2'
        "
        @click="selectView(filter)"
      >
        {{ t(`SOOR_SALES_TASKS.${filter.toUpperCase()}`) }}
      </button>
      <input
        v-model="query"
        type="search"
        class="ml-auto min-w-56 rounded-lg border border-n-weak bg-n-background px-3 py-2 text-sm text-n-slate-12"
        :placeholder="t('SOOR_SALES_TASKS.SEARCH')"
        :aria-label="t('SOOR_SALES_TASKS.SEARCH')"
      />
    </div>

    <div class="grid gap-3 border-b border-n-weak bg-n-solid-1 px-6 py-3 sm:grid-cols-2 xl:grid-cols-5">
      <label class="grid gap-1 text-xs text-n-slate-11">
        {{ t('SOOR_SALES_TASKS.STAGE') }}
        <select v-model="filters.stage" :disabled="view === 'new'" class="rounded-lg border border-n-weak bg-n-background px-3 py-2 text-sm text-n-slate-12 disabled:opacity-50">
          <option value="">{{ t('SOOR_SALES_TASKS.ALL_STAGES') }}</option>
          <option v-for="stage in stages" :key="stage" :value="stage">{{ stageLabel(stage) }}</option>
        </select>
      </label>
      <label class="grid gap-1 text-xs text-n-slate-11">
        {{ t('SOOR_SALES_TASKS.TASK') }}
        <select v-model="filters.task_type" class="rounded-lg border border-n-weak bg-n-background px-3 py-2 text-sm text-n-slate-12">
          <option value="">{{ t('SOOR_SALES_TASKS.ALL_TASK_TYPES') }}</option>
          <option v-for="type in taskTypes" :key="type" :value="type">{{ typeLabel(type) }}</option>
        </select>
      </label>
      <label class="grid gap-1 text-xs text-n-slate-11">
        {{ t('SOOR_SALES_TASKS.OWNER') }}
        <select v-model="filters.assignee_id" :disabled="['mine', 'unassigned_filter'].includes(view)" class="rounded-lg border border-n-weak bg-n-background px-3 py-2 text-sm text-n-slate-12 disabled:opacity-50">
          <option value="">{{ t('SOOR_SALES_TASKS.ALL_OWNERS') }}</option>
          <option value="unassigned">{{ t('SOOR_SALES_TASKS.UNASSIGNED') }}</option>
          <option v-for="agent in agents" :key="agent.id" :value="agent.id">{{ agent.name }}</option>
        </select>
      </label>
      <label class="grid gap-1 text-xs text-n-slate-11">
        {{ t('SOOR_SALES_TASKS.CAR') }}
        <select v-model="filters.car" class="rounded-lg border border-n-weak bg-n-background px-3 py-2 text-sm text-n-slate-12">
          <option value="">{{ t('SOOR_SALES_TASKS.ALL_CARS') }}</option>
          <option value="with">{{ t('SOOR_SALES_TASKS.WITH_CAR') }}</option>
          <option value="without">{{ t('SOOR_SALES_TASKS.WITHOUT_CAR') }}</option>
        </select>
      </label>
      <label class="grid gap-1 text-xs text-n-slate-11">
        {{ t('SOOR_SALES_TASKS.LEAD_SOURCE') }}
        <select v-model="filters.lead_source" class="rounded-lg border border-n-weak bg-n-background px-3 py-2 text-sm text-n-slate-12">
          <option value="">{{ t('SOOR_SALES_TASKS.ALL_SOURCES') }}</option>
          <option v-for="source in leadSources" :key="source" :value="source">{{ t(`SOOR_SALES_TASKS.SOURCES.${source.toUpperCase()}`) }}</option>
          <option value="unrecorded">{{ t('SOOR_SALES_TASKS.SOURCE_NOT_RECORDED') }}</option>
        </select>
      </label>
      <label class="grid gap-1 text-xs text-n-slate-11">
        {{ t('SOOR_SALES_TASKS.CALL_OUTCOME') }}
        <select v-model="filters.call_outcome" class="rounded-lg border border-n-weak bg-n-background px-3 py-2 text-sm text-n-slate-12">
          <option value="">{{ t('SOOR_SALES_TASKS.ALL_CALL_OUTCOMES') }}</option>
          <option v-for="outcome in callOutcomes" :key="outcome" :value="outcome">{{ callOutcomeLabel(outcome) }}</option>
          <option value="unrecorded">{{ t('SOOR_SALES_TASKS.CALL_OUTCOME_NOT_RECORDED') }}</option>
        </select>
      </label>
      <label class="grid gap-1 text-xs text-n-slate-11">
        {{ t('SOOR_SALES_TASKS.SORT_BY') }}
        <select v-model="filters.sort" class="rounded-lg border border-n-weak bg-n-background px-3 py-2 text-sm text-n-slate-12">
          <option value="due_soonest">{{ t('SOOR_SALES_TASKS.SORT_DUE_SOONEST') }}</option>
          <option value="due_latest">{{ t('SOOR_SALES_TASKS.SORT_DUE_LATEST') }}</option>
          <option value="joined_newest">{{ t('SOOR_SALES_TASKS.SORT_JOINED_NEWEST') }}</option>
          <option value="joined_oldest">{{ t('SOOR_SALES_TASKS.SORT_JOINED_OLDEST') }}</option>
          <option value="searched_newest">{{ t('SOOR_SALES_TASKS.SORT_SEARCHED_NEWEST') }}</option>
          <option value="searched_oldest">{{ t('SOOR_SALES_TASKS.SORT_SEARCHED_OLDEST') }}</option>
          <option value="customer_az">{{ t('SOOR_SALES_TASKS.SORT_CUSTOMER_AZ') }}</option>
          <option value="customer_za">{{ t('SOOR_SALES_TASKS.SORT_CUSTOMER_ZA') }}</option>
        </select>
      </label>
      <button type="button" class="self-end justify-self-start rounded-lg border border-n-weak px-3 py-2 text-sm text-n-slate-12 hover:bg-n-alpha-2" @click="resetFilters">
        {{ t('SOOR_SALES_TASKS.CLEAR_FILTERS') }}
      </button>
      <span class="self-end text-sm text-n-slate-11">
        {{ t('SOOR_SALES_TASKS.RESULT_COUNT', { count: meta.total }) }}
      </span>
    </div>

    <div class="min-h-0 flex-1 overflow-auto bg-n-solid-1">
      <div v-if="loading" class="p-8 text-sm text-n-slate-11">
        {{ t('SOOR_SALES_TASKS.LOADING') }}
      </div>
      <div
        v-else-if="!tasks.length"
        class="mx-auto max-w-md px-6 py-16 text-center"
      >
        <div class="text-lg font-medium text-n-slate-12">
          {{ t('SOOR_SALES_TASKS.EMPTY') }}
        </div>
        <p
          v-if="!meta.total && !hasActiveFilters"
          class="mt-2 text-sm text-n-slate-11"
        >
          {{ t('SOOR_SALES_TASKS.EMPTY_SOURCE') }}
        </p>
      </div>
      <table v-else class="w-full min-w-[1400px] text-left text-sm">
        <thead
          class="sticky top-0 z-10 border-b border-n-weak bg-n-solid-2 text-[11px] uppercase tracking-wide text-n-slate-10"
        >
          <tr>
            <th class="w-44 px-5 py-3 font-semibold">
              {{ t('SOOR_SALES_TASKS.CUSTOMER') }}
            </th>
            <th class="w-48 px-4 py-3 font-semibold">
              {{ t('SOOR_SALES_TASKS.CAR') }}
            </th>
            <th class="w-28 px-4 py-3 font-semibold">
              {{ t('SOOR_SALES_TASKS.JOINED') }}
            </th>
            <th class="w-28 px-4 py-3 font-semibold">
              {{ t('SOOR_SALES_TASKS.CAR_SEARCHED') }}
            </th>
            <th class="w-32 px-4 py-3 font-semibold">
              {{ t('SOOR_SALES_TASKS.TASK') }}
            </th>
            <th class="w-32 px-4 py-3 font-semibold">
              {{ t('SOOR_SALES_TASKS.STAGE') }}
            </th>
            <th class="w-44 px-4 py-3 font-semibold">
              {{ t('SOOR_SALES_TASKS.CALL_OUTCOME') }}
            </th>
            <th class="w-28 px-4 py-3 font-semibold">
              {{ t('SOOR_SALES_TASKS.OWNER') }}
            </th>
            <th class="w-36 px-4 py-3 font-semibold">
              {{ t('SOOR_SALES_TASKS.DUE') }}
            </th>
            <th class="sticky right-0 z-20 w-24 border-l border-n-weak bg-n-solid-2 px-4 py-3 font-semibold">
              {{ t('SOOR_SALES_TASKS.ACTION') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="task in tasks"
            :key="task.id"
            class="cursor-pointer border-b border-n-weak transition-colors hover:bg-n-alpha-1"
            @click="open(task)"
          >
            <td class="px-5 py-3">
              <button
                type="button"
                class="max-w-48 truncate text-left font-semibold text-n-slate-12 hover:text-n-brand"
                @click.stop="open(task)"
              >
                {{ task.customer_name }}
              </button>
              <div
                v-if="
                  (task.phone_number || task.email) &&
                  task.customer_name !== (task.phone_number || task.email)
                "
                class="mt-0.5 text-xs text-n-slate-10"
              >
                {{ task.phone_number || task.email }}
              </div>
            </td>
            <td class="px-4 py-3">
              <div class="font-medium text-n-slate-12">{{ carLabel(task) }}</div>
              <div
                v-if="task.vehicle?.plate || expiryLabel(task)"
                class="mt-0.5 text-xs text-n-slate-10"
              >
                {{ task.vehicle?.plate }}
                <span v-if="task.vehicle?.plate && expiryLabel(task)">·</span>
                {{ expiryLabel(task) }}
              </div>
            </td>
            <td class="whitespace-nowrap px-4 py-3 text-n-slate-11">
              {{ formatShortDate(task.registered_at) }}
            </td>
            <td class="whitespace-nowrap px-4 py-3 text-n-slate-11">
              {{ formatShortDate(task.vehicle?.searched_at) }}
            </td>
            <td class="px-4 py-3 text-n-slate-12">
              {{ typeLabel(task.task_type) }}
            </td>
            <td class="px-4 py-3">
              <span
                class="inline-flex whitespace-nowrap rounded-full px-2.5 py-1 text-xs font-medium"
                :class="stageClass(task.stage)"
              >
                {{ stageLabel(task.stage) }}
              </span>
            </td>
            <td class="px-4 py-3 text-n-slate-11">
              <span>{{ callOutcomeLabel(task.call_outcome) }}</span>
              <span v-if="task.call_outcome_detail" class="mt-0.5 block max-w-40 truncate text-xs text-n-slate-10" :title="task.call_outcome_detail">
                {{ task.call_outcome_detail }}
              </span>
            </td>
            <td class="px-4 py-3 text-n-slate-11">
              {{ task.assignee?.name || t('SOOR_SALES_TASKS.UNASSIGNED') }}
            </td>
            <td
              class="whitespace-nowrap px-4 py-3 text-xs"
              :class="
                isOverdue(task)
                  ? 'font-semibold text-n-ruby-9'
                  : 'text-n-slate-11'
              "
            >
              <template v-if="task.due_at">
                <span class="block">{{ formatShortDate(task.due_at) }}</span>
                <span class="block text-n-slate-10">{{ formatTime(task.due_at) }}</span>
              </template>
              <template v-else>{{ t('SOOR_SALES_TASKS.NO_DUE') }}</template>
            </td>
            <td class="sticky right-0 z-10 border-l border-n-weak bg-n-solid-1 px-4 py-3">
              <button
                type="button"
                class="rounded-md border border-n-weak bg-n-solid-1 px-3 py-1.5 text-xs font-semibold text-n-brand shadow-sm hover:border-n-brand hover:bg-n-brand/10 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
                :aria-label="`${t('SOOR_SALES_TASKS.WORK_TASK')}: ${task.customer_name}`"
                @click.stop="open(task)"
              >
                {{ t('SOOR_SALES_TASKS.UPDATE') }}
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <footer
      v-if="meta.pages > 1"
      class="flex items-center justify-end gap-3 border-t border-n-weak px-6 py-3 text-sm text-n-slate-11"
    >
      <button
        type="button"
        :disabled="meta.page <= 1"
        class="disabled:opacity-40"
        @click="load(meta.page - 1)"
      >
        {{ t('SOOR_SALES_TASKS.PREVIOUS') }}
      </button>
      <span>{{ meta.page }} / {{ meta.pages }}</span>
      <button
        type="button"
        :disabled="meta.page >= meta.pages"
        class="disabled:opacity-40"
        @click="load(meta.page + 1)"
      >
        {{ t('SOOR_SALES_TASKS.NEXT') }}
      </button>
    </footer>

    <div
      v-if="selected"
      class="fixed inset-0 z-50 flex justify-end bg-black/35"
      @click.self="selected = null"
    >
      <section
        class="flex h-full w-full max-w-lg flex-col overflow-y-auto bg-n-solid-1 p-6 shadow-xl"
        aria-labelledby="sales-task-heading"
      >
        <div class="flex items-start justify-between gap-3">
          <div>
            <h2
              id="sales-task-heading"
              class="text-xl font-semibold text-n-slate-12"
            >
              {{ selected.customer_name }}
            </h2>
            <p class="mt-1 text-sm text-n-slate-11">
              {{ carLabel(selected) }} ·
              {{ selected.phone_number || selected.email }}
            </p>
          </div>
          <button
            type="button"
            class="text-sm text-n-slate-11"
            @click="selected = null"
          >
            {{ t('SOOR_SALES_TASKS.CLOSE') }}
          </button>
        </div>
        <div class="mt-5 flex flex-wrap gap-3 text-sm">
          <button
            type="button"
            class="text-n-brand hover:underline"
            :disabled="opening"
            @click="openChat"
          >
            {{
              opening
                ? t('SOOR_SALES_TASKS.OPENING_CHAT')
                : t('SOOR_SALES_TASKS.OPEN_CHAT')
            }}
          </button>
          <a
            :href="`https://crm.zoho.com/crm/org904697102/tab/Contacts/${selected.zoho_contact_id}`"
            target="_blank"
            rel="noopener noreferrer"
            class="text-n-brand hover:underline"
          >
            {{ t('SOOR_SALES_TASKS.OPEN_ZOHO') }}
          </a>
        </div>
        <h3 class="mt-8 text-base font-semibold text-n-slate-12">
          {{ t('SOOR_SALES_TASKS.DETAIL_TITLE') }}
        </h3>
        <p class="mt-1 text-sm text-n-slate-11">
          {{ t('SOOR_SALES_TASKS.DETAIL_HINT') }}
        </p>
        <form class="mt-5 grid gap-4" @submit.prevent="save">
          <label class="grid gap-1 text-sm text-n-slate-12">
            {{ t('SOOR_SALES_TASKS.TASK') }}
            <select
              v-model="form.task_type"
              class="rounded-lg border border-n-weak bg-n-background px-3 py-2"
            >
              <option
                v-for="type in taskTypes"
                :key="type"
                :value="type"
              >
                {{ typeLabel(type) }}
              </option>
            </select>
          </label>
          <label class="grid gap-1 text-sm text-n-slate-12">
            {{ t('SOOR_SALES_TASKS.STAGE') }}
            <select
              v-model="form.stage"
              class="rounded-lg border border-n-weak bg-n-background px-3 py-2"
            >
              <option
                v-for="stage in stages"
                :key="stage"
                :value="stage"
              >
                {{ stageLabel(stage) }}
              </option>
            </select>
          </label>
          <label class="grid gap-1 text-sm text-n-slate-12">
            {{ t('SOOR_SALES_TASKS.OWNER') }}
            <select
              v-model="form.assignee_id"
              class="rounded-lg border border-n-weak bg-n-background px-3 py-2"
            >
              <option value="">{{ t('SOOR_SALES_TASKS.UNASSIGNED') }}</option>
              <option v-for="agent in agents" :key="agent.id" :value="agent.id">
                {{ agent.name }}
              </option>
            </select>
          </label>
          <label class="grid gap-1 text-sm text-n-slate-12">
            {{ t('SOOR_SALES_TASKS.DUE') }}
            <input
              v-model="form.due_at"
              type="datetime-local"
              class="rounded-lg border border-n-weak bg-n-background px-3 py-2"
            />
          </label>
          <label class="grid gap-1 text-sm text-n-slate-12">
            {{ t('SOOR_SALES_TASKS.OUTCOME') }}
            <textarea
              v-model="form.outcome"
              rows="5"
              maxlength="3000"
              class="rounded-lg border border-n-weak bg-n-background px-3 py-2"
              :placeholder="t('SOOR_SALES_TASKS.OUTCOME_PLACEHOLDER')"
            />
          </label>
          <label class="grid gap-1 text-sm text-n-slate-12">
            {{ t('SOOR_SALES_TASKS.CALL_OUTCOME') }}
            <select
              v-model="form.call_outcome"
              class="rounded-lg border border-n-weak bg-n-background px-3 py-2"
              @change="form.call_outcome_detail = ''"
            >
              <option value="">{{ t('SOOR_SALES_TASKS.CALL_OUTCOME_PLACEHOLDER') }}</option>
              <option v-for="outcome in callOutcomes" :key="outcome" :value="outcome">
                {{ callOutcomeLabel(outcome) }}
              </option>
            </select>
          </label>
          <label v-if="form.call_outcome === 'other_company'" class="grid gap-1 text-sm text-n-slate-12">
            {{ t('SOOR_SALES_TASKS.INSURANCE_COMPANY') }}
            <input
              v-model="form.call_outcome_detail"
              list="soor-insurance-companies"
              required
              maxlength="180"
              class="rounded-lg border border-n-weak bg-n-background px-3 py-2"
              :placeholder="t('SOOR_SALES_TASKS.INSURANCE_COMPANY_PLACEHOLDER')"
            />
            <datalist id="soor-insurance-companies">
              <option v-for="company in insuranceCompanies" :key="company" :value="company" />
            </datalist>
            <span class="text-xs text-n-slate-10">{{ t('SOOR_SALES_TASKS.INSURANCE_COMPANY_HINT') }}</span>
          </label>
          <label v-if="form.call_outcome === 'other'" class="grid gap-1 text-sm text-n-slate-12">
            {{ t('SOOR_SALES_TASKS.OTHER_REASON') }}
            <input
              v-model="form.call_outcome_detail"
              required
              maxlength="180"
              class="rounded-lg border border-n-weak bg-n-background px-3 py-2"
              :placeholder="t('SOOR_SALES_TASKS.OTHER_REASON_PLACEHOLDER')"
            />
          </label>
          <label class="grid gap-1 text-sm text-n-slate-12">
            {{ t('SOOR_SALES_TASKS.LEAD_SOURCE') }}
            <select
              v-model="form.lead_source"
              class="rounded-lg border border-n-weak bg-n-background px-3 py-2"
            >
              <option value="">{{ t('SOOR_SALES_TASKS.SOURCE_PLACEHOLDER') }}</option>
              <option
                v-for="source in leadSources"
                :key="source"
                :value="source"
              >
                {{ t(`SOOR_SALES_TASKS.SOURCES.${source.toUpperCase()}`) }}
              </option>
            </select>
          </label>
          <button
            type="submit"
            :disabled="saving"
            class="rounded-lg bg-n-brand px-4 py-2.5 font-medium text-white disabled:opacity-50"
          >
            {{
              saving ? t('SOOR_SALES_TASKS.SAVING') : t('SOOR_SALES_TASKS.SAVE')
            }}
          </button>
        </form>
      </section>
    </div>
  </div>
</template>
