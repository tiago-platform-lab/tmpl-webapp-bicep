using './main.bicep'

// Values that identify the project and the platform come from GitHub variables
// set by the vending workflow, so a freshly vended repo deploys with no edits.
param appName = readEnvironmentVariable('APP_NAME')
param env = 'dev'
param platformResourceGroup = readEnvironmentVariable('PLATFORM_RG')
param containerAppsEnvironmentName = readEnvironmentVariable('CAE_NAME')
param registryLoginServer = readEnvironmentVariable('ACR_LOGIN_SERVER')
param identityResourceGroup = readEnvironmentVariable('IDENTITY_RG')
param imageTag = readEnvironmentVariable('IMAGE_TAG', 'latest')

param tags = {
  dept: readEnvironmentVariable('TAG_DEPT', 'TODO')
  project: readEnvironmentVariable('APP_NAME')
  env: 'dev'
  owner: readEnvironmentVariable('TAG_OWNER', 'TODO')
  'cost-centre': readEnvironmentVariable('TAG_COST_CENTRE', 'TODO')
}

// Dev: scale to zero, small.
param cpu = '0.5'
param memory = '1Gi'
param minReplicas = 0
param maxReplicas = 2

param enableStorage = false
param enableWorker = false
param enablePostgres = false
