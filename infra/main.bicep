// One app, one environment. Deployed into rg-<app>-<env>, which the vending
// workflow created. The vending workflow also created, in rg-<app>-identities:
//   id-<app>-<env>-deploy   the pipeline runs as this one (not referenced here)
//   id-<app>-<env>-runtime  the app runs as this one
// and already granted the runtime identity everything it needs: AcrPull on the
// registry, and Key Vault Secrets User plus storage data roles on this resource
// group. So this file creates resources but no role assignments; the deploy
// identity is Contributor only and could not create them anyway.
//
// Ownership: this file owns every property of the app except the image tag,
// which the deploy workflow passes in. No other pipeline step may set sizing,
// scale or env vars with `az containerapp update`, or the two will fight.
//
// Shared resources (Container Apps environment, registry) live in the platform
// layer and are only referenced here.

targetScope = 'resourceGroup'

@description('App name, lowercase letters, digits and hyphens. Matches the repo.')
@minLength(3)
@maxLength(16)
param appName string

@allowed(['dev', 'prod'])
param env string

param location string = resourceGroup().location
param tags object

// ---- platform layer (set by the vending workflow as GitHub variables) ----
param platformResourceGroup string
param containerAppsEnvironmentName string
param registryLoginServer string
@description('rg-<app>-identities, where the vending workflow put the identities.')
param identityResourceGroup string

@description('Image tag to run. The deploy workflow passes the commit SHA.')
param imageTag string

// ---- sizing (per environment, in the .bicepparam files) ----
param cpu string = '0.5'
param memory string = '1Gi'
param minReplicas int = 0
param maxReplicas int = 3
param targetPort int = 8080

// ---- optional pieces ----
@description('Queue + blob storage for async work.')
param enableStorage bool = false
@description('A second Container App, same image, no ingress, for queue work.')
param enableWorker bool = false
@description('Worker command, e.g. ["python", "-m", "app.worker"].')
param workerCommand array = []
@description('Postgres Flexible Server, Entra-only auth.')
param enablePostgres bool = false
@description('Entra group that administers Postgres. Required when enablePostgres is true.')
param postgresAdminGroupName string = ''
param postgresAdminGroupObjectId string = ''

var image = '${registryLoginServer}/${appName}:${imageTag}'
// Key Vault and storage names are global and short: kv max 24, storage max 24 alnum.
var kvName = take('kv-${appName}-${env}', 24)
var storageName = take(toLower(replace('st${appName}${env}', '-', '')), 24)

resource cae 'Microsoft.App/managedEnvironments@2024-03-01' existing = {
  name: containerAppsEnvironmentName
  scope: resourceGroup(platformResourceGroup)
}

resource runtimeIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: 'id-${appName}-${env}-runtime'
  scope: resourceGroup(identityResourceGroup)
}

// ---------------- Key Vault: app secrets live here, never in the app ----------------
resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: kvName
  location: location
  tags: tags
  properties: {
    sku: { family: 'A', name: 'standard' }
    tenantId: tenant().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: env == 'prod' ? true : null
  }
}

// ---------------- Storage (optional) ----------------
resource st 'Microsoft.Storage/storageAccounts@2023-05-01' = if (enableStorage) {
  #disable-next-line BCP334 // 'st' + appName (min 3) + env is always at least 8 chars
  name: storageName
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false // identity only
    supportsHttpsTrafficOnly: true
  }
}

resource queueService 'Microsoft.Storage/storageAccounts/queueServices@2023-05-01' = if (enableStorage) {
  parent: st
  name: 'default'
}

resource jobsQueue 'Microsoft.Storage/storageAccounts/queueServices/queues@2023-05-01' = if (enableStorage) {
  parent: queueService
  name: 'jobs'
}

// ---------------- Postgres (optional, Entra-only) ----------------
resource pg 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = if (enablePostgres) {
  name: 'psql-${appName}-${env}'
  location: location
  tags: tags
  sku: { name: 'Standard_B1ms', tier: 'Burstable' }
  properties: {
    version: '16'
    storage: { storageSizeGB: 32, autoGrow: 'Enabled' }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: env == 'prod' ? 'Enabled' : 'Disabled'
    }
    highAvailability: { mode: 'Disabled' }
    authConfig: {
      activeDirectoryAuth: 'Enabled'
      passwordAuth: 'Disabled'
      tenantId: tenant().tenantId
    }
    // TODO(phase 0): firewall rules or private endpoint. Nothing can connect yet.
  }
}

resource pgDb 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2024-08-01' = if (enablePostgres) {
  parent: pg
  name: replace(appName, '-', '_')
  properties: { charset: 'UTF8', collation: 'en_US.utf8' }
}

resource pgAdmin 'Microsoft.DBforPostgreSQL/flexibleServers/administrators@2024-08-01' = if (enablePostgres && !empty(postgresAdminGroupObjectId)) {
  parent: pg
  name: postgresAdminGroupObjectId
  properties: {
    principalType: 'Group'
    principalName: postgresAdminGroupName
    tenantId: tenant().tenantId
  }
}
// The runtime identity still needs a database role. That is SQL, not ARM:
// a migration or one-off script runs `pgaadauth_create_principal(...)` as the admin.

// ---------------- the app ----------------
var commonEnv = concat(
  [
    { name: 'AZURE_CLIENT_ID', value: runtimeIdentity.properties.clientId }
    { name: 'APP_ENV', value: env }
    { name: 'KEY_VAULT_URI', value: kv.properties.vaultUri }
  ],
  enableStorage ? [
    { name: 'STORAGE_ACCOUNT', value: storageName }
    { name: 'JOBS_QUEUE', value: 'jobs' }
  ] : [],
  enablePostgres ? [
    { name: 'PGHOST', value: pg!.properties.fullyQualifiedDomainName }
    { name: 'PGDATABASE', value: replace(appName, '-', '_') }
    { name: 'PGUSER', value: runtimeIdentity.name }
  ] : []
)

var identityBlock = {
  type: 'UserAssigned'
  userAssignedIdentities: { '${runtimeIdentity.id}': {} }
}

var registries = [
  { server: registryLoginServer, identity: runtimeIdentity.id }
]

resource web 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'ca-${appName}-${env}'
  location: location
  tags: tags
  identity: identityBlock
  properties: {
    environmentId: cae.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: targetPort
        transport: 'auto'
        allowInsecure: false
      }
      registries: registries
      // TODO(phase 0): Easy Auth (authConfigs) needs an Entra app registration,
      // which Bicep here does not create. See the root README.
    }
    template: {
      containers: [
        {
          name: 'web'
          image: image
          resources: { cpu: json(cpu), memory: memory }
          env: commonEnv
          probes: [
            {
              type: 'Liveness'
              httpGet: { path: '/', port: targetPort }
              periodSeconds: 30
            }
          ]
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        rules: [
          { name: 'http', http: { metadata: { concurrentRequests: '20' } } }
        ]
      }
    }
  }
}

resource worker 'Microsoft.App/containerApps@2024-03-01' = if (enableWorker) {
  name: 'ca-${appName}-worker-${env}'
  location: location
  tags: tags
  identity: identityBlock
  properties: {
    environmentId: cae.id
    configuration: {
      activeRevisionsMode: 'Single'
      registries: registries
    }
    template: {
      containers: [
        {
          name: 'worker'
          image: image
          command: workerCommand
          resources: { cpu: json(cpu), memory: memory }
          env: commonEnv
        }
      ]
      // TODO: scale on queue depth (KEDA azure-queue with the runtime identity)
      // once the API version that supports identity-based scale rules is agreed.
      scale: { minReplicas: 1, maxReplicas: 1 }
    }
  }
}

output url string = 'https://${web.properties.configuration.ingress.fqdn}'
