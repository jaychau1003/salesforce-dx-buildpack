#!/usr/bin/env bash

START_TIME=$SECONDS

# set -x
set -o errexit      # always exit on error
set -o pipefail     # don't ignore exit codes when piping output
unset GIT_DIR       # Avoid GIT_DIR leak from previous build steps

TARGET_SCRATCH_ORG_ALIAS=${1:-}

vendorDir="vendor/sfdx"

source "$vendorDir"/common.sh
source "$vendorDir"/sfdx.sh
source "$vendorDir"/stdlib.sh

: ${SFDX_BUILDPACK_DEBUG:="false"}

header "Running release.sh"

# Setup local paths
log "Setting up paths ..."

setup_dirs "."

log "Config vars ..."
debug "DEV_HUB_SFDX_AUTH_URL: $DEV_HUB_SFDX_AUTH_URL"
debug "STAGE: $STAGE"
debug "SFDX_AUTH_URL: $SFDX_AUTH_URL"
debug "SFDX_BUILDPACK_DEBUG: $SFDX_BUILDPACK_DEBUG"
debug "CI: $CI"
debug "HEROKU_TEST_RUN_BRANCH: $HEROKU_TEST_RUN_BRANCH"
debug "HEROKU_TEST_RUN_COMMIT_VERSION: $HEROKU_TEST_RUN_COMMIT_VERSION"
debug "HEROKU_TEST_RUN_ID: $HEROKU_TEST_RUN_ID"
debug "STACK: $STACK"
debug "SOURCE_VERSION: $SOURCE_VERSION"
debug "TARGET_SCRATCH_ORG_ALIAS: $TARGET_SCRATCH_ORG_ALIAS"
debug "SFDX_INSTALL_PACKAGE_VERSION: $SFDX_INSTALL_PACKAGE_VERSION"
debug "SFDX_CREATE_PACKAGE_VERSION: $SFDX_CREATE_PACKAGE_VERSION"
debug "SFDX_PACKAGE_NAME: $SFDX_PACKAGE_NAME"

whoami=$(whoami)
debug "WHOAMI: $whoami"

log "Parse .salesforcex.yml values ..."

# Parse .salesforcedx.yml file into env
#BUG: not parsing arrays properly
eval $(parse_yaml .salesforcedx.yml)

debug "scratch-org-def: $scratch_org_def"
debug "assign-permset: $assign_permset"
debug "permset-name: $permset_name"
debug "run-apex-tests: $run_apex_tests"
debug "apex-test-format: $apex_test_format"
debug "delete-scratch-org: $delete_scratch_org"
debug "show_scratch_org_url: $show_scratch_org_url"
debug "open-path: $open_path"
debug "data-plans: $data_plans"

auth "$vendorDir/sfdxdevhuburl" "$DEV_HUB_SFDX_AUTH_URL" d huborg

# If review app or CI
if [ "$STAGE" == "" ]; then

  log "Running as a REVIEW APP ..."
  if [ ! "$CI" == "" ]; then
    log "Running via CI ..."
  fi

  # Get sfdx auth url for scratch org
  scratchSfdxAuthUrlFile=$vendorDir/$TARGET_SCRATCH_ORG_ALIAS
  scratchSfdxAuthUrl=`cat $scratchSfdxAuthUrlFile`

  debug "scratchSfdxAuthUrl: $scratchSfdxAuthUrl"

  # Auth to scratch org
  auth "$scratchSfdxAuthUrlFile" "" s "$TARGET_SCRATCH_ORG_ALIAS"

  # Push source
  invokeCmd "sfdx force:source:push -u $TARGET_SCRATCH_ORG_ALIAS"

  # Show scratch org URL
  if [ "$show_scratch_org_url" == "true" ]; then    
    if [ ! "$open_path" == "" ]; then
      invokeCmd "sfdx force:org:open -r -p $open_path"
    else
      invokeCmd "sfdx force:org:open -r"
    fi
  fi

fi

# If Development, Staging, or Prod
if [ ! "$STAGE" == "" ]; then

  log "Detected $STAGE. Kicking off deployment ..."

  auth "$vendorDir/sfdxurl" "$SFDX_AUTH_URL" s "$TARGET_SCRATCH_ORG_ALIAS"

  # create a package is specied a
  if [ "$SFDX_CREATE_PACKAGE_VERSION" == "true" ] && [ ! "$STAGE" == "" ];
  then

    # get package id
    CMD="sfdx force:package2:list --json | jq '.result[] | select((.Name) == \"$SFDX_PACKAGE_NAME\")' | jq -r .Id"
    debug "CMD: $CMD"
    SFDX_PACKAGE_ID=$($CMD)
    debug "SFDX_PACKAGE_ID: $SFDX_PACKAGE_ID"

    # create package version
    CMD="sfdx force:package2:version:create -i $SFDX_PACKAGE_ID --wait 100 --json | jq -r .result.Id"
    SFDX_PACKAGE_VERSION_ID=$($CMD)
    debug "SFDX_PACKAGE_VERSION_ID: $SFDX_PACKAGE_VERSION_ID"

  fi

  if [ "$SFDX_INSTALL_PACKAGE_VERSION" == "true" ] 
  then

    log "Install package $SFDX_PACKAGE_NAME"

  else

    log "Source convert and mdapi deploy"

    # run mdapi-deploy script
    if [ ! -f "bin/mdapi-deploy.sh" ];
    then

      invokeCmd "sfdx force:source:convert -d mdapiout"
      invokeCmd "sfdx force:mdapi:deploy -d mdapiout --wait 1000 -u $TARGET_SCRATCH_ORG_ALIAS"

    else

      log "Calling bin/mdapi-deploy.sh"
      sh "bin/mdapi-deploy.sh" "$TARGET_SCRATCH_ORG_ALIAS" "$STAGE"

    fi

  fi

fi

# run post-setup script
if [ -f "bin/post-setup.sh" ]; then

  debug "Calling bin/post-setup.sh $TARGET_SCRATCH_ORG_ALIAS $STAGE"
  sh "bin/post-setup.sh" "$TARGET_SCRATCH_ORG_ALIAS" "$STAGE"
fi

header "DONE! Completed in $(($SECONDS - $START_TIME))s"
exit 0