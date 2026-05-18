using namespace System.Collections.Generic
using namespace System.IO

# Options configuring which textures get upscaled and which models to use.
class UpscaleOptions {
	# The upscale model to use on textures unless otherwise specified.
	[string] $DefaultModel

	# Maps texture names to their respective upscale models.
	# Special values:
	#	'none' - Texture will not be copied and upscaled.
	#	'manual' - Texture will be copied, but will be upscaled by hand.
	[Dictionary[string, string]] $TextureModels

	UpscaleOptions([string] $Json) {
		$raw_options = $Json | ConvertFrom-Json

		$this.DefaultModel = $raw_options.DefaultModel
		if (-not (IsValidFilename $this.DefaultModel)) {
			throw 'DefaultModel must not be empty or contain invalid filename characters.'
		}

		$this.TextureModels = [Dictionary[string, string]]::new()

		foreach ($group in $raw_options.TextureGroups) {
			if (-not (IsValidFilename $group.Model)) {
				throw "Texture group '$($group.Name)': 'Model' must not be empty or contain invalid filename characters."
			}

			foreach ($texture_name in $group.TextureNames) {
				$this.TextureModels[$texture_name] = $group.Model
			}
		}
	}
}


<#
.SYNOPSIS
Reads the options configuring what textures get upscaled and which models to use.
#>
function Read-UpscaleOptions {
	[CmdletBinding()]
	[OutputType([UpscaleOptions])]
	param()

	Write-Host 'Reading upscale options ...'
	$upscale_options_path = Join-Path $ProjectDir 'upscale-options.json'
	[UpscaleOptions]::new([File]::ReadAllText($upscale_options_path))
}
