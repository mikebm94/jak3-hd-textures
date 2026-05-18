#!/usr/bin/env pwsh

<#
.SYNOPSIS
Searches for textures by name in the Jak 3 game files and copies them to `textures/search-results/`.

.DESCRIPTION
Searches for textures by name in the Jak 3 game files and copies them to `textures/search-results/`.

The purpose of this script is to incrementally curate a list of textures that can then be assigned
to a texture group in `upscale-options.json` to control how they are upscaled.
Texture files from previous searches will not be deleted unless the `-Clean` switch is passed.

Each search will add the filters and exclusions used to the file `textures/search-results/search-list.json`.
When you're done with your searches, you can manually delete textures you don't want to include
in the final texture group, then pass the `-WriteTextureList` switch to write a list of all unique texture names
found in the search results directory to the file `textures/search-results/texture-list.json`
The filter list and texture list file is deleted when `-Clean` is passed.
#>


using namespace System.Diagnostics.CodeAnalysis
using namespace System.Collections.Generic

[CmdletBinding(SupportsShouldProcess)]
param(
	# Generates a list of all unique texture names of the texture files in `textures/search-results/`
	# and writes them to `textures/search-results/texture-list.json`.
	[Parameter(ParameterSetName = 'WriteTextureList', Mandatory)]
	[switch]
	$WriteTextureList,

	# The filter(s) to match against texture names. Supports `*` and `?` wildcards.
	# Do not include the file extension.
	[Parameter(ParameterSetName = 'Search', Mandatory, Position = 0)]
	[string[]]
	$Filters,

	# Excludes results matching these filters from the final search results. Supports `*` and `?` wildcards.
	# Applies to all filters passed to the `-Filters` parameter.
	[Parameter(ParameterSetName = 'Search')]
	[string[]]
	$Exclude,

	# Deletes all files in `textures/search-results/` before performing the search.
	[Parameter(ParameterSetName = 'Search')]
	[switch]
	$Clean,

	# The path to the OpenGOAL installation directory. If not supplied, the environment variable `OPENGOAL_DIR`
	# will be checked. If it isn't set, OpenGOAL will be searched for in common locations.
	[string]
	$OpenGoalDir
)

. (Join-Path $PSScriptRoot 'lib/common.ps1')
. (Join-Path $PSScriptRoot 'lib/Texture.ps1')

# Represents entries in the search list JSON file.
class SearchInfo {
	[string[]] $Filters
	[string[]] $Exclusions
}


function Main {
	[CmdletBinding(SupportsShouldProcess)]
	param()

	$results_dir = Get-SearchResultsDir

	if ($WriteTextureList) {
		Write-TextureList -ResultsDir $results_dir
		return
	}

	if ([string]::IsNullOrEmpty($OpenGoalDir)) {
		$OpenGoalDir = Find-OpenGoalInstallDir
	}
	elseif (-not (Test-Path -LiteralPath $OpenGoalDir -PathType Container)) {
		throw "OpenGOAL directory '${OpenGoalDir}' (passed via -OpenGoalDir) does not exist."
	}
	else {
		$OpenGoalDir = Resolve-Path -LiteralPath $OpenGoalDir
	}

	Write-Host "OpenGOAL installation directory: ${OpenGoalDir}"

	if ($Clean) {
		Clear-Directory $results_dir
	}

	$search_dir = Find-GameTexturesDir -OpenGoalDir $OpenGoalDir
	$Filters | Search-GameTextures -SearchDir $search_dir -ResultsDir $results_dir -Exclude $Exclude
	Write-Host "Results copied to '${results_dir}'."

	Update-SearchList -Filters $Filters -Exclude $Exclude -ResultsDir $results_dir
}

function Search-GameTextures {
	[SuppressMessageAttribute('PSShouldProcess', '')]
	[CmdletBinding(SupportsShouldProcess)]
	param(
		[Parameter(Mandatory, Position = 0, ValueFromPipeline)]
		[string]
		$Filter,

		[Parameter(Mandatory)]
		[string]
		$SearchDir,

		[Parameter(Mandatory)]
		[string]
		$ResultsDir,

		[string[]]
		$Exclude
	)

	process {
		Write-Host "Searching in game textures for '${Filter}' ..."

		$results = Get-ChildItem -LiteralPath $SearchDir -Filter "$Filter.png" -Exclude $Exclude -File -Recurse -ErrorAction Stop
		$results_by_name = [Dictionary[string, Texture]]::new()

		foreach ($file in $results) {
			$texture_name = $file.BaseName

			if ($results_by_name.ContainsKey($texture_name)) {
				$results_by_name[$texture_name].AddFile($file)
			}
			else {
				$results_by_name[$texture_name] = [Texture]::new($file, '')
			}
		}

		$found = $results.Count
		$unique = $results_by_name.Keys.Count
		$copied = 0

		foreach ($texture in $results_by_name.Values) {
			$copied += $texture.CopyTo($ResultsDir, $WhatIfPreference).Count
		}

		Write-Host "Found ${found} result(s) - ${copied} copied, ${unique} unique name(s)."
	}
}

function Update-SearchList {
	[CmdletBinding(SupportsShouldProcess)]
	param(
		[Parameter(Mandatory)]
		[string[]]
		$Filters,

		[string[]]
		$Exclude,

		[Parameter(Mandatory)]
		[string]
		$ResultsDir
	)

	$searchlist_path = Join-Path $ResultsDir 'search-list.json'
	Write-Host "Writing search info to '${searchlist_path}' ..."

	$search_entries = [List[SearchInfo]]::new()

	if (Test-Path -LiteralPath $searchlist_path -PathType Leaf) {
		$existing_entries = Get-Content -LiteralPath $searchlist_path -Raw | ConvertFrom-Json
		foreach ($entry in $existing_entries) {
			$null = $search_entries.Add([SearchInfo]$entry)
		}
	}

	$null = $search_entries.Add([SearchInfo]@{
		Filters = $Filters
		Exclusions = $Exclude
	})
	
	$search_entries | ConvertTo-Json | Set-Content -LiteralPath $searchlist_path
}

function Write-TextureList {
	[CmdletBinding(SupportsShouldProcess)]
	param(
		[Parameter(Mandatory)]
		[string]
		$ResultsDir
	)

	$texturelist_path = Join-Path $ResultsDir 'texture-list.json'
	Write-Host "Writing texture list to '${texturelist_path}' ..."

	$results = Get-ChildItem -LiteralPath $ResultsDir -Filter '*%*.png' -File -ErrorAction Stop
	$unique_textures = [HashSet[string]]::new()

	foreach ($file in $results) {
		$texture_name = ($file.BaseName -split '%')[1]

		if ([string]::IsNullOrWhiteSpace($texture_name)) {
			Write-Warning "Texture file has invalid filename: '$($file.FullName)'"
			continue
		}

		$null = $unique_textures.Add($texture_name)
	}

	$unique_textures | Sort-Object | ConvertTo-Json | Set-Content -LiteralPath $texturelist_path
}


Main
