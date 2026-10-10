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
});
let searchTimer;

const apiUrl = computed(
  () => `/api/v1/accounts/${accountId.value}/soor_sales_tasks`
);
const stageLabel = stage => t(`SOOR_SALES_TASKS.STAGE_LABELS.${stage}`);
const typeLabel = type => t(`SOOR_SALES_TASKS.TYPE_LABELS.${type}`);
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
const formatDate = value =>
  value
    ? new Intl.DateTimeFormat(undefined, {
        day: 'numeric',
        month: 'short',
        year: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
      }).format(new Date(value))
    : '';
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

async function load(page = 1) {
  loading.value = true;
  try {
    const params = { page, q: query.value.trim() || undefined };
    if (view.value === 'mine') params.mine = true;
    if (view.value === 'unassigned_filter') params.unassigned = true;
    if (view.value === 'overdue') params.overdue = true;
    if (view.value === 'new') params.stage = 'new';
    const { data } = await window.axios.get(apiUrl.value, { params });
    tasks.value = data.tasks;
    meta.value = data.meta;
    counts.value = data.counts;
  } catch {
    useAlert(t('SOOR_SALES_TASKS.LOAD_FAILED'));
  } finally {
    loading.value = false;
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

watch(view, () => load());
watch(query, () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(() => load(), 300);
});
onMounted(() => {
  store.dispatch('agents/get');
  load();
});
</script>

<template>
  <div class="flex h-full min-w-0 flex-col bg-n-background">
    <header class="border-b border-n-weak bg-n-solid-1 px-6 py-5">
      <div class="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 class="text-2xl font-semibold text-n-slate-12">
            {{ t('SOOR_SALES_TASKS.TITLE') }}
          </h1>
          <p class="mt-1 text-sm text-n-slate-11">
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
      <div class="mt-5 grid max-w-3xl grid-cols-3 gap-3">
        <div class="rounded-xl border border-n-weak bg-n-background px-4 py-3">
          <div class="text-xs text-n-slate-11">
            {{ t('SOOR_SALES_TASKS.IN_PROGRESS') }}
          </div>
          <div class="mt-1 text-2xl font-semibold text-n-slate-12">
            {{ openCount }}
          </div>
        </div>
        <div class="rounded-xl border border-n-weak bg-n-background px-4 py-3">
          <div class="text-xs text-n-slate-11">
            {{ t('SOOR_SALES_TASKS.NEW') }}
          </div>
          <div class="mt-1 text-2xl font-semibold text-n-slate-12">
            {{ counts.new || 0 }}
          </div>
        </div>
        <div class="rounded-xl border border-n-weak bg-n-background px-4 py-3">
          <div class="text-xs text-n-slate-11">
            {{ t('SOOR_SALES_TASKS.WON') }}
          </div>
          <div class="mt-1 text-2xl font-semibold text-n-slate-12">
            {{ counts.won || 0 }}
          </div>
        </div>
      </div>
    </header>

    <div
      class="flex flex-wrap items-center gap-2 border-b border-n-weak px-6 py-3"
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
        @click="view = filter"
      >
        {{ t(`SOOR_SALES_TASKS.${filter.toUpperCase()}`) }}
      </button>
      <input
        v-model="query"
        type="search"
        class="ml-auto min-w-48 rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12"
        :placeholder="t('SOOR_SALES_TASKS.SEARCH')"
        :aria-label="t('SOOR_SALES_TASKS.SEARCH')"
      />
    </div>

    <div class="min-h-0 flex-1 overflow-auto">
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
          v-if="!meta.total && view === 'all'"
          class="mt-2 text-sm text-n-slate-11"
        >
          {{ t('SOOR_SALES_TASKS.EMPTY_SOURCE') }}
        </p>
      </div>
      <table v-else class="w-full min-w-[850px] text-left text-sm">
        <thead
          class="sticky top-0 z-10 bg-n-solid-2 text-xs uppercase tracking-wide text-n-slate-10"
        >
          <tr>
            <th class="px-6 py-3 font-medium">
              {{ t('SOOR_SALES_TASKS.CUSTOMER') }}
            </th>
            <th class="px-4 py-3 font-medium">
              {{ t('SOOR_SALES_TASKS.CAR') }}
            </th>
            <th class="px-4 py-3 font-medium">
              {{ t('SOOR_SALES_TASKS.TASK') }}
            </th>
            <th class="px-4 py-3 font-medium">
              {{ t('SOOR_SALES_TASKS.STAGE') }}
            </th>
            <th class="px-4 py-3 font-medium">
              {{ t('SOOR_SALES_TASKS.OWNER') }}
            </th>
            <th class="px-4 py-3 font-medium">
              {{ t('SOOR_SALES_TASKS.DUE') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="task in tasks"
            :key="task.id"
            class="border-b border-n-weak hover:bg-n-alpha-1"
          >
            <td class="px-6 py-4">
              <button
                type="button"
                class="font-medium text-n-slate-12 hover:underline"
                @click="open(task)"
              >
                {{ task.customer_name }}
              </button>
              <div class="mt-1 text-xs text-n-slate-10">
                {{ task.phone_number || task.email }}
              </div>
            </td>
            <td class="px-4 py-4 text-n-slate-12">
              {{ carLabel(task) }}
              <div
                v-if="task.vehicle?.plate || expiryLabel(task)"
                class="mt-1 text-xs text-n-slate-10"
              >
                {{ task.vehicle?.plate }}
                <span v-if="task.vehicle?.plate && expiryLabel(task)">·</span>
                {{ expiryLabel(task) }}
              </div>
            </td>
            <td class="px-4 py-4 text-n-slate-12">
              {{ typeLabel(task.task_type) }}
            </td>
            <td class="px-4 py-4">
              <span
                class="rounded-full bg-n-alpha-2 px-2.5 py-1 text-xs text-n-slate-12"
              >
                {{ stageLabel(task.stage) }}
              </span>
            </td>
            <td class="px-4 py-4 text-n-slate-11">
              {{ task.assignee?.name || t('SOOR_SALES_TASKS.UNASSIGNED') }}
            </td>
            <td
              class="px-4 py-4"
              :class="
                isOverdue(task)
                  ? 'font-semibold text-n-ruby-9'
                  : 'text-n-slate-11'
              "
            >
              {{
                task.due_at
                  ? formatDate(task.due_at)
                  : t('SOOR_SALES_TASKS.NO_DUE')
              }}
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
                v-for="type in [
                  'welcome_call',
                  'follow_up',
                  'documents',
                  'quote',
                  'renewal',
                  'other',
                ]"
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
                v-for="stage in [
                  'new',
                  'attempted',
                  'contacted',
                  'follow_up',
                  'quote_sent',
                  'won',
                  'lost',
                ]"
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
