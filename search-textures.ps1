#!/usr/bin/env pwsh

<#
.SYNOPSIS
Searches for matching files in the Jak 3 textures, or creates a list of texture names from the search results.

.DESCRIPTION
Searches for matching files in the Jak 3 textures, or creates a list of texture names from the search results.

The script is meant to aid in creating texture groups in `upscale-options.json`, or to help visually inspect
the textures already in a group. The matching textures are copied to `textures/search-results/`.

There are three ways to search for textures, which can be combined with eachother:
	Matching texture names against wildcard patterns passed to the `-Filters` parameter.
	Matching texture names against regular expression patterns passed to the `-Patterns` parameter.
	Using one of the (mutually-exclusive) texture group related parameters: `-InGroups`, `-IsGrouped`, `-NotGrouped`

You can delete any files you don't want to include in the final texture list from `textures/search-results/`.
Passing the `-WriteTextureList` parameter writes a sorted list of the unique texture names
to `textures/search-results/texture-list.json`.

Pass `-CombineWithGroup <group name>` to merge the texture names from an existing texture group
with the names in the search results when writing the texture list. 

.NOTES
For help with syntax for the `-Filters` parameter, see:
https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_wildcards

For help with syntax for the `-Patterns` parameter, see:
https://learn.microsoft.com/en-us/dotnet/standard/base-types/regular-expressions

.EXAMPLE
PS> ./search-textures.ps1 -Filters '*iris*', '*pupil*' -Patterns '\beye(?!brow)(?!lid)' -NotGrouped

.EXAMPLE
PS> ./search-textures.ps1 -InGroups 'Eye' -Clean

.EXAMPLE
PS> ./search-textures.ps1 -WriteTextureList -MergeWithGroup 'Eye'
#>


using namespace System.Diagnostics.CodeAnalysis
using namespace System.Collections.Generic

[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Search')]
param(
	# Generates a list of all unique texture names of the texture files in `textures/search-results/`
	# and writes them to `textures/search-results/texture-list.json`.
	[Parameter(ParameterSetName = 'WriteTextureList', Mandatory)]
	[switch]
	$WriteTextureList,

	# When writing the texture list, combines it with the list of textures in the specified texture group.
	# Use when adding the list to a texture group instead of creating a new group.
	[Parameter(ParameterSetName = 'WriteTextureList')]
	[string]
	$MergeWithGroup,

	# The wildcard patterns to match against texture names. (Do not include the file extension.)
	[Parameter(ParameterSetName = 'Search')]
	[Parameter(ParameterSetName = 'SearchInGroups')]
	[Parameter(ParameterSetName = 'SearchIsGrouped')]
	[Parameter(ParameterSetName = 'SearchNotGrouped')]
	[string[]]
	$Filters,

	# The regex patterns to match against texture names. (Do not include the file extension.)
	[Parameter(ParameterSetName = 'Search')]
	[Parameter(ParameterSetName = 'SearchInGroups')]
	[Parameter(ParameterSetName = 'SearchIsGrouped')]
	[Parameter(ParameterSetName = 'SearchNotGrouped')]
	[string[]]
	$Patterns,

	# Excludes textures that don't belong to any of the provided texture groups.
	[Parameter(ParameterSetName = 'SearchInGroups', Mandatory)]
	[string[]]
	$InGroups,

	# Excludes textures that don't belong to any texture group.
	[Parameter(ParameterSetName = 'SearchIsGrouped', Mandatory)]
	[switch]
	$IsGrouped,

	# Excludes textures that belong to any texture group.
	[Parameter(ParameterSetName = 'SearchNotGrouped', Mandatory)]
	[switch]
	$NotGrouped,

	# Deletes all files in `textures/search-results/` before performing the search.
	[Parameter(ParameterSetName = 'Search')]
	[Parameter(ParameterSetName = 'SearchInGroups')]
	[Parameter(ParameterSetName = 'SearchIsGrouped')]
	[Parameter(ParameterSetName = 'SearchNotGrouped')]
	[switch]
	$Clean,

	# The path to the OpenGOAL installation directory. If not supplied, the environment variable `OPENGOAL_DIR`
	# will be checked. If it isn't set, OpenGOAL will be searched for in common locations.
	[Parameter(ParameterSetName = 'Search')]
	[Parameter(ParameterSetName = 'SearchInGroups')]
	[Parameter(ParameterSetName = 'SearchIsGrouped')]
	[Parameter(ParameterSetName = 'SearchNotGrouped')]
	[string]
	$OpenGoalDir
)

. (Join-Path $PSScriptRoot 'lib/common.ps1')
. (Join-Path $PSScriptRoot 'lib/Texture.ps1')
. (Join-Path $PSScriptRoot 'lib/UpscaleOptions.ps1')


function Main {
	[CmdletBinding(SupportsShouldProcess)]
	param()

	# Check if any search criteria was provided.
	if (-not $WriteTextureList) {
		$any_criteria =
			($Filters.Count -gt 0) -or
			($Patterns.Count -gt 0) -or
			($InGroups.Count -gt 0) -or
			$IsGrouped -or
			$NotGrouped

		if (-not $any_criteria) {
			throw (
				"No search criteria provided. Please pass at least one of the following parameters: " +
			    "-Filters, -Patterns, -InGroups, -IsGrouped, -NotGrouped"
			)
		}
	}

	$upscale_options = Read-UpscaleOptions
	$results_dir = Get-SearchResultsDir

	if ($WriteTextureList) {
		Write-TextureList -ResultsDir $results_dir -UpscaleOptions $upscale_options
		return
	}

	# Check if an invalid group name was passed to -InGroups.
	foreach ($group in $InGroups) {
		if (-not $upscale_options.TextureGroups.ContainsKey($group)) {
			throw "Parameter 'InGroups': The TextureGroup '${group}' does not exist."
		}
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

	$search_dir = Find-GameTexturesDir -OpenGoalDir $OpenGoalDir

	if ($Clean) {
		Clear-Directory $results_dir
	}

	Search-Textures -SearchDir $search_dir -ResultsDir $results_dir -UpscaleOptions $upscale_options
}


function Search-Textures {
	[SuppressMessageAttribute('PSShouldProcess', '')]
	[CmdletBinding(SupportsShouldProcess)]
	param(
		[Parameter(Mandatory)]
		[string]
		$SearchDir,

		[Parameter(Mandatory)]
		[string]
		$ResultsDir,

		[Parameter(Mandatory)]
		[UpscaleOptions]
		$UpscaleOptions
	)

	Write-Host "Searching textures in '${SearchDir}' ..."

	$texture_files = Get-ChildItem -LiteralPath $SearchDir -Filter '*.png' -File -Recurse -ErrorAction Stop

	# Use `Texture` objects grouped by texture name to de-duplicate the results using their file hashes.
	# Also handles encoding the sub-directory into the filenames when copying to the result directory.
	$results = [Dictionary[string, Texture]]::new()

	# Get results.
	foreach ($texture_file in $texture_files) {
		$texture_name = $texture_file.BaseName

		# First do group-related filtering before checking the various filters and patterns.
		if (($NotGrouped -and $null -ne $UpscaleOptions.TextureGroupMap[$texture_name])) {
			# It's in a group when it shouldn't be.
			continue
		}
		elseif ($IsGrouped -and $null -eq $UpscaleOptions.TextureGroupMap[$texture_name]) {
			# It's not in a group when it should be.
			continue
		}
		elseif ($InGroups -and -not $InGroups.Contains($UpscaleOptions.TextureGroupMap[$texture_name].Name)) {
			# It's not in the right group.
			continue
		}

		if (-not (Test-TextureName $texture_name)) {
			# It's name doesn't match any of the wildcard/regex patterns.
			continue
		}

		# Store the result.
		if ($results.ContainsKey($texture_name)) {
			$results[$texture_name].AddFile($texture_file)
		}
		else {
			$results[$texture_name] = [Texture]::new($texture_file, '')
		}
	}

	# Copy results.
	$files_matched = 0
	$files_copied = 0
	$unique_names = $results.Keys.Count

	foreach ($result in $results.Values) {
		$files_matched += $result.Files.Count
		$files_copied += $result.CopyTo($ResultsDir, $WhatIfPreference).Count
	}

	Write-Host "Unique texture names : ${unique_names}"
	Write-Host "Textures matched     : ${files_matched}"
	Write-Host "Textures copied      : ${files_copied}"
	Write-Host "Results copied to    : ${ResultsDir}"
}


<#
.SYNOPSIS
Checks if a texture's name matches any of the patterns in the `Filters` and `Patterns` parameters.
#>
function Test-TextureName([string] $TextureName) {
	if (($Filters.Count -eq 0) -and ($Patterns.Count -eq 0)) {
		return $true
	}

	# Match against wildcard patterns first because it's faster than regex.
	foreach ($filter in $Filters) {
		if ($TextureName -like $filter) {
			return $true
		}
	}

	# Match against regex patterns.
	foreach ($pattern in $Patterns) {
		if ($TextureName -match $pattern) {
			return $true
		}
	}

	$false
}


function Write-TextureList {
	[CmdletBinding(SupportsShouldProcess)]
	param(
		[Parameter(Mandatory)]
		[string]
		$ResultsDir,

		[Parameter(Mandatory)]
		[UpscaleOptions]
		$UpscaleOptions
	)

	$list_path = Join-Path $ResultsDir 'texture-list.json'
	Write-Host "Writing texture list to '${list_path}' ..."

	[TextureGroup] $target_group = $null

	if (-not [string]::IsNullOrEmpty($MergeWithGroup)) {
		$target_group = $UpscaleOptions.TextureGroups[$MergeWithGroup]

		if ($null -eq $target_group) {
			throw "Could not combine list with TextureGroup '${MergeWithGroup}': The group does not exist."
		}
	}

	$results = Get-ChildItem -LiteralPath $ResultsDir -Filter '*.png' -File -ErrorAction Stop
	$texture_names = [HashSet[string]]::new()

	foreach ($result in $results) {
		$texture_name = (Split-TextureFileName $result).Name

		if ($null -eq $texture_name) {
			# Unknown texture
			continue
		}

		$null = $texture_names.Add($texture_name)
	}

	foreach ($texture_name in $target_group.TextureNames) {
		$null = $texture_names.Add($texture_name)
	}

	$texture_names |
		Sort-Object -ErrorAction Stop |
		ConvertTo-Json -ErrorAction Stop |
		Set-Content -LiteralPath $list_path -ErrorAction Stop
}


Main
