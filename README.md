# DalamudPluginPR

This action checks-out your fork of `goatcorp/DalamudPlugins` commits the build artifact and creates a PR for the Dalamud moderation team to review. It runs in a Docker container so your choice of runner is not affected.

Your artifact should contain the JSON plugin manifest and latest.zip. If you are unfamiliar with how to create these files, look into using [DalamudPackager](https://github.com/goatcorp/DalamudPackager) in your existing build process.

The PR branch is the name of your plugin, as contained in the manifest "Name" field. If you would like to PR to testing, make sure to either enable the testing field or add the required string to your commit message. 

For the PR itself, the title is the plugin name combined with the assembly version from the manifest. The body is the body of the last commit.

# Usage
```yaml
jobs:
  build:
    steps:
    ...
    - uses: actions/upload-artifact@v2
      with:
        name: PluginRepoZip
        path: Path/To/Your/Output
        if-no-files-found: error
    ...

  pull_request:
    needs: build
    runs-on: ubuntu-latest
    steps:
    - name: Download artifact
      uses: actions/download-artifact@v2
      id: download-artifact
      with:
        # This should be the same name as used in upload-artifact        
        name: PluginRepoZip
        # Pick any directory name, so long as the artifact is by itself         
        path: PluginArtifact  
    
    - name: Create pull request
      uses: daemitus/DalamudPluginPR@v1
      with: 
        # ===== Required inputs =====
        # Personal access token to authenticate with GitHub.
        # Your access token should be stored in a repository secret
        token: ${{ secrets.PAT }}

        # Path of the (downloaded) artifact, created via DalamudPacker or manually.
        artifact_path: ${{ steps.download-artifact.outputs.download-path }}
        
        # ===== Optional inputs =====
        # Enable or disable the entire action. 
        # This can be true/false or a partial string searched for within the commit message.
        # Default: "[PR]"
        # enabled: 
        
        # If the artifact should be commited to testing instead of plugins. 
        # This can be true/false or a partial string searched for within the commit message.
        # Default: "[TEST]"
        # testing:
        
        # Repository where your artifact will be committed.
        # Default: ${{ github.repository_owner }}/DalamudPlugins
        # repository:

        # Repository where the PR will be created.
        # Default: goatcorp/DalamudPlugins
        # pr_repository:
```
