#!/usr/bin/env pwsh

<#
.SYNOPSIS
Searches for matching files in the Jak 3 textures.

.DESCRIPTION
Searches for matching files in the Jak 3 textures.

The script is meant to aid in creating/updating texture groups in `upscale-options.json`, or to help visually
inspect the textures already in a group. The matching textures are copied to `textures/search-results/`.

There are numerous methods of searching for textures, which can be combined:
	By texture name using `-Filters` (wildcards) and/or `-Patterns` (regex).
		(Only one of the filters or patterns needs to match.)
	By texture subdirectory name using `-SubdirFilters` (wildcards) and/or `-SubdirPatterns` (regex).
		(Only one of the filters or patterns needs to match.)
	By texture group using `-InGroups`, `-IsGrouped` or `-NotGrouped` (mutually exclusive).
	By texture dimensions using `-Width` and/or `-Height`.

All methods used must match to return a result.

You can delete any files you don't want to include in the final texture list from `textures/search-results/`,
or move/copy the files you want to include in the list to another directory.

.NOTES
For help with creating a texture list used to create/update texture groups, run: ./write-texture-list.ps1 -?

For help with syntax for the `-Filters` or `-SubdirFilters` parameters, see:
https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_wildcards

For help with syntax for the `-Patterns` or `-SubdirPatterns` parameters, see:
https://learn.microsoft.com/en-us/dotnet/standard/base-types/regular-expressions

.EXAMPLE
PS> ./search-textures.ps1 -Filters '*iris*', '*pupil*' -Patterns '\beye(?!brow)(?!lid)' -NotGrouped

.EXAMPLE
PS> ./search-textures.ps1 -InGroups 'Eye' -Width '>64' -Clean
#>


using namespace System.Diagnostics.CodeAnalysis
using namespace System.Collections.Generic
using namespace System.IO

[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Search')]
param(
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

	# The wildcard patterns to match against texture subdirectory names (<level name>[-category]).
	[Parameter(ParameterSetName = 'Search')]
	[Parameter(ParameterSetName = 'SearchInGroups')]
	[Parameter(ParameterSetName = 'SearchIsGrouped')]
	[Parameter(ParameterSetName = 'SearchNotGrouped')]
	[string[]]
	$SubdirFilters,

	# The regex patterns to match against texture subdirectory names (<level name>[-category]).
	[Parameter(ParameterSetName = 'Search')]
	[Parameter(ParameterSetName = 'SearchInGroups')]
	[Parameter(ParameterSetName = 'SearchIsGrouped')]
	[Parameter(ParameterSetName = 'SearchNotGrouped')]
	[string[]]
	$SubdirPatterns,

	# Excludes textures that don't belong to any of the provided texture groups.
	[Parameter(ParameterSetName = 'SearchInGroups', Mandatory)]
	[ArgumentCompleter({
		param($cmd_name, $param_name, $word, $cmd_ast, $fake_bound_params)

		$upscale_opts_path = Join-Path $PSScriptRoot 'upscale-options.json'
		$upscale_opts =
			Get-Content -LiteralPath $upscale_opts_path -Raw -ErrorAction SilentlyContinue |
			ConvertFrom-Json -ErrorAction SilentlyContinue
		$upscale_opts.TextureGroups |
			Select-Object -ExpandProperty Name -ErrorAction SilentlyContinue |
			Where-Object { $_ -like "${word}*" }
	})]
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

	# Filters results by texture width in pixels by exact width, by comparison, or by a range (inclusive).
	# To filter by comparison, use one of these operators before the width:
	#     '<'  (less than)
	#     '<=' (less than or equal)
	#     '>'  (greater than)
	#     '>=' (greater than or equal)
	# To filter by a range, use a dash between the two widths.
	#
	# Example: '<=128' or '32-64'
	[Parameter(ParameterSetName = 'Search')]
	[Parameter(ParameterSetName = 'SearchInGroups')]
	[Parameter(ParameterSetName = 'SearchIsGrouped')]
	[Parameter(ParameterSetName = 'SearchNotGrouped')]
	[ValidatePattern('^(<|<=|>=|>)?\d+$|^\d+-\d+$')]
	[string]
	$Width,

	# Filters results by texture height in pixels by exact height, by comparison, or by a range (inclusive).
	# To filter by comparison, use one of these operators before the height:
	#     '<'  (less than)
	#     '<=' (less than or equal)
	#     '>'  (greater than)
	#     '>=' (greater than or equal)
	# To filter by a range, use a dash between the two heights.
	#
	# Example: '<=128' or '32-64'
	[Parameter(ParameterSetName = 'Search')]
	[Parameter(ParameterSetName = 'SearchInGroups')]
	[Parameter(ParameterSetName = 'SearchIsGrouped')]
	[Parameter(ParameterSetName = 'SearchNotGrouped')]
	[ValidatePattern('^(<|<=|>=|>)?\d+$|^\d+-\d+$')]
	[string]
	$Height,

	# Includes textures that are currently excluded from upscaling, such as those that don't meet
	# the minimum size requirement, or those explicitly assigned to a texture group with a null workflow.
	[Parameter(ParameterSetName = 'Search')]
	[Parameter(ParameterSetName = 'SearchInGroups')]
	[Parameter(ParameterSetName = 'SearchIsGrouped')]
	[Parameter(ParameterSetName = 'SearchNotGrouped')]
	[switch]
	$IncludeNotUpscaled,

	# Deletes all files in `textures/search-results/` before performing the search.
	[Parameter(ParameterSetName = 'Search')]
	[Parameter(ParameterSetName = 'SearchInGroups')]
	[Parameter(ParameterSetName = 'SearchIsGrouped')]
	[Parameter(ParameterSetName = 'SearchNotGrouped')]
	[switch]
	$Clean,

	# The path to an OpenGOAL installation directory. Used to find textures extracted from the Jak 3 ISO.
	#
	# If neither `-OpenGoalDir` nor `-Jak3TexDir` are set, first the environment variable `OPENGOAL_DIR`
	# is checked, then `JAK3_TEX_DIR`, then an automatic search for an OpenGOAL installation is performed.
	[Parameter(ParameterSetName = 'Search')]
	[Parameter(ParameterSetName = 'SearchInGroups')]
	[Parameter(ParameterSetName = 'SearchIsGrouped')]
	[Parameter(ParameterSetName = 'SearchNotGrouped')]
	[string]
	$OpenGoalDir,

	# The path to the textures extracted from the Jak 3 ISO.
	#
	# If neither `-OpenGoalDir` nor `-Jak3TexDir` are set, first the environment variable `OPENGOAL_DIR`
	# is checked, then `JAK3_TEX_DIR`, then an automatic search for an OpenGOAL installation is performed.
	[Parameter(ParameterSetName = 'Search')]
	[Parameter(ParameterSetName = 'SearchInGroups')]
	[Parameter(ParameterSetName = 'SearchIsGrouped')]
	[Parameter(ParameterSetName = 'SearchNotGrouped')]
	[string]
	$Jak3TexDir
)

. (Join-Path $PSScriptRoot 'lib/common.ps1')
. (Join-Path $PSScriptRoot 'lib/Texture.ps1')
. (Join-Path $PSScriptRoot 'lib/UpscaleOptions.ps1')


# Parses the `Width` and `Height` parameters into an object used to filter textures by their dimensions.
class DimensionFilter {
	[int[]] $Widths
	[int[]] $Heights
	[scriptblock] $CheckWidth = { $true }
	[scriptblock] $CheckHeight = { $true }

	DimensionFilter([string] $width_filter, [string] $height_filter) {
		$op_map = @{
			''   = { param([int]$a, [int[]]$b) $a -eq $b[0] }
			'<'  = { param([int]$a, [int[]]$b) $a -lt $b[0] }
			'<=' = { param([int]$a, [int[]]$b) $a -le $b[0] }
			'>'  = { param([int]$a, [int[]]$b) $a -gt $b[0] }
			'>=' = { param([int]$a, [int[]]$b) $a -ge $b[0] }
		}

		if ($width_filter -match '^\d+-\d+$') {
			# Filter by range.
			$this.Widths = $width_filter -split '-'
			[Array]::Sort($this.Widths)
			$this.CheckWidth = { param([int]$a, [int[]]$b) ($a -ge $b[0]) -and ($a -le $b[1]) }
		}
		elseif ($width_filter) {
			# Filter by comparison.
			$this.Widths = $width_filter -replace '^[<>]=?'
			$this.CheckWidth = $op_map[$width_filter -replace '\d+$']
		}

		if ($height_filter -match '^\d+-\d+$') {
			# Filter by range.
			$this.Heights = $height_filter -split '-'
			[Array]::Sort($this.Heights)
			$this.CheckHeight = { param([int]$a, [int[]]$b) ($a -ge $b[0]) -and ($a -le $b[1]) }
		}
		elseif ($height_filter) {
			# Filter by comparison.
			$this.Heights = $height_filter -replace '^[<>]=?'
			$this.CheckHeight = $op_map[$height_filter -replace '\d+$']
		}
	}

	[bool] CheckDimensions([int] $texture_width, [int] $texture_height) {
		return (
			(& $this.CheckWidth $texture_width $this.Widths) -and
			(& $this.CheckHeight $texture_height $this.Heights)
		)
	}
}


function Main {
	[SuppressMessageAttribute('PSShouldProcess', '')]
	[CmdletBinding(SupportsShouldProcess)]
	param()

	$upscale_options = Read-UpscaleOptions
	$results_dir = Get-SearchResultsDir

	if ($Clean) {
		Clear-Directory $results_dir
	}

	$any_criteria =
		($Filters.Count -gt 0) -or ($Patterns.Count -gt 0) -or
		($SubdirFilters.Count -gt 0) -or ($SubdirPatterns.Count -gt 0) -or
		($InGroups.Count -gt 0) -or $IsGrouped -or $NotGrouped -or
		$Width -or $Height

	if (-not $any_criteria) {
		Write-Host "No search criteria provided."
		return
	}

	# Check if an invalid group name was passed to -InGroups.
	foreach ($group in $InGroups) {
		if (-not $upscale_options.TextureGroups.ContainsKey($group)) {
			throw "Parameter 'InGroups': The TextureGroup '${group}' does not exist."
		}
	}

	$search_params = @{
		SearchDir = Find-ExtractedTexturesDir -OpenGoalDir $OpenGoalDir -Jak3TexDir $Jak3TexDir
		ResultsDir = $results_dir
		UpscaleOptions = $upscale_options
		DimensionFilter = if ($Width -or $Height) { [DimensionFilter]::new($Width, $Height) }
	}

	Search-Textures @search_params
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
		$UpscaleOptions,

		[DimensionFilter]
		$DimensionFilter
	)

	Write-Host "Searching textures in '${SearchDir}' ..."

	$texture_files = Get-ChildItem -LiteralPath $SearchDir -Filter '*.png' -File -Recurse -ErrorAction Stop
	$min_size = $UpscaleOptions.MinimumTextureSize

	# Use `Texture` objects grouped by texture name to de-duplicate the results using their file hashes.
	# Also handles encoding the sub-directory into the filenames when copying to the result directory.
	$results = [Dictionary[string, Texture]]::new()

	# Get results.
	foreach ($texture_file in $texture_files) {
		$subdir_name = $texture_file.Directory.BaseName
		$texture_name = $texture_file.BaseName
		$texture_group = $UpscaleOptions.TextureGroupMap[$texture_name]
		$texture_workflow = if ($texture_group) {
			$texture_group.Workflow
		} else {
			$UpscaleOptions.DefaultWorkflow
		}

		if ($texture_group -and -not $IncludeNotUpscaled -and $null -eq $texture_workflow) {
			# Upscaling is explicitly disabled for this texture, and -IncludeNotUpscaled wasn't passed.
			continue
		}

		# First do group-related filtering before checking the various filters, patterns and dimensions.
		if ($NotGrouped -and $null -ne $texture_group) {
			# It's in a group when it shouldn't be.
			continue
		}
		elseif ($IsGrouped -and $null -eq $texture_group) {
			# It's not in a group when it should be.
			continue
		}
		elseif ($InGroups -and -not $InGroups.Contains($texture_group.Name)) {
			# It's not in the right group.
			continue
		}

		# Then check if the texture name and/or subdirectory name matches any one of the wildcard/regex patterns.
		if (-not (Test-Patterns $subdir_name -Filters $SubdirFilters -Patterns $SubdirPatterns)) {
			continue
		}
		elseif (-not (Test-Patterns $texture_name -Filters $Filters -Patterns $Patterns)) {
			continue
		}

		# Finally, the most expensive check, checking the dimensions.
		if (-not $IncludeNotUpscaled -or $DimensionFilter) {
			$size = Get-TextureSize $texture_file.FullName

			if (-not $IncludeNotUpscaled -and $min_size -gt 0) {
				if ($size.Width -lt $min_size -or $size.Height -lt $min_size) {
					# Upscaling is implicitly disabled because it's smaller than the `MinimumTextureSize`
					# set in `upscale-options.json`, and -IncludeNotUpscaled wasn't passed.
					continue
				}
			}
			if ($DimensionFilter -and -not $DimensionFilter.CheckDimensions($size.Width, $size.Height)) {
				# Doesn't match the `-Width` or `-Height` filters.
				continue
			}
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
		$files_copied += $result.CopyTo($ResultsDir, $WhatIfPreference)
	}

	Write-Host "Unique texture names : ${unique_names}"
	Write-Host "Textures matched     : ${files_matched}"
	Write-Host "Textures copied      : ${files_copied}"
	Write-Host "Results copied to    : ${ResultsDir}"
}


<#
.SYNOPSIS
Checks if a texture's name or subdirectory name matches any of the given patterns.
#>
function Test-Patterns([string] $Name, [string[]] $Filters, [string[]] $Patterns) {
	if (($Filters.Count -eq 0) -and ($Patterns.Count -eq 0)) {
		return $true
	}

	# Match against wildcard patterns first because it's faster than regex.
	foreach ($filter in $Filters) {
		if ($Name -like $filter) {
			return $true
		}
	}

	# Match against regex patterns.
	foreach ($pattern in $Patterns) {
		if ($Name -match $pattern) {
			return $true
		}
	}

	$false
}


Main
