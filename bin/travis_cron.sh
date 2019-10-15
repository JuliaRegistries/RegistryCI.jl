#!/bin/bash

### Step 1: Make sure that you have curl installed
### Step 2: Install the Travis CLI client: https://github.com/travis-ci/travis.rb
### Step 3: travis login --com
### Step 4: export TRAVIS_TOKEN=$(travis token --com)
### Step 5: ./cron.sh

body='{
"request": {
"branch":"master"
}}'

curl -s -X POST \
   -H "Content-Type: application/json" \
   -H "Accept: application/json" \
   -H "Travis-API-Version: 3" \
   -H "Authorization: token $TRAVIS_TOKEN" \
   -d "$body" \
   https://api.travis-ci.com/repo/JuliaRegistries%2FGeneral/requests
