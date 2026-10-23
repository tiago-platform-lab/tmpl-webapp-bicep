using './main.bicep'

param appName = readEnvironmentVariable('APP_NAME')
param env = 'prod'
param platformResourceGroup = readEnvironmentVariable('PLATFORM_RG')
param containerAppsEnvironmentName = readEnvironmentVariable('CAE_NAME')
param registryLoginServer = readEnvironmentVariable('ACR_LOGIN_SERVER')
param identityResourceGroup = readEnvironmentVariable('IDENTITY_RG')
param imageTag = readEnvironmentVariable('IMAGE_TAG', 'latest')

param tags = {
  dept: readEnvironmentVariable('TAG_DEPT', 'TODO')
  project: readEnvironmentVariable('APP_NAME')
  env: 'prod'
  owner: readEnvironmentVariable('TAG_OWNER', 'TODO')
  'cost-centre': readEnvironmentVariable('TAG_COST_CENTRE', 'TODO')
}

// Prod: one warm replica, no cold start for the first user.
param cpu = '1.0'
param memory = '2Gi'
param minReplicas = 1
param maxReplicas = 3

param enableStorage = false
param enableWorker = false
param enablePostgres = false
