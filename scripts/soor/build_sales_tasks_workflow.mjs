import assert from 'node:assert/strict';
import fs from 'node:fs';

const [sourcePath, outputPath] = process.argv.slice(2);
assert(sourcePath && outputPath, 'Usage: node build_sales_tasks_workflow.mjs existing-workflow.json output.json');
const source = JSON.parse(fs.readFileSync(sourcePath, 'utf8'));
const clone = name => {
  const node = source.nodes.find(item => item.name === name);
  assert(node, `Missing existing node: ${name}`);
  return structuredClone(node);
};
const edge = node => ({ node, type: 'main', index: 0 });
const code = (name, jsCode, x) => ({
  id: `soor-sales-${name.toLowerCase().replace(/[^a-z0-9]+/g, '-')}`,
  name,
  type: 'n8n-nodes-base.code',
  typeVersion: 2,
  position: [x, 0],
  parameters: { mode: 'runOnceForAllItems', jsCode },
});
const schedule = {
  id: 'soor-sales-schedule', name: 'Every fifteen minutes', type: 'n8n-nodes-base.scheduleTrigger',
  typeVersion: 1.2, position: [0, 0],
  parameters: { rule: { interval: [{ field: 'minutes', minutesInterval: 15 }] } },
};

const contacts = clone('Read fresh contact batches');
contacts.id = 'soor-sales-read-contacts';
contacts.name = 'Read recent registered contacts';
contacts.position = [280, 0];
contacts.parameters.url = 'https://www.zohoapis.com/crm/v8/Contacts';
contacts.parameters.jsonQuery = JSON.stringify({
  fields: 'id,First_Name,Last_Name,Mobile,Phone,Email,External_User_ID,Created_Time',
  per_page: 100, page: 1, sort_by: 'Created_Time', sort_order: 'desc',
});
delete contacts.parameters.options.batching;

const prepare = code('Prepare registered contacts', `
const response=$input.first()?.json;
if(response?.statusCode!==200||!Array.isArray(response.body?.data)||response.body.data.length>100)throw Error('INVALID_CONTACT_RESPONSE');
function phone(value){let s=String(value??'').trim().replace(/[\\s().-]/g,'').replace(/^00/,'+');if(/^\\d{8}$/.test(s))s='+973'+s;else if(/^973\\d{8}$/.test(s))s='+'+s;else if(/^\\d{9,15}$/.test(s))s='+'+s;return /^\\+[1-9]\\d{7,14}$/.test(s)?s:null;}
const seen=new Set(),out=[];
for(const r of response.body.data){
  if(!r||typeof r!=='object'||!/^\\d{1,30}$/.test(String(r.id)))throw Error('INVALID_ZOHO_CONTACT');
  if(!r.External_User_ID)continue;
  if(seen.has(r.id))throw Error('DUPLICATE_ZOHO_CONTACT');seen.add(r.id);
  const number=phone(r.Mobile)||phone(r.Phone);
  const candidateEmail=typeof r.Email==='string'?r.Email.trim().toLowerCase():'';
  const email=/^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$/.test(candidateEmail)&&candidateEmail.length<=254&&!candidateEmail.endsWith('@temp.soor.com')?candidateEmail:null;
  const first=String(r.First_Name||'').trim(),last=String(r.Last_Name||'').trim();
  const placeholder=first.toLowerCase()==='user'&&/^\\+?\\d{8,15}$/.test(last);
  const fullName=placeholder?'':[first,last].filter(Boolean).join(' ');
  const name=fullName&&fullName.toLowerCase()!=='user'?fullName:(number||email||'SOOR customer');
  out.push({json:{contact:{zoho_contact_id:String(r.id),customer_name:name.slice(0,180),phone_number:number,email,registered_at:r.Created_Time||null},path:'/Contacts/'+r.id+'/vehicleuser1',query:{page:1,per_page:200}}});
}
return out;
`, 560);

const vehicles = clone('Read related vehicles');
vehicles.id = 'soor-sales-read-vehicles';
vehicles.name = 'Read registered contact vehicles';
vehicles.position = [840, 0];
vehicles.parameters.jsonQuery = '={{ JSON.stringify({...$json.query, fields: "id,Created_Time,make,model,year,plateNumber,registrationExpiryDate,registrationStatus,vehicleuser"}) }}';

const batches = code('Build task batches', `
const inputs=$('Prepare registered contacts').all().map(i=>i.json),results=$input.all().map(i=>i.json);
if(inputs.length!==results.length)throw Error('VEHICLE_RESPONSE_ALIGNMENT');
const tasks=[];
for(let i=0;i<inputs.length;i++){
  const response=results[i];
  if(![200,204].includes(response.statusCode))throw Error('VEHICLE_READ_FAILED');
  const data=response.statusCode===204?[]:response.body?.data;
  if(!Array.isArray(data)||data.length>200||response.body?.info?.more_records===true)throw Error('VEHICLE_RESPONSE_INVALID');
  const contact=inputs[i].contact;
  const candidates=data.map(v=>({make:v.make||null,model:v.model||null,year:v.year||null,plate:v.plateNumber||null,searched_at:v.Created_Time||null,registration_expiry:v.registrationExpiryDate||null,registration_status:v.registrationStatus||null}));
  const now=Date.now(),distance=v=>{const t=Date.parse(v.registration_expiry);return Number.isFinite(t)?Math.abs(t-now):Number.POSITIVE_INFINITY;};
  candidates.sort((a,b)=>distance(a)-distance(b));
  tasks.push({...contact,vehicle:candidates[0]||{}});
}
const out=[];for(let i=0;i<tasks.length;i+=100)out.push({json:{body:{contacts:tasks.slice(i,i+100)},expected:tasks.slice(i,i+100).length}});
return out;
`, 1120);

const sync = clone('Add selected vehicle tag');
sync.id = 'soor-sales-sync';
sync.name = 'Sync sales tasks into Chatwoot';
sync.position = [1400, 0];
sync.parameters.url = 'https://chatwoot-chatwoot.0zriwl.easypanel.host/api/v1/accounts/1/soor_sales_tasks/sync';
sync.parameters.options.response.response.responseFormat = 'json';

const verify = code('Verify task sync', `
const batches=$('Build task batches').all().map(i=>i.json),responses=$input.all().map(i=>i.json);
if(batches.length!==responses.length)throw Error('SYNC_RESPONSE_ALIGNMENT');
let synced=0;for(let i=0;i<batches.length;i++){
  const r=responses[i];if(r.statusCode!==200||r.body?.synced!==batches[i].expected)throw Error('SALES_SYNC_FAILED');
  synced+=r.body.synced;
}
return[{json:{synced,status:'verified'}}];
`, 1680);

const nodes = [schedule, contacts, prepare, vehicles, batches, sync, verify];
const connections = Object.fromEntries(nodes.slice(0, -1).map((node, index) => [
  node.name, { main: [[edge(nodes[index + 1].name)]] },
]));
const workflow = {
  name: 'SOOR — registered customer sales tasks', active: false, nodes, connections,
  settings: { executionOrder: 'v1', timezone: 'Asia/Bahrain', saveDataErrorExecution: 'none',
    saveDataSuccessExecution: 'none', saveManualExecutions: false, executionTimeout: 180 }, pinData: {},
};
fs.writeFileSync(outputPath, JSON.stringify(workflow, null, 2));
console.log(`Built inactive workflow with ${nodes.length} nodes`);
