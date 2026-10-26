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

// Prod: scales to zero when idle (no fixed cost); the first request after a
// quiet period waits a few seconds. Set minReplicas = 1 to keep one warm replica.
param cpu = '1.0'
param memory = '2Gi'
param minReplicas = 0
param maxReplicas = 3

param enableStorage = false
param enableWorker = false
param enablePostgres = false
