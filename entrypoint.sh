#!/usr/bin/env sh

set -euo pipefail

message=$(jq -r '.commits[0].message' "${GITHUB_EVENT_PATH}")

echo "> message=${message}"

# Check if enabled is true/false/substring
echo "> enabled_flag=${INPUT_ENABLED}"
if [ "${INPUT_ENABLED}" = true ]; then
  echo "> Action enabled: true"
  enabled=true
elif [ "${INPUT_ENABLED}" = false ]; then
  echo "> Action disabled: false"
  enabled=false
elif echo "${message}" | grep -qF "${INPUT_ENABLED}"; then
  echo "> Action enabled: substring match"
  enabled=true
else
  echo "> Action disabled: substring failed"
  enabled=false
fi

# Exit if disabled
if ! "${enabled}"; then
  echo "> Exiting"
  exit 0
fi

# Check if testing is true/false/substring
echo "> testing_flag=${INPUT_TESTING}"
if [ "${INPUT_TESTING}" = true ]; then
  echo "> Testing enabled: true"
  testing=true
elif [ "${INPUT_TESTING}" = false ]; then
  echo "> Testing disabled: false"
  testing=false
elif echo "${message}" | grep -qF "${INPUT_TESTING}"; then
  echo "> Testing enabled: substring match"
  testing=true
else
  echo "> Testing disabled: substring failed"
  testing=false
fi

# Login to GitHub
echo "> Logging into GitHub"
echo "${INPUT_TOKEN}" | gh auth login --with-token

# Setup artifact data
artifact="${INPUT_ARTIFACT_PATH}"
pluginName=$(jq -r '.Name' "${artifact}"/*.json)
internalName=$(jq -r '.InternalName' "${artifact}"/*.json)
assemblyVersion=$(jq -r '.AssemblyVersion' "${artifact}"/*.json)

echo "> Configuring git user"
authorName=$(jq -r '.commits[0].author.name' "${GITHUB_EVENT_PATH}")
authorEmail=$(jq -r '.commits[0].author.email' "${GITHUB_EVENT_PATH}")
git config --global user.name "${authorName}"
git config --global user.email "${authorEmail}"

# Setup plugin repo
echo "> Setting up ${INPUT_REPOSITORY}"
gh repo clone "${INPUT_REPOSITORY}" repo
cd repo
git remote add pr_repo "https://github.com/${INPUT_PR_REPOSITORY}.git"
git fetch pr_repo
git fetch origin

# Fixup the remote url so it can be pushed to
echo "> Adding token to origin push url"
originUrl=$(git config --get remote.origin.url | cut -d '/' -f 3-)
originUrl="https://${INPUT_TOKEN}@${originUrl}"
git config remote.origin.url "${originUrl}"

# The branch name is hardcoded to the plugin's name.
# If it already exists, hard reset to master.
if git show-ref --quiet "refs/heads/${pluginName}"; then
  echo "> Branch ${pluginName} already exists, reseting to master"
  git checkout "${pluginName}"
  git reset --hard pr_repo/master
else
  echo "> Creating new branch ${pluginName}"
  git reset --hard pr_repo/master
  git branch "${pluginName}"
  git checkout "${pluginName}"
  git push --set-upstream origin --force "${pluginName}"
fi

# Copy the artifact where it needs to go
cd ..

if [ -d "repo/testing/${internalName}" ]; then
  echo "> Deleting testing plugin directory"
  rm -rf "repo/testing/${internalName}"
else
  echo "> Testing plugin directory not present"
fi

if "${testing}"; then
  echo "> Moving artifact to testing"
  mv "${artifact}" "repo/testing/${internalName}"
else
  if [ -d "repo/plugins/${internalName}" ]; then
    echo "> Deleting plugin directory"
    rm -rf "repo/plugins/${internalName}"
  else
    echo "> Plugin directory not present"
  fi

  echo "> Moving artifact to plugins"
  mv "${artifact}" "repo/plugins/${internalName}"
fi
cd repo

# Add and commit
echo "> Adding and committing"
git add --all
git commit --all -m "Update ${pluginName} ${assemblyVersion}"

echo "> Pushing to origin"
git push --force --quiet origin

prRepo="${INPUT_PR_REPOSITORY}"

# The PR title is the friendly name and assembly version
prTitle="${pluginName} ${assemblyVersion}"
if "${testing}"; then
  prTitle="[Testing] ${prTitle}"
fi

# The PR body is the body of the last commit
prBody=$(echo "${message}" | tail -n +2)

prNumber=$(gh api repos/${prRepo}/pulls | jq ".[] | select(.head.ref == \"${pluginName}\") | .number")
if [ "${prNumber}" ]; then
  echo "> Editing existing PR"
  gh api "repos/${prRepo}/pulls/${prNumber}" --silent --method PATCH -f "title=${prTitle}" -f "body=${prBody}" -f "state=open"
else
  echo "> Creating PR"
  gh pr create --repo "${prRepo}" --title "${prTitle}" --body "${prBody}"
fi

echo "> Done"
