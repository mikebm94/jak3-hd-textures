using namespace System.Collections.Generic
using namespace System.IO

# Options configuring which textures get upscaled and which workflows to use.
class UpscaleOptions {
	# The upscale workflow to use on textures unless otherwise specified.
	[string] $DefaultWorkflow

	# Maps texture names to their respective upscale workflow names.
	# Value is null/empty if the texture is excluded from upscaling.
	[Dictionary[string, string]] $TextureWorkflowMap

	UpscaleOptions([string] $json) {
		$raw_options = $json | ConvertFrom-Json

		$this.DefaultWorkflow = $raw_options.DefaultWorkflow
		if (-not [string]::IsNullOrEmpty($this.DefaultWorkflow) -and -not (IsValidFilename $this.DefaultWorkflow)) {
			throw 'DefaultWorkflow must not be whitespace or contain invalid filename characters.'
		}

		$this.TextureWorkflowMap = [Dictionary[string, string]]::new()

		foreach ($group in $raw_options.TextureGroups) {
			if (-not [string]::IsNullOrEmpty($group.Workflow) -and -not (IsValidFilename $group.Workflow)) {
				throw "Texture group '$($group.Name)': 'Workflow' must not be whitespace or contain invalid filename characters."
			}

			foreach ($texture_name in $group.TextureNames) {
				$this.TextureWorkflowMap[$texture_name] = $group.Workflow
			}
		}
	}
}


<#
.SYNOPSIS
Reads the options configuring what textures get upscaled and which workflows to use.
#>
function Read-UpscaleOptions {
	[CmdletBinding()]
	[OutputType([UpscaleOptions])]
	param()

	Write-Host 'Reading upscale options ...'
	$upscale_options_path = Join-Path $ProjectDir 'upscale-options.json'
	[UpscaleOptions]::new([File]::ReadAllText($upscale_options_path))
}
