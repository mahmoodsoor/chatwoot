import { frontendURL } from '../../../helper/URLHelper';
import SalesTasksIndex from './SalesTasksIndex.vue';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/sales-tasks'),
    name: 'soor_sales_tasks_index',
    component: SalesTasksIndex,
    meta: { permissions: ['administrator', 'agent', 'custom_role'] },
  },
];
