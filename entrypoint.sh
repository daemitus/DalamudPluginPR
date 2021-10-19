#!/usr/bin/env bash

set -euo pipefail

message=$(jq -r '.commits[-1].message' "${GITHUB_EVENT_PATH}")

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

# Setup artifact data
artifact="${INPUT_ARTIFACT_PATH}"
pluginName=$(jq -r '.Name' "${artifact}"/*.json)
internalName=$(jq -r '.InternalName' "${artifact}"/*.json)
assemblyVersion=$(jq -r '.AssemblyVersion' "${artifact}"/*.json)

# Setup git variables
owner="${INPUT_REPOSITORY/\/*/}"
repo="${INPUT_REPOSITORY}"
prRepo="${INPUT_PR_REPOSITORY}"
branch="${pluginName/ /}"
prBranch="${INPUT_PR_BRANCH}"
token="${INPUT_TOKEN}"

# Login to GitHub
echo "> Logging into GitHub"
echo "${token}" | gh auth login --with-token

echo "> Configuring git user"
authorName=$(jq -r '.commits[0].author.name' "${GITHUB_EVENT_PATH}")
authorEmail=$(jq -r '.commits[0].author.email' "${GITHUB_EVENT_PATH}")
git config --global user.name "${authorName}"
git config --global user.email "${authorEmail}"

# Setup plugin repo
echo "> Setting up ${repo}"
gh repo clone "${repo}" repo
cd repo
git remote add pr_repo "https://github.com/${prRepo}.git"
git fetch pr_repo
git fetch origin

# Fixup the remote url so it can be pushed to
echo "> Adding token to origin push url"
originUrl=$(git config --get remote.origin.url | cut -d '/' -f 3-)
originUrl="https://${token}@${originUrl}"
git config remote.origin.url "${originUrl}"

# The branch name is hardcoded to the plugin's name.
# If it already exists, hard reset to master.
if git show-ref --quiet "refs/heads/${branch}"; then
  echo "> Branch ${branch} already exists, reseting to master"
  git checkout "${branch}"
  git reset --hard "pr_repo/${prBranch}"
else
  echo "> Creating new branch ${branch}"
  git reset --hard "pr_repo/${prBranch}"
  git branch "${branch}"
  git checkout "${branch}"
  git push --set-upstream origin --force "${branch}"
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
git push --force --set-upstream origin "${branch}"

# The PR title is the friendly name and assembly version
prTitle="${pluginName} ${assemblyVersion}"
if "${testing}"; then
  prTitle="[Testing] ${prTitle}"
fi

# The PR body is the body of the last commit
prBody=$(echo "${message}" | tail -n +2)

prNumber=$(gh api repos/${prRepo}/pulls | jq ".[] | select(.head.ref == \"${branch}\") | .number")
if [ "${prNumber}" ]; then
  echo "> Editing existing PR"
  gh api "repos/${prRepo}/pulls/${prNumber}" --silent --method PATCH -f "title=${prTitle}" -f "body=${prBody}" -f "state=open"
else
  echo "> Creating PR"
  gh pr create --repo "${prRepo}" --head "${owner}:${branch}" --base "${prBranch}" --title "${prTitle}" --body "${prBody}"
fi

echo "> Done"
